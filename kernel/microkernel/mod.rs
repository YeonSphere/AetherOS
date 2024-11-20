//! AetherOS Microkernel Module
//! Exports microkernel functionality

pub use self::capability::{Capability, CapabilitySpace, CapabilityType, Error as CapabilityError};
pub use self::ipc::{Message, MessageQueue, MessageType, Error as IPCError};
pub use self::memory::{MemoryManager, MemoryRegion, RegionType, Error as MemoryError};
pub use self::scheduler::{Scheduler, Task, TaskState, Priority, Error as SchedulerError};
pub use self::lib::{Kernel, Error as KernelError, KERNEL};

// Re-export modules
pub mod capability;
pub mod ipc;
pub mod memory;
pub mod scheduler;
pub mod lib;

// Common types
pub type TaskId = u64;
pub type MessageId = u64;
pub type ResourceId = u64;
pub type CpuMask = u64;
