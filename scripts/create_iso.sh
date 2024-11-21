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
xorriso -as mkisofs \
    -o "$OUTPUT_ISO" \
    -b boot/isolinux/isolinux.bin \
    -c boot/isolinux/boot.cat \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -isohybrid-mbr /usr/lib/syslinux/bios/isohdpfx.bin \
    -eltorito-alt-boot \
    -joliet \
    -rock \
    "$ISO_DIR"

if [ $? -eq 0 ]; then
    echo "ISO created successfully at $OUTPUT_ISO"
    echo "You can now write this ISO to a USB drive using 'dd' or your preferred tool"
else
    echo "Failed to create ISO"
    exit 1
fi
