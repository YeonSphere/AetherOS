#!/bin/bash

# Set paths
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
BUILD_DIR="$(readlink -f "$SCRIPT_DIR/..")/build"
SYSROOT_DIR="$BUILD_DIR/sysroot"
ISO_DIR="$BUILD_DIR/iso"
INITRAMFS="$ISO_DIR/boot/initramfs.cpio.gz"

echo "Creating initramfs from sysroot..."

# Ensure target directory exists
mkdir -p "$(dirname "$INITRAMFS")"

# Create initramfs
(cd "$SYSROOT_DIR" && find . | cpio -H newc -o | gzip > "$INITRAMFS")

if [ $? -eq 0 ]; then
    echo "Initramfs created successfully at $INITRAMFS"
else
    echo "Failed to create initramfs"
    exit 1
fi
