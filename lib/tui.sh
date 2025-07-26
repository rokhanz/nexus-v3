#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════════
#                              ENHANCED TUI SYSTEM
# ═══════════════════════════════════════════════════════════════════════════════
# Description: Responsive Terminal User Interface with adaptive layouts
# Dependencies: common.sh
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent double-loading
[[ -n "${NEXUS_TUI_LOADED:-}" ]] && return 0
readonly NEXUS_TUI_LOADED=1

# Source common utilities
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ═══════════════════════════════════════════════════════════════════════════════
#                               TUI CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

# Terminal detection and sizing
detect_terminal_size() {
    local width height
    if command -v tput >/dev/null 2>&1; then
        width=$(tput cols 2>/dev/null || echo 80)
        height=$(tput lines 2>/dev/null || echo 24)
    else
        width=${COLUMNS:-80}
        height=${LINES:-24}
    fi
    
    export TERM_WIDTH=$width
    export TERM_HEIGHT=$height
    
    # Determine layout mode
    if [[ $width -lt 80 ]]; then
        export LAYOUT_MODE="compact"
    elif [[ $width -lt 120 ]]; then
        export LAYOUT_MODE="standard"
    else
        export LAYOUT_MODE="wide"
    fi
}

# Unicode box drawing characters with fallback
init_ui_chars() {
    local terminal_env
    terminal_env=$(detect_terminal_environment)
    
    if [[ "$terminal_env" == "ssh" ]] || [[ "${TERM:-}" == "linux" ]] || [[ "${LANG:-}" != *UTF-8* ]]; then
        # ASCII fallback for compatibility
        export UI_TL="+"     # Top-left corner
        export UI_TR="+"     # Top-right corner
        export UI_BL="+"     # Bottom-left corner
        export UI_BR="+"     # Bottom-right corner
        export UI_H="-"      # Horizontal line
        export UI_V="|"      # Vertical line
        export UI_T="+"      # Top tee
        export UI_B="+"      # Bottom tee
        export UI_L="+"      # Left tee
        export UI_R="+"      # Right tee
        export UI_X="+"      # Cross
        export UI_BLOCK="#"  # Block character
    else
        # Unicode box drawing
        export UI_TL="┌"     # Top-left corner
        export UI_TR="┐"     # Top-right corner
        export UI_BL="└"     # Bottom-left corner
        export UI_BR="┘"     # Bottom-right corner
        export UI_H="─"      # Horizontal line
        export UI_V="│"      # Vertical line
        export UI_T="┬"      # Top tee
        export UI_B="┴"      # Bottom tee
        export UI_L="├"      # Left tee
        export UI_R="┤"      # Right tee
        export UI_X="┼"      # Cross
        export UI_BLOCK="█"  # Block character
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#                               LAYOUT FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Draw horizontal line
draw_horizontal_line() {
    local width=${1:-$TERM_WIDTH}
    local char=${2:-$UI_H}
    printf "%*s\n" "$width" | tr ' ' "$char"
}

# Draw box border
draw_box() {
    local width=$1
    local height=$2
    local title=${3:-""}
    
    # Top border with title
    printf "%s" "$UI_TL"
    if [[ -n "$title" ]]; then
        local title_len=${#title}
        local padding=$(( (width - title_len - 4) / 2 ))
        printf "%*s %s %*s" "$padding" | tr ' ' "$UI_H"
        printf "%s" "$title"
        printf "%*s" "$((width - title_len - padding - 4))" | tr ' ' "$UI_H"
    else
        printf "%*s" $((width - 2)) | tr ' ' "$UI_H"
    fi
    printf "%s\n" "$UI_TR"
    
    # Side borders
    for ((i=1; i<height-1; i++)); do
        printf "%s%*s%s\n" "$UI_V" $((width - 2)) "" "$UI_V"
    done
    
    # Bottom border
    printf "%s%*s%s\n" "$UI_BL" $((width - 2)) | tr ' ' "$UI_H" "$UI_BR"
}

# Center text within width
center_text() {
    local text="$1"
    local width=${2:-$TERM_WIDTH}
    local text_len=${#text}
    
    if [[ $text_len -ge $width ]]; then
        echo "$text"
        return
    fi
    
    local padding=$(( (width - text_len) / 2 ))
    printf "%*s%s%*s\n" "$padding" "" "$text" $((width - text_len - padding)) ""
}

# Progress bar component
draw_progress_bar() {
    local current=$1
    local total=$2
    local width=${3:-40}
    local show_percentage=${4:-true}
    
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "["
    printf "%*s" "$filled" | tr ' ' "$UI_BLOCK"
    printf "%*s" "$empty" | tr ' ' '-'
    printf "]"
    
    if [[ "$show_percentage" == "true" ]]; then
        printf " %3d%%" "$percentage"
    fi
}

# Status indicator with color
draw_status() {
    local status="$1"
    local text="$2"
    local indicator
    indicator=$(get_status_indicator "$status")
    
    case "$status" in
        "active"|"running"|"success")
            printf "%s %s%s%s" "$indicator" "$GREEN" "$text" "$NC"
            ;;
        "warning"|"pending")
            printf "%s %s%s%s" "$indicator" "$YELLOW" "$text" "$NC"
            ;;
        "error"|"failed"|"stopped")
            printf "%s %s%s%s" "$indicator" "$RED" "$text" "$NC"
            ;;
        *)
            printf "%s %s" "$indicator" "$text"
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
#                              DASHBOARD COMPONENTS
# ═══════════════════════════════════════════════════════════════════════════════

