#!/bin/sh
# AetherOS Installer Script

# Set up basic environment
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export TERM=linux

# Colors for better UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "${GREEN}Welcome to AetherOS Installer${NC}"
echo "This will guide you through the installation process."
echo

# Basic system checks
echo "${YELLOW}Checking system requirements...${NC}"
if [ $(uname -m) != "x86_64" ]; then
    echo "${RED}Error: This installer only supports x86_64 systems${NC}"
    exit 1
fi

# Main menu
while true; do
    echo
    echo "${GREEN}AetherOS Installation Menu${NC}"
    echo "1. Partition Disks"
    echo "2. Format Partitions"
    echo "3. Install Base System"
    echo "4. Configure System"
    echo "5. Install Bootloader"
    echo "6. Exit"
    echo
    printf "Enter your choice [1-6]: "
    read choice

    case $choice in
        1)
            echo "Starting partition manager..."
            cfdisk
            ;;
        2)
            echo "Available disks:"
            fdisk -l
            echo
            printf "Enter partition to format (e.g., /dev/sda1): "
            read partition
            printf "Enter filesystem type (ext4, btrfs): "
            read fstype
            mkfs.$fstype $partition
            ;;
        3)
            echo "Installing base system..."
            # Base system installation logic here
            ;;
        4)
            echo "Configuring system..."
            # System configuration logic here
            ;;
        5)
            echo "Installing bootloader..."
            # Bootloader installation logic here
            ;;
        6)
            echo "${GREEN}Exiting installer. You may now reboot.${NC}"
            exit 0
            ;;
        *)
            echo "${RED}Invalid choice${NC}"
            ;;
    esac
done
