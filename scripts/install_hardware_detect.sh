#!/bin/bash
# Comprehensive install-time hardware detection for AetherOS
# Detects and configures all available hardware

MODULES_CONF="/etc/modules-load.d/aetheros.conf"
MODPROBE_CONF="/etc/modprobe.d/aetheros.conf"
UDEV_RULES="/etc/udev/rules.d/90-aetheros.rules"

log() {
    logger -t "AetherOS-Install-HW" "$1"
    echo "$1"
}

# Add module to autoload
add_module() {
    local module="$1"
    if ! grep -q "^$module$" "$MODULES_CONF" 2>/dev/null; then
        echo "$module" >> "$MODULES_CONF"
        log "Added module to autoload: $module"
    fi
}

detect_cpu_features() {
    log "Detecting CPU features..."
    
    # CPU microcode
    if grep -q "GenuineIntel" /proc/cpuinfo; then
        add_module "intel_microcode"
    elif grep -q "AuthenticAMD" /proc/cpuinfo; then
        add_module "amd_microcode"
    fi
    
    # CPU frequency scaling
    if [ -d "/sys/devices/system/cpu/cpu0/cpufreq" ]; then
        if grep -q "intel_pstate" /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null; then
            echo "options intel_pstate status=active" >> "$MODPROBE_CONF"
        fi
    fi
}

detect_graphics() {
    log "Detecting graphics hardware..."
    
    # NVIDIA
    if lspci | grep -i "vga\|display" | grep -qi "nvidia"; then
        add_module "nvidia"
        echo "options nvidia NVreg_UsePageAttributeTable=1" >> "$MODPROBE_CONF"
        echo "options nvidia NVreg_EnablePCIeGen3=1" >> "$MODPROBE_CONF"
    fi
    
    # AMD
    if lspci | grep -i "vga\|display" | grep -qi "amd\|ati"; then
        add_module "amdgpu"
        echo "options amdgpu si_support=1" >> "$MODPROBE_CONF"
        echo "options amdgpu cik_support=1" >> "$MODPROBE_CONF"
    fi
    
    # Intel
    if lspci | grep -i "vga\|display" | grep -qi "intel"; then
        add_module "i915"
        echo "options i915 enable_fbc=1" >> "$MODPROBE_CONF"
        echo "options i915 fastboot=1" >> "$MODPROBE_CONF"
    fi
}

detect_network() {
    log "Detecting network devices..."
    
    # Wireless
    if lspci | grep -i "network\|wireless" | grep -qi "intel"; then
        add_module "iwlwifi"
    elif lspci | grep -i "network\|wireless" | grep -qi "broadcom"; then
        add_module "brcmfmac"
    elif lspci | grep -i "network\|wireless" | grep -qi "realtek"; then
        add_module "rtw88"
    fi
    
    # Ethernet
    if lspci | grep -i "ethernet" | grep -qi "intel"; then
        add_module "e1000e"
    elif lspci | grep -i "ethernet" | grep -qi "realtek"; then
        add_module "r8169"
    fi
}

detect_audio() {
    log "Detecting audio devices..."
    
    # ALSA base
    add_module "snd_seq"
    add_module "snd_seq_device"
    
    # HD Audio
    if lspci | grep -qi "audio" | grep -qi "intel"; then
        add_module "snd_hda_intel"
        echo "options snd_hda_intel power_save=1" >> "$MODPROBE_CONF"
    fi
}

detect_storage_controllers() {
    log "Detecting storage controllers..."
    
    # RAID controllers
    if lspci | grep -qi "raid"; then
        if lspci | grep -qi "lsi"; then
            add_module "mpt3sas"
        elif lspci | grep -qi "adaptec"; then
            add_module "aacraid"
        fi
    fi
    
    # NVMe optimization
    if [ -d "/sys/class/nvme" ]; then
        echo 'ACTION=="add|change", SUBSYSTEM=="block", ATTR{queue/scheduler}=="*", ATTR{queue/scheduler}="none"' >> "$UDEV_RULES"
    fi
}

detect_peripherals() {
    log "Detecting peripherals..."
    
    # Webcams
    if lsusb | grep -qi "webcam\|camera"; then
        add_module "uvcvideo"
    fi
    
    # Bluetooth
    if lsusb | grep -qi "bluetooth"; then
        add_module "btusb"
        add_module "bluetooth"
    fi
    
    # Printers
    if lsusb | grep -qi "printer"; then
        add_module "usblp"
    fi
}

main() {
    log "Starting comprehensive hardware detection..."
    
    # Create/clear configuration files
    mkdir -p /etc/modules-load.d
    mkdir -p /etc/modprobe.d
    mkdir -p /etc/udev/rules.d
    : > "$MODULES_CONF"
    : > "$MODPROBE_CONF"
    : > "$UDEV_RULES"
    
    # Run detection functions
    detect_cpu_features
    detect_graphics
    detect_network
    detect_audio
    detect_storage_controllers
    detect_peripherals
    
    # Apply udev rules
    udevadm control --reload-rules
    
    log "Hardware detection completed. System configuration updated."
}

main "$@"
