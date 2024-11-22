#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Starting AetherOS...${NC}"

qemu-system-x86_64 \
    -m 1G \
    -smp 2 \
    -drive file=aetheros.img,format=raw \
    -serial stdio \
    -display gtk \
    -enable-kvm \
    -cpu host \
    -monitor stdio
