#!/bin/bash

# Common functions for AetherOS scripts

# Base paths
export AETHER_ROOT="/home/dae/YeonSphere/AetherOS"
export BUILD_ROOT="${AETHER_ROOT}/build"
export SYSROOT="${BUILD_ROOT}/sysroot"
export TOOLS_DIR="${BUILD_ROOT}/tools"

# Build configuration
export ARCH="x86_64"
export TARGET="x86_64-aetheros-linux-musl"
export HOST="$(gcc -dumpmachine)"
export BUILD="$(gcc -dumpmachine)"
export CROSS_COMPILE=""  # Will be set if cross-compiling
export MAKEFLAGS="-j$(nproc)"

# Kernel paths
export KERNEL_VERSION="6.11.9"
export KERNEL_PATH="${BUILD_ROOT}/boot/vmlinuz-${KERNEL_VERSION}-aetheros"
export KERNEL_HEADERS="${SYSROOT}/usr/include"

# Logging levels
export LOG_ERROR=0
export LOG_WARN=1
export LOG_INFO=2
export LOG_DEBUG=3

# Default log level
export VERBOSE=${VERBOSE:-2}  # Set to INFO by default

# Colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m'

# Logging function
log() {
    local level=$1
    shift
    local message=$*
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        ERROR)
            [[ $VERBOSE -ge $LOG_ERROR ]] && echo -e "${timestamp} ${RED}[ERROR]${NC} $message" >&2
            ;;
        WARN)
            [[ $VERBOSE -ge $LOG_WARN ]] && echo -e "${timestamp} ${YELLOW}[WARN]${NC} $message"
            ;;
        INFO)
            [[ $VERBOSE -ge $LOG_INFO ]] && echo -e "${timestamp} ${GREEN}[INFO]${NC} $message"
            ;;
        DEBUG)
            [[ $VERBOSE -ge $LOG_DEBUG ]] && echo -e "${timestamp} ${BLUE}[DEBUG]${NC} $message"
            ;;
    esac
}

# Cleanup function
cleanup() {
    log DEBUG "Cleaning up..."
    # Add cleanup tasks here
}

# Utility functions
ensure_dir() {
    local dir=$1
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

package_installed() {
    if command_exists dpkg; then
        dpkg -l "$1" >/dev/null 2>&1
    elif command_exists rpm; then
        rpm -q "$1" >/dev/null 2>&1
    else
        return 1
    fi
}

get_arch() {
    uname -m
}

get_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

get_kernel_version() {
    uname -r
}

using_systemd() {
    [ -d /run/systemd/system ]
}

# Check if running as root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        log ERROR "This script must be run as root"
        return 1
    fi
}

# Check system requirements
check_system() {
    local required_commands=(
        "gcc"
        "make"
        "wget"
        "tar"
        "patch"
        "ld"
        "ar"
        "as"
    )
    
    # Check if we're on Arch Linux
    if [ "$(get_distro)" != "arch" ]; then
        log WARN "This build system is optimized for Arch Linux"
    fi
    
    # Check for required commands
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            log ERROR "Required command not found: $cmd. Please install base-devel package group."
            return 1
        fi
    done
    
    # Check for kernel headers
    if [ ! -f "${KERNEL_PATH}" ]; then
        log ERROR "Kernel not found at ${KERNEL_PATH}. Please build the kernel first."
        return 1
    fi
    
    # Set compilation environment
    export CROSS_COMPILE=""
    export CC="gcc"
    export CXX="g++"
    export LD="ld"
    export AR="ar"
    export AS="as"
    
    return 0
}

# Check build environment
check_build_env() {
    # Check system requirements
    if ! check_system; then
        return 1
    fi
    
    # Check directories
    ensure_dir "$BUILD_ROOT"
    ensure_dir "$SYSROOT"
    ensure_dir "$TOOLS_DIR"
    
    return 0
}

# Export functions
export -f log
export -f check_root
export -f check_system
export -f ensure_dir
export -f command_exists
export -f package_installed
export -f get_arch
export -f get_distro
export -f get_kernel_version
export -f using_systemd
export -f check_build_env

# Set up cleanup trap
trap cleanup EXIT
