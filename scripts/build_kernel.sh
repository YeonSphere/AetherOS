#!/bin/bash

# AetherOS Kernel Build System
# This script handles kernel building and local installation

set -euo pipefail

# Basic configuration
KERNEL_VERSION="6.11.9"  # Using the version we have
KERNEL_SOURCE_DIR="/home/dae/YeonSphere/AetherOS/kernel/linux/linux-${KERNEL_VERSION}"
BUILD_DIR="/home/dae/YeonSphere/AetherOS/build"
BOOT_DIR="/home/dae/YeonSphere/AetherOS/boot"
CONFIG_DIR="/home/dae/YeonSphere/AetherOS/configs"
JOBS=$(nproc)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    echo -e "${GREEN}[${level}]${NC} $message"
}

# Error handling
error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    exit 1
}

# Function to configure kernel
configure_kernel() {
    log "INFO" "Configuring kernel..."
    
    cd "$KERNEL_SOURCE_DIR" || error "Failed to change to kernel source directory"
    
    # Start with a clean slate
    make mrproper
    
    # Copy our config
    cp "$CONFIG_DIR/kernel.config" .config || error "Failed to copy kernel config"
    
    # Make sure configuration is valid
    make olddefconfig || error "Failed to validate kernel config"
}

# Function to build kernel
build_kernel() {
    log "INFO" "Building kernel..."
    
    cd "$KERNEL_SOURCE_DIR" || error "Failed to change to kernel source directory"
    
    # Clean build artifacts
    make clean
    
    # Build kernel and modules
    make -j"$JOBS" all || error "Kernel build failed"
    
    # Build modules
    make -j"$JOBS" modules || error "Module build failed"
}

# Function to install kernel to build directory
install_kernel() {
    log "INFO" "Installing kernel to build directory..."
    
    cd "$KERNEL_SOURCE_DIR" || error "Failed to change to kernel source directory"
    
    # Create target directories
    mkdir -p "$BUILD_DIR/boot" || error "Failed to create boot directory"
    mkdir -p "$BUILD_DIR/lib/modules" || error "Failed to create modules directory"
    
    # Install modules to build directory
    make INSTALL_MOD_PATH="$BUILD_DIR" modules_install || error "Module installation failed"
    
    # Copy kernel
    cp "arch/x86/boot/bzImage" "$BUILD_DIR/boot/vmlinuz-${KERNEL_VERSION}-aetheros" || error "Failed to copy kernel image"
    
    log "INFO" "Kernel installed to $BUILD_DIR/boot/vmlinuz-${KERNEL_VERSION}-aetheros"
}

# Main function
main() {
    log "INFO" "Starting AetherOS kernel build process..."
    
    # Create build directory
    mkdir -p "$BUILD_DIR" || error "Failed to create build directory"
    
    # Configure kernel
    configure_kernel
    
    # Build kernel
    build_kernel
    
    # Install kernel to build directory
    install_kernel
    
    log "INFO" "Kernel build process completed successfully"
    log "INFO" "Kernel image: $BUILD_DIR/boot/vmlinuz-${KERNEL_VERSION}-aetheros"
    log "INFO" "Note: To install the kernel system-wide, you will need to manually copy the kernel and modules with root privileges"
}

# Run main function
main "$@"
