#!/usr/bin/env bash

# ╔═══════════════════════════════════════════════════════════════╗
# ║                NEXUS CLI DOCKER MANAGER                      ║
# ║                                                               ║
# ║  ██████╗  ██████╗ ██╗  ██╗██╗  ██╗ █████╗ ███╗   ██╗███████╗ ║
# ║  ██╔══██╗██╔═══██╗██║ ██╔╝██║  ██║██╔══██╗████╗  ██║╚══███╔╝ ║
# ║  ██████╔╝██║   ██║█████╔╝ ███████║███████║██╔██╗ ██║  ███╔╝  ║
# ║  ██╔══██╗██║   ██║██╔═██╗ ██╔══██║██╔══██║██║╚██╗██║ ███╔╝   ║
# ║  ██║  ██║╚██████╔╝██║  ██╗██║  ██║██║  ██║██║ ╚████║███████╗ ║
# ║  ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝ ║
# ║                                                               ║
# ║          🚀 Nexus v3.0.0 • by Rokhanz | TUI Dashboard 🇮🇩     ║
# ║                                                               ║
# ║              Install | Uninstall | Manage | Monitor          ║
# ╚═══════════════════════════════════════════════════════════════╝

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════════
#                                CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

# Script metadata
readonly GITHUB_REPO="https://github.com/rokhanz/nexus-v3"
readonly GITHUB_RAW="https://raw.githubusercontent.com/rokhanz/nexus-v3/main"

# System paths - repository structure
readonly WORKDIR="$HOME/nexus-v3"
readonly ENV_FILE="$WORKDIR/.env"
readonly TEMP_DIR="/tmp/nexus-setup-$$"

# Nexus Network Configuration (Testnet 3)
readonly NEXUS_CONFIG_DIR="$HOME/.nexus"
readonly CREDENTIALS_FILE="$HOME/.nexus/credentials.json"
readonly CHAIN_ID="3940"
readonly RPC_HTTP="https://testnet3.rpc.nexus.xyz"
readonly RPC_WEBSOCKET="wss://testnet3.rpc.nexus.xyz"
readonly EXPLORER_URL="https://testnet3.explorer.nexus.xyz"
readonly FAUCET_URL="https://faucets.alchemy.com/faucets/nexus-testnet"

# Dynamic activity tracking
CURRENT_ACTIVITY="idle"
ACTIVITY_TITLE="📋 System Logs"

# Color definitions for TUI
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly MAGENTA='\033[0;35m'
readonly GRAY='\033[0;37m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# TUI Box drawing characters
readonly BOX_H="═"
readonly BOX_V="║"
readonly BOX_TL="╔"
readonly BOX_TR="╗"
readonly BOX_BL="╚"
readonly BOX_BR="╝"

# Global variables for dynamic logs panel
CURRENT_ACTIVITY="idle"
ACTIVITY_TITLE="📋 System Logs"

# ═══════════════════════════════════════════════════════════════════════════════
#                                UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Get current Jakarta time
now_jakarta() {
    date "+%Y-%m-%d %H:%M:%S WIB"
}

# Get terminal dimensions
get_terminal_size() {
    if command -v tput >/dev/null 2>&1; then
        TERM_HEIGHT=$(tput lines)
        TERM_WIDTH=$(tput cols)
    else
        TERM_HEIGHT=24
        TERM_WIDTH=80
    fi
}

# Clear screen and position cursor
clear_screen() {
    printf '\033[2J\033[H'
}

# Position cursor
move_cursor() {
    local row=$1
    local col=$2
    printf '\033[%d;%dH' "$row" "$col"
}

# Draw horizontal line
draw_hline() {
    local length=$1
    local char=${2:-$BOX_H}
    printf "%0.s$char" $(seq 1 "$length")
}

# Draw box with colored border
draw_box() {
    local start_row=$1
    local start_col=$2
    local height=$3
    local width=$4
    local title=${5:-""}
    local color=${6:-$WHITE}  # Default white color for border
    
    # Top line with color
    move_cursor "$start_row" "$start_col"
    printf "${color}${BOX_TL}"
    draw_hline $((width - 2)) "$BOX_H"
    printf "${BOX_TR}${NC}"
    
    # Title if provided
    if [[ -n "$title" ]]; then
        local title_pos=$((start_col + 2))
        move_cursor "$start_row" "$title_pos"
        printf "${color} %s ${NC}" "$title"
    fi
    
    # Side lines with color
    for ((i = 1; i < height - 1; i++)); do
        move_cursor $((start_row + i)) "$start_col"
        printf "${color}${BOX_V}${NC}"
        move_cursor $((start_row + i)) $((start_col + width - 1))
        printf "${color}${BOX_V}${NC}"
    done
    
    # Bottom line with color
    move_cursor $((start_row + height - 1)) "$start_col"
    printf "${color}${BOX_BL}"
    draw_hline $((width - 2)) "$BOX_H"
    printf "${BOX_BR}${NC}"
}

