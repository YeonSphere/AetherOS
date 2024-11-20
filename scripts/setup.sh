#!/bin/bash

# AetherOS Setup Script for Arch-based systems

# Default options
VERBOSE=${VERBOSE:-0}
FORCE=${FORCE:-0}
SKIP_TESTS=${SKIP_TESTS:-0}
MINIMAL=${MINIMAL:-0}
LOG_FILE="/tmp/aetheros-setup.log"
LOG_LEVEL=${LOG_LEVEL:-"INFO"}  # DEBUG, INFO, WARN, ERROR
BUILD_TYPE=${BUILD_TYPE:-"release"}  # debug, release, profile
ARCH=${ARCH:-"x86_64"}
TARGET_CPU=${TARGET_CPU:-"native"}
PACKAGE_VERSION=${PACKAGE_VERSION:-"0.1.0"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Error handling
set -eE
trap 'error_handler $? $LINENO $BASH_LINENO "$BASH_COMMAND" $(printf "::%s" ${FUNCNAME[@]:-})' ERR

# Function to handle errors
error_handler() {
    local exit_code=$1
    local line_no=$2
    local bash_lineno=$3
    local last_command=$4
    local func_trace=$5
    
    echo -e "${RED}╔════ Error Details ════╗${NC}" >&2
    echo -e "${RED}║ Script failed!        ║${NC}" >&2
    echo -e "${RED}║ Exit code: $exit_code         ║${NC}" >&2
    echo -e "${RED}║ Line: $line_no              ║${NC}" >&2
    echo -e "${RED}║ Command: $last_command${NC}" >&2
    echo -e "${RED}║ Function: $func_trace${NC}" >&2
    echo -e "${RED}╚════════════════════════╝${NC}" >&2
    
    if [ $VERBOSE -eq 1 ]; then
        echo -e "${YELLOW}Full logs available at: $LOG_FILE${NC}" >&2
        echo -e "${YELLOW}Last 10 log entries:${NC}" >&2
        tail -n 10 "$LOG_FILE" >&2
    fi
    
    cleanup
    exit $exit_code
}

# Function for cleanup on exit
cleanup() {
    # Save logs to permanent location if error occurred
    if [ $? -ne 0 ]; then
        local timestamp=$(date '+%Y%m%d_%H%M%S')
        local error_log="/var/log/aetheros/setup_error_${timestamp}.log"
        sudo mkdir -p /var/log/aetheros
        sudo cp "$LOG_FILE" "$error_log"
        echo -e "${YELLOW}Error log saved to: $error_log${NC}"
    fi
    
    # Remove temporary files
    rm -f /tmp/aetheros-setup-*
}

# Function to log messages
log() {
    local level=$1
    shift
    local msg="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_prefix=""
    
    # Only log if level is at or above LOG_LEVEL
    case $LOG_LEVEL in
        DEBUG) log_prefix="🔍";;
        INFO)  
            [[ $level == "DEBUG" ]] && return
            log_prefix="ℹ️ ";;
        WARN)  
            [[ $level == "DEBUG" || $level == "INFO" ]] && return
            log_prefix="⚠️ ";;
        ERROR) 
            [[ $level != "ERROR" ]] && return
            log_prefix="❌";;
    esac
    
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
    
    case $level in
        DEBUG)
            [[ "${VERBOSE}" = "1" ]] && echo -e "${CYAN}${log_prefix} $msg${NC}"
            ;;
        INFO)
            [[ "${VERBOSE}" = "1" ]] && echo -e "${GREEN}${log_prefix} $msg${NC}"
            ;;
        WARN)
            echo -e "${YELLOW}${log_prefix} $msg${NC}"
            ;;
        ERROR)
            echo -e "${RED}${log_prefix} $msg${NC}" >&2
            ;;
        *)
            [[ "${VERBOSE}" = "1" ]] && echo -e "$msg"
            ;;
    esac
}