# Enhanced system information
get_enhanced_system_info() {
    local cpu_usage memory_usage disk_usage uptime_info
    
    # CPU usage (simplified)
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "N/A")
    
    # Memory usage
    if command -v free >/dev/null 2>&1; then
        memory_usage=$(free | awk 'NR==2{printf "%.1f%%", $3*100/$2}' 2>/dev/null || echo "N/A")
    else
        memory_usage="N/A"
    fi
    
    # Disk usage
    disk_usage=$(df -h / 2>/dev/null | awk 'NR==2{print $5}' || echo "N/A")
    
    # System uptime
    uptime_info=$(uptime | awk -F'up ' '{print $2}' | awk -F', load' '{print $1}' 2>/dev/null || echo "N/A")
    
    cat << EOF
${CYAN}System Performance${NC}
$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H
  🖥️  CPU Usage: $cpu_usage
  💾 Memory: $memory_usage
  💿 Disk: $disk_usage
  ⏰ Uptime: $uptime_info
EOF
}

# Enhanced Docker information
get_enhanced_docker_info() {
    local docker_status="inactive"
    local compose_status="inactive"
    local container_count=0
    
    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            docker_status="active"
            container_count=$(docker ps -q 2>/dev/null | wc -l)
        fi
    fi
    
    if command -v docker-compose >/dev/null 2>&1 || (command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1); then
        compose_status="active"
    fi
    
    cat << EOF
${CYAN}Docker Environment${NC}
$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H
  $(draw_status "$docker_status" "Docker Engine")
  $(draw_status "$compose_status" "Docker Compose")
  📦 Containers: $container_count running
EOF
}

# Enhanced Nexus status
get_enhanced_nexus_info() {
    local nexus_status="inactive"
    local prover_status="inactive"
    local ops_rate="0"
    local wallet_addr="Not configured"
    local node_id="Not set"
    
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        if command -v jq >/dev/null 2>&1; then
            wallet_addr=$(jq -r '.wallet_address // "Not configured"' "$CREDENTIALS_FILE" 2>/dev/null)
            node_id=$(jq -r '.node_id // "Not set"' "$CREDENTIALS_FILE" 2>/dev/null)
        else
            wallet_addr=$(grep -o '"wallet_address":[^,}]*' "$CREDENTIALS_FILE" | cut -d'"' -f4 2>/dev/null || echo "Not configured")
            node_id=$(grep -o '"node_id":[^,}]*' "$CREDENTIALS_FILE" | cut -d'"' -f4 2>/dev/null || echo "Not set")
        fi
    fi
    
    # Check if Nexus containers are running
    if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "nexus"; then
        nexus_status="active"
        
        # Check prover specifically
        if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "prover"; then
            prover_status="active"
            
            # Get operations rate if available
            ops_rate=$(get_current_ops_rate 2>/dev/null || echo "0")
        fi
    fi
    
    cat << EOF
${CYAN}Nexus Network${NC}
$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H$UI_H
  $(draw_status "$nexus_status" "Nexus Node")
  $(draw_status "$prover_status" "Prover Service")
  ⚡ Ops/sec: $ops_rate
  🏷️  Node ID: ${node_id:0:8}...
  💰 Wallet: ${wallet_addr:0:8}...${wallet_addr: -4}
EOF
}

