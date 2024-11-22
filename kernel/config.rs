use core::sync::atomic::{AtomicUsize, Ordering};
use spin::RwLock;

/// Kernel configuration parameters for performance tuning
#[derive(Debug)]
pub struct KernelConfig {
    /// Maximum number of concurrent tasks
    pub max_tasks: AtomicUsize,
    /// Default task quantum in milliseconds
    pub task_quantum_ms: AtomicUsize,
    /// Size of the kernel stack in pages
    pub kernel_stack_pages: AtomicUsize,
    /// Maximum number of message queue entries
    pub max_message_queue_size: AtomicUsize,
    /// Size of shared memory regions in pages
    pub shared_mem_region_pages: AtomicUsize,
    /// Cache line size in bytes
    pub cache_line_size: AtomicUsize,
    /// Page size in bytes
    pub page_size: AtomicUsize,
    /// Huge page size in bytes
    pub huge_page_size: AtomicUsize,
    /// Maximum DMA buffer size
    pub max_dma_buffer_size: AtomicUsize,
    /// Number of scheduler priority levels
    pub scheduler_priority_levels: AtomicUsize,
}

lazy_static! {
    /// Global kernel configuration
    pub static ref KERNEL_CONFIG: RwLock<KernelConfig> = RwLock::new(KernelConfig::new());
}

impl KernelConfig {
    /// Create a new kernel configuration with default values
    pub const fn new() -> Self {
        Self {
            max_tasks: AtomicUsize::new(1024),
            task_quantum_ms: AtomicUsize::new(10),
            kernel_stack_pages: AtomicUsize::new(2),
            max_message_queue_size: AtomicUsize::new(256),
            shared_mem_region_pages: AtomicUsize::new(16),
            cache_line_size: AtomicUsize::new(64),
            page_size: AtomicUsize::new(4096),
            huge_page_size: AtomicUsize::new(2 * 1024 * 1024),
            max_dma_buffer_size: AtomicUsize::new(16 * 1024 * 1024),
            scheduler_priority_levels: AtomicUsize::new(32),
        }
    }

    /// Update configuration based on detected hardware capabilities
    pub fn update_from_hardware(&self) {
        use raw_cpuid::CpuId;
        
        if let Some(cpuid) = CpuId::new() {
            // Update cache line size based on CPU info
            if let Some(cparams) = cpuid.get_cache_parameters() {
                for cache in cparams {
                    if cache.cache_level() == 1 {
                        self.cache_line_size.store(
                            cache.coherency_line_size() as usize,
                            Ordering::SeqCst
                        );
                        break;
                    }
                }
            }

            // Adjust task quantum based on CPU frequency
            if let Some(freq) = cpuid.get_processor_frequency_info() {
                let base_freq = freq.processor_base_frequency() as usize;
                // Adjust quantum for higher frequency CPUs
                if base_freq > 2000 {
                    self.task_quantum_ms.store(5, Ordering::SeqCst);
                }
            }
        }
    }

    /// Configure for high-performance workloads
    pub fn optimize_for_performance(&self) {
        self.task_quantum_ms.store(5, Ordering::SeqCst);
        self.max_message_queue_size.store(1024, Ordering::SeqCst);
        self.shared_mem_region_pages.store(64, Ordering::SeqCst);
    }

    /// Configure for real-time workloads
    pub fn optimize_for_realtime(&self) {
        self.task_quantum_ms.store(1, Ordering::SeqCst);
        self.scheduler_priority_levels.store(64, Ordering::SeqCst);
    }

    /// Configure for memory-constrained environments
    pub fn optimize_for_memory_constrained(&self) {
        self.max_tasks.store(256, Ordering::SeqCst);
        self.max_message_queue_size.store(64, Ordering::SeqCst);
        self.shared_mem_region_pages.store(4, Ordering::SeqCst);
    }
}

/// Initialize kernel configuration during boot
pub fn init_kernel_config() {
    let config = KERNEL_CONFIG.write();
    config.update_from_hardware();
    
    // Default to performance optimization
    config.optimize_for_performance();
}
