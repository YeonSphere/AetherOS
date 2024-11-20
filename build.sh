#!/bin/bash

# AetherOS Build System
set -e

KERNEL_DIR="kernel/linux"
MICROKERNEL_DIR="kernel/microkernel"
CONFIG_DIR="kernel/config"
PATCHES_DIR="kernel/patches"
BUILD_DIR="build"
OUTPUT_DIR="output"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}AetherOS Build System${NC}"
echo "-------------------------"

# Create necessary directories
mkdir -p $BUILD_DIR $OUTPUT_DIR

# Build microkernel components first
echo -e "${GREEN}Building AetherOS microkernel...${NC}"
cargo build --release --manifest-path Cargo.toml
cp target/release/libaetheros.a $BUILD_DIR/

# Apply our minimal config
echo -e "${GREEN}Applying AetherOS kernel configuration...${NC}"
cp $CONFIG_DIR/minimal.config $KERNEL_DIR/.config

# Apply performance patches
echo -e "${GREEN}Applying performance patches...${NC}"
cd $KERNEL_DIR
for patch in ../$PATCHES_DIR/*.patch; do
    echo "Applying patch: $(basename $patch)"
    patch -p1 < $patch
done

# Configure kernel
echo -e "${GREEN}Configuring kernel...${NC}"
make olddefconfig

# Build kernel with optimization flags
echo -e "${GREEN}Building kernel with optimizations...${NC}"
make -j$(nproc) \
    KCFLAGS="-O3 -march=native -mtune=native -flto -fno-plt -fstack-protector-strong" \
    KCPPFLAGS="-D__KERNEL__ -DCONFIG_PREEMPT_RT -DCONFIG_NO_HZ_FULL" \
    KAFLAGS="-march=native" \
    bzImage modules

# Install modules
echo -e "${GREEN}Installing modules...${NC}"
make modules_install INSTALL_MOD_PATH=../../../$OUTPUT_DIR

# Copy kernel
echo -e "${GREEN}Copying kernel...${NC}"
cp arch/x86/boot/bzImage ../../$OUTPUT_DIR/aetheros-kernel

# Link microkernel with kernel
echo -e "${GREEN}Linking microkernel...${NC}"
cd ../../$BUILD_DIR
ld -r -o aetheros_combined.o libaetheros.a ../output/aetheros-kernel
objcopy --add-section .microkernel=libaetheros.a aetheros_combined.o ../output/aetheros-final

# Build success
echo -e "${GREEN}Build completed successfully!${NC}"
echo "Final kernel image: $OUTPUT_DIR/aetheros-final"
echo "Modules: $OUTPUT_DIR/lib/modules/"
