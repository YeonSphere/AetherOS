#!/bin/bash
# AetherOS Patch Management System
# Manages kernel patches and customizations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="$SCRIPT_DIR/../kernel/linux"
PATCHES_DIR="$SCRIPT_DIR/../patches"
BACKUP_DIR="$SCRIPT_DIR/../backups"
VERSION_FILE="$SCRIPT_DIR/../.kernel_version"

log() {
    local level="$1"
    shift
    echo "[$level] $*" >&2
}

error() {
    log "ERROR" "$@"
    exit 1
}

create_patch() {
    local name="$1"
    local description="$2"
    local date=$(date +%Y%m%d)
    local patch_file="$PATCHES_DIR/${date}_${name}.patch"
    local meta_file="$PATCHES_DIR/${date}_${name}.meta"
    
    # Create patches directory if it doesn't exist
    mkdir -p "$PATCHES_DIR"
    
    # Generate patch from current changes
    if ! git -C "$KERNEL_DIR" diff > "$patch_file"; then
        error "Failed to create patch file"
    fi
    
    # Create metadata file
    cat > "$meta_file" << EOF
Description: $description
Created: $(date -R)
Kernel-Version: $(cat "$VERSION_FILE")
Dependencies: 
EOF
    
    log "INFO" "Created patch: $patch_file"
    log "INFO" "Created metadata: $meta_file"
}

apply_patches() {
    local target_dir="$1"
    local version="$2"
    
    if [ ! -d "$PATCHES_DIR" ]; then
        log "INFO" "No patches directory found, skipping"
        return 0
    fi
    
    # Sort patches by date prefix
    for patch_file in $(ls "$PATCHES_DIR"/*.patch 2>/dev/null | sort); do
        local meta_file="${patch_file%.patch}.meta"
        
        if [ -f "$meta_file" ]; then
            local patch_version=$(grep "Kernel-Version:" "$meta_file" | cut -d: -f2 | tr -d ' ')
            if [ "$patch_version" = "$version" ]; then
                log "INFO" "Applying patch: $(basename "$patch_file")"
                if ! patch -d "$target_dir" -p1 < "$patch_file"; then
                    error "Failed to apply patch: $(basename "$patch_file")"
                fi
            fi
        fi
    done
}

backup_kernel() {
    local version="$1"
    local date=$(date +%Y%m%d)
    local backup_file="$BACKUP_DIR/kernel_${version}_${date}.tar.gz"
    
    mkdir -p "$BACKUP_DIR"
    
    log "INFO" "Creating kernel backup: $backup_file"
    if ! tar -czf "$backup_file" -C "$KERNEL_DIR" .; then
        error "Failed to create kernel backup"
    fi
}

restore_kernel() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        error "Backup file not found: $backup_file"
    fi
    
    log "INFO" "Restoring kernel from backup: $backup_file"
    rm -rf "$KERNEL_DIR"/*
    if ! tar -xzf "$backup_file" -C "$KERNEL_DIR"; then
        error "Failed to restore kernel backup"
    fi
}

update_kernel() {
    local new_source="$1"
    local current_version=$(cat "$VERSION_FILE")
    
    # Backup current kernel
    backup_kernel "$current_version"
    
    # Extract new kernel
    log "INFO" "Extracting new kernel source"
    rm -rf "$KERNEL_DIR"/*
    if ! tar -xf "$new_source" -C "$KERNEL_DIR" --strip-components=1; then
        error "Failed to extract new kernel source"
    fi
    
    # Update version file
    local new_version=$(make -C "$KERNEL_DIR" kernelversion 2>/dev/null)
    echo "$new_version" > "$VERSION_FILE"
    
    # Apply patches
    apply_patches "$KERNEL_DIR" "$new_version"
    
    log "INFO" "Kernel updated to version $new_version"
}

list_patches() {
    if [ ! -d "$PATCHES_DIR" ]; then
        log "INFO" "No patches found"
        return 0
    fi
    
    echo "Available patches:"
    for meta_file in "$PATCHES_DIR"/*.meta; do
        if [ -f "$meta_file" ]; then
            local patch_name=$(basename "${meta_file%.meta}")
            echo "- $patch_name"
            grep "Description:" "$meta_file" | cut -d: -f2-
            echo
        fi
    done
}

usage() {
    cat << EOF
Usage: $(basename "$0") COMMAND [OPTIONS]

Commands:
    create NAME DESCRIPTION  Create a new patch from current changes
    apply DIR VERSION       Apply patches to specified directory
    backup VERSION         Create a backup of current kernel
    restore FILE           Restore kernel from backup
    update FILE           Update kernel with new source
    list                  List available patches

Options:
    -h, --help           Show this help message
EOF
}

main() {
    if [ $# -lt 1 ]; then
        usage
        exit 1
    fi
    
    case "$1" in
        create)
            if [ $# -ne 3 ]; then
                error "Usage: $0 create NAME DESCRIPTION"
            fi
            create_patch "$2" "$3"
            ;;
        apply)
            if [ $# -ne 3 ]; then
                error "Usage: $0 apply DIR VERSION"
            fi
            apply_patches "$2" "$3"
            ;;
        backup)
            if [ $# -ne 2 ]; then
                error "Usage: $0 backup VERSION"
            fi
            backup_kernel "$2"
            ;;
        restore)
            if [ $# -ne 2 ]; then
                error "Usage: $0 restore FILE"
            fi
            restore_kernel "$2"
            ;;
        update)
            if [ $# -ne 2 ]; then
                error "Usage: $0 update FILE"
            fi
            update_kernel "$2"
            ;;
        list)
            list_patches
            ;;
        -h|--help)
            usage
            ;;
        *)
            error "Unknown command: $1"
            ;;
    esac
}

main "$@"
