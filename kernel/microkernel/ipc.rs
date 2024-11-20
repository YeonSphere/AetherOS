//! AetherOS Microkernel IPC System
//! High-performance, zero-copy message passing

use alloc::vec::Vec;
use core::sync::atomic::{AtomicU64, Ordering};
use spin::Mutex;

/// Message types for IPC
#[derive(Debug, Clone, Copy)]
#[repr(u8)]
pub enum MessageType {
    Synchronous,
    Asynchronous,
    SharedMemory,
    Interrupt,
    Signal,
}

/// IPC message structure
#[repr(C)]
pub struct Message {
    id: MessageId,
    typ: MessageType,
    sender: TaskId,
    receiver: TaskId,
    payload: MessagePayload,
}

/// Zero-copy message payload
#[repr(C)]
pub union MessagePayload {
    data: [u8; 64],          // Small messages
    shared_mem: SharedMemRef, // Larger messages via shared memory
}

/// Shared memory reference
#[repr(C)]
pub struct SharedMemRef {
    addr: *mut u8,
    size: usize,
}

/// Message queue implementation
pub struct MessageQueue {
    messages: Vec<Message>,
    max_size: usize,
    lock: Mutex<()>,
}

impl MessageQueue {
    /// Create new message queue
    pub const fn new(max_size: usize) -> Self {
        Self {
            messages: Vec::new(),
            max_size,
            lock: Mutex::new(()),
        }
    }

    /// Send message with timeout
    pub fn send(&mut self, msg: Message, timeout_us: u64) -> Result<(), Error> {
        let _guard = self.lock.lock();
        
        if self.messages.len() >= self.max_size {
            return Err(Error::QueueFull);
        }

        // Fast path for small messages
        if msg.payload.size() <= 64 {
            self.messages.push(msg);
            return Ok(());
        }

        // Use shared memory for large messages
        let shared_mem = self.allocate_shared_memory(msg.payload.size())?;
        unsafe {
            core::ptr::copy_nonoverlapping(
                msg.payload.data.as_ptr(),
                shared_mem.addr,
                msg.payload.size(),
            );
        }

        self.messages.push(Message {
            payload: MessagePayload { shared_mem },
            ..msg
        });

        Ok(())
    }

    /// Receive message with timeout
    pub fn receive(&mut self, timeout_us: u64) -> Result<Message, Error> {
        let _guard = self.lock.lock();
        
        match self.messages.pop() {
            Some(msg) => {
                // Clean up shared memory if used
                if let MessagePayload::SharedMemRef(ref mem) = msg.payload {
                    self.deallocate_shared_memory(mem);
                }
                Ok(msg)
            }
            None => Err(Error::NoMessage),
        }
    }

    /// Allocate shared memory for large messages
    fn allocate_shared_memory(&self, size: usize) -> Result<SharedMemRef, Error> {
        // Align size to page boundary
        let aligned_size = (size + 4095) & !4095;
        
        // Allocate memory
        let addr = unsafe {
            alloc::alloc::alloc(
                alloc::alloc::Layout::from_size_align(
                    aligned_size,
                    4096,
                ).unwrap(),
            )
        };

        if addr.is_null() {
            return Err(Error::OutOfMemory);
        }

        Ok(SharedMemRef {
            addr,
            size: aligned_size,
        })
    }

    /// Deallocate shared memory
    fn deallocate_shared_memory(&self, mem: &SharedMemRef) {
        unsafe {
            alloc::alloc::dealloc(
                mem.addr,
                alloc::alloc::Layout::from_size_align(
                    mem.size,
                    4096,
                ).unwrap(),
            );
        }
    }
}

/// Error types for IPC operations
#[derive(Debug)]
pub enum Error {
    QueueFull,
    NoMessage,
    Timeout,
    OutOfMemory,
    InvalidMessage,
}
