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
            [ $VERBOSE -eq 1 ] && echo -e "${CYAN}${log_prefix} $msg${NC}"
            ;;
        INFO)
            [ $VERBOSE -eq 1 ] && echo -e "${GREEN}${log_prefix} $msg${NC}"
            ;;
        WARN)
            echo -e "${YELLOW}${log_prefix} $msg${NC}"
            ;;
        ERROR)
            echo -e "${RED}${log_prefix} $msg${NC}" >&2
            ;;
        *)
            [ $VERBOSE -eq 1 ] && echo -e "$msg"
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

# Function to install package groups
install_packages() {
    local group=$1
    shift
    local packages=("$@")
    
    log INFO "Installing $group packages..."
    
    # Skip certain groups in minimal mode
    if [ $MINIMAL -eq 1 ]; then
        case $group in
            "optional"|"debug"|"profile")
                log INFO "Skipping $group packages in minimal mode"
                return 0
                ;;
        esac
    fi
    
    # Create a temporary file for the package list
    local pkg_file=$(mktemp /tmp/aetheros-setup-pkgs.XXXXXX)
    printf "%s\n" "${packages[@]}" > "$pkg_file"
    
    # Check which packages are not installed
    local to_install=()
    while IFS= read -r pkg; do
        if ! pacman -Qi "$pkg" &>/dev/null; then
            to_install+=("$pkg")
        else
            log DEBUG "Package already installed: $pkg"
        fi
    done < "$pkg_file"
    
    # Install missing packages
    if [ ${#to_install[@]} -gt 0 ]; then
        log INFO "Installing ${#to_install[@]} packages from $group..."
        if ! sudo pacman -S --needed --noconfirm "${to_install[@]}"; then
            log ERROR "Failed to install $group packages"
            rm "$pkg_file"
            return 1
        fi
    else
        log INFO "All $group packages already installed"
    fi
    
    rm "$pkg_file"
    return 0
}

# Package groups
declare -A PACKAGE_GROUPS

# Initialize package groups
PACKAGE_GROUPS=(
    ["essential"]="base-devel git cmake ninja meson python python-pip curl wget"
    ["compiler"]="gcc clang llvm lld binutils flex bison elfutils openssl"
    ["kernel"]="linux-headers dkms sparse pahole perf trace-cmd usbutils pciutils hwinfo dmidecode"
    ["virtualization"]="qemu qemu-arch-extra"
)

# Compiler toolchain
PACKAGE_GROUPS["compiler"]+=" edk2-ovmf"

# Kernel development
PACKAGE_GROUPS["kernel"]+=" virt-manager libvirt bridge-utils openvswitch"

# Debug tools
PACKAGE_GROUPS["debug"]="gdb lldb strace ltrace valgrind rr systemtap kdump-tools"

# Performance tools
PACKAGE_GROUPS["profile"]="perf hotspot ccache distcc kcachegrind sysprof linux-tools"

# Security tools
PACKAGE_GROUPS["security"]="audit firejail apparmor checksec clamav rkhunter lynis"

# Documentation
PACKAGE_GROUPS["docs"]="man-db man-pages texinfo devhelp zeal"

# Networking
PACKAGE_GROUPS["networking"]="iproute2 bridge-utils ethtool iptables nftables tcpdump wireshark-cli wireshark-qt net-tools netcat nmap mtr iperf3 iw wireless_tools"

# Filesystem
PACKAGE_GROUPS["filesystem"]="btrfs-progs xfsprogs e2fsprogs f2fs-tools nilfs-utils ntfs-3g dosfstools exfatprogs squashfs-tools cryptsetup lvm2 mdadm"

# Monitoring
PACKAGE_GROUPS["monitoring"]="htop atop iotop powertop sysstat collectd prometheus grafana telegraf netdata"

# Containers
PACKAGE_GROUPS["containers"]="docker podman buildah skopeo kubernetes-tools helm k9s kind minikube"

# Editors
PACKAGE_GROUPS["editors"]="vim neovim emacs vscode sublime-text helix kakoune micro"

# Analysis
PACKAGE_GROUPS["analysis"]="clang-analyzer cppcheck flawfinder splint rats sonarqube valgrind massif-visualizer kcachegrind hotspot"

# Performance tuning profiles
declare -A PERFORMANCE_PROFILES

PERFORMANCE_PROFILES[realtime]="
# CPU
kernel.sched_rt_runtime_us = -1
kernel.sched_rt_period_us = 1000000
kernel.sched_autogroup_enabled = 0
kernel.numa_balancing = 0
vm.swappiness = 0
vm.zone_reclaim_mode = 0
vm.dirty_ratio = 3
vm.dirty_background_ratio = 2
kernel.sched_min_granularity_ns = 10000000
kernel.sched_wakeup_granularity_ns = 15000000
kernel.sched_migration_cost_ns = 5000000

# Network
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.netdev_budget = 600
net.core.netdev_budget_usecs = 8000

# File System
fs.inotify.max_user_watches = 524288
fs.file-max = 2097152
fs.nr_open = 2097152
fs.pipe-max-size = 1048576
fs.pipe-user-pages-hard = 0
fs.pipe-user-pages-soft = 0

# IO
vm.dirty_bytes = 0
vm.dirty_background_bytes = 0
"

PERFORMANCE_PROFILES[low_latency]="
# CPU
kernel.sched_latency_ns = 4000000
kernel.sched_min_granularity_ns = 500000
kernel.sched_wakeup_granularity_ns = 50000
kernel.sched_migration_cost_ns = 1000000
kernel.sched_nr_migrate = 128
kernel.sched_schedstats = 0

# Memory
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.min_free_kbytes = 65536
vm.zone_reclaim_mode = 0

# Network
net.core.busy_poll = 50
net.core.busy_read = 50
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_low_latency = 1
"

PERFORMANCE_PROFILES[throughput]="
# CPU
kernel.sched_migration_cost_ns = 5000000
kernel.sched_autogroup_enabled = 1
kernel.numa_balancing = 1

# Memory
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10
vm.swappiness = 60
vm.vfs_cache_pressure = 100

# IO
vm.dirty_expire_centisecs = 3000
vm.dirty_writeback_centisecs = 500
"

# Function to apply performance profile
apply_performance_profile() {
    local profile=$1
    log INFO "Applying performance profile: $profile"
    
    if [ -z "${PERFORMANCE_PROFILES[$profile]}" ]; then
        log ERROR "Invalid performance profile: $profile"
        return 1
    fi
    
    # Create sysctl configuration
    local sysctl_file="/etc/sysctl.d/99-aetheros-${profile}.conf"
    echo "${PERFORMANCE_PROFILES[$profile]}" | sudo tee "$sysctl_file" > /dev/null
    
    # Apply settings
    sudo sysctl -p "$sysctl_file"
    
    # CPU frequency scaling
    if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
        case $profile in
            realtime|low_latency)
                sudo cpupower frequency-set -g performance
                sudo cpupower idle-set -D 0
                ;;
            throughput)
                sudo cpupower frequency-set -g ondemand
                sudo cpupower idle-set -E
                ;;
        esac
    fi
    
    # IO scheduler configuration
    for disk in /sys/block/sd*; do
        case $profile in
            realtime|low_latency)
                echo none | sudo tee "$disk/queue/scheduler"
                echo 0 | sudo tee "$disk/queue/add_random"
                echo 0 | sudo tee "$disk/queue/rotational"
                ;;
            throughput)
                echo bfq | sudo tee "$disk/queue/scheduler"
                echo 1 | sudo tee "$disk/queue/add_random"
                ;;
        esac
    done
}

