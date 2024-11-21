#!/bin/bash

# Set paths
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
PROJECT_ROOT="$(readlink -f "$SCRIPT_DIR/..")"
BUILD_DIR="$PROJECT_ROOT/build"
ISO_DIR="$BUILD_DIR/iso"
SYSLINUX_CFG="$ISO_DIR/boot/isolinux/isolinux.cfg"
OUTPUT_ISO="$BUILD_DIR/AetherOS.iso"

# Check for required tools
if ! command -v xorriso &> /dev/null; then
    echo "xorriso is required but not installed"
    exit 1
fi

if ! command -v syslinux &> /dev/null; then
    echo "syslinux is required but not installed"
    exit 1
fi

# Create isolinux configuration
echo "Creating isolinux configuration..."
mkdir -p "$(dirname "$SYSLINUX_CFG")"
cat > "$SYSLINUX_CFG" << EOF
DEFAULT aetheros
TIMEOUT 50
PROMPT 1

LABEL aetheros
    MENU LABEL AetherOS
    LINUX /boot/vmlinuz
    INITRD /boot/initramfs.cpio.gz
    APPEND root=/dev/ram0 rw quiet
EOF

# Copy necessary bootloader files
echo "Copying bootloader files..."
mkdir -p "$ISO_DIR/boot/isolinux"
cp /usr/lib/syslinux/bios/isolinux.bin "$ISO_DIR/boot/isolinux/"
cp /usr/lib/syslinux/bios/ldlinux.c32 "$ISO_DIR/boot/isolinux/"

# Look for kernel in possible locations
echo "Looking for kernel..."
POSSIBLE_KERNEL_LOCATIONS=(
    "/boot/vmlinuz-*-aetheros"
    "$BUILD_DIR/boot/vmlinuz"
    "$PROJECT_ROOT/boot/vmlinuz"
)

KERNEL_FOUND=false
for location in "${POSSIBLE_KERNEL_LOCATIONS[@]}"; do
    # Expand glob pattern if any
    for kernel in $location; do
        if [ -f "$kernel" ]; then
            echo "Found kernel at $kernel"
            mkdir -p "$ISO_DIR/boot"
            cp "$kernel" "$ISO_DIR/boot/vmlinuz"
            KERNEL_FOUND=true
            break 2
        fi
    done
done

if [ "$KERNEL_FOUND" = false ]; then
    echo "No kernel found in the following locations:"
    printf '%s\n' "${POSSIBLE_KERNEL_LOCATIONS[@]}"
    echo "Please build the kernel first using build_kernel.sh"
    exit 1
fi

# Create ISO
echo "Creating bootable ISO..."
set -euo pipefail

ISO_ROOT="${BUILD_DIR}/iso"
ISO_BOOT="${ISO_ROOT}/boot"
ISO_IMAGE="${ISO_ROOT}/AetherOS.iso"

log_msg() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] $1" | tee -a "${BUILD_DIR}/iso_build.log"
}

error_exit() {
    log_msg "ERROR: $1"
    exit 1
}

check_dependencies() {
    log_msg "Checking build dependencies..."
    
    # Check for required tools
    for cmd in grub-mkrescue xorriso mksquashfs; do
        if ! command -v $cmd >/dev/null 2>&1; then
            error_exit "Required command '$cmd' not found"
        fi
    done
    
    # Check for kernel
    if [ ! -f "${BUILD_DIR}/boot/vmlinuz" ]; then
        error_exit "Kernel not found at ${BUILD_DIR}/boot/vmlinuz"
    fi
    
    # Check for initramfs
    if [ ! -f "${BUILD_DIR}/boot/initramfs.cpio.gz" ]; then
        error_exit "initramfs not found at ${BUILD_DIR}/boot/initramfs.cpio.gz"
    fi
}

create_iso_dirs() {
    log_msg "Creating ISO directory structure..."
    
    rm -rf "${ISO_ROOT}"
    mkdir -p "${ISO_ROOT}"
    mkdir -p "${ISO_BOOT}"
    mkdir -p "${ISO_BOOT}/grub"
}

copy_boot_files() {
    log_msg "Copying boot files..."
    
    cp "${BUILD_DIR}/boot/vmlinuz" "${ISO_BOOT}/vmlinuz"
    cp "${BUILD_DIR}/boot/initramfs.cpio.gz" "${ISO_BOOT}/initramfs.img"
}

create_grub_config() {
    log_msg "Creating GRUB configuration..."
    
    cat > "${ISO_BOOT}/grub/grub.cfg" << EOF
set default=0
set timeout=5

menuentry "AetherOS" {
    linux /boot/vmlinuz root=/dev/ram0 rw quiet
    initrd /boot/initramfs.img
}

menuentry "AetherOS (Debug Mode)" {
    linux /boot/vmlinuz root=/dev/ram0 rw debug
    initrd /boot/initramfs.img
}

menuentry "AetherOS (Recovery Mode)" {
    linux /boot/vmlinuz root=/dev/ram0 rw single
    initrd /boot/initramfs.img
}
EOF
}

create_iso() {
    log_msg "Creating ISO image..."
    
    # Create ISO with GRUB2
    grub-mkrescue -o "${ISO_IMAGE}" "${ISO_ROOT}" \
        --compress=xz \
        --product-name="AetherOS" \
        --product-version="" \
        || error_exit "Failed to create ISO image"
    
    if [ ! -f "${ISO_IMAGE}" ]; then
        error_exit "ISO image was not created"
    fi
    
    log_msg "ISO image created successfully at ${ISO_IMAGE}"
}

check_dependencies
create_iso_dirs
copy_boot_files
create_grub_config
create_iso

if [ $? -eq 0 ]; then
    echo "ISO created successfully at $ISO_IMAGE"
    echo "You can now write this ISO to a USB drive using 'dd' or your preferred tool"
else
    echo "Failed to create ISO"
    exit 1
fi
