#!/bin/bash
# AetherOS ISO Builder Script

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
ROOTFS_DIR="$BUILD_DIR/rootfs"
INITRAMFS_DIR="$BUILD_DIR/initramfs"
INSTALLER_DIR="$BUILD_DIR/installer"
ISO_DIR="$BUILD_DIR/iso"
OUTPUT_DIR="$SCRIPT_DIR/output"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/build_iso.log"
VERSION_FILE="$SCRIPT_DIR/version"

# Build stages
declare -A STAGES=(
    ["kernel"]=1
    ["busybox"]=2
    ["initramfs"]=3
    ["installer"]=4
    ["bootloader"]=5
    ["rootfs"]=6
    ["iso"]=7
)

# Default values
START_STAGE="kernel"
VERBOSE=0

# Help message
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Build the AetherOS installer ISO"
    echo
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -v, --verbose           Enable verbose output"
    echo "  -s, --stage STAGE       Start from specific stage (kernel|busybox|initramfs|installer|bootloader|rootfs|iso)"
    echo
    echo "Stages:"
    echo "  kernel     - Build the Linux kernel"
    echo "  busybox    - Build BusyBox"
    echo "  initramfs  - Create initial ramdisk"
    echo "  installer  - Build the system installer"
    echo "  bootloader - Configure bootloader"
    echo "  rootfs     - Create root filesystem"
    echo "  iso        - Generate final ISO"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -s|--stage)
            if [[ -n "${2:-}" ]] && [[ -n "${STAGES[$2]:-}" ]]; then
                START_STAGE="$2"
                shift 2
            else
                echo "Error: Invalid or missing stage argument"
                echo "Valid stages: kernel, busybox, initramfs, installer, bootloader, rootfs, iso"
                exit 1
            fi
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

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
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    if [ "$VERBOSE" -eq 1 ]; then
        tail -n 1 "$LOG_FILE"
    fi
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
        # Use our custom config and force it
        cp "$SCRIPT_DIR/configs/busybox.config" .config
        # Force our configuration without prompting
        make oldconfig KCONFIG_ALLCONFIG="$SCRIPT_DIR/configs/busybox.config" >> "$LOG_FILE" 2>&1
        make -j$(nproc) >> "$LOG_FILE" 2>&1
        make install CONFIG_PREFIX="$ROOTFS_DIR" >> "$LOG_FILE" 2>&1
    fi
    
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

