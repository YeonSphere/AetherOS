#!/bin/bash

# Test script for AetherOS kernel build system
# This script verifies the kernel build process and configuration

set -e  # Exit on any error

# Source common functions if available
if [ -f "$(dirname "$0")/common.sh" ]; then
    source "$(dirname "$0")/common.sh"
else
    echo "ERROR: common.sh not found"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test status tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

log_test() {
    local level=$1
    shift
    local message=$*
    case $level in
        "PASS") echo -e "${GREEN}[PASS]${NC} $message" ;;
        "FAIL") echo -e "${RED}[FAIL]${NC} $message" ;;
        "INFO") echo -e "${YELLOW}[INFO]${NC} $message" ;;
    esac
}

run_test() {
    local test_name=$1
    local test_cmd=$2
    
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "INFO" "Running test: $test_name"
    
    if eval "$test_cmd"; then
        log_test "PASS" "$test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_test "FAIL" "$test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Test 1: Check build dependencies
test_dependencies() {
    local deps=(
        "make"
        "gcc"
        "as"  # binutils assembler
        "ld"  # binutils linker
        "flex"
        "bison"
        "readelf"  # from libelf
        "bc"
        "rsync"
    )
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            echo "Missing dependency: $dep"
            return 1
        fi
    done
    return 0
}

# Test 2: Check kernel source
test_kernel_source() {
    local kernel_dir="/home/dae/YeonSphere/AetherOS/kernel/linux/linux-6.11.9"
    
    if [ ! -d "$kernel_dir" ]; then
        echo "Kernel directory not found: $kernel_dir"
        return 1
    fi
    
    if [ ! -f "$kernel_dir/Makefile" ]; then
        echo "Kernel Makefile not found"
        return 1
    fi
    return 0
}

# Test 3: Test config generation
test_config_generation() {
    cd "/home/dae/YeonSphere/AetherOS/kernel/linux/linux-6.11.9" || return 1
    
    if [ ! -f ".config" ]; then
        if [ -f "/proc/config.gz" ]; then
            zcat /proc/config.gz > .config
            log_test "INFO" "Using current system's kernel config"
        else
            make defconfig >/dev/null 2>&1
            log_test "INFO" "Using default kernel config"
        fi
    fi
    
    return 0
}

# Test 4: Verify custom configs
test_custom_configs() {
    local config_file="/home/dae/YeonSphere/AetherOS/kernel/linux/linux-6.11.9/.config"
    local required_configs=(
        "CONFIG_PREEMPT=y"
        "CONFIG_HIGH_RES_TIMERS=y"
        "CONFIG_NO_HZ_FULL=y"
        "CONFIG_NUMA=y"
    )
    
    for config in "${required_configs[@]}"; do
        if ! grep -q "^$config" "$config_file"; then
            echo "Missing required config: $config"
            return 1
        fi
    done
    return 0
}

# Test 5: Test minimal build
test_minimal_build() {
    export MINIMAL=1
    cd "/home/dae/YeonSphere/AetherOS/kernel/linux/linux-6.11.9" || return 1
    if ! make -j"$(nproc)" bzImage modules >/dev/null 2>&1; then
        echo "Minimal kernel build failed"
        return 1
    fi
    return 0
}

# Run all tests
main() {
    log_test "INFO" "Starting AetherOS kernel build tests"
    
    run_test "Build Dependencies" test_dependencies
    run_test "Kernel Source" test_kernel_source
    run_test "Config Generation" test_config_generation
    run_test "Custom Configs" test_custom_configs
    run_test "Minimal Build" test_minimal_build
    
    # Print summary
    echo
    echo "Test Summary:"
    echo "============="
    echo "Total tests: $TESTS_RUN"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    # Return overall status
    [ "$TESTS_FAILED" -eq 0 ]
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
