#!/bin/bash

# Common functions for AetherOS scripts

# Logging levels
LOG_ERROR=0
LOG_WARN=1
LOG_INFO=2
LOG_DEBUG=3

# Default log level
VERBOSE=${VERBOSE:-1}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log ERROR "This script must be run as root"
        exit 1
    fi
}

# Check system requirements
check_system() {
    local min_ram=4  # GB
    local min_cores=2
    local min_disk=20  # GB
    
    # Check RAM
    local total_ram
    total_ram=$(awk '/MemTotal/ {print $2/1024/1024}' /proc/meminfo)
    if (( $(echo "$total_ram < $min_ram" | bc -l) )); then
        log WARN "Insufficient RAM: ${total_ram}GB (minimum ${min_ram}GB recommended)"
        return 1
    fi
    
    # Check CPU cores
    local cpu_cores
    cpu_cores=$(nproc)
    if [ "$cpu_cores" -lt "$min_cores" ]; then
        log WARN "Insufficient CPU cores: ${cpu_cores} (minimum ${min_cores} recommended)"
        return 1
    fi
    
    # Check disk space
    local free_space
    free_space=$(df -BG "$(pwd)" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$free_space" -lt "$min_disk" ]; then
        log WARN "Insufficient disk space: ${free_space}GB (minimum ${min_disk}GB recommended)"
        return 1
    fi
    
    return 0
}

# Create directory if it doesn't exist
ensure_dir() {
    local dir=$1
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
    fi
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if a package is installed
package_installed() {
    if command_exists dpkg; then
        dpkg -l "$1" >/dev/null 2>&1
    elif command_exists pacman; then
        pacman -Qi "$1" >/dev/null 2>&1
    else
        log ERROR "Unknown package manager"
        return 1
    fi
}

# Get CPU architecture
get_arch() {
    uname -m
}

# Get OS distribution
get_distro() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

# Get kernel version
get_kernel_version() {
    uname -r
}

# Check if systemd is being used
using_systemd() {
    [ "$(ps --no-headers -o comm 1)" = "systemd" ]
}

# Cleanup function
cleanup() {
    # Add cleanup tasks here
    log DEBUG "Cleaning up..."
}

# Set cleanup trap
trap cleanup EXIT

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