build_initramfs() {
    log "INFO" "Building initramfs..."
    
    # Clean and recreate initramfs directory
    rm -rf "$INITRAMFS_DIR"
    mkdir -p "$INITRAMFS_DIR"/{bin,sbin,dev,etc,lib,lib64,mnt,proc,root,sys,tmp,usr/{bin,sbin,lib,lib64}}
    
    # Copy busybox
    if [ ! -f "$ROOTFS_DIR/bin/busybox" ]; then
        log "ERROR" "BusyBox not found. Please build BusyBox first."
        exit 1
    fi
    cp "$ROOTFS_DIR/bin/busybox" "$INITRAMFS_DIR/bin/"
    
    # Create basic device nodes
    mknod -m 600 "$INITRAMFS_DIR/dev/console" c 5 1
    mknod -m 666 "$INITRAMFS_DIR/dev/null" c 1 3
    mknod -m 666 "$INITRAMFS_DIR/dev/tty" c 5 0
    mknod -m 666 "$INITRAMFS_DIR/dev/tty0" c 4 0
    mknod -m 666 "$INITRAMFS_DIR/dev/tty1" c 4 1
    
    # Install busybox symlinks
    cd "$INITRAMFS_DIR"
    ./bin/busybox --install -s bin
    
    # Copy required kernel modules if any
    if [ -d "$BUILD_DIR/kernel_modules" ]; then
        cp -r "$BUILD_DIR/kernel_modules"/* "$INITRAMFS_DIR/lib/modules/"
    fi
    
    # Create init script
    cat > "$INITRAMFS_DIR/init" << 'EOF'
#!/bin/busybox sh

# Mount essential filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# Create device nodes
mdev -s

# Set up basic environment
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

# Mount root filesystem
mkdir -p /mnt/root
mount -t tmpfs none /mnt/root

# Switch to real init
exec switch_root /mnt/root /sbin/init

# Fallback shell in case of failure
exec /bin/sh
EOF
    
    chmod +x "$INITRAMFS_DIR/init"
    
    # Create the initramfs
    cd "$INITRAMFS_DIR"
    find . | cpio -H newc -o | gzip > "$BUILD_DIR/initramfs.img"
    
    log "INFO" "Initramfs created successfully"
}

build_installer() {
    log "INFO" "Building installer system..."
    
    # Clean and create installer directory
    rm -rf "$INSTALLER_DIR"
    mkdir -p "$INSTALLER_DIR"
    
    # Copy installer scripts and tools
    cp -r "$SCRIPT_DIR/installer/"* "$INSTALLER_DIR/"
    
    # Build installer UI if using dialog/whiptail
    if [ -f "$INSTALLER_DIR/setup.py" ]; then
        cd "$INSTALLER_DIR"
        python3 setup.py build
    fi
    
    # Copy installer to initramfs
    cp -r "$INSTALLER_DIR"/* "$INITRAMFS_DIR/usr/bin/"
    chmod +x "$INITRAMFS_DIR/usr/bin/installer.sh"
    
    # Update init script to launch installer
    cat > "$INITRAMFS_DIR/init" << 'EOF'
#!/bin/busybox sh

# Mount essential filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# Create device nodes
mdev -s

# Set up basic environment
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

# Mount installation media
mkdir -p /run/media
if [ -b /dev/sr0 ]; then
    mount -t iso9660 /dev/sr0 /run/media
elif [ -b /dev/sda ]; then
    mount -t iso9660 /dev/sda /run/media
fi

# Load necessary kernel modules
modprobe loop
modprobe squashfs
modprobe ext4
modprobe vfat

# Set up networking if needed
ip link set dev lo up
udhcpc -i eth0 -n

# Start the installer
if [ -x /usr/bin/installer.sh ]; then
    /usr/bin/installer.sh
else
    echo "Installer not found! Dropping to shell..."
    exec /bin/sh
fi

# Fallback shell
exec /bin/sh
EOF
    
    log "INFO" "Installer system built successfully"
}

configure_bootloader() {
    log "INFO" "Configuring bootloader..."
    
    # Set up GRUB directories
    mkdir -p "$ISO_DIR"/{boot/grub/{i386-pc,x86_64-efi},EFI/BOOT}
    
    # Install GRUB files for BIOS
    grub-mkimage \
        -O i386-pc \
        -o "$ISO_DIR/boot/grub/i386-pc/core.img" \
        -p "(cd0)/boot/grub" \
        biosdisk iso9660 linux normal configfile search search_label search_fs_file search_fs_uuid ls reboot chain multiboot
    
    cp "/usr/share/grub/i386-pc/cdboot.img" "$ISO_DIR/boot/grub/i386-pc/"
    
    # Install GRUB files for UEFI
    grub-mkimage \
        -O x86_64-efi \
        -o "$ISO_DIR/EFI/BOOT/BOOTX64.EFI" \
        -p "/boot/grub" \
        iso9660 linux normal configfile search search_label search_fs_file search_fs_uuid ls reboot chain multiboot fat ext2
    
    # Create GRUB configuration
    cat > "$ISO_DIR/boot/grub/grub.cfg" << EOF
set default=0
set timeout=5

insmod all_video
insmod gfxterm
insmod png

loadfont unicode

set gfxmode=auto
terminal_output gfxterm

# Background image
if [ -f /boot/grub/splash.png ]; then
    background_image /boot/grub/splash.png
fi

menuentry "Install AetherOS $(cat "$VERSION_FILE")" {
    linux /boot/vmlinuz quiet loglevel=3
    initrd /boot/initrd.img
}

menuentry "Install AetherOS (Debug Mode)" {
    linux /boot/vmlinuz debug
    initrd /boot/initrd.img
}

menuentry "Boot from First Hard Drive" {
    chainloader (hd0)
}
EOF
    
    # Copy splash image if it exists
    if [ -f "$SCRIPT_DIR/artwork/splash.png" ]; then
        cp "$SCRIPT_DIR/artwork/splash.png" "$ISO_DIR/boot/grub/"
    fi
    
    log "INFO" "Bootloader configured successfully"
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

should_run_stage() {
    local stage="$1"
    [[ ${STAGES[$stage]} -ge ${STAGES[$START_STAGE]} ]]
}

main() {
    # Create necessary directories
    mkdir -p "$BUILD_DIR" "$OUTPUT_DIR" "$LOG_DIR"
    
    # Initialize or read version
    if [ ! -f "$VERSION_FILE" ]; then
        echo "0.1.0" > "$VERSION_FILE"
    fi
    VERSION=$(cat "$VERSION_FILE")
    
    log "INFO" "Starting AetherOS build process v$VERSION"
    log "INFO" "Starting from stage: $START_STAGE"
    
    # Build kernel if needed
    if should_run_stage "kernel"; then
        build_kernel
    else
        log "INFO" "Skipping kernel build stage"
    fi
    
    # Build busybox if needed
    if should_run_stage "busybox"; then
        build_busybox
    else
        log "INFO" "Skipping busybox build stage"
    fi
    
    # Build initramfs if needed
    if should_run_stage "initramfs"; then
        build_initramfs
    else
        log "INFO" "Skipping initramfs creation stage"
    fi
    
    # Build installer if needed
    if should_run_stage "installer"; then
        build_installer
    else
        log "INFO" "Skipping installer build stage"
    fi
    
    # Configure bootloader if needed
    if should_run_stage "bootloader"; then
        configure_bootloader
    else
        log "INFO" "Skipping bootloader configuration stage"
    fi
    
    # Create rootfs if needed
    if should_run_stage "rootfs"; then
        build_rootfs
    else
        log "INFO" "Skipping rootfs creation stage"
    fi
    
    # Create ISO if needed
    if should_run_stage "iso"; then
        create_iso
    else
        log "INFO" "Skipping ISO creation stage"
    fi
    
    log "INFO" "Build process completed successfully"
}

# Run the main function
main "$@"