# Get current operations rate
get_current_ops_rate() {
    local ops_rate=0
    
    # Try to get from metrics API or logs
    if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "prover"; then
        # Try to extract from prover logs
        local log_output
        log_output=$(docker logs nexus-prover --tail 10 2>/dev/null | grep -i "ops\|operations\|rate" | tail -1)
        
        if [[ -n "$log_output" ]]; then
            # Extract numeric value (simplified)
            ops_rate=$(echo "$log_output" | grep -o '[0-9]\+\(\.[0-9]\+\)\?' | tail -1 || echo "0")
        fi
    fi
    
    echo "$ops_rate"
}

# ═══════════════════════════════════════════════════════════════════════════════
#                              MAIN DASHBOARD
# ═══════════════════════════════════════════════════════════════════════════════

# Enhanced responsive dashboard
draw_enhanced_dashboard() {
    local header_text="NEXUS V3 Network Manager"
    local timestamp
    timestamp=$(now_jakarta)
    
    # Initialize UI
    detect_terminal_size
    init_ui_chars
    
    clear_screen
    
    # Header section
    case "$LAYOUT_MODE" in
        "compact")
            draw_compact_header "$header_text" "$timestamp"
            draw_compact_panels
            ;;
        "standard")
            draw_standard_header "$header_text" "$timestamp"
            draw_standard_panels
            ;;
        "wide")
            draw_wide_header "$header_text" "$timestamp"
            draw_wide_panels
            ;;
    esac
    
    # Footer
    draw_footer
}

# Compact layout for narrow terminals
draw_compact_header() {
    local title="$1"
    local timestamp="$2"
    
    echo -e "${BOLD}${CYAN}$title${NC}"
    echo "$timestamp"
    draw_horizontal_line "$TERM_WIDTH"
}

draw_compact_panels() {
    get_enhanced_system_info
    echo ""
    get_enhanced_docker_info
    echo ""
    get_enhanced_nexus_info
}

# Standard layout for medium terminals
draw_standard_header() {
    local title="$1"
    local timestamp="$2"
    
    center_text "${BOLD}${CYAN}$title${NC}" "$TERM_WIDTH"
    center_text "$timestamp" "$TERM_WIDTH"
    draw_horizontal_line "$TERM_WIDTH"
}

draw_standard_panels() {
    # Two-column layout
    local col_width=$((TERM_WIDTH / 2 - 2))
    
    echo -e "${BOLD}System & Docker Status${NC}"
    draw_horizontal_line "$TERM_WIDTH" "$UI_H"
    
    get_enhanced_system_info
    echo ""
    get_enhanced_docker_info
    echo ""
    
    echo -e "${BOLD}Nexus Network Status${NC}"
    draw_horizontal_line "$TERM_WIDTH" "$UI_H"
    get_enhanced_nexus_info
}

# Wide layout for large terminals
draw_wide_header() {
    local title="$1"
    local timestamp="$2"
    
    printf "%s%*s%s\n" "$UI_TL" $((TERM_WIDTH - 2)) | tr ' ' "$UI_H" "$UI_TR"
    center_text "${BOLD}${CYAN}$title${NC}" "$TERM_WIDTH"
    center_text "$timestamp" "$TERM_WIDTH"
    printf "%s%*s%s\n" "$UI_BL" $((TERM_WIDTH - 2)) | tr ' ' "$UI_H" "$UI_BR"
}

draw_wide_panels() {
    # Three-column layout
    local col_width=$((TERM_WIDTH / 3 - 4))
    
    echo -e "${BOLD}System Monitor${NC}     ${BOLD}Docker Status${NC}     ${BOLD}Nexus Network${NC}"
    draw_horizontal_line "$TERM_WIDTH" "$UI_H"
    
    # Side-by-side display (simplified for now)
    get_enhanced_system_info
    echo ""
    get_enhanced_docker_info
    echo ""
    get_enhanced_nexus_info
}

# Footer with navigation
draw_footer() {
    echo ""
    draw_horizontal_line "$TERM_WIDTH" "$UI_H"
    case "$LAYOUT_MODE" in
        "compact")
            echo -e "${CYAN}[1]Install [2]Manage [3]Monitor [4]Settings [0]Exit${NC}"
            ;;
        *)
            center_text "${CYAN}[1] Install Nexus  [2] Manage  [3] Monitor  [4] Settings  [0] Exit${NC}" "$TERM_WIDTH"
            ;;
    esac
    echo ""
}

# Export functions for use by other modules
export -f detect_terminal_size init_ui_chars draw_enhanced_dashboard
export -f get_enhanced_system_info get_enhanced_docker_info get_enhanced_nexus_info
