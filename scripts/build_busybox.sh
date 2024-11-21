#!/bin/bash

# Build script for BusyBox
# This provides our core system utilities

set -e

source "$(dirname "$0")/common.sh"

BUSYBOX_VERSION="1.36.1"
BUSYBOX_URL="https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2"
BUILD_DIR="${BUILD_ROOT}/busybox"
SYSROOT="${BUILD_ROOT}/sysroot"

# Set compiler variables
export CC="gcc"
export CFLAGS="-O2 -static -I${KERNEL_HEADERS} -fno-omit-frame-pointer"
export LDFLAGS="-static -Wl,--gc-sections"
export LDLIBS="-ldl -lpthread"
export CONFIG_EXTRA_LDLIBS="dl pthread"

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
    
    # Enable static build and other features
    sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
    sed -i 's/CONFIG_EXTRA_LDLIBS=""/CONFIG_EXTRA_LDLIBS="dl pthread"/' .config
    sed -i 's/# CONFIG_INSTALL_NO_USR is not set/CONFIG_INSTALL_NO_USR=y/' .config
    sed -i 's/# CONFIG_FEATURE_FAST_TOP is not set/CONFIG_FEATURE_FAST_TOP=y/' .config
    sed -i 's/# CONFIG_FEATURE_EDITING_HISTORY is not set/CONFIG_FEATURE_EDITING_HISTORY=1000/' .config
    
    # Enable advanced features
    sed -i 's/# CONFIG_FEATURE_EDITING_ASK_TERMINAL is not set/CONFIG_FEATURE_EDITING_ASK_TERMINAL=y/' .config
    sed -i 's/# CONFIG_FEATURE_EDITING_VI is not set/CONFIG_FEATURE_EDITING_VI=y/' .config
    sed -i 's/# CONFIG_FEATURE_EDITING_SAVEHISTORY is not set/CONFIG_FEATURE_EDITING_SAVEHISTORY=y/' .config
    sed -i 's/# CONFIG_FEATURE_LESS_MAXLINES is not set/CONFIG_FEATURE_LESS_MAXLINES=9999999/' .config
    
    # Disable problematic components
    sed -i 's/CONFIG_TC=y/# CONFIG_TC is not set/' .config
    sed -i 's/CONFIG_WERROR=y/# CONFIG_WERROR is not set/' .config
    
    # Build with musl
    make -j"$(nproc)" \
        CC="${CC}" \
        CFLAGS="${CFLAGS}" \
        LDFLAGS="${LDFLAGS}" \
        LDLIBS="${LDLIBS}" \
        CROSS_COMPILE="" \
        CONFIG_SYSROOT="${SYSROOT}" \
        CONFIG_PREFIX="${SYSROOT}" \
        CONFIG_EXTRA_LDLIBS="dl pthread"
    
    # Install
    make CONFIG_PREFIX="${SYSROOT}" install
    
    # Create essential symlinks
    ln -sf busybox "${SYSROOT}/bin/sh"
    
    # Create basic system directories
    for dir in root home dev proc sys tmp var mnt media run; do
        ensure_dir "${SYSROOT}/${dir}"
    done
    
    # Create /etc directory
    ensure_dir "${SYSROOT}/etc"
    
    log INFO "BusyBox build completed"
}

# Configure BusyBox
configure_busybox() {
    log INFO "Configuring BusyBox system"
    
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

    # Create minimal inittab
    cat > "${SYSROOT}/etc/inittab" << "EOF"
# /etc/inittab
::sysinit:/etc/init.d/rcS
::askfirst:-/bin/sh
::ctrlaltdel:/sbin/reboot
::shutdown:/bin/umount -a -r
::restart:/sbin/init
EOF

    # Create startup script
    ensure_dir "${SYSROOT}/etc/init.d"
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
    
    log INFO "BusyBox configuration completed"
}

# Main build process
main() {
    log INFO "Starting BusyBox build process"
    
    # Check build environment
    check_build_env || exit 1
    
    # Build steps
    build_busybox
    configure_busybox
    
    log INFO "BusyBox build process completed successfully"
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
