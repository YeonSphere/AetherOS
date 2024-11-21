#!/bin/bash

# Build script for musl libc
# This provides our core C library implementation

set -euo pipefail

# Source common functions and variables
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/common.sh"

# Build configuration
MUSL_VERSION="${MUSL_VERSION:-1.2.4}"
MUSL_URL="https://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz"
MUSL_SHA256="7a35eae33d5372a7c0da1188de798726f68825513b7ae3ebe97aaaa52114f039"
BUILD_DIR="${BUILD_ROOT}/musl"
SOURCE_DIR="${BUILD_DIR}/musl-${MUSL_VERSION}"

# Ensure build directories exist with proper permissions
setup_build_dirs() {
    log INFO "Setting up build directories"
    
    # Create build directories with proper permissions
    for dir in "${BUILD_DIR}" "${SYSROOT}" "${TOOLS_DIR}"; do
        if ! ensure_dir "${dir}"; then
            log ERROR "Failed to create directory: ${dir}"
            return 1
        fi
        
        # Ensure proper permissions
        if ! chmod 755 "${dir}"; then
            log ERROR "Failed to set permissions on ${dir}"
            return 1
        fi
    done
    
    log INFO "Build directories setup completed"
    return 0
}

# Compiler flags
export CFLAGS="-O2 -fPIC -fno-omit-frame-pointer -Wno-return-local-addr ${CFLAGS:-}"
export LDFLAGS="-static ${LDFLAGS:-}"
export CROSS_COMPILE="${CROSS_COMPILE:-}"
export CC="${CROSS_COMPILE}gcc"
export AR="${CROSS_COMPILE}ar"
export RANLIB="${CROSS_COMPILE}ranlib"
export STRIP="${CROSS_COMPILE}strip"

# Download musl source
download_musl() {
    log INFO "Downloading musl libc ${MUSL_VERSION}"
    
    cd "${BUILD_DIR}"
    
    local archive="musl-${MUSL_VERSION}.tar.gz"
    
    # Check if we already have the correct archive
    if [ -f "${archive}" ]; then
        if echo "${MUSL_SHA256}  ${archive}" | sha256sum -c - >/dev/null 2>&1; then
            log INFO "Existing musl archive verified"
            return 0
        else
            log WARN "Existing musl archive is corrupt, re-downloading"
            rm -f "${archive}"
        fi
    fi
    
    # Download and verify
    if ! wget -q --show-progress "${MUSL_URL}"; then
        log ERROR "Failed to download musl source"
        return 1
    fi
    
    if ! echo "${MUSL_SHA256}  ${archive}" | sha256sum -c -; then
        log ERROR "musl source verification failed"
        rm -f "${archive}"
        return 1
    fi
    
    # Extract source
    if [ -d "${SOURCE_DIR}" ]; then
        rm -rf "${SOURCE_DIR}"
    fi
    
    if ! tar xf "${archive}"; then
        log ERROR "Failed to extract musl source"
        return 1
    fi
    
    # Set proper permissions on source directory
    if ! chmod -R u+w "${SOURCE_DIR}"; then
        log ERROR "Failed to set permissions on source directory"
        return 1
    fi
    
    log INFO "Successfully downloaded and verified musl source"
    return 0
}

# Configure musl build
configure_musl() {
    log INFO "Configuring musl ${MUSL_VERSION}"
    
    cd "${SOURCE_DIR}"
    
    # Clean any previous build
    if [ -f "Makefile" ]; then
        make clean >/dev/null 2>&1 || true
    fi
    
    # Configure options
    ./configure \
        --prefix=/usr \
        --syslibdir=/lib \
        --target="${TARGET}" \
        --disable-shared \
        --enable-static \
        --enable-wrapper=all \
        --enable-debug \
        CC="${CC}" \
        CFLAGS="${CFLAGS}" \
        LDFLAGS="${LDFLAGS}" \
        AR="${AR}" \
        RANLIB="${RANLIB}" \
        LIBCC="$(${CC} -print-libgcc-file-name)" \
        || {
            log ERROR "musl configuration failed"
            return 1
        }
    
    log INFO "musl configuration completed"
    return 0
}

# Build musl
build_musl() {
    log INFO "Building musl libc"
    
    cd "${SOURCE_DIR}"
    
    # Use all available CPU cores but limit load
    if ! make -j"${PARALLEL_JOBS}" CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}"; then
        log ERROR "musl build failed"
        return 1
    fi
    
    log INFO "musl build completed"
    return 0
}

# Install musl to sysroot
install_musl() {
    log INFO "Installing musl to sysroot"
    
    cd "${SOURCE_DIR}"
    
    # Create sysroot directories with proper permissions
    for dir in "${SYSROOT}/usr/lib" "${SYSROOT}/usr/include" "${SYSROOT}/lib"; do
        if ! ensure_dir "${dir}"; then
            log ERROR "Failed to create directory: ${dir}"
            return 1
        fi
        if ! chmod 755 "${dir}"; then
            log ERROR "Failed to set permissions on ${dir}"
            return 1
        fi
    done
    
    # Install files
    if ! make DESTDIR="${SYSROOT}" install; then
        log ERROR "musl installation failed"
        return 1
    fi
    
    # Create symlink for dynamic linker
    ln -sf /usr/lib/libc.so "${SYSROOT}/lib/ld-musl-${TARGET_ARCH}.so.1"
    
    # Strip debug symbols if not a debug build
    if [ "${DEBUG_BUILD:-0}" -eq 0 ]; then
        find "${SYSROOT}" -type f -name "*.so*" -exec "${STRIP}" --strip-debug {} \;
        find "${SYSROOT}" -type f -name "*.a" -exec "${STRIP}" --strip-debug {} \;
    fi
    
    # Set proper permissions on installed files
    chmod -R u+rw "${SYSROOT}/usr/lib" "${SYSROOT}/usr/include" "${SYSROOT}/lib"
    
    # Verify installation
    if [ ! -f "${SYSROOT}/usr/lib/libc.a" ]; then
        log ERROR "musl static library not found in sysroot"
        return 1
    fi
    
    log INFO "musl installation completed successfully"
    return 0
}

# Main build process
main() {
    log INFO "Starting musl libc build process"
    
    # Build steps
    local steps=(
        setup_build_dirs
        download_musl
        configure_musl
        build_musl
        install_musl
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
    
    log INFO "musl libc build process completed successfully"
    return 0
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