# Security hardening function
harden_system() {
    log INFO "Applying security hardening..."
    
    # Kernel parameters
    cat > /etc/sysctl.d/99-aetheros-security.conf << EOF
# Kernel hardening
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.printk = 3 4 1 3
kernel.unprivileged_bpf_disabled = 1
kernel.kexec_load_disabled = 1
kernel.sysrq = 0
kernel.core_uses_pid = 1
kernel.randomize_va_space = 2

# Network security
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.icmp_echo_ignore_all = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# File system security
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.suid_dumpable = 0
EOF
    
    # Apply sysctl settings
    sudo sysctl -p /etc/sysctl.d/99-aetheros-security.conf
    
    # Secure mount options
    cat > /etc/fstab.aetheros << EOF
# AetherOS secure mount options
LABEL=root / ext4 defaults,nodev,nosuid,noexec 0 1
LABEL=boot /boot ext4 defaults,nodev,nosuid,noexec 0 2
tmpfs /tmp tmpfs defaults,nodev,nosuid,noexec 0 0
EOF
    
    # PAM security
    cat > /etc/security/limits.d/99-aetheros.conf << EOF
# AetherOS security limits
* hard core 0
* soft nproc 1000
* hard nproc 2000
* soft nofile 100000
* hard nofile 200000
EOF
    
    # Secure boot configuration
    cat > /etc/default/grub.d/40-aetheros.cfg << EOF
# AetherOS secure boot parameters
GRUB_CMDLINE_LINUX_DEFAULT="\$GRUB_CMDLINE_LINUX_DEFAULT page_poison=1 page_alloc.shuffle=1 pti=on spectre_v2=on spec_store_bypass_disable=on l1tf=full,force mds=full,nosmt mce=0 init_on_alloc=1 init_on_free=1 slab_nomerge slub_debug=FZ"
EOF
    
    # Update GRUB
    sudo update-grub
}

# Function to optimize compiler flags
optimize_compiler_flags() {
    log INFO "Optimizing compiler flags..."
    
    # Get CPU features
    local cpu_flags=$(grep -m1 flags /proc/cpuinfo | cut -d: -f2)
    local march="native"
    
    # Detect specific CPU features
    local cpu_opts=""
    [[ $cpu_flags =~ avx2 ]] && cpu_opts+=" -mavx2"
    [[ $cpu_flags =~ fma ]] && cpu_opts+=" -mfma"
    [[ $cpu_flags =~ sse4_2 ]] && cpu_opts+=" -msse4.2"
    
    # Create optimized CFLAGS
    cat > ~/.aetheros/build/compiler_flags << EOF
# AetherOS optimized compiler flags
CFLAGS="-march=$march -O3 -pipe $cpu_opts -fno-plt -fstack-clash-protection -fdevirtualize-at-ltrans -fipa-pta -fno-semantic-interposition"
CXXFLAGS="\$CFLAGS -fvisibility-inlines-hidden"
RUSTFLAGS="-C target-cpu=$march -C opt-level=3 -C link-arg=-fuse-ld=lld -C target-feature=+crt-static"
LDFLAGS="-Wl,-O3 -Wl,--as-needed -Wl,-z,relro,-z,now"
EOF
}

