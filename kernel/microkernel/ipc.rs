//! AetherOS IPC System
//! Zero-copy, low-latency IPC implementation

use alloc::collections::{BTreeMap, VecDeque};
use core::sync::atomic::{AtomicU64, Ordering};
use spin::RwLock;

/// Message types
#[derive(Debug, Clone, Copy)]
#[repr(u8)]
pub enum MessageType {
    Signal,     // Lightweight signal
    Data,       // Regular data message
    SharedMem,  // Shared memory region
    Stream,     // Continuous data stream
}

#[derive(Debug)]
pub struct Message {
    id: MessageId,
    typ: MessageType,
    sender: TaskId,
    receiver: TaskId,
    data: Option<*const u8>,
    size: usize,
    flags: MessageFlags,
}

#[derive(Debug, Clone, Copy)]
pub struct MessageFlags {
    priority: u8,
    nonblocking: bool,
    zero_copy: bool,
}

#[derive(Debug)]
pub struct MessageQueue {
    capacity: usize,
    queues: BTreeMap<TaskId, VecDeque<Message>>,
    shared_buffers: BTreeMap<MessageId, SharedBuffer>,
    lock: RwLock<()>,
    stats: IPCStats,
}

#[derive(Debug)]
struct SharedBuffer {
    data: *mut u8,
    size: usize,
    refcount: AtomicU64,
}

#[derive(Debug)]
struct IPCStats {
    messages_sent: AtomicU64,
    messages_received: AtomicU64,
    total_bytes: AtomicU64,
}

impl MessageQueue {
    pub fn new(capacity: usize) -> Self {
        Self {
            capacity,
            queues: BTreeMap::new(),
            shared_buffers: BTreeMap::new(),
            lock: RwLock::new(()),
            stats: IPCStats {
                messages_sent: AtomicU64::new(0),
                messages_received: AtomicU64::new(0),
                total_bytes: AtomicU64::new(0),
            },
        }
    }

    #[inline(always)]
    pub fn send(&mut self, msg: Message) -> Result<(), Error> {
        let _guard = self.lock.write();

        // Fast path for signals
        if msg.typ == MessageType::Signal {
            return self.send_signal(msg);
        }

        // Check queue capacity
        let queue = self.queues.entry(msg.receiver).or_insert_with(VecDeque::new);
        if queue.len() >= self.capacity && !msg.flags.nonblocking {
            return Err(Error::QueueFull);
        }

        // Handle zero-copy transfer
        if msg.flags.zero_copy {
            if let Some(data) = msg.data {
                let shared_buf = SharedBuffer {
                    data: data as *mut u8,
                    size: msg.size,
                    refcount: AtomicU64::new(1),
                };
                self.shared_buffers.insert(msg.id, shared_buf);
            }
        }

        // Update stats
        self.stats.messages_sent.fetch_add(1, Ordering::Relaxed);
        self.stats.total_bytes.fetch_add(msg.size as u64, Ordering::Relaxed);

        queue.push_back(msg);
        Ok(())
    }

    #[inline(always)]
    pub fn receive(&mut self, timeout: u64) -> Result<Message, Error> {
        let _guard = self.lock.write();

        let task_id = get_current_task();
        let queue = self.queues.get_mut(&task_id).ok_or(Error::NoMessages)?;

        // Try to get a message
        if let Some(msg) = queue.pop_front() {
            // Handle zero-copy cleanup
            if msg.flags.zero_copy {
                if let Some(buf) = self.shared_buffers.get(&msg.id) {
                    if buf.refcount.fetch_sub(1, Ordering::Release) == 1 {
                        // Last reference, clean up
                        self.shared_buffers.remove(&msg.id);
                    }
                }
            }

            // Update stats
            self.stats.messages_received.fetch_add(1, Ordering::Relaxed);
            
            Ok(msg)
        } else if timeout == 0 {
            Err(Error::NoMessages)
        } else {
            // Wait for message with timeout
            self.wait_for_message(timeout)
        }
    }

    #[inline(always)]
    fn send_signal(&mut self, msg: Message) -> Result<(), Error> {
        let queue = self.queues.entry(msg.receiver).or_insert_with(VecDeque::new);
        queue.push_front(msg);  // Signals get priority
        self.stats.messages_sent.fetch_add(1, Ordering::Relaxed);
        Ok(())
    }

    fn wait_for_message(&self, timeout: u64) -> Result<Message, Error> {
        let start = get_current_time();
        while get_current_time() - start < timeout {
            if let Some(msg) = self.try_receive() {
                return Ok(msg);
            }
            cpu_relax();
        }
        Err(Error::Timeout)
    }

    #[inline(always)]
    fn try_receive(&self) -> Option<Message> {
        let task_id = get_current_task();
        self.queues.get(&task_id)?.front().cloned()
    }
}

// Error types
#[derive(Debug)]
pub enum Error {
    QueueFull,
    NoMessages,
    InvalidReceiver,
    Timeout,
    ZeroCopyFailed,
}

// Helper functions
#[inline(always)]
fn cpu_relax() {
    #[cfg(target_arch = "x86_64")]
    unsafe {
        core::arch::asm!("pause");
    }
}
