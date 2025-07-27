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
readonly CHAIN_ID="3940"
readonly RPC_HTTP="https://testnet3.rpc.nexus.xyz"
readonly WS_URL="wss://testnet3.rpc.nexus.xyz"
readonly EXPLORER_URL="https://testnet3.explorer.nexus.xyz"

# Directory paths
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
readonly WORKDIR="$SCRIPT_DIR/workdir"
readonly CREDENTIALS_FILE="$WORKDIR/credentials.json"
readonly LOG_FILE="$WORKDIR/logs/activity.log"
readonly PROXY_FILE="$WORKDIR/proxy_list.txt"
readonly COMPOSE_FILE="$WORKDIR/docker-compose.yml"

# Safe temp directory creation with race condition protection
TEMP_DIR_BASE="/tmp/nexus"
readonly TEMP_DIR_BASE
readonly TEMP_DIR="$(mktemp -d "${TEMP_DIR_BASE}-XXXXXX" 2>/dev/null || echo "${TEMP_DIR_BASE}-$$-$(date +%s)")"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly GRAY='\033[0;37m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# ═══════════════════════════════════════════════════════════════════════════════
#                                UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Auto-detect and copy credentials and proxy files from system locations
auto_detect_and_copy_files() {
    log_activity "Starting auto-detection of credentials and proxy files"
    
    # Jakarta timezone setup
    export TZ='Asia/Jakarta'
    
    # Search locations for credentials.json
    local credentials_paths=(
        "/root/credentials.json"
        "/root/.nexus/credentials.json" 
        "/root/nexus-backup/credentials.json"
        "/root/nexus/credentials.json"
        "/home/$USER/credentials.json"
        "/home/$USER/.nexus/credentials.json"
        "$HOME/credentials.json"
        "$HOME/.nexus/credentials.json"
    )
    
    # Search locations for proxy_list.txt
    local proxy_paths=(
        "/root/proxy_list.txt"
        "/root/.nexus/proxy_list.txt"
        "/root/nexus-backup/proxy_list.txt" 
        "/root/nexus/proxy_list.txt"
        "/home/$USER/proxy_list.txt"
        "/home/$USER/.nexus/proxy_list.txt"
        "$HOME/proxy_list.txt"
        "$HOME/.nexus/proxy_list.txt"
    )
    
    # Auto-detect and copy credentials.json
    if [[ ! -f "$CREDENTIALS_FILE" ]]; then
        for cred_path in "${credentials_paths[@]}"; do
            if [[ -f "$cred_path" ]]; then
                echo -e "${CYAN}📋 Found credentials at: $cred_path${NC}"
                cp "$cred_path" "$CREDENTIALS_FILE" 2>/dev/null
                chmod 600 "$CREDENTIALS_FILE" 2>/dev/null
                log_activity "Credentials copied from $cred_path to $CREDENTIALS_FILE"
                break
            fi
        done
    fi
    
    # Auto-detect and copy proxy_list.txt
    if [[ ! -f "$PROXY_FILE" ]]; then
        for proxy_path in "${proxy_paths[@]}"; do
            if [[ -f "$proxy_path" ]]; then
                echo -e "${CYAN}🌐 Found proxy list at: $proxy_path${NC}"
                cp "$proxy_path" "$PROXY_FILE" 2>/dev/null
                chmod 644 "$PROXY_FILE" 2>/dev/null
                log_activity "Proxy list copied from $proxy_path to $PROXY_FILE"
                break
            fi
        done
    fi
    
    # Create default proxy_list.txt if not found
    if [[ ! -f "$PROXY_FILE" ]]; then
        echo -e "${YELLOW}⚠️ No proxy list found, creating default${NC}"
        cat > "$PROXY_FILE" << 'EOF'
# Nexus V3 Proxy List
# Format: http://user:pass@ip:port
# Example: http://username:password@proxy.example.com:8080
EOF
        chmod 644 "$PROXY_FILE"
        log_activity "Default proxy_list.txt created"
    fi
}

# Generate dynamic docker-compose.yml based on detected credentials
generate_docker_compose() {
    local node_id=""
    local container_name="nexus-prover"
    
    # Get node ID from credentials for dynamic container naming
    if [[ -f "$CREDENTIALS_FILE" ]] && command -v jq >/dev/null 2>&1; then
        node_id=$(jq -r '.node_id // empty' "$CREDENTIALS_FILE" 2>/dev/null)
        if [[ -n "$node_id" && "$node_id" != "null" ]]; then
            container_name="nexus-node-$node_id"
        fi
    fi
    
    log_activity "Generating docker-compose.yml with container name: $container_name"
    
    cat > "$COMPOSE_FILE" << EOF
version: '3.8'

services:
  nexus-node:
    image: nexusxyz/nexus-network:latest
    container_name: $container_name
    restart: unless-stopped
    networks:
      - nexus-network
    ports:
      - "3030:3030"
      - "10000:10000"
    environment:
      - RUST_LOG=info
      - NEXUS_HOME=/app/.nexus
      - NETWORK=testnet3
      - TZ=Asia/Jakarta
    volumes:
      - nexus_data:/app/.nexus
      - ./credentials.json:/app/.nexus/credentials.json:ro
      - ./proxy_list.txt:/app/.nexus/proxy_list.txt:ro
    command: >
      sh -c "
        echo 'Starting Nexus Network Node...';
        echo 'Configuration check...';
        if [ ! -f /app/.nexus/credentials.json ]; then
          echo 'ERROR: credentials.json not found';
          exit 1;
        fi;
        echo 'Starting prover with node ID: $node_id';
        /app/nexus-prover --config /app/.nexus/credentials.json --network testnet3
      "
    labels:
      - "nexus.network=true"
      - "nexus.service=prover"
      - "nexus.node_id=$node_id"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3030/health", "||", "exit", "1"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  nexus-network:
    driver: bridge

volumes:
  nexus_data:
    driver: local
EOF
    
    chmod 644 "$COMPOSE_FILE"
    log_activity "docker-compose.yml generated successfully"
}

