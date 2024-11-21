#!/bin/bash

# Script to install required dependencies for AetherOS build system
# Specifically for Arch Linux

set -euo pipefail

# Required packages and their Arch Linux package names
declare -A PACKAGES=(
    ["gcc"]="gcc"
    ["make"]="make"
    ["wget"]="wget"
    ["tar"]="tar"
    ["systemd-run"]="systemd"
    ["xorriso"]="libisoburn"
    ["grub-mkrescue"]="grub"
    ["bc"]="bc"                     # Required for kernel build
    ["flex"]="flex"                 # Required for kernel build
    ["bison"]="bison"              # Required for kernel build
    ["eu-readelf"]="elfutils"      # Required for kernel build (checking for eu-readelf instead of elfutils)
    ["openssl"]="openssl"          # Required for kernel build
    ["xz"]="xz"                    # Required for compression
    ["cpio"]="cpio"                # Required for initramfs
    ["gzip"]="gzip"                # Required for compression
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check if running on Arch Linux
if [ ! -f "/etc/arch-release" ]; then
    error "This script is intended for Arch Linux only"
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root"
fi

# Check if pacman is available
if ! command -v pacman &> /dev/null; then
    error "pacman package manager not found"
fi

# Update package database
log "Updating package database..."
pacman -Sy

# Check which packages need to be installed
PACKAGES_TO_INSTALL=()
for cmd in "${!PACKAGES[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        PACKAGES_TO_INSTALL+=("${PACKAGES[$cmd]}")
    else
        log "$cmd already installed (package: ${PACKAGES[$cmd]})"
    fi
done

# Install missing packages
if [ ${#PACKAGES_TO_INSTALL[@]} -eq 0 ]; then
    log "All required packages are already installed"
else
    log "Installing missing packages: ${PACKAGES_TO_INSTALL[*]}"
    pacman -S --needed --noconfirm "${PACKAGES_TO_INSTALL[@]}"
fi

# Verify all commands are available
MISSING_COMMANDS=()
for cmd in "${!PACKAGES[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        MISSING_COMMANDS+=("$cmd")
    fi
done

if [ ${#MISSING_COMMANDS[@]} -eq 0 ]; then
    log "All required commands are now available"
else
    error "Some commands are still missing: ${MISSING_COMMANDS[*]}"
fi

log "All dependencies have been installed successfully"