# Input sanitization
sanitize_input() {
    local input="$1"
    echo "$input" | sed 's/[;&|$`<>]//g' | tr -d '\n' | head -c 100
}

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Log activity to file and update TUI
log_activity() {
    local message="$1"
    local log_file="$WORKDIR/logs/activity.log"
    
    # Create logs directory if not exists
    mkdir -p "$WORKDIR/logs" 2>/dev/null
    
    # Add timestamp and log message
    echo "$(now_jakarta) - $message" >> "$log_file"
    
    # Keep only last 50 lines to prevent log file from growing too large
    tail -50 "$log_file" > "$log_file.tmp" 2>/dev/null && mv "$log_file.tmp" "$log_file"
}

# ═══════════════════════════════════════════════════════════════════════════════
#                                SYSTEM INFO FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Get VPS specifications
get_vps_info() {
    local cpu_cores
    local cpu_model
    local total_ram
    local used_ram
    local disk_info
    local os_info
    local uptime_info
    
    cpu_cores=$(nproc)
    cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs || echo "Unknown")
    total_ram=$(free -h | grep "Mem:" | awk '{print $2}')
    used_ram=$(free -h | grep "Mem:" | awk '{print $3}')
    disk_info=$(df -h / | tail -1 | awk '{print $2 " used " $3 " (" $5 ")"}')
    os_info=$(lsb_release -d 2>/dev/null | cut -f2 || echo "$(uname -s) $(uname -r)")
    uptime_info=$(uptime -p 2>/dev/null || uptime | cut -d, -f1)
    
    echo "CPU: $cpu_cores cores"
    echo "Model: $cpu_model"
    echo "RAM: $used_ram / $total_ram"
    echo "Disk: $disk_info"
    echo "OS: $os_info"
    echo "Uptime: $uptime_info"
}

# Get wallet information
get_wallet_info() {
    # Check if credentials exist
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        # Extract info from credentials.json if jq is available
        if command -v jq >/dev/null 2>&1; then
            local user_id node_id wallet_address
            user_id=$(jq -r '.user_id // "Not available"' "$CREDENTIALS_FILE" 2>/dev/null)
            node_id=$(jq -r '.node_id // "Not available"' "$CREDENTIALS_FILE" 2>/dev/null)
            wallet_address=$(jq -r '.wallet_address // "Not available"' "$CREDENTIALS_FILE" 2>/dev/null)
            
            echo "User ID: ${user_id:0:12}..."
            echo "Node ID: ${node_id:0:12}..."
            echo "Address: ${wallet_address:0:20}..."
            echo "Network: Testnet 3 (Chain $CHAIN_ID)"
        else
            echo "Credentials: ✓ Found"
            echo "Config: ~/.nexus/credentials.json"
            echo "Network: Testnet 3 (Chain $CHAIN_ID)"
            echo "Install 'jq' for details"
        fi
    elif [[ -f "$ENV_FILE" ]]; then
        # Fallback to legacy env file
        # shellcheck disable=SC1090
        source "$ENV_FILE" 2>/dev/null || true
        echo "Address: ${WALLET_ADDRESS:-"Not configured"}"
        echo "Balance: ${WALLET_BALANCE:-"0"} NEX"
        echo "Status: ${WALLET_STATUS:-"Inactive"}"
        echo "Docker: $(command -v docker >/dev/null 2>&1 && echo "✓" || echo "✗") | Autorestart: ${AUTO_RESTART:-"Disabled"}"
    else
        echo "Credentials: Not found"
        echo "Config: ~/.nexus/credentials.json"
        echo "Status: Not registered"
        echo "Network: Testnet 3 (Chain $CHAIN_ID)"
    fi
}