# Function to check system compatibility
check_system() {
    log INFO "Performing comprehensive system check..."
    
    # CPU checks
    log DEBUG "Checking CPU compatibility..."
    if ! grep -q "^flags.*sse4_2" /proc/cpuinfo; then
        log ERROR "CPU does not support SSE4.2 (required for LLVM)"
        exit 1
    fi
    
    # Check virtualization support
    if ! grep -q "^flags.*vmx\|svm" /proc/cpuinfo; then
        log WARN "CPU virtualization not detected - QEMU performance may be impacted"
    fi
    
    # Architecture check
    local arch=$(uname -m)
    if [ "$arch" != "x86_64" ]; then
        log ERROR "Unsupported architecture: $arch (only x86_64 is supported)"
        exit 1
    fi
    
    # OS check
    if ! command -v pacman &> /dev/null; then
        log ERROR "This script requires pacman package manager (Arch-based system)"
        exit 1
    fi
    
    # Kernel version check
    local kernel_version=$(uname -r | cut -d. -f1,2)
    if (( $(echo "$kernel_version < 5.10" | bc -l) )); then
        log ERROR "Kernel version too old. Required: >= 5.10, Found: $kernel_version"
        exit 1
    fi
    
    # Check for systemd (required for some services)
    if ! pidof systemd &> /dev/null; then
        log ERROR "systemd is required but not running"
        exit 1
    fi
    
    # Resource checks
    log DEBUG "Checking system resources..."
    
    # CPU cores
    local cpu_cores=$(nproc)
    if [ $cpu_cores -lt 2 ]; then
        log WARN "Only $cpu_cores CPU core(s) detected - build performance may be impacted"
    else
        log DEBUG "CPU cores: $cpu_cores"
    fi
    
    # Memory check
    local total_mem=$(free -g | awk '/^Mem:/{print $2}')
    local required_mem=4
    if [ $total_mem -lt $required_mem ]; then
        log ERROR "Insufficient memory. Required: ${required_mem}GB, Available: ${total_mem}GB"
        exit 1
    fi
    
    # Swap check
    local total_swap=$(free -g | awk '/^Swap:/{print $2}')
    if [ $total_swap -lt 2 ]; then
        log WARN "Low swap space detected (< 2GB) - may impact build performance"
    fi
    
    # Disk space
    local required_space=10
    local available_space=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ $available_space -lt $required_space ]; then
        log ERROR "Insufficient disk space. Required: ${required_space}GB, Available: ${available_space}GB"
        exit 1
    fi
    
    # Check for required base commands
    local required_commands=("git" "curl" "gcc" "make" "sudo")
    for cmd in "${required_commands[@]}"; do
        if ! command -v $cmd &> /dev/null; then
            log ERROR "Required command not found: $cmd"
            exit 1
        fi
    done
    
    # Network connectivity
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        log ERROR "No internet connectivity detected"
        exit 1
    fi
    
    # Check for required services
    local required_services=("dbus" "systemd-logind" "systemd-journald")
    for service in "${required_services[@]}"; do
        if ! systemctl is-active --quiet $service; then
            log ERROR "Required service not running: $service"
            exit 1
        fi
    done
    
    # Development tools version checks
    if command -v gcc &> /dev/null; then
        local gcc_version=$(gcc -dumpversion)
        if (( $(echo "${gcc_version%%.*} < 10" | bc -l) )); then
            log ERROR "GCC version too old. Required: >= 10.0, Found: $gcc_version"
            exit 1
        fi
    fi
    
    if command -v clang &> /dev/null; then
        local clang_version=$(clang --version | grep -oP 'clang version \K[0-9]+')
        if (( $(echo "${clang_version%%.*} < 12" | bc -l) )); then
            log ERROR "Clang version too old. Required: >= 12.0, Found: $clang_version"
            exit 1
        fi
    fi
    
    log INFO "System check completed successfully"
}
