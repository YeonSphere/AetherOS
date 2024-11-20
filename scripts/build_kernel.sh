#!/bin/bash

# AetherOS Kernel Build System
# This script handles kernel building, testing, and bootloader configuration

set -euo pipefail

# Source common functions
source "$(dirname "$0")/setup.sh"

# Kernel configuration
KERNEL_VERSION="6.6"  # Latest stable as of now
KERNEL_SOURCE="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz"
BUILD_DIR="/home/dae/YeonSphere/AetherOS/kernel"
BOOT_DIR="/home/dae/YeonSphere/AetherOS/boot"
CONFIG_DIR="/home/dae/YeonSphere/AetherOS/configs"
JOBS=$(nproc)

# Bootloader configurations
declare -A BOOTLOADER_CONFIGS
BOOTLOADER_CONFIGS=(
    ["uefi"]="efi64 efi32"
    ["bios"]="i386-pc"
    ["coreboot"]="i386-coreboot"
    ["efi-chromebook"]="arm64-efi"
)

# Function to download and extract kernel
download_kernel() {
    log INFO "Downloading Linux kernel ${KERNEL_VERSION}..."
    
    cd "$BUILD_DIR"
    
    if [ ! -f "linux-${KERNEL_VERSION}.tar.xz" ]; then
        wget "$KERNEL_SOURCE" || {
            log ERROR "Failed to download kernel source"
            exit 1
        }
    fi
    
    if [ ! -d "linux-${KERNEL_VERSION}" ]; then
        tar xf "linux-${KERNEL_VERSION}.tar.xz" || {
            log ERROR "Failed to extract kernel source"
            exit 1
        }
    fi
    
    cd "linux-${KERNEL_VERSION}"
}

# Function to configure kernel
configure_kernel() {
    log INFO "Configuring kernel..."
    
    # Start with a clean slate
    make mrproper
    
    # Copy current system's config as base
    if [ -f "/boot/config-$(uname -r)" ]; then
        cp "/boot/config-$(uname -r)" .config
        log INFO "Using current system's kernel config as base"
    else
        # Generate default config
        make defconfig
        log INFO "Using default kernel config"
    fi
    
    # Apply AetherOS specific configurations
    cat >> .config << EOF
# AetherOS Kernel Configuration
CONFIG_LOCALVERSION="-aetheros"
CONFIG_PREEMPT=y
CONFIG_PREEMPT_RCU=y
CONFIG_HZ_1000=y
CONFIG_HZ=1000
CONFIG_NO_HZ=y
CONFIG_HIGH_RES_TIMERS=y
CONFIG_TRANSPARENT_HUGEPAGE=y
CONFIG_NUMA=y
CONFIG_NUMA_BALANCING=y
CONFIG_CHECKPOINT_RESTORE=y
CONFIG_KEXEC=y
CONFIG_KEXEC_FILE=y
CONFIG_SECURITY=y
CONFIG_SECURITY_NETWORK=y
CONFIG_HARDENED_USERCOPY=y
CONFIG_FORTIFY_SOURCE=y
CONFIG_STATIC_USERMODEHELPER=y
CONFIG_SECURITY_SELINUX=y
CONFIG_SECURITY_APPARMOR=y
CONFIG_SECURITY_LOCKDOWN_LSM=y
CONFIG_SECURITY_LOCKDOWN_LSM_EARLY=y
CONFIG_SECURITY_YAMA=y
CONFIG_INTEGRITY=y
CONFIG_IMA=y
CONFIG_EVM=y
CONFIG_CRYPTO_SHA512=y
CONFIG_CRYPTO_AES_NI_INTEL=y
CONFIG_CRYPTO_USER_API_HASH=y
CONFIG_CRYPTO_USER_API_SKCIPHER=y
CONFIG_CRYPTO_USER_API_RNG=y
CONFIG_CRYPTO_USER_API_AEAD=y
EOF
    
    # Make sure configuration is valid
    make olddefconfig
    
    # Allow user to make additional configurations
    log INFO "Opening menuconfig for additional customization..."
    make menuconfig
}

# Function to build kernel
build_kernel() {
    log INFO "Building kernel..."
    
    # Clean build artifacts
    make clean
    
    # Build kernel and modules
    make -j"$JOBS" all || {
        log ERROR "Kernel build failed"
        exit 1
    }
    
    # Build modules
    make -j"$JOBS" modules || {
        log ERROR "Module build failed"
        exit 1
    }
}

# Function to install kernel for testing
install_kernel_test() {
    log INFO "Installing kernel for testing..."
    
    # Install modules
    sudo make modules_install || {
        log ERROR "Module installation failed"
        exit 1
    }
    
    # Install kernel
    sudo make install || {
        log ERROR "Kernel installation failed"
        exit 1
    }
    
    # Generate initial ramdisk
    sudo mkinitcpio -k "${KERNEL_VERSION}-aetheros" -g "/boot/initramfs-${KERNEL_VERSION}-aetheros.img" || {
        log ERROR "Failed to generate initramfs"
        exit 1
    }
}

