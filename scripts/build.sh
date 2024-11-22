#!/bin/bash

set -euo pipefail

# Build configuration
RUST_VERSION="nightly-2023-10-01"
TARGET="x86_64-unknown-none"
FEATURES="--features full"
BUILD_TYPE=${1:-debug}  # debug or release

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_ROOT}/target/${TARGET}"
PATCHES_DIR="${PROJECT_ROOT}/patches"

# Function to check required tools
check_dependencies() {
    echo -e "${YELLOW}Checking build dependencies...${NC}"
    
    local REQUIRED_TOOLS=("rustup" "cargo" "git" "make" "nasm" "qemu-system-x86_64")
    local MISSING_TOOLS=()
    
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            MISSING_TOOLS+=("$tool")
        fi
    done
    
    if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
        echo -e "${RED}Error: Missing required tools: ${MISSING_TOOLS[*]}${NC}"
        exit 1
    fi
    
    # Check Rust version
    if ! rustup toolchain list | grep -q "$RUST_VERSION"; then
        echo -e "${YELLOW}Installing Rust $RUST_VERSION...${NC}"
        rustup toolchain install "$RUST_VERSION"
    fi
    
    # Install required components
    rustup component add rust-src --toolchain "$RUST_VERSION"
    rustup component add llvm-tools-preview --toolchain "$RUST_VERSION"
}

# Function to apply patches
apply_patches() {
    echo -e "${YELLOW}Applying patches...${NC}"
    
    if [ -d "$PATCHES_DIR" ]; then
        for patch in "$PATCHES_DIR"/*.patch; do
            if [ -f "$patch" ]; then
                echo "Applying patch: $(basename "$patch")"
                if ! git apply --check "$patch" &> /dev/null; then
                    if ! git apply -3 "$patch" &> /dev/null; then
                        echo -e "${RED}Failed to apply patch: $(basename "$patch")${NC}"
                        exit 1
                    fi
                fi
            fi
        done
    fi
}

# Function to build the kernel
build_kernel() {
    echo -e "${YELLOW}Building AetherOS kernel...${NC}"
    
    local BUILD_FLAGS=""
    if [ "$BUILD_TYPE" = "release" ]; then
        BUILD_FLAGS="--release"
    fi
    
    # Build bootloader
    cd "$PROJECT_ROOT/bootloader"
    cargo "+$RUST_VERSION" build $BUILD_FLAGS --target "$TARGET"
    
    # Build kernel
    cd "$PROJECT_ROOT"
    RUSTFLAGS="-C target-cpu=native" cargo "+$RUST_VERSION" build $BUILD_FLAGS $FEATURES --target "$TARGET"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Build successful!${NC}"
    else
        echo -e "${RED}Build failed!${NC}"
        exit 1
    fi
}

# Function to generate documentation
generate_docs() {
    echo -e "${YELLOW}Generating documentation...${NC}"
    
    cd "$PROJECT_ROOT"
    RUSTDOCFLAGS="--enable-index-page -Zunstable-options" \
    cargo "+$RUST_VERSION" doc --no-deps $FEATURES
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Documentation generated successfully!${NC}"
    else
        echo -e "${RED}Documentation generation failed!${NC}"
        exit 1
    fi
}

# Main build process
main() {
    echo -e "${YELLOW}Starting AetherOS build process...${NC}"
    
    check_dependencies
    apply_patches
    build_kernel
    generate_docs
    
    echo -e "${GREEN}Build process completed successfully!${NC}"
}

main