# Build environment setup
setup_build_env() {
    log INFO "Setting up build environment..."
    
    # Create build directories
    mkdir -p ~/.aetheros/{build,cache,logs,tools}
    
    # Configure ccache
    if command -v ccache &>/dev/null; then
        log INFO "Configuring ccache..."
        ccache --max-size=50G
        ccache --set-config=compression=true
        ccache --set-config=compression_level=1
        ccache --set-config=cache_dir=~/.aetheros/cache/ccache
    fi
    
    # Configure distcc if not in minimal mode
    if [ $MINIMAL -eq 0 ] && command -v distcc &>/dev/null; then
        log INFO "Configuring distcc..."
        # Allow local network
        echo "192.168.0.0/16" > ~/.distcc/hosts
        # Start distcc daemon
        systemctl --user enable --now distcc
    fi
    
    # Configure kernel build settings
    cat > ~/.aetheros/build/kernel_config << EOF
# Kernel build configuration
MAKEFLAGS="-j$(nproc)"
CCACHE_DIR=~/.aetheros/cache/ccache
USE_CCACHE=1
USE_DISTCC=$([ $MINIMAL -eq 0 ] && echo "1" || echo "0")
LOCALVERSION="-aetheros"
EOF
    
    # Set up git hooks
    if [ -d .git ]; then
        log INFO "Setting up git hooks..."
        cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
# Run kernel checkpatch
if git rev-parse --verify HEAD >/dev/null 2>&1; then
    against=HEAD
else
    against=$(git hash-object -t tree /dev/null)
fi

# Check changed files
exec ./scripts/checkpatch.pl --no-tree -q --no-signoff --ignore GERRIT_CHANGE_ID --git-dir .git \
    $(git diff-index --cached --name-only $against | grep -E '\.(c|h)$')
EOF
        chmod +x .git/hooks/pre-commit
    fi
}

# Configure development tools
configure_dev_tools() {
    log INFO "Configuring development tools..."
    
    # GDB configuration
    mkdir -p ~/.config/gdb
    cat > ~/.config/gdb/gdbinit << 'EOF'
set history save on
set print pretty on
set pagination off
set confirm off
set verbose off
set print array on
set print array-indexes on
set python print-stack full

# Custom commands
define xxd
    dump binary memory dump.bin $arg0 $arg0+$arg1
    shell xxd dump.bin
    shell rm dump.bin
end

# Kernel debugging helpers
source /usr/share/gdb/auto-load/vmlinux-gdb.py
EOF
    
    # QEMU default configuration
    mkdir -p ~/.config/qemu
    cat > ~/.config/qemu/qemu.conf << EOF
# QEMU configuration for AetherOS
vnc = "127.0.0.1:0"
spice = "port=5930,addr=127.0.0.1"
memory = "4G"
smp = "$(nproc)"
machine = "q35"
cpu = "${TARGET_CPU}"
EOF
    
    # Configure LLDB
    mkdir -p ~/.config/lldb
    cat > ~/.config/lldb/lldbinit << 'EOF'
settings set frame-format "frame #${frame.index}: ${frame.pc}{ ${module.file.basename}}{\n\t${function.name}}}{\n\t${line.file.fullpath}:${line.number}}\n"
settings set thread-format "thread #${thread.index}: tid = ${thread.id}{, ${frame.function}}{\n\t${frame.file}:${frame.line}}\n"
settings set target.load-script-from-symbol-file true
EOF
    
    # Perf configuration
    mkdir -p ~/.config/perf
    cat > ~/.config/perf/perf.conf << EOF
[general]
debug = false
stat = true
timestamp = true
EOF
}

# Function to configure editors
configure_editors() {
    log INFO "Configuring text editors..."
    
    # Neovim configuration
    if command -v nvim &>/dev/null; then
        mkdir -p ~/.config/nvim
        cat > ~/.config/nvim/init.vim << 'EOF'
" AetherOS Neovim Configuration
set number
set relativenumber
set expandtab
set tabstop=4
set shiftwidth=4
set autoindent
set smartindent
set mouse=a
set termguicolors
set clipboard+=unnamedplus

" Rust development
autocmd FileType rust setlocal formatprg=rustfmt
autocmd BufWritePre *.rs silent! execute '!rustfmt %'

" Kernel development
autocmd FileType c,cpp setlocal cindent
autocmd FileType c,cpp setlocal cinoptions=:0,l1,t0,g0,(0
EOF
    fi
    
    # VSCode configuration
    if command -v code &>/dev/null; then
        mkdir -p ~/.config/Code/User
        cat > ~/.config/Code/User/settings.json << EOF
{
    "editor.formatOnSave": true,
    "editor.renderWhitespace": "all",
    "editor.rulers": [80, 100],
    "editor.suggestSelection": "first",
    "files.trimTrailingWhitespace": true,
    "rust-analyzer.checkOnSave.command": "clippy",
    "rust-analyzer.cargo.allFeatures": true,
    "C_Cpp.clang_format_style": "Chromium",
    "C_Cpp.default.cppStandard": "c++17",
    "C_Cpp.default.cStandard": "c11"
}
EOF
    fi
    
    # Emacs configuration
    if command -v emacs &>/dev/null; then
        mkdir -p ~/.emacs.d
        cat > ~/.emacs.d/init.el << 'EOF'
;; AetherOS Emacs Configuration
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)

;; Basic settings
(setq-default
 indent-tabs-mode nil
 tab-width 4
 c-basic-offset 4)

;; Development settings
(show-paren-mode 1)
(electric-pair-mode 1)
(global-display-line-numbers-mode 1)
(global-hl-line-mode 1)

;; Rust mode
(use-package rust-mode
  :ensure t
  :hook (rust-mode . lsp))

;; C/C++ mode
(use-package cc-mode
  :config
  (setq c-default-style "linux"
        c-basic-offset 4))
EOF
    fi
}