# Get bot dashboard info
get_bot_info() {
    local node_count=0
    local running_nodes=0
    local stopped_nodes=0
    
    if command -v docker >/dev/null 2>&1; then
        node_count=$(docker ps -a --filter "name=nexus-node-" 2>/dev/null | wc -l)
        running_nodes=$(docker ps --filter "name=nexus-node-" 2>/dev/null | wc -l)
        ((node_count > 0)) && ((node_count--)) # Remove header line
        ((running_nodes > 0)) && ((running_nodes--)) # Remove header line
        stopped_nodes=$((node_count - running_nodes))
    fi
    
    # First line: summary stats
    echo "Total Node: $node_count | Running: $running_nodes | Stop: $stopped_nodes"
    
    # Show individual nodes in compact 2-column layout
    if [[ $node_count -gt 0 ]]; then
        local node_list
        node_list=$(docker ps -a --filter "name=nexus-node-" --format "{{.Names}}" 2>/dev/null | head -6)
        local node_array=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && node_array+=("$line")
        done <<< "$node_list"
        
        # Display nodes in 2-column format (node 1 | node 4, node 2 | node 5, etc)
        for ((i=0; i<${#node_array[@]}; i+=2)); do
            local left_node="${node_array[i]:-}"
            local right_node="${node_array[i+1]:-}"
            local left_id="${left_node#nexus-node-}"
            local right_id="${right_node#nexus-node-}"
            
            if [[ -n "$right_node" ]]; then
                echo "Node $((i+1)): ${left_id:0:8} | Node $((i+2)): ${right_id:0:8}"
            else
                echo "Node $((i+1)): ${left_id:0:8}"
            fi
        done
    fi
}

# Get system logs (setup, installation, activity logs)
get_system_logs() {
    local main_log="$WORKDIR/logs/nexus.log"
    local install_log="$WORKDIR/logs/install.log"
    local activity_log="$WORKDIR/logs/activity.log"
    
    # Create logs directory if not exists
    [[ ! -d "$WORKDIR/logs" ]] && mkdir -p "$WORKDIR/logs" 2>/dev/null
    
    # Check for existing log files and display recent entries
    if [[ -f "$activity_log" ]]; then
        echo "Recent Activity:"
        tail -4 "$activity_log" 2>/dev/null || echo "No recent activity"
    elif [[ -f "$install_log" ]]; then
        echo "Installation Log:"
        tail -4 "$install_log" 2>/dev/null || echo "No installation logs"
    elif [[ -f "$main_log" ]]; then
        echo "System Log:"
        tail -4 "$main_log" 2>/dev/null || echo "No system logs"
    else
        echo "System Status:"
        echo "$(now_jakarta) - TUI Dashboard active"
        echo "$(now_jakarta) - Monitoring system activity"
        echo "$(now_jakarta) - Ready for operations"
        echo "Logs: $WORKDIR/logs/"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#                                TUI DASHBOARD
# ═══════════════════════════════════════════════════════════════════════════════

# Display real-time header with running time
display_header() {
    local header
    header="🚀 Nexus v3.0.0 • by Rokhanz | $(now_jakarta) 🇮🇩"
    local header_pos=$(((TERM_WIDTH - ${#header}) / 2))
    [[ $header_pos -lt 0 ]] && header_pos=0
    
    # Clear header line and redraw
    move_cursor 1 1
    printf "%*s" "$TERM_WIDTH" " "  # Clear entire line
    move_cursor 1 "$header_pos"
    printf "${BOLD}${CYAN}%s${NC}" "$header"
}

# Draw main dashboard with new layout
draw_dashboard() {
    clear_screen
    get_terminal_size
    
    # Display header at top
    display_header
    
    # Layout calculations for clean grid
    local top_panel_height=8
    local top_panel_start=3
    
    # Three equal columns for top panels (VPS | Wallet | Bot) - Compact layout
    local panel_width=$((TERM_WIDTH / 3 - 1))
    local vps_x=1
    local wallet_x=$((panel_width + 1))
    local bot_x=$((panel_width * 2 + 1))
    
    # Bottom section: Menu (left) + System Logs (right) - Compact layout
    local bottom_start_row=$((top_panel_start + top_panel_height + 1))
    local menu_width=22  # Compact menu width
    local menu_height=$((TERM_HEIGHT - bottom_start_row - 1))
    local logs_x=$((menu_width + 2))
    local logs_width=$((TERM_WIDTH - menu_width - 3))
    local logs_height=$menu_height
    
    # Draw top row: 3 panels side by side with colored borders
    # VPS Info Panel (left) - Green border
    draw_box "$top_panel_start" "$vps_x" "$top_panel_height" "$panel_width" "🖥️ VPS Info" "$GREEN"
    local vps_row=$((top_panel_start + 2))
    while IFS= read -r line; do
        [[ $vps_row -ge $((top_panel_start + top_panel_height - 1)) ]] && break
        move_cursor "$vps_row" $((vps_x + 1))
        printf "${GREEN}%s${NC}" "${line:0:$((panel_width-2))}"
        ((vps_row++))
    done <<< "$(get_vps_info)"
    
    # Wallet Info Panel (center) - Magenta border
    draw_box "$top_panel_start" "$wallet_x" "$top_panel_height" "$panel_width" "💳 Wallet Info" "$MAGENTA"
    local wallet_row=$((top_panel_start + 2))
    while IFS= read -r line; do
        [[ $wallet_row -ge $((top_panel_start + top_panel_height - 1)) ]] && break
        move_cursor "$wallet_row" $((wallet_x + 1))
        printf "${MAGENTA}%s${NC}" "${line:0:$((panel_width-2))}"
        ((wallet_row++))
    done <<< "$(get_wallet_info)"
    
    # Bot Dashboard Panel (right) - Blue border
    draw_box "$top_panel_start" "$bot_x" "$top_panel_height" "$panel_width" "🤖 Bot Dashboard" "$BLUE"
    local bot_row=$((top_panel_start + 2))
    while IFS= read -r line; do
        [[ $bot_row -ge $((top_panel_start + top_panel_height - 1)) ]] && break
        move_cursor "$bot_row" $((bot_x + 1))
        printf "${BLUE}%s${NC}" "${line:0:$((panel_width-2))}"
        ((bot_row++))
    done <<< "$(get_bot_info)"
    
    # Draw bottom row: Menu (left) + System Logs (right) with colored borders
    draw_menu_panel "$bottom_start_row" "$vps_x" "$menu_height" "$menu_width"
    draw_logs_panel "$bottom_start_row" "$logs_x" "$logs_height" "$logs_width"
}

# Draw menu panel (bottom left) with input area
draw_menu_panel() {
    local start_row=$1
    local start_col=$2
    local height=$3
    local width=$4
    
    # Yellow border for menu panel
    draw_box "$start_row" "$start_col" "$height" "$width" "⚙️ Menu" "$YELLOW"
    
    # Menu items inside the box with compact layout
    local menu_row=$((start_row + 2))
    local menu_col=$((start_col + 1))
    
    move_cursor "$menu_row" "$menu_col"
    printf "${YELLOW}[1]${NC} 🔧 Install"
    
    ((menu_row++))
    move_cursor "$menu_row" "$menu_col"
    printf "${YELLOW}[2]${NC} 🗑️ Uninstall"
    
    ((menu_row++))
    move_cursor "$menu_row" "$menu_col"
    printf "${YELLOW}[3]${NC} 🚀 Manage"
    
    ((menu_row++))
    move_cursor "$menu_row" "$menu_col"
    printf "${YELLOW}[4]${NC} 💳 Wallet"
    
    ((menu_row++))
    move_cursor "$menu_row" "$menu_col"
    printf "${YELLOW}[5]${NC} 📋 Logs"
    
    ((menu_row++))
    move_cursor "$menu_row" "$menu_col"
    printf "${YELLOW}[0]${NC} ❌ Exit"
    
    # Add input prompt at the bottom
    ((menu_row += 2))
    move_cursor "$menu_row" "$menu_col"
    printf "${BOLD}${WHITE}Choice: ${NC}"
}

# Draw system logs panel (bottom right) - Dynamic title based on activity
draw_logs_panel() {
    local start_row=$1
    local start_col=$2
    local height=$3
    local width=$4
    
    # Use dynamic title based on current activity with Cyan border
    draw_box "$start_row" "$start_col" "$height" "$width" "$ACTIVITY_TITLE" "$CYAN"
    
    local log_row=$((start_row + 2))
    local log_col=$((start_col + 1))
    local max_row=$((start_row + height - 2))
    
    # Show different content based on current activity
    case "$CURRENT_ACTIVITY" in
        "install")
            show_install_logs "$log_row" "$log_col" "$max_row" "$width"
            ;;
        "uninstall")
            show_uninstall_logs "$log_row" "$log_col" "$max_row" "$width"
            ;;
        "manage")
            show_manage_logs "$log_row" "$log_col" "$max_row" "$width"
            ;;
        "wallet")
            show_wallet_logs "$log_row" "$log_col" "$max_row" "$width"
            ;;
        *)
            # Default system logs
            while IFS= read -r line && [[ $log_row -lt $max_row ]]; do
                move_cursor "$log_row" "$log_col"
                printf "${GRAY}%s${NC}" "${line:0:$((width-2))}"
                ((log_row++))
            done <<< "$(get_system_logs)"
            ;;
    esac
}

# Show activity-specific logs
show_install_logs() {
    local log_row=$1
    local log_col=$2
    local max_row=$3
    local width=$4
    
    move_cursor "$log_row" "$log_col"
    printf "${BLUE}🔧 Installation Process${NC}"
    ((log_row++))
    
    move_cursor "$log_row" "$log_col"
    printf "${GRAY}$(now_jakarta)${NC}"
    ((log_row++))
    
    move_cursor "$log_row" "$log_col"
    printf "${YELLOW}Downloading install.sh...${NC}"
    ((log_row++))
    
    move_cursor "$log_row" "$log_col"
    printf "${GREEN}Ready to install Nexus${NC}"
    ((log_row++))
}

show_uninstall_logs() {
    local log_row=$1
    local log_col=$2
    local max_row=$3
    local width=$4
    
    move_cursor "$log_row" "$log_col"
    printf "${RED}🗑️ Uninstall Process${NC}"
    ((log_row++))
    
    move_cursor "$log_row" "$log_col"
    printf "${GRAY}$(now_jakarta)${NC}"
    ((log_row++))
    
    move_cursor "$log_row" "$log_col"
    printf "${YELLOW}Downloading uninstall.sh...${NC}"
    ((log_row++))
    
    move_cursor "$log_row" "$log_col"
    printf "${RED}Ready to remove Nexus${NC}"
    ((log_row++))
}

show_manage_logs() {
    local log_row=$1
    local log_col=$2
    local max_row=$3
    local width=$4
    
    move_cursor "$log_row" "$log_col"
    printf "${BLUE}🚀 Node Management${NC}"
    ((log_row++))
    
    move_cursor "$log_row" "$log_col"
    printf "${GRAY}$(now_jakarta)${NC}"
    ((log_row++))
    
    move_cursor "$log_row" "$log_col"
    printf "${YELLOW}Downloading manager.sh...${NC}"
    ((log_row++))
    
    move_cursor "$log_row" "$log_col"
    printf "${BLUE}Managing Docker nodes${NC}"
    ((log_row++))
}

show_wallet_logs() {
    local log_row=$1
    local log_col=$2
    local max_row=$3
    local width=$4
    
    move_cursor "$log_row" "$log_col"
    printf "${MAGENTA}💳 Wallet Configuration${NC}"
    ((log_row++))
    
    move_cursor "$log_row" "$log_col"
    printf "${GRAY}$(now_jakarta)${NC}"
    ((log_row++))
    
    move_cursor "$log_row" "$log_col"
    printf "${YELLOW}Wallet setup in progress...${NC}"
    ((log_row++))
    
    move_cursor "$log_row" "$log_col"
    printf "${MAGENTA}Coming soon feature${NC}"
    ((log_row++))
}

# Set activity and update logs panel title
set_activity() {
    local activity="$1"
    CURRENT_ACTIVITY="$activity"
    
    case "$activity" in
        "install")
            ACTIVITY_TITLE="🔧 Install Process"
            ;;
        "uninstall")
            ACTIVITY_TITLE="🗑️ Uninstall Process"
            ;;
        "manage")
            ACTIVITY_TITLE="🚀 Node Management"
            ;;
        "wallet")
            ACTIVITY_TITLE="💳 Wallet Config"
            ;;
        *)
            ACTIVITY_TITLE="📋 System Logs"
            CURRENT_ACTIVITY="idle"
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
#                              MODULAR FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Update logs panel in real-time without full redraw
update_logs_panel() {
    local message="$1"
    
    # Calculate logs panel position based on compact layout
    local top_panel_height=8
    local bottom_start_row=$((3 + top_panel_height + 1))
    local menu_width=22
    local logs_x=$((menu_width + 2))
    
    # Clear first few lines of logs area
    for ((i = 2; i <= 4; i++)); do
        move_cursor $((bottom_start_row + i)) $((logs_x + 1))
        printf "%*s" $((TERM_WIDTH - logs_x - 2)) " "  # Clear line
    done
    
    # Show current message
    move_cursor $((bottom_start_row + 2)) $((logs_x + 1))
    printf "${YELLOW}%s${NC}" "$message"
    
    # Show timestamp
    move_cursor $((bottom_start_row + 3)) $((logs_x + 1))
    printf "${GRAY}$(now_jakarta)${NC}"
    
    # Show system status
    move_cursor $((bottom_start_row + 4)) $((logs_x + 1))
    printf "${BLUE}Status: Active${NC}"
}