# Download files from GitHub if using wget
download_github_files() {
    local github_base="https://raw.githubusercontent.com/rokhanz/nexus-v3/main"
    local files_to_download=(
        "credentials-generator.sh"
        "proxy_list.txt"
    )
    
    for file in "${files_to_download[@]}"; do
        if [[ ! -f "$WORKDIR/$file" ]]; then
            echo -e "${CYAN}📥 Downloading $file from GitHub...${NC}"
            if command -v wget >/dev/null 2>&1; then
                wget -q --timeout=30 -O "$WORKDIR/$file" "$github_base/$file" 2>/dev/null
            elif command -v curl >/dev/null 2>&1; then
                curl -s --connect-timeout 30 -o "$WORKDIR/$file" "$github_base/$file" 2>/dev/null
            fi
            
            if [[ -f "$WORKDIR/$file" ]]; then
                chmod +x "$WORKDIR/$file" 2>/dev/null
                log_activity "Downloaded $file from GitHub"
            fi
        fi
    done
}

# Get dynamic container name based on node ID
get_container_name() {
    local node_id=""
    local container_name="nexus-prover"
    
    # Get node ID from credentials for dynamic container naming
    if [[ -f "$CREDENTIALS_FILE" ]] && command -v jq >/dev/null 2>&1; then
        node_id=$(jq -r '.node_id // empty' "$CREDENTIALS_FILE" 2>/dev/null)
        if [[ -n "$node_id" && "$node_id" != "null" ]]; then
            container_name="nexus-node-$node_id"
        fi
    fi
    
    echo "$container_name"
}

# Initialize common system with enhanced safety
init_common() {
    # Set Jakarta timezone with error handling
    if ! export TZ='Asia/Jakarta'; then
        echo "Warning: Could not set timezone" >&2
    fi
    
    # Create temp directory safely with race condition protection
    if [[ -n "$TEMP_DIR" ]] && ! mkdir -p "$TEMP_DIR" 2>/dev/null; then
        echo "Warning: Could not create temp directory: $TEMP_DIR" >&2
        # Fallback to basic temp dir
        TEMP_DIR="/tmp/nexus-$$"
        mkdir -p "$TEMP_DIR" 2>/dev/null || {
            echo "Error: Cannot create any temp directory" >&2
            return 1
        }
    fi
    
    # Create working directories with error handling
    if ! mkdir -p "$WORKDIR"/{logs,backup,config} 2>/dev/null; then
        echo "Error: Cannot create working directories" >&2
        return 1
    fi
    
    # Auto-detect and copy files with error handling
    if ! auto_detect_and_copy_files; then
        echo "Warning: Auto-detection of files failed" >&2
    fi
    
    # Download additional files from GitHub (non-critical)
    download_github_files || true
    
    # Generate docker-compose.yml with error handling
    if ! generate_docker_compose; then
        echo "Warning: Could not generate docker-compose.yml" >&2
    fi
    
    # Set trap for cleanup with error handling
    if ! trap 'cleanup_temp' EXIT; then
        echo "Warning: Could not set cleanup trap" >&2
    fi
    
    return 0
}

# Get current Jakarta time
now_jakarta() {
    date "+%Y-%m-%d %H:%M:%S WIB"
}

# Clear screen utility
clear_screen() {
    printf '\033[2J\033[H'
}

# Status display function with colored indicators
# Status indicator with colored icons
draw_status() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        "active"|"running"|"connected")
            echo -e "${GREEN}✅ $message${NC}"
            ;;
        "stopped"|"inactive"|"disconnected")
            echo -e "${RED}⏸️  $message${NC}"
            ;;
        "warning"|"pending")
            echo -e "${YELLOW}⚠️  $message${NC}"
            ;;
        "error"|"failed")
            echo -e "${RED}❌ $message${NC}"
            ;;
        *)
            echo -e "${GRAY}ℹ️  $message${NC}"
            ;;
    esac
}

# Progress bar display
draw_progress_bar() {
    local current="$1"
    local total="$2"
    local width="${3:-20}"
    
    local percentage=0
    if [[ $total -gt 0 ]]; then
        percentage=$((current * 100 / total))
    fi
    
    local filled=$((width * current / total))
    local empty=$((width - filled))
    
    # Ensure we don't have negative values
    if [[ $filled -lt 0 ]]; then filled=0; fi
    if [[ $empty -lt 0 ]]; then empty=0; fi
    
    local bar=""
    for ((i=0; i<filled; i++)); do
        bar+="█"
    done
    for ((i=0; i<empty; i++)); do
        bar+="░"
    done
    
    echo -e "${CYAN}[$bar]${NC} ${percentage}%"
}