# Function to configure system services
configure_services() {
    log INFO "Configuring system services..."
    
    # Docker configuration
    if command -v docker &>/dev/null; then
        sudo usermod -aG docker $USER
        cat > /etc/docker/daemon.json << EOF
{
    "storage-driver": "overlay2",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "default-ulimits": {
        "nofile": {
            "Name": "nofile",
            "Hard": 64000,
            "Soft": 64000
        }
    },
    "registry-mirrors": [],
    "dns": ["8.8.8.8", "8.8.4.4"]
}
EOF
        sudo systemctl enable docker
    fi
    
    # Podman configuration
    if command -v podman &>/dev/null; then
        mkdir -p ~/.config/containers
        cat > ~/.config/containers/storage.conf << EOF
[storage]
driver = "overlay"
runroot = "/run/user/1000"
graphroot = "/home/$USER/.local/share/containers/storage"
EOF
    fi
    
    # Prometheus configuration
    if command -v prometheus &>/dev/null; then
        sudo mkdir -p /etc/prometheus
        cat > /etc/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
EOF
        sudo systemctl enable prometheus
    fi
}

# Function to install Rust tools
install_rust_tools() {
    log INFO "Installing Rust development tools..."
    
    # Core components
    rustup component add \
        rust-src \
        rust-analysis \
        rust-analyzer-preview \
        clippy \
        rustfmt \
        llvm-tools-preview
    
    # Additional targets
    rustup target add \
        x86_64-unknown-none \
        x86_64-unknown-linux-musl \
        i686-unknown-linux-gnu
    
    # Cargo tools
    local cargo_tools=(
        cargo-xbuild      # Cross compilation
        cargo-watch       # Auto-rebuild
        cargo-edit       # Dependency management
        cargo-audit      # Security audit
        cargo-outdated   # Dependency updates
        cargo-expand     # Macro expansion
        cargo-flamegraph # Performance profiling
        cargo-bloat      # Binary size analysis
        cargo-udeps      # Unused dependencies
        cargo-criterion  # Benchmarking
    )
    
    for tool in "${cargo_tools[@]}"; do
        if ! cargo install --list | grep -q "^$tool"; then
            log INFO "Installing $tool..."
            cargo install "$tool" || log WARN "Failed to install $tool"
        else
            log DEBUG "$tool already installed"
        fi
    done
}