# Function to create installable package
create_package() {
    log INFO "Creating installable kernel package..."
    
    local pkg_dir="/tmp/aetheros-kernel-${KERNEL_VERSION}"
    local pkg_name="aetheros-kernel-${KERNEL_VERSION}-${ARCH}.tar.zst"
    
    # Create package directory structure
    mkdir -p "${pkg_dir}/"{boot,lib/modules,PKGBUILD}
    
    # Copy kernel and modules
    cp "/boot/vmlinuz-${KERNEL_VERSION}-aetheros" "${pkg_dir}/boot/"
    cp "/boot/initramfs-${KERNEL_VERSION}-aetheros.img" "${pkg_dir}/boot/"
    cp -r "/lib/modules/${KERNEL_VERSION}-aetheros" "${pkg_dir}/lib/modules/"
    
    # Create PKGBUILD
    cat > "${pkg_dir}/PKGBUILD" << EOF
# Maintainer: AetherOS Team
pkgname=aetheros-kernel
pkgver=${KERNEL_VERSION}
pkgrel=1
pkgdesc="AetherOS optimized kernel"
arch=('${ARCH}')
url="https://github.com/YeonSphere/AetherOS"
license=('GPL2')
depends=('kmod' 'linux-firmware' 'mkinitcpio')
optdepends=('crda: to set the correct wireless channels of your country')
provides=("linux=${KERNEL_VERSION}")
conflicts=('linux')
backup=("etc/mkinitcpio.d/\${pkgname}.preset")
options=('!strip')

package() {
    cp -r boot "\${pkgdir}/"
    cp -r lib "\${pkgdir}/"
    
    # Install mkinitcpio preset
    install -Dm644 /dev/null "\${pkgdir}/etc/mkinitcpio.d/\${pkgname}.preset"
    cat > "\${pkgdir}/etc/mkinitcpio.d/\${pkgname}.preset" << _EOF
# mkinitcpio preset file for AetherOS kernel
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-${KERNEL_VERSION}-aetheros"

PRESETS=('default' 'fallback')

default_image="/boot/initramfs-${KERNEL_VERSION}-aetheros.img"
default_options=""

fallback_image="/boot/initramfs-${KERNEL_VERSION}-aetheros-fallback.img"
fallback_options="-S autodetect"
_EOF
}
EOF
    
    # Build the package
    cd "${pkg_dir}"
    makepkg -s --noconfirm
    
    # Move package to build directory
    mv "${pkg_name}" "${BUILD_DIR}/"
    
    log INFO "Kernel package created: ${BUILD_DIR}/${pkg_name}"
    
    # Cleanup
    rm -rf "${pkg_dir}"
}

# Function to configure bootloader
configure_bootloader() {
    log INFO "Configuring bootloader..."
    
    # Detect boot type
    if [ -d "/sys/firmware/efi" ]; then
        BOOT_TYPE="uefi"
    else
        BOOT_TYPE="bios"
    fi
    
    # Create GRUB configuration
    sudo mkdir -p /etc/grub.d/custom
    cat > /etc/grub.d/custom/40_aetheros << EOF
#!/bin/sh
exec tail -n +3 \$0
menuentry "AetherOS Linux ${KERNEL_VERSION}" {
    load_video
    insmod gzio
    if [ x\$grub_platform = xxen ]; then insmod xzio; insmod lzopio; fi
    insmod part_gpt
    insmod ext2
    search --no-floppy --fs-uuid --set=root $(blkid -s UUID -o value $(df -P / | awk 'NR==2 {print $1}'))
    echo    'Loading Linux ${KERNEL_VERSION}-aetheros ...'
    linux   /boot/vmlinuz-${KERNEL_VERSION}-aetheros root=UUID=$(blkid -s UUID -o value $(df -P / | awk 'NR==2 {print $1}')) rw quiet
    echo    'Loading initial ramdisk ...'
    initrd  /boot/initramfs-${KERNEL_VERSION}-aetheros.img
}
EOF
    
    chmod +x /etc/grub.d/custom/40_aetheros
    
    # Update GRUB configuration
    sudo grub-mkconfig -o /boot/grub/grub.cfg
}

# Main function
main() {
    log INFO "Starting AetherOS kernel build process..."
    
    # Download and extract kernel
    download_kernel
    
    # Configure kernel
    configure_kernel
    
    # Build kernel
    build_kernel
    
    # Install for testing
    install_kernel_test
    
    # Create installable package
    create_package
    
    # Configure bootloader
    configure_bootloader
    
    log INFO "Kernel build process completed successfully"
    log INFO "You can now reboot and select AetherOS kernel from the boot menu"
    log INFO "Installable package created at: ${BUILD_DIR}/aetheros-kernel-${KERNEL_VERSION}-${ARCH}.tar.zst"
}

# Run main function
main "$@"
