#!/bin/bash

# Build script for musl libc
# This provides our core C library implementation

set -e

source "$(dirname "$0")/common.sh"

MUSL_VERSION="1.2.4"
MUSL_URL="https://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz"
BUILD_DIR="${AETHER_ROOT}/build/musl"
SYSROOT="${AETHER_ROOT}/build/sysroot"

build_musl() {
    log INFO "Building musl libc ${MUSL_VERSION}"
    
    # Create build directory
    ensure_dir "${BUILD_DIR}"
    cd "${BUILD_DIR}"
    
    # Download and extract
    if [ ! -f "musl-${MUSL_VERSION}.tar.gz" ]; then
        wget "${MUSL_URL}"
        tar xf "musl-${MUSL_VERSION}.tar.gz"
    fi
    
    cd "musl-${MUSL_VERSION}"
    
    # Configure
    ./configure \
        --prefix=/usr \
        --syslibdir=/lib \
        --disable-gcc-wrapper \
        --enable-optimize
    
    # Build and install
    make -j"$(nproc)"
    make DESTDIR="${SYSROOT}" install
    
    # Create compatibility links
    ln -sf /lib/libc.so "${SYSROOT}/lib/ld-musl-x86_64.so.1"
    
    log INFO "musl libc build completed"
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    build_musl
fi