# Sanitize user input
sanitize_input() {
    local input="$1"
    # Remove dangerous characters - fixed to avoid glob expansion
    echo "$input" | tr -d '\r\n;|&(){}[]<>*?~^#!"'"'"
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
    # Display ASCII banner first
    echo -e "${CYAN}"
    cat << 'EOF'

  ██████╗  ██████╗ ██╗  ██╗██╗  ██╗ █████╗ ███╗   ██╗███████╗ 
  ██╔══██╗██╔═══██╗██║ ██╔╝██║  ██║██╔══██╗████╗  ██║╚══███╔╝ 
  ██████╔╝██║   ██║█████╔╝ ███████║███████║██╔██╗ ██║  ███╔╝  
  ██╔══██╗██║   ██║██╔═██╗ ██╔══██║██╔══██║██║╚██╗██║ ███╔╝   
  ██║  ██║╚██████╔╝██║  ██╗██║  ██║██║  ██║██║ ╚████║███████╗ 
  ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝ 

EOF
    echo -e "${NC}"
    echo -e "${BLUE}                    Nexus V3 management                    ${NC}"
    echo ""
    
    if [[ $EUID -eq 0 ]]; then
        echo -e "${RED}⚠️  PERINGATAN: Script dijalankan sebagai root user!${NC}"
        echo -e "${YELLOW}📋 Untuk keamanan yang lebih baik, disarankan menggunakan user non-root${NC}"
        echo ""
        
        # Tampilkan opsi untuk user
        echo -e "${CYAN}Pilihan yang tersedia:${NC}"
        echo -e "  ${GREEN}[1]${NC} Setup user non-root (buat baru / gunakan existing)"
        echo -e "  ${RED}[0]${NC} Keluar dari script"
        echo ""
        
        while true; do
            read -p "$(echo -e "${YELLOW}Pilih opsi [0-1]: ${NC}")" root_choice
            
            case $root_choice in
                1)
                    setup_non_root_user
                    break
                    ;;
                0)
                    echo -e "${CYAN}👋 Script dibatalkan untuk keamanan${NC}"
                    log_activity "Script dibatalkan - user memilih tidak melanjutkan sebagai root"
                    exit 0
                    ;;
                *)
                    echo -e "${RED}❌ Pilihan tidak valid${NC}"
                    continue
                    ;;
            esac
        done
    else
        # Jika sudah non-root, tampilkan konfirmasi dan lanjutkan
        echo -e "${GREEN}✅ Berjalan sebagai user non-root: $(whoami)${NC}"
        log_activity "Script dijalankan sebagai user non-root: $(whoami)"
    fi
}

# Fungsi untuk setup user non-root (gabungan buat baru / gunakan existing)
setup_non_root_user() {
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        echo -e "${CYAN}👤 Setup User Non-Root (Attempt $attempt/$max_attempts)${NC}"
        echo -e "${CYAN}═══════════════════════${NC}"
        echo ""
        
        echo -e "${CYAN}Pilihan setup:${NC}"
        echo -e "  ${GREEN}[1]${NC} Buat user baru"
        echo -e "  ${GREEN}[2]${NC} Gunakan user existing"
        echo -e "  ${RED}[0]${NC} Keluar dari script"
        echo ""
        
        local user_choice
        read -p "$(echo -e "${YELLOW}Pilih opsi [0-2]: ${NC}")" user_choice
        
        case $user_choice in
            1)
                if create_new_user_flow; then
                    return 0
                else
                    echo -e "${RED}❌ Gagal membuat user baru${NC}"
                fi
                ;;
            2)
                if use_existing_user_flow; then
                    return 0
                else
                    echo -e "${RED}❌ Gagal menggunakan user existing${NC}"
                fi
                ;;
            0)
                echo -e "${CYAN}👋 Script dibatalkan untuk keamanan${NC}"
                log_activity "Script dibatalkan - user memilih keluar dari setup non-root"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Pilihan tidak valid${NC}"
                ;;
        esac
        
        ((attempt++))
        if [[ $attempt -le $max_attempts ]]; then
            echo -e "${YELLOW}⚠️  Mencoba lagi...${NC}"
            sleep 1
        fi
    done
    
    echo -e "${RED}❌ Maksimal percobaan tercapai. Keluar dari script.${NC}"
    log_activity "Setup non-root user gagal setelah $max_attempts percobaan"
    exit 1
}

# Flow untuk membuat user baru
create_new_user_flow() {
    echo -e "${CYAN}🔧 Membuat User Baru${NC}"
    echo ""
    
    # Input nama user baru
    while true; do
        read -p "$(echo -e "${YELLOW}Masukkan nama user baru (contoh: nexususer): ${NC}")" new_username
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
    
    # Setup dan langsung switch ke user tersebut
    setup_and_switch_to_user "$new_username"
}

