#!/bin/bash

# Hardware detection and optimization script for AetherOS
# Focuses on minimal resource usage while maintaining high performance

detect_cpu() {
    local cpu_vendor=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
    local cpu_flags=$(grep -m1 'flags' /proc/cpuinfo)
    local cpu_cores=$(nproc)
    
    # CPU-specific optimizations
    echo "# CPU Optimizations" > "$1"
    echo "CONFIG_GENERIC_CPU=n" >> "$1"
    
    case $cpu_vendor in
        "GenuineIntel")
            echo "CONFIG_MCORE2=y" >> "$1"
            echo "CONFIG_PROCESSOR_SELECT=y" >> "$1"
            [[ $cpu_flags =~ "avx2" ]] && echo "CONFIG_MGEN_AVX2=y" >> "$1"
            ;;
        "AuthenticAMD")
            echo "CONFIG_GENERIC_CPU2=y" >> "$1"
            echo "CONFIG_X86_AMD_PLATFORM_DEVICE=y" >> "$1"
            [[ $cpu_flags =~ "avx2" ]] && echo "CONFIG_MGEN_AVX2=y" >> "$1"
            ;;
    esac
    
    # Optimize for number of cores
    if [ "$cpu_cores" -le "2" ]; then
        echo "CONFIG_NR_CPUS=4" >> "$1"
    else
        echo "CONFIG_NR_CPUS=$((cpu_cores * 2))" >> "$1"
    fi
}

detect_memory() {
    local mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_gb=$((mem_total / 1024 / 1024))
    
    echo "# Memory Optimizations" >> "$1"
    if [ "$mem_gb" -le "2" ]; then
        # Low memory optimizations
        echo "CONFIG_LOW_MEM_NOTIFY=y" >> "$1"
        echo "CONFIG_CLEANCACHE=y" >> "$1"
        echo "CONFIG_FRONTSWAP=y" >> "$1"
        echo "CONFIG_ZSWAP=y" >> "$1"
    else
        # Standard memory configuration
        echo "CONFIG_TRANSPARENT_HUGEPAGE=y" >> "$1"
        echo "CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS=n" >> "$1"
        echo "CONFIG_TRANSPARENT_HUGEPAGE_MADVISE=y" >> "$1"
    fi
}

detect_storage() {
    echo "# Storage Optimizations" >> "$1"
    
    # Check for NVMe
    if [ -d "/sys/class/nvme" ]; then
        echo "CONFIG_NVME_CORE=y" >> "$1"
        echo "CONFIG_BLK_DEV_NVME=y" >> "$1"
        echo "CONFIG_NVME_MULTIPATH=n" >> "$1"  # Disable unless needed
    fi
    
    # Check for SATA
    if [ -d "/sys/class/ata_device" ]; then
        echo "CONFIG_ATA=y" >> "$1"
        echo "CONFIG_SATA_AHCI=y" >> "$1"
    fi
    
    # Minimal IO schedulers
    echo "CONFIG_IOSCHED_BFQ=n" >> "$1"
    echo "CONFIG_IOSCHED_DEADLINE=y" >> "$1"
    echo "CONFIG_MQ_IOSCHED_DEADLINE=y" >> "$1"
}

detect_network() {
    echo "# Network Optimizations" >> "$1"
    
    # Check for wireless
    if [ -d "/sys/class/net/wlan0" ] || [ -d "/sys/class/net/wifi0" ]; then
        echo "CONFIG_WIRELESS=y" >> "$1"
        echo "CONFIG_CFG80211=y" >> "$1"
        echo "CONFIG_MAC80211=y" >> "$1"
    else
        echo "CONFIG_WIRELESS=n" >> "$1"
        echo "CONFIG_CFG80211=n" >> "$1"
        echo "CONFIG_MAC80211=n" >> "$1"
    fi
    
    # Minimal network stack
    echo "CONFIG_NET_RX_BUSY_POLL=y" >> "$1"
    echo "CONFIG_INET_ESP=y" >> "$1"
    echo "CONFIG_INET6=n" >> "$1"  # Disable IPv6 unless needed
    echo "CONFIG_TCP_CONG_BBR=y" >> "$1"
}

detect_security() {
    echo "# Security Optimizations" >> "$1"
    
    # Essential security features
    echo "CONFIG_SECURITY=y" >> "$1"
    echo "CONFIG_SECURITY_NETWORK=y" >> "$1"
    echo "CONFIG_SECCOMP=y" >> "$1"
    echo "CONFIG_SECCOMP_FILTER=y" >> "$1"
    
    # Minimal LSM
    echo "CONFIG_LSM=\"landlock,lockdown,yama,integrity,selinux\"" >> "$1"
    echo "CONFIG_SECURITY_SELINUX=y" >> "$1"
    echo "CONFIG_SECURITY_SELINUX_BOOTPARAM=y" >> "$1"
    
    # Hardware security features
    if grep -q "rdrand" /proc/cpuinfo; then
        echo "CONFIG_RANDOM_TRUST_CPU=y" >> "$1"
    fi
}

main() {
    local config_file="$1"
    if [ -z "$config_file" ]; then
        echo "Usage: $0 <output_config_file>"
        exit 1
    fi
    
    # Create fresh config
    echo "# AetherOS Hardware-Optimized Configuration" > "$config_file"
    echo "# Generated on $(date)" >> "$config_file"
    
    # Detect and configure for each hardware component
    detect_cpu "$config_file"
    detect_memory "$config_file"
    detect_storage "$config_file"
    detect_network "$config_file"
    detect_security "$config_file"
    
    # Basic performance optimizations
    echo "# Performance Optimizations" >> "$config_file"
    echo "CONFIG_PREEMPT=y" >> "$config_file"
    echo "CONFIG_HZ_1000=y" >> "$config_file"
    echo "CONFIG_HZ=1000" >> "$config_file"
    echo "CONFIG_NUMA=n" >> "$config_file"  # Enable only if NUMA hardware detected
    echo "CONFIG_ACPI_CPPC_CPUFREQ=y" >> "$config_file"
}

main "$@"
