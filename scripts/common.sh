#!/bin/bash
# Common functions for AetherOS build system

log() {
    local level="$1"
    shift
    echo "[$level] $*" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >> "$BUILD_LOG"
}

error() {
    log "ERROR" "$@"
    exit 1
}

check_dependencies() {
    local bins=(
        make gcc g++ flex bison bc rsync cpio
        grub-install xorriso mkinitcpio pacstrap
    )
    local pkgs=(
        elfutils openssl grub efibootmgr
        arch-install-scripts
    )
    
    log "INFO" "Checking build dependencies..."
    
    # Check binary dependencies
    for bin in "${bins[@]}"; do
        if ! command -v "$bin" >/dev/null 2>&1; then
            error "Missing binary dependency: $bin"
        fi
    done
    
    # Check package dependencies
    for pkg in "${pkgs[@]}"; do
        if ! pacman -Qi "$pkg" >/dev/null 2>&1; then
            error "Missing package dependency: $pkg"
        fi
    done
}
