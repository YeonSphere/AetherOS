#!/bin/bash

# AetherOS Dependency Setup Script
# This script handles the installation of all required build dependencies

set -euo pipefail

# Source common functions and variables
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/common.sh"

# Package lists for different distributions
declare -A PKG_MAPS
PKG_MAPS["pacman"]="base-devel elfutils grub xorriso bison xz perl cpio mtools binutils squashfs-tools flex curl bc ncurses libelf gcc openssl syslinux"
PKG_MAPS["apt"]="build-essential elfutils grub-pc grub-efi-amd64 xorriso bison xz-utils perl cpio mtools binutils squashfs-tools flex curl bc libncurses-dev libelf-dev gcc libssl-dev syslinux"
PKG_MAPS["dnf"]="elfutils-devel grub2 grub2-efi-x64 xorriso bison xz perl cpio mtools binutils squashfs-tools flex curl bc ncurses-devel elfutils-libelf-devel gcc openssl-devel syslinux"

# Detect package manager
detect_package_manager() {
    for pkg_manager in "pacman" "apt" "dnf"; do
        if command -v "$pkg_manager" >/dev/null 2>&1; then
            echo "$pkg_manager"
            return 0
        fi
    done
    return 1
}

# Install packages based on distribution
install_packages() {
    local pkg_manager
    pkg_manager=$(detect_package_manager)
    
    case "${pkg_manager}" in
        pacman)
            log INFO "Installing packages for Arch Linux"
            # First sync the package database
            if ! sudo pacman -Sy; then
                log ERROR "Failed to sync package database"
                return 1
            fi
            # Install packages
            if ! sudo pacman -S --needed --noconfirm ${PKG_MAPS["pacman"]}; then
                log ERROR "Failed to install packages"
                return 1
            fi
            ;;
        apt)
            log INFO "Installing packages for Debian/Ubuntu"
            if ! sudo apt-get update; then
                log ERROR "Failed to update package database"
                return 1
            fi
            if ! sudo apt-get install -y ${PKG_MAPS["apt"]}; then
                log ERROR "Failed to install packages"
                return 1
            fi
            ;;
        dnf)
            log INFO "Installing packages for Fedora"
            if ! sudo dnf check-update; then
                log ERROR "Failed to update package database"
                return 1
            fi
            if ! sudo dnf install -y ${PKG_MAPS["dnf"]}; then
                log ERROR "Failed to install packages"
                return 1
            fi
            ;;
        *)
            log ERROR "Unsupported package manager"
            return 1
            ;;
    esac
    
    log INFO "Package installation completed successfully"
    return 0
}

# Verify installed packages
verify_packages() {
    log INFO "Verifying installed packages"
    
    local missing_packages=()
    local pkg_manager
    pkg_manager=$(detect_package_manager)
    
    case "${pkg_manager}" in
        pacman)
            for pkg in ${PKG_MAPS["pacman"]}; do
                if ! pacman -Qi "${pkg}" &>/dev/null; then
                    missing_packages+=("${pkg}")
                fi
            done
            ;;
        apt)
            for pkg in ${PKG_MAPS["apt"]}; do
                if ! dpkg -l "${pkg}" &>/dev/null; then
                    missing_packages+=("${pkg}")
                fi
            done
            ;;
        dnf)
            for pkg in ${PKG_MAPS["dnf"]}; do
                if ! rpm -q "${pkg}" &>/dev/null; then
                    missing_packages+=("${pkg}")
                fi
            done
            ;;
    esac
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        log ERROR "Missing packages: ${missing_packages[*]}"
        return 1
    fi
    
    log INFO "All required packages are installed"
    return 0
}

# Main function
main() {
    log INFO "Setting up build dependencies"
    
    local pkg_manager
    pkg_manager=$(detect_package_manager)
    log INFO "Using package manager: ${pkg_manager}"
    
    # Install packages
    if ! install_packages; then
        log ERROR "Failed to install packages"
        return 1
    fi
    
    # Verify installation
    if ! verify_packages; then
        log ERROR "Package verification failed"
        return 1
    fi
    
    log INFO "Build dependencies setup completed successfully"
    return 0
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

