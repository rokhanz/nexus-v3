#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════════
#                              COMMON UTILITIES
# ═══════════════════════════════════════════════════════════════════════════════
# Description: Shared utilities, configurations, and helper functions
# Dependencies: None (standalone)
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent double-loading
[[ -n "${NEXUS_COMMON_LOADED:-}" ]] && return 0
readonly NEXUS_COMMON_LOADED=1

# ═══════════════════════════════════════════════════════════════════════════════
#                                CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

# Default configurations
readonly GITHUB_REPO="https://github.com/rokhanz/nexus-v3"
readonly GITHUB_RAW="https://raw.githubusercontent.com/rokhanz/nexus-v3/main"
readonly CHAIN_ID="1337"
readonly RPC_HTTP="http://localhost:8545"

# Directory paths
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
readonly WORKDIR="$SCRIPT_DIR/nexus-v3"
readonly CREDENTIALS_FILE="$WORKDIR/credentials.json"
readonly LOG_FILE="$WORKDIR/logs/activity.log"
readonly TEMP_DIR="/tmp/nexus-$(date +%s)"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# ═══════════════════════════════════════════════════════════════════════════════
#                                UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Initialize common system
init_common() {
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    
    # Create working directories
    mkdir -p "$WORKDIR"/{logs,backup,config}
    
    # Set trap for cleanup
    trap 'cleanup_temp' EXIT
}

# Get current Jakarta time
now_jakarta() {
    date "+%Y-%m-%d %H:%M:%S WIB"
}

# Clear screen utility
clear_screen() {
    printf '\033[2J\033[H'
}

# Sanitize user input
sanitize_input() {
    local input="$1"
    # Remove dangerous characters
    echo "$input" | tr -d '\r\n;|&$`(){}[]<>*?~^#!"\\'\'
}

# Log activity with timestamp
log_activity() {
    local message="$1"
    local timestamp
    timestamp=$(now_jakarta)
    echo "[$timestamp] $message" >> "$LOG_FILE"
}

# Check if running as root with strict validation
check_root_user() {
    if [[ $EUID -eq 0 ]]; then
        echo -e "${RED}⚠️  PERINGATAN: Script dijalankan sebagai root user!${NC}"
        echo -e "${YELLOW}📋 Untuk keamanan yang lebih baik, disarankan menggunakan user non-root${NC}"
        echo ""
        
        # Tampilkan opsi untuk user
        echo -e "${CYAN}Pilihan yang tersedia:${NC}"
        echo -e "  ${GREEN}[1]${NC} Lanjutkan sebagai root (TIDAK DISARANKAN)"
        echo -e "  ${GREEN}[2]${NC} Buat user baru"
        echo -e "  ${GREEN}[3]${NC} Gunakan user existing"
        echo -e "  ${RED}[0]${NC} Keluar dari script"
        echo ""
        
        read -p "$(echo -e "${YELLOW}Pilih opsi [0-3]: ${NC}")" root_choice
        
        case $root_choice in
            1)
                echo -e "${YELLOW}⚠️  Melanjutkan sebagai root user...${NC}"
                echo -e "${RED}PERHATIAN: Ini dapat menimbulkan risiko keamanan!${NC}"
                log_activity "WARNING: Script dijalankan sebagai root user"
                sleep 3
                ;;
            2)
                create_and_switch_user
                ;;
            3)
                switch_to_existing_user
                ;;
            0)
                echo -e "${CYAN}👋 Script dibatalkan untuk keamanan${NC}"
                log_activity "Script dibatalkan - user memilih tidak melanjutkan sebagai root"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Pilihan tidak valid${NC}"
                check_root_user  # Ulang pertanyaan
                ;;
        esac
    else
        # Jika sudah non-root, tampilkan konfirmasi dan lanjutkan
        echo -e "${GREEN}✅ Berjalan sebagai user non-root: $(whoami)${NC}"
        log_activity "Script dijalankan sebagai user non-root: $(whoami)"
    fi
}

