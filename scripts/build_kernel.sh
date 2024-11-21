#!/bin/bash

set -euo pipefail

# Use AETHER_ROOT consistently
if [ -z "${AETHER_ROOT:-}" ]; then
    export AETHER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Source common functions and variables
source "${AETHER_ROOT}/scripts/common.sh"

KERNEL_VERSION="6.11.9"
KERNEL_SRC="${AETHER_ROOT}/kernel/linux/linux-${KERNEL_VERSION}"
KERNEL_CONFIG="${AETHER_ROOT}/configs/kernel.config"
KERNEL_BUILD_MARKER="${BUILD_ROOT}/.kernel_built"

log_msg() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] $1" | tee -a "${KERNEL_LOG}"
}

# Check if kernel is already built and up to date
check_kernel_built() {
    # Skip the check if FORCE_REBUILD is set
    if [ "${FORCE_REBUILD:-0}" = "1" ]; then
        return 1
    fi
    
    if [ -f "${KERNEL_BUILD_MARKER}" ]; then
        local built_version=$(cat "${KERNEL_BUILD_MARKER}")
        if [ "${built_version}" = "${KERNEL_VERSION}" ]; then
            return 0
        fi
    fi
    return 1
}

# Copy and verify kernel config
setup_kernel_config() {
    log_msg "Setting up kernel configuration..."
    
    # Always copy a fresh config
    cp "${KERNEL_CONFIG}" "${KERNEL_SRC}/.config" || {
        log_msg "ERROR: Failed to copy kernel config"
        return 1
    }
    
    # Verify config
    cd "${KERNEL_SRC}"
    make olddefconfig || {
        log_msg "ERROR: Failed to verify kernel config"
        return 1
    }
    
    return 0
}

# Verify scheduler configuration
verify_scheduler_config() {
    log_msg "Verifying scheduler configuration..."
    cd "${KERNEL_SRC}"
    
    # Check if CFS Rusty is enabled in the final config
    if ! grep -q "CONFIG_SCHED_RUSTY=y" .config; then
        log_msg "ERROR: CFS Rusty scheduler not enabled in final config"
        return 1
    fi
    
    # Verify priority settings
    if ! grep -q "CONFIG_SCHED_RUSTY_LOCAL_PRIO=5" .config || \
       ! grep -q "CONFIG_SCHED_RUSTY_GLOBAL_PRIO=5" .config; then
        log_msg "ERROR: CFS Rusty priority settings not correctly set"
        return 1
    fi
    
    log_msg "Scheduler configuration verified successfully"
    return 0
}

# Build kernel and modules
build_kernel_full() {
    cd "${KERNEL_SRC}"
    
    # Use parent's CPU limit or default to number of cores
    local jobs="${cpu_limit:-$(nproc)}"
    
    log_msg "Building kernel with $jobs parallel jobs..."
    make -j"${jobs}" || {
        log_msg "ERROR: Kernel build failed"
        return 1
    }
    
    log_msg "Building kernel modules..."
    make modules -j"${jobs}" || {
        log_msg "ERROR: Kernel modules build failed"
        return 1
    }
    
    log_msg "Installing kernel modules..."
    make INSTALL_MOD_PATH="${BUILD_ROOT}/sysroot" modules_install || {
        log_msg "ERROR: Kernel module installation failed"
        return 1
    }
    
    # Create boot directory if it doesn't exist
    mkdir -p "${BUILD_ROOT}/boot"
    
    # Copy kernel to boot directory
    cp arch/x86/boot/bzImage "${BUILD_ROOT}/boot/vmlinuz" || {
        log_msg "ERROR: Failed to copy kernel image"
        return 1
    }
    
    # Create build marker
    echo "${KERNEL_VERSION}" > "${KERNEL_BUILD_MARKER}"
    
    return 0
}

# Main build process
main() {
    # Ensure source exists
    if [ ! -d "${KERNEL_SRC}" ]; then
        log_msg "ERROR: Kernel source not found at ${KERNEL_SRC}"
        exit 1
    }
    
    if check_kernel_built; then
        log_msg "Kernel already built, skipping build process"
        return 0
    fi
    
    setup_kernel_config || exit 1
    verify_scheduler_config || exit 1
    build_kernel_full || exit 1
    
    log_msg "Kernel build completed successfully"
}

main "$@"
