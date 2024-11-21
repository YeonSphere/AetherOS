#!/bin/bash

# AetherOS Master Build Script
# This script orchestrates the entire build process for AetherOS

set -euo pipefail

# Source common functions and variables
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/common.sh"

# Build configuration
export AETHER_VERSION="0.1.0"
export BUILD_TYPE="${BUILD_TYPE:-release}"  # release or debug
export PARALLEL_JOBS="$(nproc)"
export CPU_LIMIT="$(( $(nproc) * 80 / 100 ))"  # 80% of CPU
export MEM_LIMIT="$(free -m | awk '/^Mem:/{print int($2*0.8)}')"  # 80% of RAM

# Component versions
export KERNEL_VERSION="6.11.9"
export BUSYBOX_VERSION="1.36.1"
export MUSL_VERSION="1.2.4"

# Target architecture and system
export TARGET="x86_64-aetheros-linux-musl"
export TARGET_ARCH="x86_64"
export TARGET_VENDOR="aetheros"
export TARGET_OS="linux"
export TARGET_LIBC="musl"

# Build stages
declare -A BUILD_STAGES=(
    [1]="setup"
    [2]="musl"    # Build musl first as it's needed for other components
    [3]="busybox" # Build busybox before initramfs
    [4]="kernel"  # Build kernel with initramfs
    [5]="iso"     # Create final ISO
)

# Build flags
declare -A BUILD_FLAGS=(
    [FORCE_REBUILD]=${FORCE_REBUILD:-0}
    [SKIP_TESTS]=${SKIP_TESTS:-0}
    [DEBUG_BUILD]=${DEBUG_BUILD:-0}
    [VERBOSE]=${VERBOSE:-1}
)

# Export common paths
export BUILD_ROOT="${AETHER_ROOT}/build"
export SYSROOT="${BUILD_ROOT}/sysroot"
export TOOLS_DIR="${BUILD_ROOT}/tools"
export INITRAMFS_ROOT="${BUILD_ROOT}/initramfs"
export INITRAMFS_CPIO="${BUILD_ROOT}/initramfs.cpio.gz"
export ISO_DIR="${BUILD_ROOT}/iso"

# Log files
setup_logging() {
    export LOGS_DIR="${AETHER_ROOT}/logs"
    mkdir -p "${LOGS_DIR}"
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    export MAIN_LOG="${LOGS_DIR}/build_${timestamp}.log"
    export ERROR_LOG="${LOGS_DIR}/errors_${timestamp}.log"
    
    # Component-specific logs
    export SETUP_LOG="${LOGS_DIR}/setup_${timestamp}.log"
    export KERNEL_LOG="${LOGS_DIR}/kernel_${timestamp}.log"
    export MUSL_LOG="${LOGS_DIR}/musl_${timestamp}.log"
    export BUSYBOX_LOG="${LOGS_DIR}/busybox_${timestamp}.log"
    export ISO_LOG="${LOGS_DIR}/iso_${timestamp}.log"
    
    # Start logging
    exec 1> >(tee -a "${MAIN_LOG}")
    exec 2> >(tee -a "${ERROR_LOG}" >&2)
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    log ERROR "Error occurred in ${BASH_SOURCE[1]} at line ${line_number}, exit code ${exit_code}"
    
    # Collect system information for debugging
    {
        echo "=== System Information ==="
        uname -a
        free -h
        df -h
        echo "=== Environment Variables ==="
        env | sort
        echo "=== Last 50 lines of logs ==="
        tail -n 50 "${MAIN_LOG}"
        echo "=== Error details ==="
        tail -n 20 "${ERROR_LOG}"
    } >> "${ERROR_LOG}"
    
    cleanup
    exit ${exit_code}
}

trap 'handle_error ${LINENO}' ERR

# Stage functions
stage_setup() {
    log INFO "Setting up build environment"
    
    # Check build environment first
    if ! check_build_env; then
        log ERROR "Build environment check failed"
        return 1
    fi
    
    # Detect package manager and install dependencies
    "${SCRIPT_DIR}/setup_deps.sh"
    local deps_status=$?
    if [ ${deps_status} -ne 0 ]; then
        log ERROR "Failed to set up dependencies"
        return 1
    fi
    
    # Create build directories
    local dirs=(
        "${BUILD_ROOT}"
        "${SYSROOT}"
        "${TOOLS_DIR}"
        "${INITRAMFS_ROOT}"
        "${ISO_DIR}"
        "${LOGS_DIR}"
        "${BUILD_ROOT}/boot"
    )
    
    for dir in "${dirs[@]}"; do
        ensure_dir "${dir}"
    done
    
    # Create target sysroot structure
    local sysroot_dirs=(
        "bin" "sbin" "lib" "lib64"
        "usr/bin" "usr/sbin" "usr/lib" "usr/lib64"
        "usr/include" "usr/share"
        "var/log" "var/tmp"
        "etc" "proc" "sys" "dev" "tmp"
    )
    
    for dir in "${sysroot_dirs[@]}"; do
        ensure_dir "${SYSROOT}/${dir}"
    done
    
    log INFO "Build environment setup completed successfully"
    return 0
}