# Fungsi untuk setup dan langsung switch ke user
setup_and_switch_to_user() {
    local target_user="$1"
    local target_home
    target_home=$(getent passwd "$target_user" | cut -d: -f6)
    local target_script_dir="$target_home/nexus-v3"
    
    echo -e "${CYAN}📦 Setup script untuk user '$target_user'...${NC}"
    
    # Buat direktori target
    mkdir -p "$target_script_dir"
    
    # Copy seluruh script ke direktori user baru
    if ! cp -r "$SCRIPT_DIR"/* "$target_script_dir/" 2>/dev/null; then
        echo -e "${RED}❌ Gagal mengcopy script ke direktori user${NC}"
        return 1
    fi
    
    # Enhanced credentials and proxy migration
    local target_backup_dir="$target_home/nexus-backup"
    mkdir -p "$target_backup_dir" 2>/dev/null
    
    # Migrate existing credentials if any
    local source_credentials_paths=(
        "/root/nexus-backup/credentials.json"
        "/root/.nexus/credentials.json"
        "$HOME/workdir/credentials.json"
        "$SCRIPT_DIR/workdir/credentials.json"
    )
    
    for cred_path in "${source_credentials_paths[@]}"; do
        if [[ -f "$cred_path" ]]; then
            echo -e "${CYAN}  📋 Migrating credentials from $cred_path${NC}"
            cp "$cred_path" "$target_backup_dir/credentials.json" 2>/dev/null
            cp "$cred_path" "$target_script_dir/workdir/credentials.json" 2>/dev/null
            break
        fi
    done
    
    # Enhanced proxy list migration with multiple sources
    local source_proxy_paths=(
        "/root/nexus-backup/proxy_list.txt"
        "/root/proxy_list.txt"
        "/root/.nexus/proxy_list.txt"
        "$HOME/workdir/proxy_list.txt"
        "/root/nexus-multi-docker/proxy_list.txt"
        "$SCRIPT_DIR/proxy_list.txt"
        "$SCRIPT_DIR/workdir/proxy_list.txt"
    )
    
    local found_proxy=""
    for proxy_path in "${source_proxy_paths[@]}"; do
        if [[ -f "$proxy_path" ]]; then
            # Check if file has valid proxy entries
            local valid_proxies
            valid_proxies=$(grep -v '^[[:space:]]*#' "$proxy_path" | grep -v '^[[:space:]]*$' | wc -l 2>/dev/null)
            if [[ "$valid_proxies" -gt 0 ]]; then
                found_proxy="$proxy_path"
                echo -e "${CYAN}  🌐 Found proxy list: $proxy_path ($valid_proxies proxies)${NC}"
                break
            fi
        fi
    done
    
    if [[ -n "$found_proxy" ]]; then
        # Backup proxy list
        cp "$found_proxy" "$target_backup_dir/proxy_list.txt" 2>/dev/null
        
        # Create formatted proxy list with header
        {
            echo "# Auto-imported for user $target_user - $(date)"
            echo "# Source: $found_proxy"
            cat "$found_proxy"
        } > "$target_script_dir/workdir/proxy_list.txt" 2>/dev/null
        
        echo -e "${GREEN}  ✅ Proxy list migrated successfully${NC}"
    else
        echo -e "${YELLOW}  ⚠️  No proxy list found to migrate${NC}"
    fi
    
    # Set ownership recursively
    chown -R "$target_user:$target_user" "$target_script_dir"
    chown -R "$target_user:$target_user" "$target_backup_dir" 2>/dev/null || true
    
    # Set proper permissions
    chmod +x "$target_script_dir/main.sh"
    chmod +x "$target_script_dir/lib"/*.sh 2>/dev/null || true
    chmod +x "$target_script_dir/test"*.sh 2>/dev/null || true
    
    # Set secure permissions for sensitive files
    chmod 600 "$target_script_dir/workdir/credentials.json" 2>/dev/null || true
    chmod 644 "$target_script_dir/workdir/proxy_list.txt" 2>/dev/null || true
    
    echo -e "${GREEN}✅ Setup selesai untuk user '$target_user'${NC}"
    
    log_activity "Script di-setup untuk user '$target_user' di '$target_script_dir' dengan migrasi lengkap"
    
    echo ""
    echo -e "${CYAN}🔄 Beralih ke user '$target_user' dan menjalankan script...${NC}"
    echo -e "${YELLOW}📍 Script location: $target_script_dir${NC}"
    
    # Enhanced user switch with path verification
    if ! su - "$target_user" -c "test -d '$target_script_dir'"; then
        echo -e "${RED}❌ Cannot access target directory${NC}"
        return 1
    fi

    exec su - "$target_user" -c "
        if [[ -d '$target_script_dir' ]] && [[ -f '$target_script_dir/main.sh' ]]; then
            cd '$target_script_dir' && ./main.sh
        else
            echo 'Error: Cannot find script directory or main.sh'
            echo 'Expected location: $target_script_dir'
            echo 'Please check the setup manually.'
        fi
    " || {
        echo -e "${RED}❌ Failed to switch to user '$target_user'${NC}"
        exit 1
    }
}

# Flow untuk menggunakan user existing
use_existing_user_flow() {
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        echo -e "${CYAN}👥 Pilih User Existing (Attempt $attempt/$max_attempts)${NC}"
        echo ""
        
        # Tampilkan daftar user dengan jelas dan error handling
        local users
        if ! users=$(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1}' | head -10 2>/dev/null); then
            echo -e "${RED}❌ Gagal mendapatkan daftar user${NC}"
            return 1
        fi
        
        if [[ -z "$users" ]]; then
            echo -e "${RED}❌ Tidak ada user reguler yang ditemukan${NC}"
            echo -e "${CYAN}💡 Silakan pilih opsi 1 untuk membuat user baru${NC}"
            return 1
        fi
        
        echo -e "${CYAN}📋 User yang tersedia:${NC}"
        echo "$users" | while IFS= read -r user; do
            echo "   • $user"
        done
        echo ""
        
        local existing_username
        read -p "$(echo -e "${YELLOW}Masukkan nama user (contoh: rokhanz): ${NC}")" existing_username
        existing_username=$(sanitize_input "$existing_username")
        
        if [[ -z "$existing_username" ]]; then
            echo -e "${RED}❌ Nama user tidak boleh kosong${NC}"
            ((attempt++))
            continue
        fi
        
        if ! id "$existing_username" &>/dev/null; then
            echo -e "${RED}❌ User '$existing_username' tidak ditemukan${NC}"
            echo -e "${CYAN}💡 Pastikan menggunakan nama user yang ada di daftar di atas${NC}"
            ((attempt++))
            continue
        fi
        
        # Pastikan user ada akses docker dengan error handling
        if getent group docker >/dev/null 2>&1; then
            if ! groups "$existing_username" | grep -q docker; then
                echo -e "${YELLOW}⚠️  User '$existing_username' belum ada di grup docker${NC}"
                echo -e "${CYAN}✅ Menambahkan '$existing_username' ke grup docker...${NC}"
                if usermod -aG docker "$existing_username" 2>/dev/null; then
                    echo -e "${GREEN}✅ User '$existing_username' ditambahkan ke grup docker${NC}"
                else
                    echo -e "${YELLOW}⚠️  Gagal menambahkan ke grup docker, tapi melanjutkan...${NC}"
                fi
            else
                echo -e "${GREEN}✅ User '$existing_username' sudah ada di grup docker${NC}"
            fi
        fi
        
        # Setup dan langsung switch ke user tersebut
        if setup_and_switch_to_user "$existing_username"; then
            return 0
        else
            echo -e "${RED}❌ Gagal setup untuk user '$existing_username'${NC}"
            ((attempt++))
        fi
        
        if [[ $attempt -le $max_attempts ]]; then
            echo -e "${YELLOW}⚠️  Mencoba lagi...${NC}"
            sleep 1
        fi
    done
    
    echo -e "${RED}❌ Maksimal percobaan tercapai untuk use existing user${NC}"
    return 1
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
    local target_script_dir="$target_home/nexus-v3"
    
    echo -e "${CYAN}📦 Setup script untuk user '$target_user'...${NC}"
    
    # Buat direktori target
    mkdir -p "$target_script_dir"
    
    # Copy seluruh script ke direktori user baru dengan error handling
    if ! cp -r "$SCRIPT_DIR"/* "$target_script_dir/" 2>/dev/null; then
        echo -e "${RED}❌ Gagal mengcopy script ke direktori user${NC}"
        return 1
    fi
    
    # Enhanced migration dengan multiple sources
    local target_backup_dir="$target_home/nexus-backup"
    mkdir -p "$target_backup_dir" 2>/dev/null
    
    # Migrate credentials
    local source_credentials_paths=(
        "/root/nexus-backup/credentials.json"
        "/root/.nexus/credentials.json"
        "$HOME/workdir/credentials.json"
        "$SCRIPT_DIR/workdir/credentials.json"
    )
    
    for cred_path in "${source_credentials_paths[@]}"; do
        if [[ -f "$cred_path" ]]; then
            echo -e "${CYAN}  📋 Migrating credentials from $cred_path${NC}"
            cp "$cred_path" "$target_backup_dir/credentials.json" 2>/dev/null
            cp "$cred_path" "$target_script_dir/workdir/credentials.json" 2>/dev/null
            break
        fi
    done
    
    # Enhanced proxy migration
    local source_proxy_paths=(
        "/root/nexus-backup/proxy_list.txt"
        "/root/proxy_list.txt"
        "/root/.nexus/proxy_list.txt"
        "$HOME/workdir/proxy_list.txt"
        "/root/nexus-multi-docker/proxy_list.txt"
        "$SCRIPT_DIR/proxy_list.txt"
        "$SCRIPT_DIR/workdir/proxy_list.txt"
    )
    
    local found_proxy=""
    for proxy_path in "${source_proxy_paths[@]}"; do
        if [[ -f "$proxy_path" ]]; then
            local valid_proxies
            valid_proxies=$(grep -v '^[[:space:]]*#' "$proxy_path" | grep -v '^[[:space:]]*$' | wc -l 2>/dev/null)
            if [[ "$valid_proxies" -gt 0 ]]; then
                found_proxy="$proxy_path"
                echo -e "${CYAN}  🌐 Found proxy list: $proxy_path ($valid_proxies proxies)${NC}"
                break
            fi
        fi
    done
    
    if [[ -n "$found_proxy" ]]; then
        cp "$found_proxy" "$target_backup_dir/proxy_list.txt" 2>/dev/null
        {
            echo "# Auto-migrated for user $target_user - $(date)"
            echo "# Source: $found_proxy"
            cat "$found_proxy"
        } > "$target_script_dir/workdir/proxy_list.txt" 2>/dev/null
        echo -e "${GREEN}  ✅ Proxy list migrated successfully${NC}"
    fi
    
    # Set ownership
    chown -R "$target_user:$target_user" "$target_script_dir"
    chown -R "$target_user:$target_user" "$target_backup_dir" 2>/dev/null || true
    
    # Set comprehensive permissions
    chmod +x "$target_script_dir/main.sh"
    chmod +x "$target_script_dir/lib"/*.sh 2>/dev/null || true
    chmod +x "$target_script_dir/test"*.sh 2>/dev/null || true
    chmod 600 "$target_script_dir/workdir/credentials.json" 2>/dev/null || true
    chmod 644 "$target_script_dir/workdir/proxy_list.txt" 2>/dev/null || true
    
    echo -e "${GREEN}✅ Setup selesai untuk user '$target_user'${NC}"
    
    # Informasi untuk user dengan path verification
    echo ""
    echo -e "${CYAN}📋 Langkah selanjutnya:${NC}"
    echo -e "1. ${YELLOW}Login sebagai user '$target_user':${NC} ${WHITE}su - $target_user${NC}"
    echo -e "2. ${YELLOW}Jalankan script:${NC} ${WHITE}cd nexus-v3 && ./main.sh${NC}"
    echo -e "3. ${YELLOW}Script location:${NC} ${WHITE}$target_script_dir${NC}"
    echo ""
    
    # Verify setup
    if [[ -f "$target_script_dir/main.sh" ]] && [[ -x "$target_script_dir/main.sh" ]]; then
        echo -e "${GREEN}✅ Verification: Script setup successful${NC}"
    else
        echo -e "${RED}⚠️  Warning: main.sh not found or not executable${NC}"
    fi
    
    log_activity "Script di-setup untuk user '$target_user' di '$target_script_dir' dengan migrasi lengkap"
    
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

# Silent backup for all critical files (no timestamps, overwrite mode)
backup_files_silently() {
    local backup_dir="$HOME/nexus-backup"
    mkdir -p "$backup_dir" 2>/dev/null
    
    # Backup credentials
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        cp "$CREDENTIALS_FILE" "$backup_dir/credentials.json" 2>/dev/null
    fi
    
    # Backup proxy list
    if [[ -f "$WORKDIR/proxy_list.txt" ]]; then
        cp "$WORKDIR/proxy_list.txt" "$backup_dir/proxy_list.txt" 2>/dev/null
    fi
    
    # Backup other important configs
    if [[ -f "$WORKDIR/.env" ]]; then
        cp "$WORKDIR/.env" "$backup_dir/.env" 2>/dev/null
    fi
    
    if [[ -f "$WORKDIR/docker-compose.yml" ]]; then
        cp "$WORKDIR/docker-compose.yml" "$backup_dir/docker-compose.yml" 2>/dev/null
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
    
    # Check for credentials file (primary requirement)
    if [[ ! -f "$CREDENTIALS_FILE" ]]; then
        return 1
    fi
    
    # Check for docker-compose.yml or create it if missing
    if [[ ! -f "$WORKDIR/docker-compose.yml" ]]; then
        # Try to create basic docker-compose.yml
        mkdir -p "$WORKDIR"
        if command -v download_nexus_files >/dev/null 2>&1; then
            download_nexus_files >/dev/null 2>&1
        fi
        
        # If still no docker-compose.yml, return false
        if [[ ! -f "$WORKDIR/docker-compose.yml" ]]; then
            return 1
        fi
    fi
    
    return 0
}

# Get available ports starting from 10000 with bounds validation
get_available_ports() {
    local count=${1:-1}
    local start_port=${2:-10000}
    
    # Validate input parameters
    if ! [[ "$count" =~ ^[0-9]+$ ]] || [[ "$count" -lt 1 ]] || [[ "$count" -gt 100 ]]; then
        echo "Error: Invalid count parameter. Must be 1-100" >&2
        return 1
    fi
    
    if ! [[ "$start_port" =~ ^[0-9]+$ ]] || [[ "$start_port" -lt 1024 ]] || [[ "$start_port" -gt 65000 ]]; then
        echo "Error: Invalid start_port parameter. Must be 1024-65000" >&2
        return 1
    fi
    
    local ports=()
    local port=$start_port
    local max_attempts=2000  # Prevent infinite loops
    local attempts=0
    
    while [[ ${#ports[@]} -lt $count ]] && [[ $attempts -lt $max_attempts ]]; do
        # Validate array bounds before accessing
        if [[ ${#ports[@]} -ge 100 ]]; then
            echo "Error: Maximum ports limit reached" >&2
            break
        fi
        
        if ! netstat -tuln 2>/dev/null | grep -q ":$port " && ! ss -tuln 2>/dev/null | grep -q ":$port "; then
            ports+=("$port")
        fi
        ((port++))
        ((attempts++))
        
        # Prevent searching beyond reasonable range
        if [[ $port -gt 65535 ]]; then
            echo "Error: Reached maximum port number" >&2
            break
        fi
    done
    
    if [[ ${#ports[@]} -lt $count ]]; then
        echo "Error: Could not find $count available ports (found ${#ports[@]})" >&2
        return 1
    fi
    
    # Safely output array elements
    printf '%s\n' "${ports[@]}"
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

# Enhanced cleanup temporary files with proper error handling
cleanup_temp() {
    local cleanup_errors=0
    
    # Clean up temp directory safely
    if [[ -n "${TEMP_DIR:-}" ]] && [[ -d "$TEMP_DIR" ]]; then
        if ! rm -rf "$TEMP_DIR" 2>/dev/null; then
            echo "Warning: Could not clean up temp directory: $TEMP_DIR" >&2
            ((cleanup_errors++))
        fi
    fi
    
    # Clean up any stray temp files
    find /tmp -maxdepth 1 -name "nexus-*" -type d -user "$(id -u)" -mtime +1 2>/dev/null | while IFS= read -r old_temp; do
        if [[ -d "$old_temp" ]]; then
            rm -rf "$old_temp" 2>/dev/null || ((cleanup_errors++))
        fi
    done
    
    # Clean up process-specific temp files
    local process_temp="/tmp/nexus-$$"
    if [[ -d "$process_temp" ]]; then
        rm -rf "$process_temp" 2>/dev/null || ((cleanup_errors++))
    fi
    
    return $cleanup_errors
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
    printf "%*s" "$filled" "" | tr ' ' '='
    printf "%*s" "$empty" "" | tr ' ' '-'
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
    
    # Update proxy settings if setup.sh functions are available
    if command -v update_proxy_settings >/dev/null 2>&1; then
        update_proxy_settings
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
    
    # Enhanced proxy list detection with multiple sources
    local proxy_sources=(
        "$backup_proxy"                      # User backup
        "$current_proxy"                     # Current script directory
        "/root/proxy_list.txt"               # Root directory (common location)
        "$HOME/.nexus/proxy_list.txt"        # Legacy nexus directory
        "$HOME/workdir/proxy_list.txt"      # Root nexus-v3 directory
        "/root/nexus-multi-docker/proxy_list.txt"  # Other nexus installations
    )
    
    local found_proxy=""
    for proxy_path in "${proxy_sources[@]}"; do
        if [[ -f "$proxy_path" ]]; then
            # Check if file has valid proxy entries (not just comments)
            local valid_proxies
            valid_proxies=$(grep -v '^[[:space:]]*#' "$proxy_path" | grep -v '^[[:space:]]*$' | wc -l 2>/dev/null)
            if [[ "$valid_proxies" -gt 0 ]]; then
                found_proxy="$proxy_path"
                break
            fi
        fi
    done
    
    # Copy proxy list with proper header if found
    if [[ -n "$found_proxy" ]]; then
        # Try to backup first
        mkdir -p "$HOME/nexus-backup" 2>/dev/null
        if [[ "$found_proxy" != "$backup_proxy" ]]; then
            cp "$found_proxy" "$backup_proxy" 2>/dev/null
        fi
        
        # Copy to working directory with auto-import header
        {
            echo "# Auto-imported from $found_proxy - $(date)"
            echo "# Original file: $found_proxy (preserved)"
            cat "$found_proxy"
        } > "$WORKDIR/proxy_list.txt" 2>/dev/null
        
        local proxy_count
        proxy_count=$(grep -v '^[[:space:]]*#' "$found_proxy" | grep -v '^[[:space:]]*$' | wc -l 2>/dev/null)
        log_activity "Auto-imported proxy list from $found_proxy ($proxy_count proxies)"
    fi
}

# Enhanced system information functions
get_enhanced_system_info() {
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│                    System Information                   │${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────┘${NC}"
    
    # OS Information
    if [[ -f /etc/os-release ]]; then
        # Parse /etc/os-release safely without sourcing to avoid readonly variable conflicts
        local os_pretty_name
        os_pretty_name=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "Unknown")
        echo -e "${CYAN}OS:${NC} $os_pretty_name"
    fi
    
    # Kernel version
    echo -e "${CYAN}Kernel:${NC} $(uname -r)"
    
    # Architecture
    echo -e "${CYAN}Architecture:${NC} $(uname -m)"
    
    # Uptime
    local uptime_info
    if command -v uptime >/dev/null; then
        uptime_info=$(uptime -p 2>/dev/null || uptime | awk '{print $3,$4}' | sed 's/,//')
        echo -e "${CYAN}Uptime:${NC} $uptime_info"
    fi
    
    # CPU Info
    if [[ -f /proc/cpuinfo ]]; then
        local cpu_model
        cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^ *//')
        echo -e "${CYAN}CPU:${NC} $cpu_model"
        
        local cpu_cores
        cpu_cores=$(nproc 2>/dev/null || echo "Unknown")
        echo -e "${CYAN}CPU Cores:${NC} $cpu_cores"
    fi
    
    # Memory Info
    if [[ -f /proc/meminfo ]]; then
        local mem_total mem_free mem_used
        mem_total=$(awk '/MemTotal/ {printf "%.1f", $2/1024/1024}' /proc/meminfo)
        mem_free=$(awk '/MemAvailable/ {printf "%.1f", $2/1024/1024}' /proc/meminfo)
        mem_used=$(echo "$mem_total $mem_free" | awk '{printf "%.1f", $1-$2}')
        echo -e "${CYAN}Memory:${NC} ${mem_used}GB used / ${mem_total}GB total"
    fi
    
    # Disk Info
    local disk_info
    disk_info=$(df -h / 2>/dev/null | tail -1 | awk '{print $3" used / "$2" total ("$5" used)"}')
    echo -e "${CYAN}Disk (/):${NC} $disk_info"
    
    # Network interfaces
    local interfaces
    interfaces=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -v lo | head -3 | tr '\n' ' ')
    if [[ -n "$interfaces" ]]; then
        echo -e "${CYAN}Network:${NC} $interfaces"
    fi
}

