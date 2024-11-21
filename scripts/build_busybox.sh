#!/bin/bash

# Build script for BusyBox
# This provides our core system utilities

set -euo pipefail

# Source common functions and variables
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/common.sh"

# Build configuration
BUSYBOX_VERSION="${BUSYBOX_VERSION:-1.36.1}"
BUSYBOX_URL="https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2"
BUSYBOX_SHA256="b8cc24c9574d809e7279c3be349795c5d5ceb6fdf19ca709f80cde50e47de314"
BUILD_DIR="${BUILD_ROOT}/busybox"
SOURCE_DIR="${BUILD_DIR}/busybox-${BUSYBOX_VERSION}"

# Compiler flags
export CROSS_COMPILE="${CROSS_COMPILE:-}"
export CC="${CROSS_COMPILE}gcc"
export CFLAGS="-O2 -static -fno-omit-frame-pointer ${CFLAGS:-}"
export LDFLAGS="-static -Wl,--gc-sections ${LDFLAGS:-}"
export LDLIBS="-ldl -lpthread -lm -lresolv"
export CONFIG_EXTRA_LDLIBS="dl pthread m resolv"

# Download and extract busybox
download_busybox() {
    log INFO "Downloading BusyBox ${BUSYBOX_VERSION}"
    
    ensure_dir "${BUILD_DIR}"
    cd "${BUILD_DIR}"
    
    local archive="busybox-${BUSYBOX_VERSION}.tar.bz2"
    
    # Check if we already have the correct archive
    if [ -f "${archive}" ]; then
        if echo "${BUSYBOX_SHA256}  ${archive}" | sha256sum -c - >/dev/null 2>&1; then
            log INFO "Existing BusyBox archive verified"
            return 0
        else
            log WARN "Existing BusyBox archive is corrupt, re-downloading"
            rm -f "${archive}"
        fi
    fi
    
    # Download and verify
    if ! wget -q --show-progress "${BUSYBOX_URL}"; then
        log ERROR "Failed to download BusyBox source"
        return 1
    fi
    
    if ! echo "${BUSYBOX_SHA256}  ${archive}" | sha256sum -c -; then
        log ERROR "BusyBox source verification failed"
        rm -f "${archive}"
        return 1
    fi
    
    # Extract source
    if [ -d "${SOURCE_DIR}" ]; then
        rm -rf "${SOURCE_DIR}"
    fi
    
    if ! tar xf "${archive}"; then
        log ERROR "Failed to extract BusyBox source"
        return 1
    fi
    
    log INFO "Successfully downloaded and verified BusyBox source"
}

