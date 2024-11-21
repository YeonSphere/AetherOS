#!/bin/bash

# Enable error tracing
set -e

source "$(dirname "$0")/common.sh"

# Additional kernel-specific paths
KERNEL_SRC="${AETHER_ROOT}/kernel/linux/linux-${KERNEL_VERSION}"
KERNEL_CONFIG="${AETHER_ROOT}/configs/kernel.config"
INITRAMFS_ROOT="${BUILD_ROOT}/initramfs"
INITRAMFS_CPIO="${BUILD_ROOT}/initramfs.cpio.gz"

# Log with timestamp and file descriptor
log() {
    local level=$1
    shift
    local message=$*
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        ERROR)
            echo "${timestamp} [ERROR] $message" >&2
            ;;
        WARN)
            echo "${timestamp} [WARN] $message" >&1
            ;;
        INFO)
            echo "${timestamp} [INFO] $message" >&1
            ;;
        DEBUG)
            if [ "${VERBOSE:-0}" -ge 2 ]; then
                echo "${timestamp} [DEBUG] $message" >&1
            fi
            ;;
    esac
}

# Download kernel source
download_kernel() {
    log INFO "Downloading kernel source..."
    local src_dir="$(dirname "$KERNEL_SRC")"
    
    # Create source directory
    if ! mkdir -p "$src_dir"; then
        log ERROR "Failed to create source directory: $src_dir"
        return 1
    fi
    
    cd "$src_dir" || {
        log ERROR "Failed to change to source directory: $src_dir"
        return 1
    }
    
    # Download kernel if needed
    if [ ! -f "${KERNEL_ARCHIVE}" ]; then
        log INFO "Downloading ${KERNEL_URL}..."
        if ! curl -L -o "${KERNEL_ARCHIVE}" "${KERNEL_URL}"; then
            log ERROR "Failed to download kernel source from ${KERNEL_URL}"
            return 1
        fi
    else
        log INFO "Kernel archive already exists, skipping download"
    fi
    
    # Extract kernel if needed
    if [ ! -d "${KERNEL_SRC}" ]; then
        log INFO "Extracting kernel source..."
        if ! tar xf "${KERNEL_ARCHIVE}"; then
            log ERROR "Failed to extract kernel archive: ${KERNEL_ARCHIVE}"
            return 1
        fi
        if [ ! -d "${KERNEL_SRC}" ]; then
            log ERROR "Kernel source directory not found after extraction: ${KERNEL_SRC}"
            return 1
        fi
    else
        log INFO "Kernel source directory already exists"
    fi
}

# Clean kernel source tree
clean_kernel_source() {
    log INFO "Cleaning kernel source tree..."
    cd "$KERNEL_SRC" || {
        log ERROR "Failed to change to kernel source directory: $KERNEL_SRC"
        return 1
    }
    
    if ! make clean >/dev/null 2>&1; then
        log WARN "make clean failed, this might be normal for a fresh source tree"
    fi
    
    if ! make mrproper >/dev/null 2>&1; then
        log WARN "make mrproper failed, this might be normal for a fresh source tree"
    fi
}

# Create default kernel config
create_default_config() {
    log INFO "Creating default kernel config..."
    cd "$KERNEL_SRC" || {
        log ERROR "Failed to change to kernel source directory: $KERNEL_SRC"
        return 1
    }
    
    # Create configs directory if it doesn't exist
    if ! mkdir -p "$(dirname "$KERNEL_CONFIG")"; then
        log ERROR "Failed to create config directory: $(dirname "$KERNEL_CONFIG")"
        return 1
    fi
    
    # If no config exists, create a minimal one
    if [ ! -f "$KERNEL_CONFIG" ]; then
        log INFO "No existing config found, creating minimal config..."
        if ! make x86_64_defconfig; then
            log ERROR "Failed to create default x86_64 config"
            return 1
        fi
        
        # Customize for AetherOS
        log INFO "Customizing kernel config for AetherOS..."
        if ! ./scripts/config \
            --set-val CONFIG_SCHED_RUSTY y \
            --set-val RUSTY_LOCAL_PRIO "${RUSTY_LOCAL_PRIO:-5}" \
            --set-val RUSTY_GLOBAL_PRIO "${RUSTY_GLOBAL_PRIO:-5}" \
            --set-val ENABLE_OPTIMIZATIONS "${ENABLE_OPTIMIZATIONS:-0}" \
            --enable CONFIG_BLK_DEV_INITRD \
            --enable CONFIG_DEVTMPFS \
            --enable CONFIG_DEVTMPFS_MOUNT \
            --enable CONFIG_TMPFS \
            --enable CONFIG_TMPFS_POSIX_ACL \
            --enable CONFIG_BINFMT_ELF \
            --enable CONFIG_BINFMT_SCRIPT \
            --enable CONFIG_SYSVIPC \
            --enable CONFIG_SYSVIPC_SYSCTL \
            --enable CONFIG_NET \
            --enable CONFIG_PACKET \
            --enable CONFIG_UNIX \
            --enable CONFIG_INET \
            --enable CONFIG_TTY \
            --enable CONFIG_SERIAL_8250 \
            --enable CONFIG_SERIAL_8250_CONSOLE; then
            log ERROR "Failed to customize kernel config"
            return 1
        fi
            
        # Save as our default config
        if ! cp .config "$KERNEL_CONFIG"; then
            log ERROR "Failed to save kernel config to: $KERNEL_CONFIG"
            return 1
        fi
    fi
}