# Fungsi untuk membuat user baru dan pindah script
create_and_switch_user() {
    echo -e "${CYAN}🔧 Membuat user baru untuk menjalankan Nexus...${NC}"
    
    # Input nama user baru
    while true; do
        read -p "$(echo -e "${YELLOW}Masukkan nama user baru: ${NC}")" new_username
        new_username=$(sanitize_input "$new_username")
        
        if [[ -z "$new_username" ]]; then
            echo -e "${RED}❌ Nama user tidak boleh kosong${NC}"
            continue
        fi
        
        if id "$new_username" &>/dev/null; then
            echo -e "${RED}❌ User '$new_username' sudah ada${NC}"
            continue
        fi
        
        if [[ ! "$new_username" =~ ^[a-z][-a-z0-9]*$ ]]; then
            echo -e "${RED}❌ Nama user harus dimulai dengan huruf kecil dan hanya boleh mengandung huruf, angka, dan tanda strip${NC}"
            continue
        fi
        
        break
    done
    
    # Buat user baru
    echo -e "${CYAN}📝 Membuat user '$new_username'...${NC}"
    if useradd -m -s /bin/bash "$new_username"; then
        echo -e "${GREEN}✅ User '$new_username' berhasil dibuat${NC}"
    else
        echo -e "${RED}❌ Gagal membuat user '$new_username'${NC}"
        return 1
    fi
    
    # Tambahkan ke grup docker jika ada
    if getent group docker >/dev/null 2>&1; then
        usermod -aG docker "$new_username"
        echo -e "${GREEN}✅ User '$new_username' ditambahkan ke grup docker${NC}"
    fi
    
    # Pindah script ke user baru
    migrate_script_to_user "$new_username"
}

# Fungsi untuk beralih ke user existing
switch_to_existing_user() {
    echo -e "${CYAN}👥 Daftar user yang tersedia:${NC}"
    
    # Tampilkan daftar user (kecuali system users)
    local users
    users=$(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1}' | head -10)
    
    if [[ -z "$users" ]]; then
        echo -e "${RED}❌ Tidak ada user reguler yang ditemukan${NC}"
        echo -e "${CYAN}💡 Gunakan opsi 2 untuk membuat user baru${NC}"
        check_root_user
        return
    fi
    
    echo "$users" | nl -w2 -s') '
    echo ""
    
    read -p "$(echo -e "${YELLOW}Masukkan nama user yang akan digunakan: ${NC}")" existing_username
    existing_username=$(sanitize_input "$existing_username")
    
    if ! id "$existing_username" &>/dev/null; then
        echo -e "${RED}❌ User '$existing_username' tidak ditemukan${NC}"
        switch_to_existing_user
        return
    fi
    
    # Pastikan user ada akses docker
    if getent group docker >/dev/null 2>&1; then
        if ! groups "$existing_username" | grep -q docker; then
            echo -e "${YELLOW}⚠️  User '$existing_username' belum ada di grup docker${NC}"
            read -p "$(echo -e "${CYAN}Tambahkan ke grup docker? [y/N]: ${NC}")" add_docker
            if [[ "$add_docker" =~ ^[Yy]$ ]]; then
                usermod -aG docker "$existing_username"
                echo -e "${GREEN}✅ User '$existing_username' ditambahkan ke grup docker${NC}"
            fi
        fi
    fi
    
    # Pindah script ke user tersebut
    migrate_script_to_user "$existing_username"
}