# Hardware detection and module management
detect_and_configure_modules() {
    log INFO "Detecting hardware and configuring kernel modules..."
    
    # Create module configuration directories
    sudo mkdir -p /etc/modprobe.d/
    sudo mkdir -p /etc/modules-load.d/
    
    # Initialize lists for required and blacklisted modules
    declare -a required_modules
    declare -a blacklisted_modules
    
    # Detect CPU vendor and features
    local cpu_vendor=$(grep -m1 vendor_id /proc/cpuinfo | cut -d: -f2 | tr -d ' ')
    local cpu_flags=$(grep -m1 flags /proc/cpuinfo | cut -d: -f2)
    
    # CPU microcode and specific modules
    case $cpu_vendor in
        *Intel*)
            required_modules+=("intel_cpufreq" "intel_pstate" "intel_rapl_common")
            # Check for Intel GPU
            if lspci | grep -i "VGA.*Intel" >/dev/null; then
                required_modules+=("i915")
            fi
            ;;
        *AMD*)
            required_modules+=("amd_cpufreq" "amd_pstate")
            # Check for AMD GPU
            if lspci | grep -i "VGA.*AMD" >/dev/null; then
                required_modules+=("amdgpu")
            fi
            ;;
    esac
    
    # Detect and configure storage controllers
    while read -r line; do
        case "$line" in
            *"RAID"*)
                if [[ $line =~ "Intel" ]]; then
                    required_modules+=("raid0" "raid1" "raid10" "raid456")
                elif [[ $line =~ "AMD" ]]; then
                    required_modules+=("raid0" "raid1" "raid10")
                fi
                ;;
            *"AHCI"*)
                required_modules+=("ahci")
                ;;
            *"NVMe"*)
                required_modules+=("nvme")
                ;;
        esac
    done < <(lspci | grep -i "RAID\|AHCI\|NVMe")
    
    # Network interface detection
    while read -r line; do
        case "$line" in
            *"Ethernet"*)
                if [[ $line =~ "Intel" ]]; then
                    required_modules+=("e1000e" "igb" "ixgbe")
                elif [[ $line =~ "Realtek" ]]; then
                    required_modules+=("r8169")
                elif [[ $line =~ "Broadcom" ]]; then
                    required_modules+=("tg3")
                fi
                ;;
            *"Wireless"*)
                if [[ $line =~ "Intel" ]]; then
                    required_modules+=("iwlwifi" "iwldvm" "iwlmvm")
                elif [[ $line =~ "Broadcom" ]]; then
                    required_modules+=("brcmfmac")
                elif [[ $line =~ "Atheros" ]]; then
                    required_modules+=("ath9k" "ath10k_pci")
                fi
                ;;
        esac
    done < <(lspci | grep -i "Ethernet\|Wireless")
    
    # USB controller detection
    if lspci | grep -i "USB" >/dev/null; then
        required_modules+=("xhci_pci" "ehci_pci" "uhci_hcd")
    fi
    
    # Sound card detection
    if lspci | grep -i "Audio" >/dev/null; then
        required_modules+=("snd_hda_intel" "snd_hda_codec")
    fi
    
    # Blacklist unused modules and potential conflicts
    blacklisted_modules=(
        # Legacy modules
        "parport" "parport_pc" "lp" "ppdev"
        "floppy" "fd0" "fd1"
        # Unused network protocols
        "dccp" "sctp" "rds" "tipc"
        # Unused filesystems
        "cramfs" "freevxfs" "jffs2" "hfs" "hfsplus" "squashfs" "udf"
        # Unused hardware
        "thunderbolt" "firewire-core" "firewire_ohci"
        # Potentially dangerous modules
        "bluetooth" "btusb"
        "uvcvideo"
        "pcspkr"
    )
    
    # Remove detected hardware modules from blacklist
    for module in "${required_modules[@]}"; do
        blacklisted_modules=(${blacklisted_modules[@]//*$module*})
    done
    
    # Create modprobe configuration
    log INFO "Creating modprobe configuration..."
    
    # Required modules configuration
    {
        echo "# AetherOS required modules"
        printf "%s\n" "${required_modules[@]}" | sort -u
    } | sudo tee /etc/modules-load.d/aetheros.conf
    
    # Blacklisted modules configuration
    {
        echo "# AetherOS blacklisted modules"
        for module in "${blacklisted_modules[@]}"; do
            echo "blacklist $module"
            echo "install $module /bin/false"
        done
    } | sudo tee /etc/modprobe.d/aetheros-blacklist.conf
    
    # Module parameters optimization
    {
        echo "# AetherOS module parameters"
        echo "options iwlwifi power_save=0 swcrypto=0"
        echo "options iwlmvm power_scheme=1"
        echo "options e1000e InterruptThrottleRate=3000,3000"
        echo "options i915 enable_rc6=1 enable_fbc=1 fastboot=1"
        echo "options amdgpu ppfeaturemask=0xffffffff"
        echo "options snd_hda_intel power_save=0 power_save_controller=0"
        echo "options usbcore autosuspend=-1"
    } | sudo tee /etc/modprobe.d/aetheros-parameters.conf
    
    # Update initramfs
    log INFO "Updating initramfs with new module configuration..."
    sudo update-initramfs -u
    
    # Create hardware profile
    {
        echo "# AetherOS Hardware Profile"
        echo "# Generated on $(date)"
        echo "CPU_VENDOR=$cpu_vendor"
        echo "CPU_FLAGS=$cpu_flags"
        echo "REQUIRED_MODULES=${required_modules[*]}"
        echo "BLACKLISTED_MODULES=${blacklisted_modules[*]}"
    } > ~/.aetheros/hardware_profile
    
    log INFO "Hardware detection and module configuration completed"
}

# Module dependency mapping
declare -A MODULE_DEPENDENCIES
MODULE_DEPENDENCIES=(
    ["i915"]="drm drm_kms_helper"
    ["amdgpu"]="drm drm_kms_helper amdkfd"
    ["snd_hda_intel"]="snd_hda_codec snd_hda_core snd_pcm snd"
    ["iwlwifi"]="mac80211 cfg80211"
    ["e1000e"]="ptp pps_core"
    ["nvme"]="nvme_core"
)

# Hardware-specific performance profiles
declare -A HARDWARE_PROFILES
HARDWARE_PROFILES[intel_desktop]="
options intel_pstate no_hwp=1
options i915 enable_fbc=1 enable_rc6=1 enable_guc=2 enable_dc=2
options e1000e InterruptThrottleRate=3000,3000
"

HARDWARE_PROFILES[intel_server]="
options intel_pstate no_hwp=0
options i915 enable_fbc=0 enable_rc6=0 enable_guc=0
options e1000e InterruptThrottleRate=1,1
"

HARDWARE_PROFILES[amd_desktop]="
options amd_pstate shared_mem=1
options amdgpu ppfeaturemask=0xffffffff gpu_recovery=1
options k10temp force=1
"

HARDWARE_PROFILES[amd_server]="
options amd_pstate shared_mem=1
options amdgpu ppfeaturemask=0xff7fffff gpu_recovery=0
"

# Enhanced hardware detection
detect_specialized_hardware() {
    log INFO "Detecting specialized hardware..."
    
    # Initialize arrays
    declare -a specialized_modules
    declare -a security_modules
    
    # TPM detection
    if [ -d "/sys/class/tpm" ] || [ -e "/dev/tpm0" ]; then
        security_modules+=("tpm_tis" "tpm_crb")
        log INFO "TPM device detected"
    fi
    
    # IOMMU detection and configuration
    if grep -q "intel_iommu=on" /proc/cmdline || grep -q "amd_iommu=on" /proc/cmdline; then
        if [ "$cpu_vendor" = "Intel" ]; then
            security_modules+=("intel_iommu")
            echo "options intel_iommu=on intremap=1 iommu=pt" | sudo tee -a /etc/modprobe.d/aetheros-security.conf
        else
            security_modules+=("amd_iommu")
            echo "options amd_iommu=on iommu=pt" | sudo tee -a /etc/modprobe.d/aetheros-security.conf
        fi
        log INFO "IOMMU support enabled"
    fi
    
    # PCIe device detection
    while read -r line; do
        local pci_id=$(echo "$line" | awk '{print $1}')
        local pci_class=$(lspci -n -s "$pci_id" | awk '{print $2}' | cut -d: -f2)
        
        case "$pci_class" in
            # Storage controllers
            "0104"|"0106"|"0107")
                if [[ $line =~ "Fusion" ]]; then
                    specialized_modules+=("fusion")
                elif [[ $line =~ "MegaRAID" ]]; then
                    specialized_modules+=("megaraid_sas")
                elif [[ $line =~ "SmartArray" ]]; then
                    specialized_modules+=("hpsa")
                fi
                ;;
            # Network controllers
            "0200")
                if [[ $line =~ "Mellanox" ]]; then
                    specialized_modules+=("mlx4_core" "mlx4_en" "mlx5_core")
                elif [[ $line =~ "QLogic" ]]; then
                    specialized_modules+=("qla2xxx" "qed" "qede")
                fi
                ;;
            # GPU and compute accelerators
            "0302"|"0380")
                if [[ $line =~ "NVIDIA" ]]; then
                    log WARN "NVIDIA GPU detected - proprietary modules not included"
                elif [[ $line =~ "Xilinx" ]]; then
                    specialized_modules+=("xocl")
                fi
                ;;
        esac
    done < <(lspci)
    
    # Hardware Crypto Detection
    if grep -q "aes" /proc/cpuinfo; then
        security_modules+=("aesni-intel")
        log INFO "AES-NI support detected"
    fi
    
    if grep -q "sha_ni" /proc/cpuinfo; then
        security_modules+=("sha-ni")
        log INFO "SHA-NI support detected"
    fi

    # TPM 2.0 Detection with version check
    if [ -d "/sys/class/tpm" ]; then
        for tpm in /sys/class/tpm/tpm*; do
            if [ -f "$tpm/caps" ]; then
                if grep -q "2.0" "$tpm/caps"; then
                    security_modules+=("tpm_crb" "tpm_tis")
                    log INFO "TPM 2.0 detected"
                fi
            fi
        done
    fi

    echo "${specialized_modules[@]} ${security_modules[@]}"
}