# Configure BusyBox build
configure_build() {
    log INFO "Configuring BusyBox build"
    
    cd "${SOURCE_DIR}"
    
    # Start with default configuration
    make defconfig
    
    # Configure build options
    local config_options=(
        'CONFIG_STATIC=y'
        'CONFIG_INSTALL_NO_USR=y'
        'CONFIG_FEATURE_FAST_TOP=y'
        'CONFIG_FEATURE_EDITING_HISTORY=1000'
        'CONFIG_FEATURE_EDITING_ASK_TERMINAL=y'
        'CONFIG_FEATURE_EDITING_VI=y'
        'CONFIG_FEATURE_EDITING_SAVEHISTORY=y'
        'CONFIG_FEATURE_LESS_MAXLINES=9999999'
        '# CONFIG_TC is not set'
        '# CONFIG_WERROR is not set'
        "CONFIG_EXTRA_LDLIBS=\"${CONFIG_EXTRA_LDLIBS}\""
    )
    
    # Apply configuration options
    for option in "${config_options[@]}"; do
        if [[ "${option}" == \#* ]]; then
            # Disable option
            local key="${option#\# }"
            key="${key% is not set}"
            sed -i "s/^${key}=.*\$/${option}/" .config
        else
            # Enable option
            local key="${option%=*}"
            sed -i "s/^# ${key} is not set\$/${option}/" .config
            sed -i "s/^${key}=.*\$/${option}/" .config
        fi
    done
    
    log INFO "BusyBox build configuration completed"
}

# Build BusyBox
build_busybox() {
    log INFO "Building BusyBox"
    
    cd "${SOURCE_DIR}"
    
    # Build with all available cores but limit load
    if ! make -j"${PARALLEL_JOBS}" \
        CC="${CC}" \
        CFLAGS="${CFLAGS}" \
        LDFLAGS="${LDFLAGS}" \
        LDLIBS="${LDLIBS}" \
        CROSS_COMPILE="${CROSS_COMPILE}" \
        CONFIG_SYSROOT="${SYSROOT}" \
        CONFIG_PREFIX="${SYSROOT}"; then
        log ERROR "BusyBox build failed"
        return 1
    fi
    
    log INFO "BusyBox build completed"
}

# Install BusyBox
install_busybox() {
    log INFO "Installing BusyBox"
    
    cd "${SOURCE_DIR}"
    
    # Install BusyBox
    if ! make CONFIG_PREFIX="${SYSROOT}" install; then
        log ERROR "BusyBox installation failed"
        return 1
    fi
    
    # Create essential symlinks
    ln -sf busybox "${SYSROOT}/bin/sh"
    
    # Create basic system directories
    local system_dirs=(
        root home dev proc sys tmp var mnt media run
        etc/init.d
    )
    
    for dir in "${system_dirs[@]}"; do
        ensure_dir "${SYSROOT}/${dir}"
    done
    
    log INFO "BusyBox installation completed"
}

# Configure system
configure_system() {
    log INFO "Configuring system"
    
    # Create basic configuration files
    cat > "${SYSROOT}/etc/passwd" << "EOF"
root:x:0:0:root:/root:/bin/sh
nobody:x:99:99:nobody:/dev/null:/bin/false
EOF

    cat > "${SYSROOT}/etc/group" << "EOF"
root:x:0:
bin:x:1:
sys:x:2:
kmem:x:3:
tty:x:4:
daemon:x:6:
disk:x:8:
dialout:x:10:
video:x:12:
utmp:x:13:
usb:x:14:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
input:x:24:
mail:x:34:
kvm:x:61:
nobody:x:99:
users:x:100:
EOF

    cat > "${SYSROOT}/etc/profile" << "EOF"
# AetherOS System Environment

# Set up paths
export PATH="/bin:/sbin:/usr/bin:/usr/sbin"
export TERM="linux"
export PS1='\[\033[1;32m\]\u@\h\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]\$ '

# System aliases
alias ls='ls --color=auto'
alias ll='ls -l'
alias la='ls -la'
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Load user configuration
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
EOF

    # System configuration files
    echo "AetherOS" > "${SYSROOT}/etc/hostname"
    
    cat > "${SYSROOT}/etc/fstab" << "EOF"
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
/dev/root       /              auto    defaults        1       1
proc            /proc          proc    defaults        0       0
sysfs           /sys           sysfs   defaults        0       0
devpts          /dev/pts       devpts  gid=5,mode=620  0       0
tmpfs           /run           tmpfs   defaults        0       0
tmpfs           /tmp           tmpfs   defaults        0       0
EOF

    cat > "${SYSROOT}/etc/inittab" << "EOF"
# /etc/inittab
::sysinit:/etc/init.d/rcS
::askfirst:-/bin/sh
::ctrlaltdel:/sbin/reboot
::shutdown:/bin/umount -a -r
::restart:/sbin/init
EOF

    # System startup script
    cat > "${SYSROOT}/etc/init.d/rcS" << "EOF"
#!/bin/sh

# Mount virtual filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devpts devpts /dev/pts
mount -t tmpfs tmpfs /run

# Set up hostname
hostname -F /etc/hostname

# Start system log
syslogd
klogd

# Set up loopback interface
ip link set lo up

echo "AetherOS startup completed"
EOF
    chmod +x "${SYSROOT}/etc/init.d/rcS"
    
    # Verify system configuration
    if [ ! -x "${SYSROOT}/bin/busybox" ]; then
        log ERROR "BusyBox binary not found or not executable"
        return 1
    fi
    
    if [ ! -x "${SYSROOT}/etc/init.d/rcS" ]; then
        log ERROR "System startup script not found or not executable"
        return 1
    fi
    
    log INFO "System configuration completed"
}

# Main build process
main() {
    log INFO "Starting BusyBox build process"
    
    # Build steps
    local steps=(
        download_busybox
        configure_build
        build_busybox
        install_busybox
        configure_system
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
    
    log INFO "BusyBox build process completed successfully"
    return 0
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
