#!/bin/bash

set -euo pipefail

# Test configuration
RUST_VERSION="nightly-2023-10-01"
TARGET="x86_64-unknown-none"
TEST_TYPE=${1:-unit}  # unit, integration, or all

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_DIR="${PROJECT_ROOT}/tests"

# Function to run unit tests
run_unit_tests() {
    echo -e "${YELLOW}Running unit tests...${NC}"
    
    cd "$PROJECT_ROOT"
    RUSTFLAGS="-C target-cpu=native" \
    cargo "+$RUST_VERSION" test \
        --target "$TARGET" \
        --lib \
        -- --nocapture
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Unit tests passed!${NC}"
    else
        echo -e "${RED}Unit tests failed!${NC}"
        exit 1
    fi
}

# Function to run integration tests
run_integration_tests() {
    echo -e "${YELLOW}Running integration tests...${NC}"
    
    cd "$PROJECT_ROOT"
    RUSTFLAGS="-C target-cpu=native" \
    cargo "+$RUST_VERSION" test \
        --target "$TARGET" \
        --test '*' \
        -- --nocapture
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Integration tests passed!${NC}"
    else
        echo -e "${RED}Integration tests failed!${NC}"
        exit 1
    fi
}

# Function to run performance tests
run_performance_tests() {
    echo -e "${YELLOW}Running performance tests...${NC}"
    
    cd "$PROJECT_ROOT"
    RUSTFLAGS="-C target-cpu=native" \
    cargo "+$RUST_VERSION" bench \
        --target "$TARGET" \
        -- --nocapture
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Performance tests completed!${NC}"
    else
        echo -e "${RED}Performance tests failed!${NC}"
        exit 1
    fi
}

# Function to run security tests
run_security_tests() {
    echo -e "${YELLOW}Running security tests...${NC}"
    
    cd "$PROJECT_ROOT/tests/security"
    ./run_security_tests.sh
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Security tests passed!${NC}"
    else
        echo -e "${RED}Security tests failed!${NC}"
        exit 1
    fi
}

# Function to generate test coverage report
generate_coverage_report() {
    echo -e "${YELLOW}Generating test coverage report...${NC}"
    
    cd "$PROJECT_ROOT"
    cargo "+$RUST_VERSION" tarpaulin \
        --target "$TARGET" \
        --out Html \
        --output-dir target/coverage
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Coverage report generated successfully!${NC}"
    else
        echo -e "${RED}Coverage report generation failed!${NC}"
        exit 1
    fi
}

# Main test process
main() {
    echo -e "${YELLOW}Starting AetherOS test suite...${NC}"
    
    case "$TEST_TYPE" in
        "unit")
            run_unit_tests
            ;;
        "integration")
            run_integration_tests
            ;;
        "performance")
            run_performance_tests
            ;;
        "security")
            run_security_tests
            ;;
        "all")
            run_unit_tests
            run_integration_tests
            run_performance_tests
            run_security_tests
            generate_coverage_report
            ;;
        *)
            echo -e "${RED}Invalid test type: $TEST_TYPE${NC}"
            echo "Valid options: unit, integration, performance, security, all"
            exit 1
            ;;
    esac
    
    echo -e "${GREEN}Test suite completed successfully!${NC}"
}

main
