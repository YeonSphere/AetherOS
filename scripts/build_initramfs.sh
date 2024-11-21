#!/bin/bash

# Build script for initramfs
# This creates our initial ramdisk with basic system structure

set -euo pipefail

source "$(dirname "$0")/common.sh"

INITRAMFS_ROOT="${BUILD_ROOT}/initramfs"
SYSROOT="${BUILD_ROOT}/sysroot"
INITRAMFS_LOG="${BUILD_ROOT}/initramfs.log"

log_msg() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] $1" | tee -a "${INITRAMFS_LOG}"
}

error_exit() {
    log_msg "ERROR: $1"
    exit 1
}

check_dependencies() {
    log_msg "Checking build dependencies..."
    
    # Check if busybox is built
    if [ ! -f "${SYSROOT}/bin/busybox" ]; then
        error_exit "busybox not found in sysroot. Please build busybox first."
    fi
    
    # Check if kernel modules exist (if we're using them)
    if [ -d "${BUILD_ROOT}/lib/modules" ]; then
        log_msg "Kernel modules found, will include in initramfs"
    else
        log_msg "No kernel modules found, continuing without them"
    fi
}

create_directory_structure() {
    log_msg "Creating initramfs directory structure..."
    
    rm -rf "${INITRAMFS_ROOT}"
    ensure_dir "${INITRAMFS_ROOT}"
    
    # Create basic directory structure
    for dir in bin sbin lib etc proc sys tmp var mnt dev root usr/bin usr/sbin; do
        ensure_dir "${INITRAMFS_ROOT}/$dir"
    done
    
    # Create basic device nodes
    mknod -m 622 "${INITRAMFS_ROOT}/dev/console" c 5 1
    mknod -m 666 "${INITRAMFS_ROOT}/dev/null" c 1 3
    mknod -m 666 "${INITRAMFS_ROOT}/dev/zero" c 1 5
    mknod -m 666 "${INITRAMFS_ROOT}/dev/ptmx" c 5 2
    mknod -m 666 "${INITRAMFS_ROOT}/dev/tty" c 5 0
    mknod -m 444 "${INITRAMFS_ROOT}/dev/random" c 1 8
    mknod -m 444 "${INITRAMFS_ROOT}/dev/urandom" c 1 9
}

copy_system_files() {
    log_msg "Copying system files..."
    
    # Copy busybox and create symlinks
    cp "${SYSROOT}/bin/busybox" "${INITRAMFS_ROOT}/bin/"
    cd "${INITRAMFS_ROOT}/bin"
    for cmd in $(./busybox --list); do
        ln -sf busybox "$cmd"
    done
    
    # Copy kernel modules if they exist
    if [ -d "${BUILD_ROOT}/lib/modules" ]; then
        cp -a "${BUILD_ROOT}/lib/modules" "${INITRAMFS_ROOT}/lib/"
    fi
    
    # Copy basic configuration files
    cat > "${INITRAMFS_ROOT}/etc/passwd" << EOF
root:x:0:0:root:/root:/bin/sh
EOF
    
    cat > "${INITRAMFS_ROOT}/etc/group" << EOF
root:x:0:
EOF
    
    # Create init script
    cat > "${INITRAMFS_ROOT}/init" << EOF
#!/bin/sh

# Mount essential filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# Set up basic environment
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/root
export TERM=linux

# Load kernel modules if present
if [ -d "/lib/modules" ]; then
    for module in \$(find /lib/modules -name '*.ko'); do
        insmod \$module
    done
fi

# Start system initialization
echo "Welcome to AetherOS!"
echo "Starting system initialization..."

# Start shell
exec /bin/sh
EOF
    
    chmod +x "${INITRAMFS_ROOT}/init"
}

create_initramfs() {
    log_msg "Creating initramfs image..."
    
    cd "${INITRAMFS_ROOT}"
    find . | cpio -H newc -o | gzip > "${BUILD_ROOT}/boot/initramfs.img"
    
    if [ ! -f "${BUILD_ROOT}/boot/initramfs.img" ]; then
        error_exit "Failed to create initramfs image"
    fi
    
    log_msg "initramfs created successfully at ${BUILD_ROOT}/boot/initramfs.img"
}

main() {
    log_msg "Starting initramfs build..."
    
    check_dependencies
    create_directory_structure
    copy_system_files
    create_initramfs
    
    log_msg "initramfs build completed successfully"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
