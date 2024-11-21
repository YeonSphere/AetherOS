#!/bin/bash

# Build script for AetherOS ISO
# This creates a bootable ISO image from our built components

set -euo pipefail

# Source common functions and variables
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/common.sh"

# ISO configuration
ISO_ROOT="${BUILD_ROOT}/iso"
ISO_BOOT="${ISO_ROOT}/boot"
ISO_IMAGE="${ISO_DIR}/aetheros-${AETHER_VERSION}.iso"
GRUB_CFG="${ISO_BOOT}/grub/grub.cfg"

# Required files
KERNEL_IMAGE="${BUILD_ROOT}/boot/vmlinuz"
INITRAMFS_IMAGE="${BUILD_ROOT}/boot/initramfs.cpio.gz"

# Verify build dependencies
verify_dependencies() {
    log INFO "Verifying build dependencies"
    
    # Check for required tools
    local required_tools=(
        "grub-mkrescue"
        "xorriso"
        "mksquashfs"
        "grub-mkimage"
    )
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "${tool}" >/dev/null 2>&1; then
            log ERROR "Required tool '${tool}' not found"
            return 1
        fi
    done
    
    # Check for required files
    if [ ! -f "${KERNEL_IMAGE}" ]; then
        log ERROR "Kernel image not found at ${KERNEL_IMAGE}"
        return 1
    fi
    
    if [ ! -f "${INITRAMFS_IMAGE}" ]; then
        log ERROR "Initramfs not found at ${INITRAMFS_IMAGE}"
        return 1
    fi
    
    log INFO "All dependencies verified"
}

# Create ISO directory structure
create_iso_structure() {
    log INFO "Creating ISO directory structure"
    
    # Clean previous build
    if [ -d "${ISO_ROOT}" ]; then
        rm -rf "${ISO_ROOT}"
    fi
    
    # Create required directories
    local iso_dirs=(
        "${ISO_ROOT}"
        "${ISO_BOOT}"
        "${ISO_BOOT}/grub"
        "${ISO_ROOT}/EFI/BOOT"
    )
    
    for dir in "${iso_dirs[@]}"; do
        ensure_dir "${dir}"
    done
    
    log INFO "ISO directory structure created"
}

# Copy boot files
copy_boot_files() {
    log INFO "Copying boot files"
    
    # Copy kernel and initramfs
    cp "${KERNEL_IMAGE}" "${ISO_BOOT}/vmlinuz" || {
        log ERROR "Failed to copy kernel image"
        return 1
    }
    
    cp "${INITRAMFS_IMAGE}" "${ISO_BOOT}/initramfs.img" || {
        log ERROR "Failed to copy initramfs"
        return 1
    }
    
    # Copy GRUB modules for both BIOS and UEFI
    local grub_lib
    if [ -d "/usr/lib/grub/x86_64-efi" ]; then
        grub_lib="/usr/lib/grub/x86_64-efi"
    elif [ -d "/usr/lib/grub/i386-pc" ]; then
        grub_lib="/usr/lib/grub/i386-pc"
    else
        log ERROR "GRUB modules directory not found"
        return 1
    fi
    
    cp -r "${grub_lib}"/* "${ISO_BOOT}/grub/" || {
        log ERROR "Failed to copy GRUB modules"
        return 1
    }
    
    log INFO "Boot files copied successfully"
}

# Create GRUB configuration
create_grub_config() {
    log INFO "Creating GRUB configuration"
    
    cat > "${GRUB_CFG}" << EOF
set default=0
set timeout=5
set timeout_style=menu

function load_video {
    if [ x\$feature_all_video_module = xy ]; then
        insmod all_video
    else
        insmod efi_gop
        insmod efi_uga
        insmod ieee1275_fb
        insmod vbe
        insmod vga
        insmod video_bochs
        insmod video_cirrus
    fi
}

load_video
set gfxpayload=keep
insmod gzio
insmod part_gpt
insmod ext2

menuentry "AetherOS ${AETHER_VERSION}" {
    linux /boot/vmlinuz root=/dev/ram0 rw quiet loglevel=3
    initrd /boot/initramfs.img
}

menuentry "AetherOS ${AETHER_VERSION} (Debug Mode)" {
    linux /boot/vmlinuz root=/dev/ram0 rw debug loglevel=7
    initrd /boot/initramfs.img
}

menuentry "AetherOS ${AETHER_VERSION} (Recovery Mode)" {
    linux /boot/vmlinuz root=/dev/ram0 rw single
    initrd /boot/initramfs.img
}
EOF
    
    if [ ! -f "${GRUB_CFG}" ]; then
        log ERROR "Failed to create GRUB configuration"
        return 1
    fi
    
    log INFO "GRUB configuration created"
}

# Create UEFI boot support
create_uefi_support() {
    log INFO "Creating UEFI boot support"
    
    # Create UEFI bootloader
    grub-mkimage \
        -O x86_64-efi \
        -o "${ISO_ROOT}/EFI/BOOT/bootx64.efi" \
        -p "/boot/grub" \
        part_gpt part_msdos fat iso9660 normal boot linux configfile \
        linuxefi gzio all_video efi_gop efi_uga font gfxterm gettext \
        || {
            log ERROR "Failed to create UEFI bootloader"
            return 1
        }
    
    log INFO "UEFI boot support created"
}

# Create ISO image
create_iso_image() {
    log INFO "Creating ISO image"
    
    # Create ISO with both BIOS and UEFI support
    grub-mkrescue \
        -o "${ISO_IMAGE}" \
        "${ISO_ROOT}" \
        --compress=xz \
        --product-name="AetherOS" \
        --product-version="${AETHER_VERSION}" \
        || {
            log ERROR "Failed to create ISO image"
            return 1
        }
    
    if [ ! -f "${ISO_IMAGE}" ]; then
        log ERROR "ISO image was not created"
        return 1
    fi
    
    # Calculate and store checksums
    local checksum_file="${ISO_DIR}/SHA256SUMS"
    cd "${ISO_DIR}"
    sha256sum "$(basename "${ISO_IMAGE}")" > "${checksum_file}"
    
    log INFO "ISO image created successfully at ${ISO_IMAGE}"
    log INFO "SHA256 checksum stored in ${checksum_file}"
}

# Main build process
main() {
    log INFO "Starting ISO build process"
    
    # Build steps
    local steps=(
        verify_dependencies
        create_iso_structure
        copy_boot_files
        create_grub_config
        create_uefi_support
        create_iso_image
    )
    
    local step_count=${#steps[@]}
    local current_step=1
    
    for step in "${steps[@]}"; do
        log INFO "Step ${current_step}/${step_count}: Running ${step}"
        if ! ${step}; then
            log ERROR "Step ${step} failed"
            return 1
        fi
        ((current_step++))
    done
    
    log INFO "ISO build process completed successfully"
    log INFO "You can write the ISO to a USB drive using 'dd' or your preferred tool"
    return 0
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
