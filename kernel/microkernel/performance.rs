use core::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use spin::RwLock;
use x86_64::registers::model_specific::{Msr, MsrFlags};
use crate::config::KERNEL_CONFIG;

/// Performance optimization module
pub struct PerformanceManager {
    /// CPU frequency scaling enabled
    cpu_freq_scaling: AtomicBool,
    /// CPU performance counters
    perf_counters: [AtomicU64; 4],
    /// Thermal throttling enabled
    thermal_throttling: AtomicBool,
    /// Power management profile
    power_profile: RwLock<PowerProfile>,
}

#[derive(Debug, Clone, Copy)]
pub enum PowerProfile {
    Performance,
    Balanced,
    PowerSave,
}

impl PerformanceManager {
    pub const fn new() -> Self {
        Self {
            cpu_freq_scaling: AtomicBool::new(true),
            perf_counters: [
                AtomicU64::new(0),
                AtomicU64::new(0),
                AtomicU64::new(0),
                AtomicU64::new(0),
            ],
            thermal_throttling: AtomicBool::new(true),
            power_profile: RwLock::new(PowerProfile::Performance),
        }
    }

    /// Initialize performance optimizations
    pub fn init(&self) {
        unsafe {
            // Enable hardware prefetcher
            let mut msr = Msr::new(0x1A4);
            msr.write(0x0); // Enable all prefetchers

            // Disable CPU throttling for maximum performance
            if !self.thermal_throttling.load(Ordering::Relaxed) {
                let mut msr = Msr::new(0x1FC);
                msr.write(0x0);
            }

            // Configure CPU power management
            self.configure_power_management();

            // Enable performance counters
            self.init_performance_counters();
        }
    }

    /// Configure CPU power management based on profile
    fn configure_power_management(&self) {
        let profile = *self.power_profile.read();
        unsafe {
            match profile {
                PowerProfile::Performance => {
                    // Disable C-states except C0 for lowest latency
                    let mut msr = Msr::new(0xE2);
                    msr.write(0x1);

                    // Set maximum performance
                    let mut msr = Msr::new(0x199);
                    msr.write(0xFFFF);
                }
                PowerProfile::Balanced => {
                    // Enable balanced C-state control
                    let mut msr = Msr::new(0xE2);
                    msr.write(0x7);
                }
                PowerProfile::PowerSave => {
                    // Enable all C-states
                    let mut msr = Msr::new(0xE2);
                    msr.write(0xFF);
                }
            }
        }
    }

    /// Initialize CPU performance counters
    fn init_performance_counters(&self) {
        unsafe {
            // Enable performance monitoring
            let mut msr = Msr::new(0x38F);
            msr.write(0x7);

            // Configure counters for:
            // 1. Instructions retired
            // 2. CPU cycles
            // 3. Cache misses
            // 4. Branch mispredictions
            let counter_configs = [
                (0xC0, 0x00), // Instructions
                (0x3C, 0x00), // Cycles
                (0x2E, 0x41), // LLC misses
                (0xC5, 0x00), // Branch misses
            ];

            for (i, (event, umask)) in counter_configs.iter().enumerate() {
                let mut msr = Msr::new(0x186 + i as u32);
                msr.write((*event as u64) | ((*umask as u64) << 8) | (1 << 22));
            }
        }
    }

    /// Get current performance metrics
    pub fn get_metrics(&self) -> PerformanceMetrics {
        PerformanceMetrics {
            instructions: self.perf_counters[0].load(Ordering::Relaxed),
            cycles: self.perf_counters[1].load(Ordering::Relaxed),
            cache_misses: self.perf_counters[2].load(Ordering::Relaxed),
            branch_misses: self.perf_counters[3].load(Ordering::Relaxed),
        }
    }

    /// Update performance configuration based on workload
    pub fn adapt_to_workload(&self, metrics: &PerformanceMetrics) {
        let config = KERNEL_CONFIG.write();
        
        // Adjust scheduler quantum based on branch prediction accuracy
        let branch_miss_rate = metrics.branch_misses as f64 / metrics.instructions as f64;
        if branch_miss_rate > 0.1 {
            // High branch misprediction rate - increase quantum
            config.task_quantum_ms.store(15, Ordering::SeqCst);
        } else {
            // Good branch prediction - decrease quantum
            config.task_quantum_ms.store(5, Ordering::SeqCst);
        }

        // Adjust cache configuration based on miss rate
        let cache_miss_rate = metrics.cache_misses as f64 / metrics.instructions as f64;
        if cache_miss_rate > 0.05 {
            // High cache miss rate - increase prefetch aggressiveness
            unsafe {
                let mut msr = Msr::new(0x1A4);
                msr.write(0x0); // Maximum prefetch
            }
        }
    }
}

#[derive(Debug, Clone)]
pub struct PerformanceMetrics {
    pub instructions: u64,
    pub cycles: u64,
    pub cache_misses: u64,
    pub branch_misses: u64,
}

// Global performance manager instance
lazy_static! {
    pub static ref PERFORMANCE_MANAGER: PerformanceManager = PerformanceManager::new();
}
