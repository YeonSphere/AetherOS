#!/bin/bash
# AetherOS Kernel Build System
# Efficient and automated kernel build process

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
KERNEL_DIR="$SCRIPT_DIR/kernel/linux/linux-6.11.9"
OUTPUT_DIR="$SCRIPT_DIR/output"
INSTALL_DIR="$SCRIPT_DIR/install"
LOG_DIR="$SCRIPT_DIR/logs"
VERSION_FILE="$SCRIPT_DIR/.kernel_version"
PATCH_MANAGER="$SCRIPT_DIR/scripts/patch_manager.sh"

BUILD_LOG="$LOG_DIR/build.log"
ERROR_LOG="$LOG_DIR/error.log"

# Number of CPU cores for parallel build
CORES=$(nproc)

log() {
    local level="$1"
    shift
    echo "[$level] $*" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >> "$BUILD_LOG"
}

error() {
    log "ERROR" "$@"
    exit 1
}

setup_directories() {
    mkdir -p "$BUILD_DIR" "$OUTPUT_DIR" "$INSTALL_DIR" "$LOG_DIR"
    : > "$BUILD_LOG"
    : > "$ERROR_LOG"
}

check_dependencies() {
    local bins=(make gcc g++ flex bison bc rsync cpio)
    local pkgs=(elfutils openssl)
    
    log "INFO" "Checking build dependencies..."
    
    # Check binary dependencies
    for bin in "${bins[@]}"; do
        if ! command -v "$bin" >/dev/null 2>&1; then
            error "Missing binary dependency: $bin"
        fi
    done
    
    # Check package dependencies
    for pkg in "${pkgs[@]}"; do
        if ! pacman -Qi "$pkg" >/dev/null 2>&1; then
            error "Missing package dependency: $pkg"
        fi
    done
}

prepare_kernel() {
    # Try to detect kernel version from directory if version file doesn't exist
    if [ ! -f "$VERSION_FILE" ]; then
        if [ -d "$KERNEL_DIR" ]; then
            local kernel_dir_name=$(basename "$KERNEL_DIR")
            if [[ "$kernel_dir_name" =~ linux-([0-9]+\.[0-9]+\.[0-9]+.*) ]]; then
                echo "${BASH_REMATCH[1]}" > "$VERSION_FILE"
                log "INFO" "Created version file with detected version ${BASH_REMATCH[1]}"
            else
                error "Could not detect kernel version from directory name: $kernel_dir_name"
            fi
        else
            error "Kernel directory not found at $KERNEL_DIR"
        fi
    fi
    
    local version=$(cat "$VERSION_FILE")
    log "INFO" "Preparing kernel version $version"
    
    # Clean the kernel source tree thoroughly
    log "INFO" "Cleaning kernel source tree..."
    make -C "$KERNEL_DIR" mrproper
    
    # Apply any pending patches
    "$PATCH_MANAGER" apply "$KERNEL_DIR" "$version"
    
    # Clean build directory and prepare for new build
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    
    # Copy base config
    if [ -f "$SCRIPT_DIR/kernel/config/minimal.config" ]; then
        cp "$SCRIPT_DIR/kernel/config/minimal.config" "$BUILD_DIR/.config"
    else
        error "Base kernel config not found at $SCRIPT_DIR/kernel/config/minimal.config"
    fi
}

configure_kernel() {
    log "INFO" "Configuring kernel..."
    
    local config_script="$KERNEL_DIR/scripts/config"
    
    # Basic kernel options
    "$config_script" --file "$BUILD_DIR/.config" \
        --set-val LOCALVERSION "-aetheros" \
        --enable MODULES \
        --enable MODVERSIONS \
        --enable MODULE_UNLOAD \
        --enable IKCONFIG \
        --enable IKCONFIG_PROC
    
    # Performance options
    "$config_script" --file "$BUILD_DIR/.config" \
        --enable PREEMPT \
        --set-val HZ 1000 \
        --enable NO_HZ \
        --enable HIGH_RES_TIMERS
    
    # Hardware support (as modules)
    "$config_script" --file "$BUILD_DIR/.config" \
        --module NVME_CORE \
        --module SATA_AHCI \
        --module USB_XHCI_HCD \
        --module USB_EHCI_HCD \
        --module USB_OHCI_HCD \
        --module USB_HID
    
    # Security options
    "$config_script" --file "$BUILD_DIR/.config" \
        --enable SECURITY \
        --enable SECURITY_NETWORK \
        --enable SECCOMP \
        --enable SECCOMP_FILTER
    
    # Update config
    make -C "$KERNEL_DIR" O="$BUILD_DIR" olddefconfig
}

build_kernel() {
    log "INFO" "Building kernel..."
    
    # Build kernel and modules
    if ! make -C "$KERNEL_DIR" O="$BUILD_DIR" -j"$CORES" all; then
        error "Kernel build failed"
    fi
}

install_kernel() {
    log "INFO" "Installing kernel..."
    
    # Install modules
    if ! make -C "$KERNEL_DIR" O="$BUILD_DIR" \
        INSTALL_MOD_PATH="$INSTALL_DIR" modules_install; then
        error "Module installation failed"
    fi
    
    # Install kernel
    cp "$BUILD_DIR/arch/x86/boot/bzImage" "$OUTPUT_DIR/vmlinuz"
    cp "$BUILD_DIR/System.map" "$OUTPUT_DIR/"
    cp "$BUILD_DIR/.config" "$OUTPUT_DIR/config"
    
    # Install hardware detection scripts
    install -Dm755 "$SCRIPT_DIR/scripts/boot_hardware_detect.sh" \
        "$INSTALL_DIR/usr/lib/aetheros/boot_hardware_detect.sh"
    install -Dm755 "$SCRIPT_DIR/scripts/install_hardware_detect.sh" \
        "$INSTALL_DIR/usr/lib/aetheros/install_hardware_detect.sh"
    
    # Install systemd service
    install -Dm644 "$SCRIPT_DIR/scripts/aetheros-hw-boot.service" \
        "$INSTALL_DIR/etc/systemd/system/aetheros-hw-boot.service"
}

create_package() {
    log "INFO" "Creating kernel package..."
    
    local version=$(cat "$VERSION_FILE")
    local package="$OUTPUT_DIR/linux-aether-$version.tar.xz"
    
    # Create package with xz compression for better compression ratio
    tar -cJf "$package" -C "$INSTALL_DIR" .
    
    log "INFO" "Package created: $package"
    log "INFO" "Kernel version: $version"
}

main() {
    log "INFO" "Starting AetherOS kernel build"
    
    setup_directories
    check_dependencies
    prepare_kernel
    configure_kernel
    build_kernel
    install_kernel
    create_package
    
    log "INFO" "Build completed successfully"
}

main "$@"