stage_musl() {
    log INFO "Building musl libc ${MUSL_VERSION}"
    
    # Set resource limits using ulimit
    ulimit -u ${CPU_LIMIT} || log WARN "Failed to set CPU limit"
    ulimit -m ${MEM_LIMIT} || log WARN "Failed to set memory limit"
    
    if ! "${SCRIPT_DIR}/build_musl.sh"; then
        log ERROR "musl build failed"
        return 1
    fi
}

stage_busybox() {
    log INFO "Building Busybox ${BUSYBOX_VERSION}"
    
    # Set resource limits using ulimit
    ulimit -u ${CPU_LIMIT} || log WARN "Failed to set CPU limit"
    ulimit -m ${MEM_LIMIT} || log WARN "Failed to set memory limit"
    
    if ! "${SCRIPT_DIR}/build_busybox.sh"; then
        log ERROR "Busybox build failed"
        return 1
    fi
}

stage_kernel() {
    log INFO "Building Linux kernel ${KERNEL_VERSION}"
    
    # Ensure initramfs components are ready
    if [ ! -x "${SYSROOT}/bin/busybox" ]; then
        log ERROR "Busybox not found in sysroot. Build busybox first."
        return 1
    fi
    
    # Set resource limits using ulimit
    ulimit -u ${CPU_LIMIT} || log WARN "Failed to set CPU limit"
    ulimit -m ${MEM_LIMIT} || log WARN "Failed to set memory limit"
    
    if ! "${SCRIPT_DIR}/build_kernel.sh"; then
        log ERROR "Kernel build failed"
        return 1
    fi
}

stage_iso() {
    log INFO "Building ISO image"
    
    # Check for required files
    if [ ! -f "${BUILD_ROOT}/boot/vmlinuz" ]; then
        log ERROR "Kernel image not found"
        return 1
    fi
    
    # Set resource limits using ulimit
    ulimit -u ${CPU_LIMIT} || log WARN "Failed to set CPU limit"
    ulimit -m ${MEM_LIMIT} || log WARN "Failed to set memory limit"
    
    if ! "${SCRIPT_DIR}/build_iso.sh"; then
        log ERROR "ISO build failed"
        return 1
    fi
}

cleanup() {
    log INFO "Performing cleanup"
    
    # Save logs on failure
    if [ $? -ne 0 ]; then
        local failure_dir="${LOGS_DIR}/failures/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "${failure_dir}"
        cp "${LOGS_DIR}"/*.log "${failure_dir}/"
        log WARN "Build failed. Logs saved to ${failure_dir}"
    fi
    
    # Remove temporary files
    if [ "${BUILD_FLAGS[DEBUG_BUILD]}" -eq 0 ]; then
        rm -rf "${BUILD_ROOT}/tmp"
    fi
}

# Progress tracking
update_progress() {
    local stage=$1
    local total=${#BUILD_STAGES[@]}
    local percentage=$(( (stage * 100) / total ))
    log INFO "Build progress: ${percentage}% (Stage ${stage}/${total})"
}

# Main build process
main() {
    local start_time=$(date +%s)
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force-rebuild)
                BUILD_FLAGS[FORCE_REBUILD]=1
                shift
                ;;
            --skip-tests)
                BUILD_FLAGS[SKIP_TESTS]=1
                shift
                ;;
            --debug)
                BUILD_FLAGS[DEBUG_BUILD]=1
                shift
                ;;
            --verbose)
                BUILD_FLAGS[VERBOSE]=2
                shift
                ;;
            *)
                log ERROR "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Initialize logging
    setup_logging
    
    log INFO "Starting AetherOS build v${AETHER_VERSION}"
    log INFO "Build type: ${BUILD_TYPE}"
    log INFO "Target: ${TARGET}"
    
    # Run each stage in order
    for stage in $(seq 1 ${#BUILD_STAGES[@]}); do
        local stage_name="${BUILD_STAGES[$stage]}"
        local stage_func="stage_${stage_name}"
        
        log INFO "Starting stage ${stage}/${#BUILD_STAGES[@]}: ${stage_name}"
        update_progress "${stage}"
        
        if ! ${stage_func}; then
            log ERROR "Stage ${stage_name} failed"
            exit 1
        fi
        
        log INFO "Completed stage ${stage}/${#BUILD_STAGES[@]}: ${stage_name}"
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log INFO "Build completed successfully in ${duration} seconds"
    log INFO "ISO image available at: ${ISO_DIR}/aetheros-${AETHER_VERSION}.iso"
    
    cleanup
}

# Run the build process
main "$@"