# Kernel update preparation
prepare_kernel_update() {
    log INFO "Preparing for kernel updates..."
    
    # Create kernel update hook directory
    sudo mkdir -p /etc/kernel/postinst.d
    
    # Create update hook script
    cat > /etc/kernel/postinst.d/90-aetheros-module-update << 'EOF'
#!/bin/bash

# Get new kernel version
NEW_KERNEL="$1"

# Source AetherOS configuration
source ~/.aetheros/hardware_profile

# Rebuild module configuration for new kernel
/usr/local/sbin/aetheros-module-update "$NEW_KERNEL"

# Update initramfs for new kernel
update-initramfs -c -k "$NEW_KERNEL"
EOF
    
    chmod +x /etc/kernel/postinst.d/90-aetheros-module-update
    
    # Create module update script
    cat > /usr/local/sbin/aetheros-module-update << 'EOF'
#!/bin/bash

NEW_KERNEL="$1"
HARDWARE_PROFILE="$HOME/.aetheros/hardware_profile"

# Recreate module configurations for new kernel
if [ -f "$HARDWARE_PROFILE" ]; then
    source "$HARDWARE_PROFILE"
    
    # Update module configurations
    for module in $REQUIRED_MODULES; do
        if modinfo -k "$NEW_KERNEL" "$module" &>/dev/null; then
            echo "$module" >> "/etc/modules-load.d/aetheros.conf.new"
        fi
    done
    
    # Apply new configuration
    mv "/etc/modules-load.d/aetheros.conf.new" "/etc/modules-load.d/aetheros.conf"
fi
EOF
    
    chmod +x /usr/local/sbin/aetheros-module-update
}

# Enhanced memory protection
setup_memory_protection() {
    log INFO "Configuring advanced memory protection..."
    
    {
        echo "# AetherOS Memory Protection Configuration"
        echo "kernel.kptr_restrict=2"
        echo "kernel.dmesg_restrict=1"
        echo "kernel.perf_event_paranoid=3"
        echo "kernel.kexec_load_disabled=1"
        echo "kernel.yama.ptrace_scope=2"
        echo "kernel.unprivileged_bpf_disabled=1"
        echo "vm.mmap_min_addr=65536"
        echo "vm.mmap_rnd_bits=32"
        echo "vm.mmap_rnd_compat_bits=16"
        echo "vm.unprivileged_userfaultfd=0"
    } | sudo tee /etc/sysctl.d/99-aetheros-memory.conf

    # Enable kernel page table isolation
    if grep -q "pti=on" /proc/cmdline; then
        log INFO "KPTI already enabled"
    else
        echo "GRUB_CMDLINE_LINUX_DEFAULT=\"\$GRUB_CMDLINE_LINUX_DEFAULT pti=on\"" | \
            sudo tee -a /etc/default/grub.d/40-aetheros.cfg
    fi
}

# Update detect_and_configure_modules
detect_and_configure_modules() {
    # ... (previous code) ...
    
    # Add advanced hardware detection
    local advanced_hw=$(detect_specialized_hardware)
    required_modules+=($advanced_hw)
    
    # Version compatibility check
    local compatible_modules=()
    for module in "${required_modules[@]}"; do
        if [ -n "${MODULE_KERNEL_COMPAT[$module]}" ]; then
            if dpkg --compare-versions "$KERNEL_VERSION" "${MODULE_KERNEL_COMPAT[$module]}"; then
                compatible_modules+=("$module")
            else
                log WARN "Module $module not compatible with kernel $KERNEL_VERSION"
            fi
        else
            compatible_modules+=("$module")
        fi
    done
    required_modules=("${compatible_modules[@]}")
    
    # Setup kernel update handling
    prepare_kernel_update
    
    # Configure memory protection
    setup_memory_protection
    
    # ... (rest of the function) ...
}