get_enhanced_docker_info() {
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│                   Docker Information                    │${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────┘${NC}"
    
    if ! command -v docker >/dev/null; then
        echo -e "${RED}❌ Docker not installed${NC}"
        return 0
    fi
    
    # Docker version
    local docker_version
    docker_version=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')
    echo -e "${CYAN}Version:${NC} $docker_version"
    
    # Docker daemon status
    if docker info >/dev/null 2>&1; then
        echo -e "${CYAN}Status:${NC} ${GREEN}✅ Running${NC}"
        
        # Container counts
        local running_containers total_containers
        running_containers=$(docker ps -q 2>/dev/null | wc -l)
        total_containers=$(docker ps -aq 2>/dev/null | wc -l)
        echo -e "${CYAN}Containers:${NC} $running_containers running / $total_containers total"
        
        # Image count
        local image_count
        image_count=$(docker images -q 2>/dev/null | wc -l)
        echo -e "${CYAN}Images:${NC} $image_count total"
        
        # Nexus containers specifically
        local nexus_containers
        nexus_containers=$(docker ps --filter "label=nexus.network" --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | tail -n +2)
        if [[ -n "$nexus_containers" ]]; then
            echo -e "${CYAN}Nexus Containers:${NC}"
            echo "$nexus_containers" | while read -r line; do
                echo -e "  ${YELLOW}•${NC} $line"
            done
        else
            echo -e "${CYAN}Nexus Containers:${NC} ${YELLOW}None running${NC}"
        fi
    else
        echo -e "${CYAN}Status:${NC} ${RED}❌ Not running${NC}"
    fi
}

get_enhanced_nexus_info() {
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│                    Nexus Information                    │${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────┘${NC}"
    
    # Credentials status
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        echo -e "${CYAN}Credentials:${NC} ${GREEN}✅ Found${NC}"
        
        # Parse credentials with jq if available
        if command -v jq >/dev/null; then
            local node_count wallet_address proxy_count
            node_count=$(jq -r '.node_id | length' "$CREDENTIALS_FILE" 2>/dev/null || echo "0")
            wallet_address=$(jq -r '.wallet_address // "Not set"' "$CREDENTIALS_FILE" 2>/dev/null)
            proxy_count=$(jq -r '.proxy_settings.proxy_count // 0' "$CREDENTIALS_FILE" 2>/dev/null)
            
            echo -e "${CYAN}Wallet:${NC} $wallet_address"
            echo -e "${CYAN}Nodes:${NC} $node_count configured"
            echo -e "${CYAN}Proxies:${NC} $proxy_count available"
            
            # Show active node IDs
            if [[ "$node_count" -gt 0 ]]; then
                echo -e "${CYAN}Node IDs:${NC}"
                jq -r '.node_id[]' "$CREDENTIALS_FILE" 2>/dev/null | head -5 | while read -r node_id; do
                    echo -e "  ${YELLOW}•${NC} $node_id"
                done
                if [[ "$node_count" -gt 5 ]]; then
                    echo -e "  ${YELLOW}•${NC} ... and $((node_count - 5)) more"
                fi
            fi
        else
            echo -e "${YELLOW}⚠️  jq not available for detailed parsing${NC}"
        fi
        
        # File modification time
        local mod_time
        mod_time=$(stat -c %y "$CREDENTIALS_FILE" 2>/dev/null | cut -d. -f1)
        echo -e "${CYAN}Last Updated:${NC} $mod_time"
    else
        echo -e "${CYAN}Credentials:${NC} ${RED}❌ Not found${NC}"
    fi
    
    # Configuration directory
    if [[ -d "$WORKDIR" ]]; then
        local config_size
        config_size=$(du -sh "$WORKDIR" 2>/dev/null | cut -f1)
        echo -e "${CYAN}Config Dir:${NC} $WORKDIR ($config_size)"
    fi
    
    # Logs
    if [[ -f "$LOG_FILE" ]]; then
        local log_size log_lines
        log_size=$(du -sh "$LOG_FILE" 2>/dev/null | cut -f1)
        log_lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo "0")
        echo -e "${CYAN}Activity Log:${NC} $log_lines lines ($log_size)"
    fi
    
    # Proxy list
    local proxy_file="$WORKDIR/proxy_list.txt"
    if [[ -f "$proxy_file" ]]; then
        local proxy_lines
        proxy_lines=$(grep -v '^[[:space:]]*#' "$proxy_file" | grep -v '^[[:space:]]*$' | wc -l)
        echo -e "${CYAN}Proxy List:${NC} $proxy_lines entries"
    fi
}

# Export functions for use by other modules
export -f now_jakarta clear_screen draw_status draw_progress_bar sanitize_input log_activity
export -f check_root_user setup_non_root_user create_new_user_flow use_existing_user_flow setup_and_switch_to_user
export -f create_and_switch_user switch_to_existing_user migrate_script_to_user
export -f backup_proxy_list restore_proxy_list backup_files_silently
export -f is_nexus_installed get_available_ports
export -f get_status_indicator detect_terminal_environment
export -f validate_wallet_address show_progress setup_directory_structure
export -f get_enhanced_system_info get_enhanced_docker_info get_enhanced_nexus_info