# Download and execute module with real-time logging
execute_module() {
    local module_name="$1"
    local module_url="$GITHUB_RAW/$module_name"
    local module_path="/tmp/nexus-$module_name"
    
    log_activity "Starting: $module_name download"
    
    # Show download progress in logs panel
    update_logs_panel "Downloading $module_name..."
    sleep 1
    
    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL "$module_url" -o "$module_path" 2>/dev/null; then
            log_activity "Downloaded: $module_name successfully"
            update_logs_panel "✅ Download complete: $module_name"
        else
            log_activity "Error: Failed to download $module_name"
            update_logs_panel "❌ Download failed: $module_name"
            sleep 2
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q -O "$module_path" "$module_url" 2>/dev/null; then
            log_activity "Downloaded: $module_name successfully"
            update_logs_panel "✅ Download complete: $module_name"
        else
            log_activity "Error: Failed to download $module_name"
            update_logs_panel "❌ Download failed: $module_name"
            sleep 2
            return 1
        fi
    else
        log_activity "Error: No download tool available (curl/wget)"
        update_logs_panel "❌ No download tool available"
        sleep 2
        return 1
    fi
    
    if [[ -f "$module_path" ]]; then
        chmod +x "$module_path"
        log_activity "Executing: $module_name"
        update_logs_panel "🔄 Executing: $module_name..."
        
        # Execute module and capture output
        if bash "$module_path"; then
            log_activity "Completed: $module_name successfully"
            update_logs_panel "✅ Completed: $module_name"
        else
            log_activity "Error: $module_name execution failed"
            update_logs_panel "❌ Failed: $module_name execution"
        fi
        
        rm -f "$module_path" 2>/dev/null || true
        sleep 2
    else
        log_activity "Error: Module file not found after download"
        update_logs_panel "❌ Module file not found"
        sleep 2
        return 1
    fi
}