# Update main function
main() {
    # ... (previous code) ...
    
    # Store kernel version for future updates
    echo "KERNEL_VERSION=$KERNEL_VERSION" >> ~/.aetheros/hardware_profile
    
    # ... (rest of the main function) ...
}

# Kernel version management
KERNEL_VERSION=$(uname -r)
KERNEL_MAJOR=$(echo $KERNEL_VERSION | cut -d. -f1)
KERNEL_MINOR=$(echo $KERNEL_VERSION | cut -d. -f2)

# Module version compatibility mapping
declare -A MODULE_KERNEL_COMPAT
MODULE_KERNEL_COMPAT=(
    ["i915"]=">=5.4"
    ["amdgpu"]=">=5.4"
    ["nouveau"]=">=5.4"
    ["zfs"]=">=5.4"
    ["btrfs"]=">=5.4"
)

# Additional hardware accelerator support
declare -A ACCELERATOR_MODULES
ACCELERATOR_MODULES=(
    ["ARM_NPU"]="mali-npu"
    ["Intel_VPU"]="myriad hddl-bsl"
    ["Qualcomm_NPU"]="qnpu"
    ["MediaTek_APU"]="mtk-apu"
    ["AMD_ROCm"]="amdgpu amdkfd"
    ["Intel_GNA"]="intel-gna"
    ["Graphcore_IPU"]="graphcore-ipu"
    ["Cerebras_WSE"]="cerebras-wse"
)

# Extended crypto hardware support
declare -A CRYPTO_MODULES
CRYPTO_MODULES=(
    ["Intel_QAT"]="qat_c3xxx qat_c62x qat_dh895xcc"
    ["AMD_PSP"]="ccp sp-psp"
    ["ARM_CryptoCell"]="cryptocell"
    ["NXP_CAAM"]="caam caam_jr"
    ["Microchip_ECC"]="microchip-ecc"
    ["IBM_POWER"]="ibmvtpm"
)

# Power management profiles
declare -A POWER_PROFILES
POWER_PROFILES[performance]="
# CPU Governor
GOVERNOR=performance
ENERGY_PERF_BIAS=performance
CPU_BOOST=1
CPU_HWP_DYN_BOOST=1

# GPU Settings
GPU_POWER_LEVEL=high
GPU_PERFORMANCE_LEVEL=auto

# Memory
VM_DIRTY_RATIO=40
VM_DIRTY_BACKGROUND_RATIO=10
VM_SWAPPINESS=10

# Disk
DISK_SCHEDULER=none
DISK_READ_AHEAD=2048
"

POWER_PROFILES[balanced]="
# CPU Governor
GOVERNOR=schedutil
ENERGY_PERF_BIAS=normal
CPU_BOOST=1
CPU_HWP_DYN_BOOST=1

# GPU Settings
GPU_POWER_LEVEL=auto
GPU_PERFORMANCE_LEVEL=auto

# Memory
VM_DIRTY_RATIO=20
VM_DIRTY_BACKGROUND_RATIO=10
VM_SWAPPINESS=60

# Disk
DISK_SCHEDULER=bfq
DISK_READ_AHEAD=1024
"

POWER_PROFILES[powersave]="
# CPU Governor
GOVERNOR=powersave
ENERGY_PERF_BIAS=powersave
CPU_BOOST=0
CPU_HWP_DYN_BOOST=0

# GPU Settings
GPU_POWER_LEVEL=low
GPU_PERFORMANCE_LEVEL=low

# Memory
VM_DIRTY_RATIO=10
VM_DIRTY_BACKGROUND_RATIO=5
VM_SWAPPINESS=100

# Disk
DISK_SCHEDULER=bfq
DISK_READ_AHEAD=512
"

# Enhanced module dependency tracking
declare -A MODULE_DEPENDENCIES_EXTENDED
MODULE_DEPENDENCIES_EXTENDED=(
    ["amdgpu"]="drm drm_kms_helper amdkfd amd_iommu_v2 ttm"
    ["i915"]="drm drm_kms_helper intel_gtt agpgart i2c_algo_bit ttm"
    ["nouveau"]="drm drm_kms_helper ttm mxm_wmi"
    ["iwlwifi"]="mac80211 cfg80211 firmware_class"
    ["e1000e"]="ptp pps_core"
    ["nvme"]="nvme_core"
    ["qat"]="intel_qat"
    ["mlx5_core"]="mlx5_core_ipoib rdma_cm ib_core"
)

# Function to detect and configure advanced hardware
detect_advanced_hardware_extended() {
    log INFO "Detecting advanced hardware features..."
    
    declare -a detected_modules
    
    # Check for ARM NPU
    if grep -q "Mali" /proc/cpuinfo || lspci | grep -qi "Mali"; then
        detected_modules+=("${ACCELERATOR_MODULES[ARM_NPU]}")
    fi
    
    # Check for Intel VPU
    if lspci | grep -qi "Vision Processing Unit"; then
        detected_modules+=("${ACCELERATOR_MODULES[Intel_VPU]}")
    fi
    
    # Check for specialized crypto hardware
    for crypto_hw in "${!CRYPTO_MODULES[@]}"; do
        case $crypto_hw in
            "Intel_QAT")
                if lspci | grep -qi "QuickAssist"; then
                    detected_modules+=("${CRYPTO_MODULES[$crypto_hw]}")
                fi
                ;;
            "AMD_PSP")
                if lspci | grep -qi "PSP"; then
                    detected_modules+=("${CRYPTO_MODULES[$crypto_hw]}")
                fi
                ;;
            *)
                # Generic detection based on PCI devices
                if lspci | grep -qi "$crypto_hw"; then
                    detected_modules+=("${CRYPTO_MODULES[$crypto_hw]}")
                fi
                ;;
        esac
    done
    
    echo "${detected_modules[@]}"
}

