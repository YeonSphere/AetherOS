//! AetherOS Capability System
//! Secure, fine-grained access control

use alloc::vec::Vec;
use core::sync::atomic::{AtomicU64, Ordering};
use spin::RwLock;

/// Capability types
#[derive(Debug, Clone, Copy, PartialEq)]
#[repr(u8)]
pub enum CapabilityType {
    Memory,         // Memory access
    IO,            // I/O operations
    IPC,           // IPC operations
    Process,       // Process management
    Device,        // Device access
    Network,       // Network operations
    FileSystem,    // File system access
    System,        // System operations
}

/// Capability rights
#[derive(Debug, Clone, Copy)]
pub struct CapabilityRights {
    read: bool,
    write: bool,
    execute: bool,
    grant: bool,    // Can grant to others
    revoke: bool,   // Can revoke from others
}

/// Capability identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct CapabilityId(u64);

/// Capability structure
#[repr(C)]
pub struct Capability {
    id: CapabilityId,
    typ: CapabilityType,
    rights: CapabilityRights,
    resource: ResourceId,
    owner: TaskId,
}

/// Capability space for a task
pub struct CapabilitySpace {
    capabilities: Vec<Capability>,
    lock: RwLock<()>,
}

impl CapabilitySpace {
    /// Create new capability space
    pub fn new() -> Self {
        Self {
            capabilities: Vec::new(),
            lock: RwLock::new(()),
        }
    }

    /// Grant a capability
    pub fn grant(&mut self, cap: Capability) -> Result<(), Error> {
        let _guard = self.lock.write();
        
        // Check if we have the right to grant
        if !self.can_grant(&cap) {
            return Err(Error::InsufficientRights);
        }

        // Check resource limits
        if !self.check_resource_limits(&cap) {
            return Err(Error::ResourceLimitExceeded);
        }

        // Add capability
        self.capabilities.push(cap);
        Ok(())
    }

    /// Revoke a capability
    pub fn revoke(&mut self, cap_id: CapabilityId) -> Result<(), Error> {
        let _guard = self.lock.write();
        
        // Find and remove capability
        if let Some(pos) = self.capabilities.iter().position(|c| c.id == cap_id) {
            if !self.can_revoke(&self.capabilities[pos]) {
                return Err(Error::InsufficientRights);
            }
            self.capabilities.remove(pos);
            Ok(())
        } else {
            Err(Error::CapabilityNotFound)
        }
    }

    /// Check if we have a capability
    pub fn check(&self, typ: CapabilityType, rights: CapabilityRights) -> bool {
        let _guard = self.lock.read();
        
        self.capabilities.iter().any(|cap| {
            cap.typ == typ && 
            cap.rights.read >= rights.read &&
            cap.rights.write >= rights.write &&
            cap.rights.execute >= rights.execute
        })
    }

    /// Derive a new capability with reduced rights
    pub fn derive(&self, cap_id: CapabilityId, new_rights: CapabilityRights) 
        -> Result<Capability, Error> 
    {
        let _guard = self.lock.read();
        
        if let Some(cap) = self.capabilities.iter().find(|c| c.id == cap_id) {
            // Check if new rights are subset of original
            if !self.rights_are_subset(&new_rights, &cap.rights) {
                return Err(Error::InsufficientRights);
            }

            Ok(Capability {
                id: CapabilityId(generate_id()),
                typ: cap.typ,
                rights: new_rights,
                resource: cap.resource,
                owner: cap.owner,
            })
        } else {
            Err(Error::CapabilityNotFound)
        }
    }

    // Helper functions
    fn can_grant(&self, cap: &Capability) -> bool {
        self.capabilities.iter().any(|c| {
            c.typ == cap.typ && 
            c.rights.grant &&
            self.rights_are_subset(&cap.rights, &c.rights)
        })
    }

    fn can_revoke(&self, cap: &Capability) -> bool {
        self.capabilities.iter().any(|c| {
            c.typ == cap.typ && 
            c.rights.revoke &&
            c.resource == cap.resource
        })
    }

    fn rights_are_subset(&self, subset: &CapabilityRights, superset: &CapabilityRights) -> bool {
        (!subset.read || superset.read) &&
        (!subset.write || superset.write) &&
        (!subset.execute || superset.execute) &&
        (!subset.grant || superset.grant) &&
        (!subset.revoke || superset.revoke)
    }

    fn check_resource_limits(&self, cap: &Capability) -> bool {
        // Implement resource limit checking
        true // Placeholder
    }
}

/// Generate unique capability ID
fn generate_id() -> u64 {
    static NEXT_ID: AtomicU64 = AtomicU64::new(1);
    NEXT_ID.fetch_add(1, Ordering::SeqCst)
}

/// Error types for capability operations
#[derive(Debug)]
pub enum Error {
    InsufficientRights,
    CapabilityNotFound,
    ResourceLimitExceeded,
    InvalidCapability,
}
