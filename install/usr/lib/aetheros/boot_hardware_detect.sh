#!/bin/bash
# Essential boot-time hardware detection for AetherOS
# Focuses on critical hardware needed for basic system operation

MODULES_DIR="/lib/modules/$(uname -r)"
LOADED_MODULES="/tmp/loaded_modules"

log() {
    logger -t "AetherOS-Boot-HW" "$1"
    echo "$1"
}

# Load a module if it exists and isn't already loaded
load_module() {
    local module="$1"
    if ! lsmod | grep -q "^$module"; then
        if modprobe "$module" 2>/dev/null; then
            echo "$module" >> "$LOADED_MODULES"
            log "Loaded module: $module"
        fi
    fi
}

# Essential Input Devices
detect_input_devices() {
    log "Detecting essential input devices..."
    
    # PS/2 Devices
    if [ -d "/sys/bus/platform/devices/i8042" ]; then
        load_module "atkbd"
        load_module "psmouse"
    fi
    
    # USB HID
    if [ -d "/sys/bus/usb" ]; then
        load_module "usbhid"
        load_module "hid_generic"
    fi
    
    # Basic USB support
    load_module "ehci_hcd"
    load_module "uhci_hcd"
    load_module "xhci_hcd"
    load_module "ohci_hcd"
}

# Essential Storage
detect_boot_storage() {
    log "Detecting boot storage devices..."
    
    # SATA/PATA
    if [ -d "/sys/class/ata_device" ]; then
        load_module "libata"
        load_module "ata_piix"
        load_module "ata_generic"
    fi
    
    # NVMe
    if [ -d "/sys/class/nvme" ]; then
        load_module "nvme"
        load_module "nvme_core"
    fi
}

# Essential Display
detect_display() {
    log "Detecting display hardware..."
    
    # Basic framebuffer
    load_module "efifb"
    load_module "simple_framebuffer"
    
    # Basic GPU support
    if lspci | grep -i "vga\|display" | grep -qi "nvidia"; then
        load_module "nouveau"  # Basic NVIDIA support
    elif lspci | grep -i "vga\|display" | grep -qi "amd\|ati"; then
        load_module "amdgpu"  # Basic AMD support
    fi
    
    # Intel graphics
    if lspci | grep -i "vga\|display" | grep -qi "intel"; then
        load_module "i915"
    fi
}

main() {
    log "Starting essential hardware detection..."
    
    # Create fresh loaded modules list
    : > "$LOADED_MODULES"
    
    # Detect and load essential hardware modules
    detect_input_devices
    detect_boot_storage
    detect_display
    
    log "Essential hardware detection completed"
}

main "$@"