# Function to apply power management profile
apply_power_profile() {
    local profile=$1
    log INFO "Applying power profile: $profile"
    
    if [ -z "${POWER_PROFILES[$profile]}" ]; then
        log ERROR "Invalid power profile: $profile"
        return 1
    fi
    
    # Parse and apply profile settings
    while IFS='=' read -r key value; do
        case "$key" in
            "GOVERNOR")
                for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
                    echo "$value" | sudo tee "$cpu" >/dev/null
                done
                ;;
            "ENERGY_PERF_BIAS")
                if command -v x86_energy_perf_policy >/dev/null; then
                    sudo x86_energy_perf_policy "$value"
                fi
                ;;
            "CPU_BOOST")
                echo "$value" | sudo tee /sys/devices/system/cpu/cpufreq/boost >/dev/null
                ;;
            "GPU_POWER_LEVEL")
                for gpu in /sys/class/drm/card*/device/power_dpm_force_performance_level; do
                    echo "$value" | sudo tee "$gpu" >/dev/null
                done
                ;;
            "VM_"*)
                sysctl_name="vm.${key#VM_}" 
                sysctl_name=$(echo "$sysctl_name" | tr '[:upper:]' '[:lower:]')
                sudo sysctl -w "$sysctl_name=$value"
                ;;
            "DISK_SCHEDULER")
                for disk in /sys/block/sd*/queue/scheduler; do
                    echo "$value" | sudo tee "$disk" >/dev/null
                done
                ;;
        esac
    done <<< "${POWER_PROFILES[$profile]}"
}

# Update detect_and_configure_modules
detect_and_configure_modules() {
    # ... (previous code) ...
    
    # Detect advanced hardware
    local advanced_hw=$(detect_advanced_hardware_extended)
    required_modules+=($advanced_hw)
    
    # Apply extended dependencies
    for module in "${required_modules[@]}"; do
        if [ -n "${MODULE_DEPENDENCIES_EXTENDED[$module]}" ]; then
            required_modules+=(${MODULE_DEPENDENCIES_EXTENDED[$module]})
        fi
    done
    
    # Apply power profile based on system type
    if [ -f "/sys/class/power_supply/BAT0/status" ]; then
        apply_power_profile "balanced"
    else
        apply_power_profile "performance"
    fi
    
    # ... (rest of the function) ...
}

# Main installation function
install_all() {
    # Install package groups
    for group in "${!PACKAGE_GROUPS[@]}"; do
        install_packages "$group" "${PACKAGE_GROUPS[$group]}" || exit 1
    done
    
    # Setup build environment
    setup_build_env || exit 1
    
    # Configure development tools
    configure_dev_tools || exit 1
    
    # Configure editors
    configure_editors || exit 1
    
    # Configure system services
    configure_services || exit 1
    
    # Install Rust tools
    install_rust_tools || exit 1
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=1
                LOG_LEVEL="DEBUG"
                shift
                ;;
            -f|--force)
                FORCE=1
                shift
                ;;
            -m|--minimal)
                MINIMAL=1
                shift
                ;;
            -s|--skip-tests)
                SKIP_TESTS=1
                shift
                ;;
            --build-type)
                BUILD_TYPE="$2"
                shift 2
                ;;
            --target-cpu)
                TARGET_CPU="$2"
                shift 2
                ;;
            --log-level)
                LOG_LEVEL="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << EOF
AetherOS Setup Script
Usage: $0 [options]

Options:
  -v, --verbose     Enable verbose output
  -f, --force       Force installation even if packages exist
  -m, --minimal     Install minimal set of packages
  -s, --skip-tests  Skip running tests after installation
  --build-type      Set build type (debug|release|profile)
  --target-cpu      Set target CPU (native|generic|specific model)
  --log-level       Set log level (DEBUG|INFO|WARN|ERROR)
  -h, --help        Show this help message

Example:
  $0 -v --build-type release --target-cpu native

Report bugs to: https://github.com/aetheros/aetheros/issues
EOF
}

# Main script execution starts here
main() {
    # Initialize
    > "$LOG_FILE"
    chmod 600 "$LOG_FILE"
    
    log INFO "╔════ AetherOS Setup ════╗"
    log INFO "║ Version: 1.0.0         ║"
    log INFO "║ Build Type: $BUILD_TYPE    ║"
    log INFO "║ Target CPU: $TARGET_CPU   ║"
    log INFO "╚════════════════════════╝"
    
    # Run system checks
    check_system
    
    # Apply performance profile based on build type
    case $BUILD_TYPE in
        release)
            apply_performance_profile throughput
            ;;
        debug)
            apply_performance_profile low_latency
            ;;
        profile)
            apply_performance_profile realtime
            ;;
    esac
    
    # Apply security hardening
    harden_system
    
    # Optimize compiler flags
    optimize_compiler_flags
    
    # Detect hardware and configure modules
    detect_and_configure_modules
    
    # Install all packages and configure environment
    install_all
    
    log INFO "Setup completed successfully!"
    [ $VERBOSE -eq 1 ] && log INFO "Log file: $LOG_FILE"
}

# Parse arguments and run main
parse_args "$@"
main