# Show detailed logs without leaving TUI
show_detailed_logs() {
    log_activity "Displaying detailed system logs"
    
    # Calculate logs panel position for detailed view - compact layout
    local top_panel_height=8
    local bottom_start_row=$((3 + top_panel_height + 1))
    local menu_width=22
    local logs_x=$((menu_width + 2))
    local logs_width=$((TERM_WIDTH - menu_width - 3))
    local log_height=$((TERM_HEIGHT - bottom_start_row - 1))
    
    # Draw detailed logs display box (overwrites system logs panel)
    draw_box "$bottom_start_row" "$logs_x" "$log_height" "$logs_width" "Detailed Logs"
    
    local log_row=$((bottom_start_row + 2))
    local max_log_row=$((bottom_start_row + log_height - 3))
    
    # Display different log files
    if [[ -d "$WORKDIR/logs" ]]; then
        move_cursor "$log_row" $((logs_x + 1))
        printf "${BOLD}${CYAN}Available Log Files:${NC}"
        ((log_row += 2))
        
        for log_file in "$WORKDIR/logs"/*.log; do
            [[ ! -f "$log_file" ]] && continue
            [[ $log_row -gt $max_log_row ]] && break
            
            local filename
            filename=$(basename "$log_file")
            move_cursor "$log_row" $((logs_x + 1))
            printf "${YELLOW}● %s${NC}" "$filename"
            ((log_row++))
            
            # Show last 2 lines of each log
            while IFS= read -r line && [[ $log_row -lt $max_log_row ]]; do
                move_cursor "$log_row" $((logs_x + 3))
                printf "${GRAY}%s${NC}" "${line:0:$((logs_width-4))}"
                ((log_row++))
            done < <(tail -2 "$log_file" 2>/dev/null)
            ((log_row++))
        done
    else
        move_cursor "$log_row" $((logs_x + 1))
        printf "${YELLOW}No logs directory found${NC}"
        ((log_row += 2))
        move_cursor "$log_row" $((logs_x + 1))
        printf "${GRAY}Install system first to generate logs${NC}"
    fi
    
    # Show navigation hint
    move_cursor $((TERM_HEIGHT - 2)) $((logs_x + 1))
    printf "${BOLD}${WHITE}Press any key to return${NC}"
    
    # Wait for user input
    read -n 1 -r
    log_activity "Returned to main dashboard"
}

# Position cursor at input area in menu
position_input_cursor() {
    local top_panel_height=8
    local bottom_start_row=$((3 + top_panel_height + 1))
    local menu_col=2  # start_col + 1 (sama dengan di draw_menu_panel)
    local input_row=$((bottom_start_row + 9))  # start_row + 2 + 6 menu items + 2 gap
    local input_col=$((menu_col + 8))  # menu_col + panjang "Choice: " (8 karakter)
    
    # Move cursor to input position
    move_cursor "$input_row" "$input_col"
}

# Show error message in logs panel
show_error_message() {
    local message="$1"
    local top_panel_height=8
    local bottom_start_row=$((3 + top_panel_height + 1))
    local menu_width=22
    local logs_x=$((menu_width + 2))
    
    # Clear first few lines of logs area
    for ((i = 2; i <= 4; i++)); do
        move_cursor $((bottom_start_row + i)) $((logs_x + 1))
        printf "%*s" $((TERM_WIDTH - logs_x - 2)) " "  # Clear line
    done
    
    # Show error message
    move_cursor $((bottom_start_row + 2)) $((logs_x + 1))
    printf "${RED}❌ %s${NC}" "$message"
    
    # Show timestamp
    move_cursor $((bottom_start_row + 3)) $((logs_x + 1))
    printf "${GRAY}$(now_jakarta)${NC}"
    
    # Show help text
    move_cursor $((bottom_start_row + 4)) $((logs_x + 1))
    printf "${YELLOW}Valid choices: 0-5${NC}"
    
    sleep 2
}

# Check if system is installed
is_nexus_installed() {
    [[ -d "$WORKDIR" ]] && [[ -f "$ENV_FILE" ]] && command -v docker >/dev/null 2>&1
}

# ═══════════════════════════════════════════════════════════════════════════════
#                              MENU HANDLERS
# ═══════════════════════════════════════════════════════════════════════════════

# Handle menu choices
handle_menu_choice() {
    local choice="$1"
    
    case "$choice" in
        1)
            log_activity "User selected: Install System"
            if is_nexus_installed; then
                log_activity "Installation skipped - System already installed"
                update_logs_panel "⚠️ System already installed"
                sleep 2
            else
                log_activity "Starting system installation..."
                set_activity "install"
                execute_module "install.sh"
            fi
            ;;
        2)
            log_activity "User selected: Uninstall System"
            if ! is_nexus_installed; then
                log_activity "Uninstall skipped - System not installed"
                update_logs_panel "⚠️ System not installed"
                sleep 2
            else
                log_activity "Starting system uninstallation..."
                set_activity "uninstall"
                execute_module "uninstall.sh"
            fi
            ;;
        3)
            log_activity "User selected: Manage Nodes"
            if ! is_nexus_installed; then
                log_activity "Node management unavailable - System not installed"
                update_logs_panel "⚠️ Install system first"
                sleep 2
            else
                log_activity "Opening node management..."
                set_activity "manage"
                execute_module "manager.sh"
            fi
            ;;
        4)
            log_activity "User selected: Wallet Configuration"
            set_activity "wallet"
            log_activity "Wallet configuration - Feature in development"
            update_logs_panel "🚧 Wallet config - Coming soon"
            sleep 2
            ;;
        5)
            log_activity "User selected: View All Logs"
            set_activity "idle"
            show_detailed_logs
            ;;
        0)
            log_activity "User exited the program"
            clear_screen
            echo -e "${GREEN}✅ Thank you for using Nexus CLI Docker Manager!${NC}"
            echo -e "${CYAN}Repository: $GITHUB_REPO${NC}"
            exit 0
            ;;
        *)
            # Invalid choice - show error and refresh logs panel
            show_error_message "Invalid choice: '$choice'"
            set_activity "idle"
            # Redraw logs panel to show system info again
            local top_panel_height=8
            local bottom_start_row=$((3 + top_panel_height + 1))
            local menu_width=22
            local logs_x=$((menu_width + 2))
            local logs_width=$((TERM_WIDTH - menu_width - 3))
            local logs_height=$((TERM_HEIGHT - bottom_start_row - 1))
            draw_logs_panel "$bottom_start_row" "$logs_x" "$logs_height" "$logs_width"
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
#                            ROOT USER HANDLING
# ═══════════════════════════════════════════════════════════════════════════════

# Install basic dependencies
install_basic_dependencies() {
    local target_user="$1"
    
    echo -e "${BLUE}ℹ️  Installing curl, wget, and basic tools...${NC}"
    
    # Update package list
    apt-get update -qq 2>/dev/null || true
    
    # Install essential tools
    apt-get install -y curl wget git unzip software-properties-common 2>/dev/null || {
        echo -e "${YELLOW}⚠️  Some packages may require manual installation${NC}"
    }
    
    # Install Docker if not present
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${BLUE}ℹ️  Installing Docker...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh 2>/dev/null && \
        sh get-docker.sh 2>/dev/null && \
        rm get-docker.sh
        
        # Add user to docker group
        usermod -aG docker "$target_user" 2>/dev/null || true
        echo -e "${GREEN}✅ Docker installed and user added to docker group${NC}"
    fi
    
    echo -e "${GREEN}✅ Basic dependencies installation completed${NC}"
    sleep 2
}

# Check if running as root and offer options
check_root_user() {
    if [[ $EUID -eq 0 ]]; then
        clear_screen
        echo -e "${RED}"
        cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                    ⚠️  ROOT USER DETECTED ⚠️                   ║
╚═══════════════════════════════════════════════════════════════╝
EOF
        echo -e "${NC}"
        echo ""
        echo -e "${YELLOW}You are running this script as root user.${NC}"
        echo -e "${WHITE}For security reasons, it's recommended to run as a regular user.${NC}"
        echo ""
        echo -e "${YELLOW}Choose an option:${NC}"
        echo ""
        echo -e "${WHITE}1.${NC} Create a new user and switch to it"
        echo -e "${WHITE}2.${NC} Continue as root (NOT RECOMMENDED)"
        echo -e "${WHITE}3.${NC} Exit and run as regular user"
        echo ""
        
        while true; do
            read -p "$(echo -e "${YELLOW}Select option [1-3]: ${NC}")" choice
            choice=$(sanitize_input "$choice")
            
            case "$choice" in
                1)
                    create_new_user
                    break
                    ;;
                2)
                    echo ""
                    echo -e "${YELLOW}⚠️  Continuing as root - Security risks acknowledged${NC}"
                    echo -e "${WHITE}Nexus will be installed in /root/nexus-v3${NC}"
                    sleep 2
                    break
                    ;;
                3)
                    echo ""
                    echo -e "${GREEN}Exiting script. Please create a regular user and run again.${NC}"
                    echo -e "${WHITE}Example: sudo useradd -m -s /bin/bash nexususer${NC}"
                    echo -e "${WHITE}Then: su - nexususer${NC}"
                    exit 0
                    ;;
                *)
                    echo -e "${RED}Invalid choice. Please select 1, 2, or 3.${NC}"
                    ;;
            esac
        done
    fi
}

# Create new user function
create_new_user() {
    echo ""
    echo -e "${BLUE}ℹ️  Creating new user for Nexus management...${NC}"
    
    read -p "$(echo -e "${YELLOW}Enter username for new user: ${NC}")" new_username
    new_username=$(sanitize_input "$new_username")
    
    if [[ -z "$new_username" ]]; then
        echo -e "${RED}❌ Username cannot be empty${NC}"
        exit 1
    fi
    
    # Check if user already exists
    if id "$new_username" &>/dev/null; then
        echo -e "${YELLOW}⚠️  User $new_username already exists${NC}"
        read -p "$(echo -e "${YELLOW}Switch to this user? [y/N]: ${NC}")" -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            switch_to_user "$new_username"
        else
            exit 0
        fi
    else
        # Create new user
        echo -e "${BLUE}ℹ️  Creating user: $new_username${NC}"
        useradd -m -s /bin/bash "$new_username"
        
        # Set password
        echo ""
        echo -e "${BLUE}ℹ️  Please set password for user: $new_username${NC}"
        passwd "$new_username"
        
        # Add to sudo group
        usermod -aG sudo "$new_username"
        echo -e "${GREEN}✅ User $new_username created and added to sudo group${NC}"
        
        switch_to_user "$new_username"
    fi
}

# Switch to user function
switch_to_user() {
    local target_user="$1"
    
    echo -e "${BLUE}ℹ️  Switching to user: $target_user${NC}"
    
    # Copy script to user home
    local user_home
    user_home=$(eval echo "~$target_user")
    local script_path="$user_home/main-setup.sh"
    
    cp "$0" "$script_path"
    chown "$target_user:$target_user" "$script_path"
    chmod +x "$script_path"
    
    echo -e "${GREEN}✅ Script copied to: $script_path${NC}"
    echo -e "${BLUE}ℹ️  Switching to user $target_user...${NC}"
    echo -e "${YELLOW}⚙️  Installing basic dependencies...${NC}"
    
    # Install basic dependencies for new user
    install_basic_dependencies "$target_user"
    
    # Switch to user and run script
    exec su - "$target_user" -c "$script_path"
}

# ═══════════════════════════════════════════════════════════════════════════════
#                                MAIN FUNCTION
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    # Trap for cleanup
    trap 'clear_screen; exit 0' INT TERM
    trap 'rm -rf "$TEMP_DIR" 2>/dev/null || true' EXIT
    
    # Root check
    check_root_user
    
    # Initialize logging
    log_activity "Nexus TUI Dashboard started"
    log_activity "System monitoring initialized"
    
    # Initial dashboard draw
    # Initial draw
    draw_dashboard
    
    # Track last update time to reduce flickering
    local last_header_update=0
    local last_full_update=0
    local current_time
    
    # Main TUI loop with optimized updates and input handling
    while true; do
        current_time=$(date +%s)
        
        # Position cursor at input area
        position_input_cursor
        
        # Read user input with proper cursor positioning
        if read -n 1 -t 1 -r choice 2>/dev/null; then
            # Clear the input area after receiving input
            local top_panel_height=8
            local bottom_start_row=$((3 + top_panel_height + 1))
            local input_row=$((bottom_start_row + 9))
            local menu_col=2
            local input_col=$((menu_col + 8))
            move_cursor "$input_row" "$input_col"
            printf "   "  # Clear any previous input display
            
            handle_menu_choice "$choice"
            # Full redraw after menu action
            draw_dashboard
            last_full_update=$current_time
            last_header_update=$current_time
        else
            # Update ONLY header every 1 second for real-time clock
            if [[ $((current_time - last_header_update)) -ge 1 ]]; then
                # Only update header time - no other redraw
                display_header
                # Reposition cursor after header update
                position_input_cursor
                last_header_update=$current_time
            fi
            
            # Full refresh every 60 seconds for system info
            if [[ $((current_time - last_full_update)) -ge 60 ]]; then
                draw_dashboard
                last_full_update=$current_time
                last_header_update=$current_time
            fi
        fi
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
#                                SCRIPT ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════════

# Ensure script is executed, not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
