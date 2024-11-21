#!/bin/bash

# Build script for musl libc
# This provides our core C library implementation

set -e

source "$(dirname "$0")/common.sh"

MUSL_VERSION="1.2.4"
MUSL_URL="https://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz"
BUILD_DIR="${BUILD_ROOT}/musl"
SYSROOT="${BUILD_ROOT}/sysroot"

# Set compiler variables
export CC="gcc"
export CFLAGS="-O2 -fPIC -fno-omit-frame-pointer -I${KERNEL_HEADERS}"
export LDFLAGS="-static"
export AR="ar"
export RANLIB="ranlib"

# Set make variables
export MAKE_AR="ar"
export MAKE_RANLIB="ranlib"
export PATH="/usr/bin:$PATH"

# Download musl source
download_musl() {
    log INFO "Downloading musl libc ${MUSL_VERSION}"
    
    if [ -f "${BUILD_DIR}/musl-${MUSL_VERSION}.tar.gz" ]; then
        log INFO "musl source already downloaded"
        return 0
    fi
    
    ensure_dir "${BUILD_DIR}"
    cd "${BUILD_DIR}" || return 1
    
    if ! wget -q --show-progress "${MUSL_URL}"; then
        log ERROR "Failed to download musl source"
        return 1
    fi
    
    if ! tar xf "musl-${MUSL_VERSION}.tar.gz"; then
        log ERROR "Failed to extract musl source"
        return 1
    fi
    
    log INFO "Successfully downloaded and extracted musl source"
}

# Configure musl build
configure_musl() {
    log INFO "Configuring musl ${MUSL_VERSION}"
    
    cd "${BUILD_DIR}/musl-${MUSL_VERSION}" || return 1
    
    # Clean any previous build
    make clean >/dev/null 2>&1 || true
    
    # Configure options
    ./configure \
        --prefix=/usr \
        --syslibdir=/lib \
        --target="${TARGET}" \
        --host="${HOST}" \
        --build="${BUILD}" \
        --disable-shared \
        --enable-static \
        --enable-wrapper=all \
        --enable-debug \
        CC="${CC}" \
        CFLAGS="${CFLAGS}" \
        LDFLAGS="${LDFLAGS}" \
        AR="${AR}" \
        RANLIB="${RANLIB}" \
        MAKE_AR="${MAKE_AR}" \
        MAKE_RANLIB="${MAKE_RANLIB}"
    
    if [ $? -ne 0 ]; then
        log ERROR "musl configuration failed"
        return 1
    fi
    
    log INFO "musl configuration completed"
}

# Build musl
build_musl() {
    log INFO "Building musl libc"
    
    cd "${BUILD_DIR}/musl-${MUSL_VERSION}" || return 1
    
    if ! make ${MAKEFLAGS}; then
        log ERROR "musl build failed"
        return 1
    fi
    
    log INFO "musl build completed"
}

# Install musl to sysroot
install_musl() {
    log INFO "Installing musl to sysroot"
    
    cd "${BUILD_DIR}/musl-${MUSL_VERSION}" || return 1
    
    # Create sysroot directories
    mkdir -p "${SYSROOT}/usr/lib"
    mkdir -p "${SYSROOT}/usr/include"
    mkdir -p "${SYSROOT}/lib"
    
    # Install files
    make DESTDIR="${SYSROOT}" install
    
    # Create symlink for dynamic linker
    ln -sf /usr/lib/libc.so "${SYSROOT}/lib/ld-musl-x86_64.so.1"
    
    # Copy kernel headers
    cp -r "${KERNEL_HEADERS}"/* "${SYSROOT}/usr/include/"
    
    log INFO "musl installation completed"
}

# Main build process
main() {
    log INFO "Starting musl libc build process"
    
    # Check build environment
    check_build_env || exit 1
    
    # Build steps
    if ! download_musl; then
        log ERROR "Failed to download musl"
        exit 1
    fi
    
    if ! configure_musl; then
        log ERROR "Failed to configure musl"
        exit 1
    fi
    
    if ! build_musl; then
        log ERROR "Failed to build musl"
        exit 1
    fi
    
    if ! install_musl; then
        log ERROR "Failed to install musl"
        exit 1
    fi
    
    log INFO "musl libc build process completed successfully"
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