# Create initramfs structure and contents
create_initramfs() {
    log INFO "Creating initramfs structure..."
    
    # Create necessary directories
    mkdir -p "${INITRAMFS_ROOT}"/{bin,sbin,dev,proc,sys,usr/{bin,sbin},etc,lib64,var/log}
    
    # Create init script
    cat > "${INITRAMFS_ROOT}/init" << 'EOF'
#!/bin/sh

# Mount essential filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# Set up basic environment
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

# Create basic device nodes if devtmpfs is not available
[ -e /dev/console ] || mknod /dev/console c 5 1
[ -e /dev/null ] || mknod /dev/null c 1 3

# Set up basic networking
ip link set lo up
ip link set eth0 up

# Start system initialization
echo "AetherOS: Starting system initialization..."

# Start a shell for debugging
exec /bin/sh
EOF
    
    # Make init executable
    chmod +x "${INITRAMFS_ROOT}/init"
    
    # Create CPIO archive
    log INFO "Creating initramfs CPIO archive..."
    cd "${INITRAMFS_ROOT}"
    find . | cpio -H newc -o | gzip > "${INITRAMFS_CPIO}"
    
    if [ ! -f "${INITRAMFS_CPIO}" ]; then
        log ERROR "Failed to create initramfs CPIO archive"
        return 1
    fi
    
    log INFO "Initramfs created successfully at ${INITRAMFS_CPIO}"
}

# Configure and build kernel
build_kernel() {
    log INFO "Configuring kernel..."
    cd "$KERNEL_SRC" || {
        log ERROR "Failed to change to kernel source directory: $KERNEL_SRC"
        return 1
    }
    
    if [ ! -f "$KERNEL_CONFIG" ]; then
        create_default_config
    else
        if ! cp "$KERNEL_CONFIG" .config; then
            log ERROR "Failed to copy existing config from: $KERNEL_CONFIG"
            return 1
        fi
    fi

    log INFO "Updating kernel config..."
    if ! ./scripts/config \
        --set-val CONFIG_SCHED_RUSTY y \
        --set-val RUSTY_LOCAL_PRIO "${RUSTY_LOCAL_PRIO:-5}" \
        --set-val RUSTY_GLOBAL_PRIO "${RUSTY_GLOBAL_PRIO:-5}" \
        --set-val ENABLE_OPTIMIZATIONS "${ENABLE_OPTIMIZATIONS:-0}"; then
        log ERROR "Failed to update kernel config options"
        return 1
    fi

    log INFO "Building kernel with $(nproc) jobs..."
    if ! make -j$(nproc); then
        log ERROR "Kernel build failed. Check the build log for details."
        return 1
    fi
    
    # Copy kernel to build directory
    log INFO "Copying kernel to build directory..."
    if ! mkdir -p "${BUILD_ROOT}/boot"; then
        log ERROR "Failed to create boot directory: ${BUILD_ROOT}/boot"
        return 1
    fi
    
    if [ ! -f "arch/x86/boot/bzImage" ]; then
        log ERROR "Kernel image not found at: arch/x86/boot/bzImage"
        return 1
    fi
    
    if ! cp arch/x86/boot/bzImage "${BUILD_ROOT}/boot/vmlinuz"; then
        log ERROR "Failed to copy kernel image to: ${BUILD_ROOT}/boot/vmlinuz"
        return 1
    fi
}

# Main build process
main() {
    log INFO "Starting kernel build process..."
    
    # Verify kernel source exists
    if [ ! -d "$KERNEL_SRC" ]; then
        log INFO "Kernel source not found at: $KERNEL_SRC, downloading and extracting..."
        if ! download_kernel; then
            log ERROR "Failed to prepare kernel source"
            return 1
        fi
    else
        log INFO "Kernel source directory already exists, skipping download and extraction"
    fi
    
    # Create build directory structure
    mkdir -p "${BUILD_ROOT}"/{boot,initramfs}
    
    # Create initramfs first
    if ! create_initramfs; then
        log ERROR "Failed to create initramfs"
        return 1
    fi
    
    if ! clean_kernel_source; then
        log ERROR "Failed to clean kernel source"
        return 1
    fi
    
    if ! build_kernel; then
        log ERROR "Failed to build kernel"
        return 1
    fi
    
    log INFO "Kernel build completed successfully!"
}

# Run main function with error handling
if ! main "$@" 2>&1 | tee "${BUILD_ROOT}/kernel_build.log"; then
    log ERROR "Kernel build failed. Check ${BUILD_ROOT}/kernel_build.log for details"
    exit 1
fi
