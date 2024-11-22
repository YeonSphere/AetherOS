//! AetherOS Microkernel Scheduler
//! Low-latency, real-time capable scheduler

use alloc::collections::{BinaryHeap, HashMap, VecDeque};
use core::cmp::Ordering;
use core::sync::atomic::{AtomicU64, Ordering as AtomicOrdering};
use spin::RwLock;

/// Task states
#[derive(Debug, Clone, Copy, PartialEq)]
#[repr(u8)]
pub enum TaskState {
    Ready,
    Running,
    Blocked,
    Sleeping,
    Terminated,
}

/// Task priorities
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
#[repr(u8)]
pub enum Priority {
    Realtime = 0,
    High = 1,
    Normal = 2,
    Low = 3,
    Background = 4,
}

/// Task structure
#[repr(C)]
pub struct Task {
    id: TaskId,
    state: TaskState,
    priority: Priority,
    quantum: u64,           // Time slice in microseconds
    runtime: u64,           // Total runtime
    last_run: u64,         // Last run timestamp
    affinity: CpuMask,     // CPU affinity
    capabilities: CapabilitySpace,
    last_cpu: Option<u32>,
    switches: u64,
}

/// Scheduler implementation
pub struct Scheduler {
    tasks: BinaryHeap<Task>,
    current: Option<Task>,
    time_slice: u64,       // Base time slice in microseconds
    lock: RwLock<()>,
    cpu_affinity: HashMap<TaskId, CpuMask>,
    realtime_queue: VecDeque<Task>,
    stats: SchedulerStats,
}

#[derive(Debug)]
struct SchedulerStats {
    context_switches: AtomicU64,
    preemptions: AtomicU64,
    total_runtime: AtomicU64,
}

impl Scheduler {
    /// Create new scheduler
    pub fn new(time_slice: u64) -> Self {
        Self {
            tasks: BinaryHeap::new(),
            current: None,
            time_slice,
            lock: RwLock::new(()),
            cpu_affinity: HashMap::new(),
            realtime_queue: VecDeque::new(),
            stats: SchedulerStats {
                context_switches: AtomicU64::new(0),
                preemptions: AtomicU64::new(0),
                total_runtime: AtomicU64::new(0),
            },
        }
    }

    /// Schedule next task
    pub fn schedule(&mut self) -> Option<Task> {
        let _guard = self.lock.write();
        
        // First check realtime queue
        if let Some(task) = self.realtime_queue.pop_front() {
            self.stats.context_switches.fetch_add(1, Ordering::Relaxed);
            return Some(task);
        }

        // Update current task if any
        if let Some(mut task) = self.current.take() {
            if task.state == TaskState::Running {
                let runtime = get_current_time() - task.last_run;
                task.runtime += runtime;
                self.stats.total_runtime.fetch_add(runtime, Ordering::Relaxed);
                
                if runtime >= task.quantum {
                    self.stats.preemptions.fetch_add(1, Ordering::Relaxed);
                    task.state = TaskState::Ready;
                    self.tasks.push(task);
                } else {
                    // Task still has quantum left
                    return Some(task);
                }
            }
        }

        // Find next task to run using priority and affinity
        while let Some(mut next_task) = self.tasks.pop() {
            if next_task.state == TaskState::Ready {
                let cpu = get_current_cpu();
                if let Some(affinity) = self.cpu_affinity.get(&next_task.id) {
                    if (affinity & (1 << cpu)) == 0 {
                        // Wrong CPU, put back in queue
                        self.tasks.push(next_task);
                        continue;
                    }
                }

                next_task.quantum = self.calculate_quantum(&next_task);
                next_task.state = TaskState::Running;
                next_task.last_run = get_current_time();
                next_task.last_cpu = Some(cpu);
                next_task.switches += 1;
                self.current = Some(next_task.clone());
                self.stats.context_switches.fetch_add(1, Ordering::Relaxed);
                return Some(next_task);
            }
        }

        None
    }

