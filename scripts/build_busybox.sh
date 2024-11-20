#!/bin/bash

# Build script for BusyBox
# This provides our core system utilities

set -e

source "$(dirname "$0")/common.sh"

BUSYBOX_VERSION="1.36.1"
BUSYBOX_URL="https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2"
BUILD_DIR="${AETHER_ROOT}/build/busybox"
SYSROOT="${AETHER_ROOT}/build/sysroot"

build_busybox() {
    log INFO "Building BusyBox ${BUSYBOX_VERSION}"
    
    # Create build directory
    ensure_dir "${BUILD_DIR}"
    cd "${BUILD_DIR}"
    
    # Download and extract
    if [ ! -f "busybox-${BUSYBOX_VERSION}.tar.bz2" ]; then
        wget "${BUSYBOX_URL}"
        tar xf "busybox-${BUSYBOX_VERSION}.tar.bz2"
    fi
    
    cd "busybox-${BUSYBOX_VERSION}"
    
    # Configure
    make defconfig
    
    # Enable advanced features
    sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
    sed -i 's/# CONFIG_INSTALL_NO_USR is not set/CONFIG_INSTALL_NO_USR=y/' .config
    sed -i 's/# CONFIG_FEATURE_FAST_TOP is not set/CONFIG_FEATURE_FAST_TOP=y/' .config
    sed -i 's/# CONFIG_FEATURE_EDITING_HISTORY is not set/CONFIG_FEATURE_EDITING_HISTORY=1000/' .config
    
    # Build
    make -j"$(nproc)" CC="${CROSS_COMPILE}gcc" LDFLAGS="--static"
    
    # Install
    make CONFIG_PREFIX="${SYSROOT}" install
    
    # Create essential symlinks
    ln -sf /bin/busybox "${SYSROOT}/bin/sh"
    
    # Create basic system directories
    for dir in root home dev proc sys tmp var mnt media; do
        ensure_dir "${SYSROOT}/${dir}"
    done
    
    log INFO "BusyBox build completed"
}

# Configure BusyBox
configure_busybox() {
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
export PATH="/bin:/sbin:/usr/bin:/usr/sbin"
export TERM="linux"
export PS1='\u@\h:\w\$ '

alias ls='ls --color=auto'
alias ll='ls -l'
alias la='ls -la'

if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
EOF

    # Set up basic system configuration
    echo "AetherOS" > "${SYSROOT}/etc/hostname"
    
    # Create minimal fstab
    cat > "${SYSROOT}/etc/fstab" << "EOF"
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
/dev/root       /              auto    defaults        1       1
proc            /proc          proc    defaults        0       0
sysfs           /sys           sysfs   defaults        0       0
devpts          /dev/pts       devpts  gid=5,mode=620  0       0
tmpfs           /run           tmpfs   defaults        0       0
tmpfs           /tmp           tmpfs   defaults        0       0
EOF
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    build_busybox
    configure_busybox
fi
