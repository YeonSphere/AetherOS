#!/bin/bash

set -euo pipefail

# First ensure we have all dependencies
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
if [ ! -x "${SCRIPT_DIR}/install_deps.sh" ]; then
    chmod +x "${SCRIPT_DIR}/install_deps.sh"
fi

"${SCRIPT_DIR}/install_deps.sh"

export AETHER_ROOT="/home/dae/YeonSphere/AetherOS"
export BUILD_ROOT="${AETHER_ROOT}/build"
export SCRIPTS_DIR="${AETHER_ROOT}/scripts"
export LOGS_DIR="${AETHER_ROOT}/logs"

# Export resource limits so child scripts can use them
export cpu_limit=$(( $(nproc) * 80 / 100 ))
export mem_limit=$(free -m | awk '/^Mem:/{print int($2*0.8)}')
export FORCE_REBUILD=1  # Force rebuild by default
export KERNEL_VERSION="6.11.9"
export BUSYBOX_VERSION="1.36.1"
export ISO_NAME="aetheros-${KERNEL_VERSION}"

source "${SCRIPTS_DIR}/common.sh"

mkdir -p "${LOGS_DIR}"
BUILD_LOG="${LOGS_DIR}/build_$(date +%Y%m%d).log"
KERNEL_LOG="${LOGS_DIR}/kernel_build.log"
MUSL_LOG="${LOGS_DIR}/musl_build.log"
BUSYBOX_LOG="${LOGS_DIR}/busybox_build.log"
INITRAMFS_LOG="${LOGS_DIR}/initramfs_build.log"
ISO_LOG="${LOGS_DIR}/iso_build.log"

rm -f "${LOGS_DIR}/build_*.log"

log_msg() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] $1" | tee -a "${BUILD_LOG}"
}

error_exit() {
    log_msg "ERROR: $1"
    log_msg "Check ${BUILD_LOG} for details (lines ${BASH_LINENO[0]}-EOF)"
    exit 1
}

check_basic_requirements() {
    log_msg "Checking basic requirements..."
    # We don't need to check for commands here anymore as install_deps.sh handles it
    
    # Check for root privileges for device nodes
    if [ "$EUID" -ne 0 ]; then
        error_exit "This script must be run as root for creating device nodes"
    fi
}

init_env() {
    log_msg "Initializing build environment..."
    ensure_dir "${BUILD_ROOT}" || error_exit "Failed to create BUILD_ROOT"
    ensure_dir "${BUILD_ROOT}/kernel" || error_exit "Failed to create kernel directory"
    ensure_dir "${BUILD_ROOT}/boot" || error_exit "Failed to create boot directory"
    ensure_dir "${BUILD_ROOT}/initramfs" || error_exit "Failed to create initramfs directory"
    ensure_dir "${BUILD_ROOT}/iso" || error_exit "Failed to create iso directory"
    ensure_dir "${BUILD_ROOT}/sysroot" || error_exit "Failed to create sysroot directory"
    ensure_dir "${LOGS_DIR}" || error_exit "Failed to create logs directory"
    
    local kernel_src="${AETHER_ROOT}/kernel/linux/linux-${KERNEL_VERSION}"
    if [ ! -d "${kernel_src}" ]; then
        error_exit "Kernel source not found at ${kernel_src}"
    fi
}

cleanup() {
    log_msg "Cleaning up old builds..."
    if [ -d "${BUILD_ROOT}" ]; then
        log_msg "Cleaning build directory..."
        rm -rf "${BUILD_ROOT}"/* || error_exit "Failed to clean BUILD_ROOT"
    fi
    log_msg "Cleanup completed"
}

build_kernel() {
    log_msg "Building kernel..."
    if ! systemd-run --user --scope -p CPUQuota=${cpu_limit}% -p MemoryMax=${mem_limit}M \
            "${SCRIPTS_DIR}/build_kernel.sh" 2>&1 | tee "${KERNEL_LOG}"; then
        error_exit "Kernel build failed. Check ${KERNEL_LOG} for details"
    fi
    log_msg "Kernel build completed successfully"
}

build_musl() {
    log_msg "Building musl..."
    if ! systemd-run --user --scope -p CPUQuota=${cpu_limit}% -p MemoryMax=${mem_limit}M \
            "${SCRIPTS_DIR}/build_musl.sh" 2>&1 | tee "${MUSL_LOG}"; then
        error_exit "musl build failed. Check ${MUSL_LOG} for details"
    fi
    log_msg "musl build completed successfully"
}

build_busybox() {
    log_msg "Building busybox..."
    if ! systemd-run --user --scope -p CPUQuota=${cpu_limit}% -p MemoryMax=${mem_limit}M \
            "${SCRIPTS_DIR}/build_busybox.sh" 2>&1 | tee "${BUSYBOX_LOG}"; then
        error_exit "busybox build failed. Check ${BUSYBOX_LOG} for details"
    fi
    log_msg "busybox build completed successfully"
}

build_initramfs() {
    log_msg "Building initramfs..."
    if ! systemd-run --user --scope -p CPUQuota=${cpu_limit}% -p MemoryMax=${mem_limit}M \
            "${SCRIPTS_DIR}/build_initramfs.sh" 2>&1 | tee "${INITRAMFS_LOG}"; then
        error_exit "initramfs build failed. Check ${INITRAMFS_LOG} for details"
    fi
    log_msg "initramfs build completed successfully"
}

build_iso() {
    log_msg "Building ISO..."
    if ! systemd-run --user --scope -p CPUQuota=${cpu_limit}% -p MemoryMax=${mem_limit}M \
            "${SCRIPTS_DIR}/build_iso.sh" 2>&1 | tee "${ISO_LOG}"; then
        error_exit "ISO build failed. Check ${ISO_LOG} for details"
    fi
    log_msg "ISO build completed successfully at ${BUILD_ROOT}/iso/${ISO_NAME}.iso"
}

main() {
    cd "${SCRIPTS_DIR}" || error_exit "Could not change to scripts directory at ${SCRIPTS_DIR}"

    log_msg "Starting AetherOS build..."

    # First check basic requirements and environment
    check_basic_requirements
    check_system || error_exit "System requirements check failed"
    check_build_env || error_exit "Build environment check failed"

    # Initialize and clean
    init_env
    cleanup

    # Build components in order:
    # 1. Kernel (needed for modules in initramfs)
    # 2. musl (needed for busybox)
    # 3. busybox (needed for initramfs)
    # 4. initramfs (needed for ISO)
    # 5. ISO (final product)
    build_kernel
    build_musl
    build_busybox
    build_initramfs
    build_iso

    log_msg "Build completed successfully!"
    log_msg "ISO image is available at: ${BUILD_ROOT}/iso/${ISO_NAME}.iso"
}

main "$@"