    /// Add new task
    pub fn add_task(&mut self, mut task: Task) -> Result<(), Error> {
        let _guard = self.lock.write();
        
        // Initialize task
        task.state = TaskState::Ready;
        task.last_run = 0;
        task.runtime = 0;
        task.last_cpu = None;
        task.switches = 0;
        
        // Add to queue
        self.tasks.push(task);
        Ok(())
    }

    /// Block task
    pub fn block_task(&mut self, task_id: TaskId) -> Result<(), Error> {
        let _guard = self.lock.write();
        
        if let Some(task) = self.find_task_mut(task_id) {
            task.state = TaskState::Blocked;
            Ok(())
        } else {
            Err(Error::TaskNotFound)
        }
    }

    /// Wake task
    pub fn wake_task(&mut self, task_id: TaskId) -> Result<(), Error> {
        let _guard = self.lock.write();
        
        if let Some(task) = self.find_task_mut(task_id) {
            if task.state == TaskState::Blocked {
                task.state = TaskState::Ready;
                Ok(())
            } else {
                Err(Error::InvalidState)
            }
        } else {
            Err(Error::TaskNotFound)
        }
    }

    /// Set task priority
    pub fn set_priority(&mut self, task_id: TaskId, priority: Priority) -> Result<(), Error> {
        let _guard = self.lock.write();
        
        if let Some(task) = self.find_task_mut(task_id) {
            task.priority = priority;
            Ok(())
        } else {
            Err(Error::TaskNotFound)
        }
    }

    /// Set CPU affinity
    pub fn set_affinity(&mut self, task_id: TaskId, affinity: CpuMask) -> Result<(), Error> {
        let _guard = self.lock.write();
        
        if let Some(task) = self.find_task_mut(task_id) {
            task.affinity = affinity;
            self.cpu_affinity.insert(task_id, affinity);
            Ok(())
        } else {
            Err(Error::TaskNotFound)
        }
    }

    // Helper functions
    fn calculate_quantum(&self, task: &Task) -> u64 {
        let base = self.time_slice;
        
        // Priority-based quantum adjustment
        let priority_factor = match task.priority {
            Priority::Realtime => 0.5,  // Shorter quantum for realtime tasks
            Priority::High => 0.75,
            Priority::Normal => 1.0,
            Priority::Low => 1.5,
            Priority::Background => 2.0,
        };

        // History-based adjustment
        let history_factor = if task.runtime > 0 {
            let avg_quantum = task.runtime as f64 / task.switches as f64;
            if avg_quantum < self.time_slice as f64 {
                0.8  // Task typically needs less time
            } else {
                1.2  // Task typically needs more time
            }
        } else {
            1.0
        };

        // Cache-aware adjustment
        let cache_factor = if self.is_cache_hot(task) {
            1.2  // Favor cache-hot tasks
        } else {
            0.8
        };

        (base as f64 * priority_factor * history_factor * cache_factor) as u64
    }

    fn is_cache_hot(&self, task: &Task) -> bool {
        // Check if task was recently run on this CPU
        let current_time = get_current_time();
        let cpu = get_current_cpu();
        
        if let Some(last_cpu) = task.last_cpu {
            if last_cpu == cpu && (current_time - task.last_run) < CACHE_HOT_THRESHOLD {
                return true;
            }
        }
        false
    }

    fn find_task_mut(&mut self, task_id: TaskId) -> Option<&mut Task> {
        self.tasks.iter_mut().find(|t| t.id == task_id)
    }
}

/// Get current timestamp in microseconds
fn get_current_time() -> u64 {
    // Implementation depends on platform
    0 // Placeholder
}

/// Error types for scheduler operations
#[derive(Debug)]
pub enum Error {
    TaskNotFound,
    InvalidState,
    InvalidPriority,
    InvalidAffinity,
}

// Constants
const CACHE_HOT_THRESHOLD: u64 = 1_000_000;  // 1ms in microseconds

// Helper functions
#[inline(always)]
fn get_current_cpu() -> u32 {
    #[cfg(target_arch = "x86_64")]
    unsafe {
        let mut cpu: u32;
        asm!("rdtscp", out("eax") _, out("ecx") cpu, out("edx") _);
        cpu
    }
    #[cfg(not(target_arch = "x86_64"))]
    0
}
