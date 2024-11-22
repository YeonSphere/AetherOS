#!/bin/bash

set -euo pipefail

# QEMU configuration
MEMORY="4G"
SMP="4"
CPU_MODEL="host"
MACHINE="q35"
ACCEL="kvm"
DISPLAY="gtk"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_ROOT}/target/x86_64-unknown-none"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --memory=*)
            MEMORY="${1#*=}"
            shift
            ;;
        --smp=*)
            SMP="${1#*=}"
            shift
            ;;
        --cpu=*)
            CPU_MODEL="${1#*=}"
            shift
            ;;
        --machine=*)
            MACHINE="${1#*=}"
            shift
            ;;
        --accel=*)
            ACCEL="${1#*=}"
            shift
            ;;
        --display=*)
            DISPLAY="${1#*=}"
            shift
            ;;
        --debug)
            DEBUG=1
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Check if kernel binary exists
if [ ! -f "${BUILD_DIR}/debug/aetheros" ]; then
    echo -e "${RED}Kernel binary not found. Please build the kernel first.${NC}"
    exit 1
fi

# Function to detect system capabilities
detect_capabilities() {
    echo -e "${YELLOW}Detecting system capabilities...${NC}"
    
    # Check KVM support
    if ! grep -q "^flags.*\bvmx\b" /proc/cpuinfo && ! grep -q "^flags.*\bsvm\b" /proc/cpuinfo; then
        echo -e "${YELLOW}KVM acceleration not available, falling back to TCG${NC}"
        ACCEL="tcg"
    fi
    
    # Check CPU features
    if ! grep -q "^flags.*\bpopcnt\b" /proc/cpuinfo; then
        echo -e "${YELLOW}Advanced CPU features not available${NC}"
        CPU_MODEL="max"
    fi
}

# Function to configure QEMU options
configure_qemu() {
    QEMU_OPTS=()
    
    # Basic machine configuration
    QEMU_OPTS+=(
        "-machine" "$MACHINE,accel=$ACCEL"
        "-cpu" "$CPU_MODEL"
        "-smp" "$SMP"
        "-m" "$MEMORY"
    )
    
    # Display configuration
    QEMU_OPTS+=(
        "-display" "$DISPLAY"
        "-device" "virtio-gpu-pci"
    )
    
    # Network configuration
    QEMU_OPTS+=(
        "-netdev" "user,id=net0"
        "-device" "virtio-net-pci,netdev=net0"
    )
    
    # Storage configuration
    QEMU_OPTS+=(
        "-drive" "file=${BUILD_DIR}/debug/aetheros,format=raw,if=virtio"
    )
    
    # Debug configuration
    if [ "${DEBUG:-0}" -eq 1 ]; then
        QEMU_OPTS+=(
            "-s" "-S"
            "-d" "int,cpu_reset"
            "-no-reboot"
            "-no-shutdown"
        )
    fi
    
    # Serial output
    QEMU_OPTS+=(
        "-serial" "stdio"
    )
}

# Function to run QEMU
run_qemu() {
    echo -e "${YELLOW}Starting QEMU...${NC}"
    
    if [ "${DEBUG:-0}" -eq 1 ]; then
        echo -e "${YELLOW}Debug mode enabled. Connect GDB to localhost:1234${NC}"
    fi
    
    qemu-system-x86_64 "${QEMU_OPTS[@]}"
}

# Main function
main() {
    echo -e "${YELLOW}Preparing to run AetherOS...${NC}"
    
    detect_capabilities
    configure_qemu
    run_qemu
}

main
