#!/bin/bash
# AetherOS ISO Builder Script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
ROOTFS_DIR="$BUILD_DIR/rootfs"
ISO_DIR="$BUILD_DIR/iso"
OUTPUT_DIR="$SCRIPT_DIR/output"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/build_iso.log"
VERSION_FILE="$SCRIPT_DIR/version"

# Source common functions
source "$SCRIPT_DIR/scripts/common.sh"

# Ensure directories exist
mkdir -p "$LOG_DIR" "$OUTPUT_DIR"

# Redirect all output to log file while still showing important messages
exec 3>&1 4>&2
exec 1>"$LOG_FILE" 2>&1

# Function to show progress while logging details
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $level: $message"
    echo "[$level] $message" >&3
}

cleanup() {
    # Restore original stdout/stderr
    exec 1>&3 2>&4
}
trap cleanup EXIT

setup_iso_directories() {
    log "INFO" "Setting up ISO directories..."
    # Clean existing directories
    rm -rf "$ISO_DIR" "$ROOTFS_DIR"
    mkdir -p "$ISO_DIR" "$ROOTFS_DIR"
}

build_rootfs() {
    log "INFO" "Building minimal installer environment..."
    
    # Ensure rootfs is clean
    if [ -d "$ROOTFS_DIR" ] && [ -n "$(ls -A "$ROOTFS_DIR")" ]; then
        log "INFO" "Cleaning existing rootfs..."
        rm -rf "${ROOTFS_DIR:?}"/*
    fi
    
    # Create basic directory structure
    mkdir -p "$ROOTFS_DIR"/{bin,sbin,lib,lib64,usr/{bin,sbin,lib,lib64},etc,proc,sys,dev,tmp,run}
    
    # Download and build busybox if not already done
    BUSYBOX_VERSION="1.36.1"
    BUSYBOX_DIR="$BUILD_DIR/busybox/busybox-$BUSYBOX_VERSION"
    
    if [ ! -f "$BUSYBOX_DIR/busybox" ]; then
        log "INFO" "Downloading busybox..."
        mkdir -p "$BUILD_DIR/busybox"
        cd "$BUILD_DIR/busybox"
        
        if [ ! -f "busybox-$BUSYBOX_VERSION.tar.bz2" ]; then
            wget "https://busybox.net/downloads/busybox-$BUSYBOX_VERSION.tar.bz2" >> "$LOG_FILE" 2>&1
        fi
        
        if [ ! -d "busybox-$BUSYBOX_VERSION" ]; then
            tar xjf "busybox-$BUSYBOX_VERSION.tar.bz2" >> "$LOG_FILE" 2>&1
        fi
        
        cd "busybox-$BUSYBOX_VERSION"
        
        log "INFO" "Building busybox..."
        # Use our custom config
        cp "$SCRIPT_DIR/configs/busybox.config" .config
        yes "" | make oldconfig >> "$LOG_FILE" 2>&1
        make -j$(nproc) >> "$LOG_FILE" 2>&1
    fi
    
    cp "$BUSYBOX_DIR/busybox" "$ROOTFS_DIR/bin/"
    
    # Create basic busybox symlinks
    cd "$ROOTFS_DIR"
    ./bin/busybox --install -s bin
    
    # Copy installer scripts and tools
    mkdir -p "$ROOTFS_DIR/usr/bin"
    cp "$SCRIPT_DIR/scripts/installer.sh" "$ROOTFS_DIR/usr/bin/"
    chmod +x "$ROOTFS_DIR/usr/bin/installer.sh"
    
    # Copy necessary system configuration
    mkdir -p "$ROOTFS_DIR/etc"
    cp "$SCRIPT_DIR/configs/installer/inittab" "$ROOTFS_DIR/etc/"
    cp "$SCRIPT_DIR/configs/installer/init" "$ROOTFS_DIR/init"
    chmod +x "$ROOTFS_DIR/init"
    
    cd "$SCRIPT_DIR"  # Return to original directory
}

install_kernel() {
    log "INFO" "Installing kernel to ISO..."
    local version=$(cat "$VERSION_FILE")
    local kernel_package="$OUTPUT_DIR/linux-aether-$version.tar.xz"

    if [ ! -f "$kernel_package" ]; then
        error "Kernel package not found. Please build the kernel first."
    fi

    # Extract kernel to ISO directory
    tar xf "$kernel_package" -C "$ISO_DIR"
}

configure_bootloader() {
    log "INFO" "Configuring bootloader..."
    
    # Create GRUB config
    cat > "$ISO_DIR/boot/grub/grub.cfg" << EOF
set default=0
set timeout=5

menuentry "Install AetherOS" {
    linux /boot/vmlinuz quiet
    initrd /boot/initrd.img
}

menuentry "Install AetherOS (Debug Mode)" {
    linux /boot/vmlinuz debug
    initrd /boot/initrd.img
}
EOF
    
    # Install GRUB EFI
    grub-install --target=x86_64-efi \
        --efi-directory="$ISO_DIR" \
        --boot-directory="$ISO_DIR/boot" \
        --removable \
        --recheck

    # Install GRUB BIOS
    grub-install --target=i386-pc \
        --boot-directory="$ISO_DIR/boot" \
        --recheck \
        "$ISO_DIR/boot/grub/bios.img"
}

create_iso() {
    log "INFO" "Creating installer ISO..."
    local version=$(cat "$VERSION_FILE")
    local iso_file="$OUTPUT_DIR/aetheros-installer-$version.iso"

    # Create ISO image
    xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid "AETHEROS_INSTALLER" \
        -eltorito-boot boot/grub/bios.img \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --eltorito-catalog boot/grub/boot.cat \
        --grub2-boot-info \
        --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
        -eltorito-alt-boot \
        -e EFI/efiboot.img \
        -no-emul-boot \
        -append_partition 2 0xef ${ISO_DIR}/EFI/efiboot.img \
        -output "$iso_file" \
        -graft-points \
        "$ISO_DIR" \
        /boot/grub/bios.img=isolinux/bios.img \
        /EFI/efiboot.img=isolinux/efiboot.img \
        /boot/grub/grub.cfg=isolinux/grub.cfg \
        /EFI="$ISO_DIR/EFI"

    log "INFO" "ISO created: $iso_file"
}

main() {
    log "INFO" "Starting AetherOS installer ISO build"
    
    # Build kernel first if not already built
    if [ ! -f "$OUTPUT_DIR/linux-aether-$(cat "$VERSION_FILE").tar.xz" ]; then
        log "INFO" "Building kernel first..."
        "$SCRIPT_DIR/build.sh"
    fi
    
    setup_iso_directories
    build_rootfs
    install_kernel
    configure_bootloader
    create_iso
    
    log "INFO" "Installer ISO build completed successfully"
}

main "$@"