# Fungsi untuk memindahkan script ke user lain
migrate_script_to_user() {
    local target_user="$1"
    local target_home
    target_home=$(getent passwd "$target_user" | cut -d: -f6)
    local target_script_dir="$target_home/nexus-v3-manager"
    
    echo -e "${CYAN}📦 Setup script untuk user '$target_user'...${NC}"
    
    # Buat direktori target
    mkdir -p "$target_script_dir"
    
    # Copy seluruh script ke direktori user baru
    cp -r "$SCRIPT_DIR"/* "$target_script_dir/"
    
    # Handle proxy_list.txt jika ada
    local current_proxy="$SCRIPT_DIR/proxy_list.txt"
    local target_backup_dir="$target_home/nexus-backup"
    
    if [[ -f "$current_proxy" ]]; then
        # Buat direktori backup di home user
        mkdir -p "$target_backup_dir" 2>/dev/null
        
        # Backup ke user home
        cp "$current_proxy" "$target_backup_dir/proxy_list.txt" 2>/dev/null
        
        # Copy ke workdir user
        cp "$current_proxy" "$target_script_dir/nexus-v3/proxy_list.txt" 2>/dev/null
    fi
    
    # Set ownership
    chown -R "$target_user:$target_user" "$target_script_dir"
    chown -R "$target_user:$target_user" "$target_backup_dir" 2>/dev/null || true
    
    # Set permission
    chmod +x "$target_script_dir/main.sh"
    chmod +x "$target_script_dir/lib"/*.sh
    
    echo -e "${GREEN}✅ Setup selesai untuk user '$target_user'${NC}"
    
    # Informasi untuk user
    echo ""
    echo -e "${CYAN}📋 Langkah selanjutnya:${NC}"
    echo -e "1. ${YELLOW}Login sebagai user '$target_user':${NC} ${WHITE}su - $target_user${NC}"
    echo -e "2. ${YELLOW}Jalankan script:${NC} ${WHITE}cd nexus-v3-manager && ./main.sh${NC}"
    echo ""
    
    log_activity "Script di-setup untuk user '$target_user' di '$target_script_dir'"
    
    echo -e "${GREEN}🎉 Setup selesai! Silakan login sebagai user '$target_user'${NC}"
    
    exit 0
}

# Backup proxy list ke user backup directory
backup_proxy_list() {
    local backup_dir="$HOME/nexus-backup"
    local proxy_file="$WORKDIR/proxy_list.txt"
    
    if [[ -f "$proxy_file" ]]; then
        mkdir -p "$backup_dir" 2>/dev/null
        cp "$proxy_file" "$backup_dir/proxy_list.txt" 2>/dev/null
    fi
    return 0
}

# Restore proxy list dari user backup directory
restore_proxy_list() {
    local backup_dir="$HOME/nexus-backup"
    local backup_proxy="$backup_dir/proxy_list.txt"
    local target_proxy="$WORKDIR/proxy_list.txt"
    
    if [[ -f "$backup_proxy" ]]; then
        cp "$backup_proxy" "$target_proxy" 2>/dev/null
    fi
    return 0
}

# Check if Nexus is installed
is_nexus_installed() {
    # Check for Docker installation
    if ! command -v docker >/dev/null 2>&1; then
        return 1
    fi
    
    # Check for docker-compose
    if ! command -v docker-compose >/dev/null 2>&1 && ! (command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1); then
        return 1
    fi
    
    # Check for project files
    if [[ ! -f "$WORKDIR/docker-compose.yml" ]] || [[ ! -f "$CREDENTIALS_FILE" ]]; then
        return 1
    fi
    
    return 0
}

# Get available ports
get_available_ports() {
    local count=${1:-1}
    local start_port=${2:-10000}
    local ports=()
    local port=$start_port
    
    while [[ ${#ports[@]} -lt $count ]]; do
        if ! netstat -tuln 2>/dev/null | grep -q ":$port "; then
            ports+=("$port")
        fi
        ((port++))
        
        # Prevent infinite loop
        if [[ $port -gt $((start_port + 1000)) ]]; then
            echo "Error: Could not find $count available ports" >&2
            return 1
        fi
    done
    
    echo "${ports[*]}"
}

# Status indicator helper
get_status_indicator() {
    local status="$1"
    case "$status" in
        "active"|"running"|"success")
            echo "🟢"
            ;;
        "warning"|"pending")
            echo "🟡"
            ;;
        "error"|"failed"|"stopped")
            echo "🔴"
            ;;
        *)
            echo "⚫"
            ;;
    esac
}

# Cleanup temporary files
cleanup_temp() {
    [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR" 2>/dev/null || true
}

# Terminal detection
detect_terminal_environment() {
    if [[ -n "${VSCODE_PID:-}" ]] || [[ "${TERM_PROGRAM:-}" == "vscode" ]]; then
        echo "vscode"
    elif [[ -n "${WT_SESSION:-}" ]] || [[ "${TERM_PROGRAM:-}" == "Windows Terminal" ]]; then
        echo "windows_terminal"
    elif [[ -n "${SSH_CLIENT:-}" ]] || [[ -n "${SSH_TTY:-}" ]]; then
        echo "ssh"
    elif [[ -n "${TMUX:-}" ]] || [[ "${TERM:-}" == "screen"* ]]; then
        echo "multiplexer"
    else
        echo "standard"
    fi
}

# Validate wallet address
validate_wallet_address() {
    local wallet="$1"
    if [[ "$wallet" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Progress bar utility
show_progress() {
    local current=$1
    local total=$2
    local width=${3:-50}
    local prefix=${4:-"Progress"}
    
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r%s: [" "$prefix"
    printf "%*s" "$filled" | tr ' ' '='
    printf "%*s" "$empty" | tr ' ' '-'
    printf "] %d%%" "$percentage"
    
    if [[ $current -eq $total ]]; then
        echo ""
    fi
}

# Directory setup
setup_directory_structure() {
    echo -e "${CYAN}🗂️  Setting up directory structure...${NC}"
    
    # Create main directories (tanpa subfolder backup)
    mkdir -p "$WORKDIR"/{logs,config}
    
    # Create persistent backup directory
    mkdir -p "$HOME/nexus-backup" 2>/dev/null || {
        echo -e "${YELLOW}   ⚠️  Cannot create user backup directory${NC}"
    }
    
    # Handle credentials and proxy list migration
    migrate_credentials
    
    # Try to restore proxy list from user backup if not already present
    if [[ ! -f "$WORKDIR/proxy_list.txt" ]]; then
        restore_proxy_list
    fi
    
    echo -e "${GREEN}✅ Directory structure ready${NC}"
}

# Migrate existing credentials and proxy list
migrate_credentials() {
    local backup_cred="$HOME/nexus-backup/credentials.json"
    local legacy_cred="$HOME/.nexus/credentials.json"
    
    local backup_proxy="$HOME/nexus-backup/proxy_list.txt"
    local current_proxy="$SCRIPT_DIR/proxy_list.txt"
    
    # Check for existing credentials
    if [[ -f "$backup_cred" ]]; then
        cp "$backup_cred" "$CREDENTIALS_FILE" 2>/dev/null
    elif [[ -f "$legacy_cred" ]]; then
        # Try to backup first
        mkdir -p "$HOME/nexus-backup" 2>/dev/null
        cp "$legacy_cred" "$backup_cred" 2>/dev/null
        
        # Copy to working directory
        cp "$legacy_cred" "$CREDENTIALS_FILE" 2>/dev/null
    fi
    
    # Check for existing proxy list
    if [[ -f "$backup_proxy" ]]; then
        cp "$backup_proxy" "$WORKDIR/proxy_list.txt" 2>/dev/null
    elif [[ -f "$current_proxy" ]]; then
        # Try to backup first (jangan hapus file asli)
        mkdir -p "$HOME/nexus-backup" 2>/dev/null
        cp "$current_proxy" "$backup_proxy" 2>/dev/null
        
        # Copy to working directory (jangan hapus file asli)
        cp "$current_proxy" "$WORKDIR/proxy_list.txt" 2>/dev/null
    fi
}

# Export functions for use by other modules
export -f now_jakarta clear_screen sanitize_input log_activity
export -f check_root_user create_and_switch_user switch_to_existing_user migrate_script_to_user
export -f backup_proxy_list restore_proxy_list
export -f is_nexus_installed get_available_ports
export -f get_status_indicator detect_terminal_environment
export -f validate_wallet_address show_progress setup_directory_structure
