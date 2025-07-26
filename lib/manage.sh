#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════════
#                              MANAGEMENT MODULE
# ═══════════════════════════════════════════════════════════════════════════════
# Description: Nexus network management and monitoring operations
# Dependencies: common.sh, tui.sh
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent double-loading
[[ -n "${NEXUS_MANAGE_LOADED:-}" ]] && return 0
readonly NEXUS_MANAGE_LOADED=1

# Source dependencies
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tui.sh"

# ═══════════════════════════════════════════════════════════════════════════════
#                            MANAGEMENT FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Main management interface
manage_nexus_system() {
    while true; do
        draw_enhanced_dashboard
        echo -e "${CYAN}Management Options:${NC}"
        echo -e "${CYAN}══════════════════${NC}"
        echo ""
        echo -e "  ${GREEN}[1]${NC} Start Nexus Services"
        echo -e "  ${GREEN}[2]${NC} Stop Nexus Services"
        echo -e "  ${GREEN}[3]${NC} Restart Services"
        echo -e "  ${GREEN}[4]${NC} View Service Logs"
        echo -e "  ${GREEN}[5]${NC} Performance Monitor"
        echo -e "  ${GREEN}[6]${NC} Service Status"
        echo -e "  ${GREEN}[7]${NC} Update System"
        echo -e "  ${RED}[0]${NC} Back to Main Menu"
        echo ""
        
        read -p "$(echo -e "${YELLOW}Select option [0-7]: ${NC}")" choice
        
        case $choice in
            1) start_nexus_services ;;
            2) stop_nexus_services ;;
            3) restart_nexus_services ;;
            4) view_service_logs ;;
            5) performance_monitor ;;
            6) service_status_detailed ;;
            7) update_nexus_system ;;
            0) break ;;
            *) 
                echo -e "${RED}❌ Invalid option. Please try again.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Start Nexus services
start_nexus_services() {
    echo -e "${CYAN}🚀 Starting Nexus services...${NC}"
    
    if [[ ! -f "$WORKDIR/docker-compose.yml" ]]; then
        echo -e "${RED}❌ Nexus not installed. Please install first.${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    cd "$WORKDIR" || return 1
    
    echo -e "${CYAN}   Starting containers...${NC}"
    if docker-compose up -d; then
        echo -e "${GREEN}✅ Nexus services started successfully${NC}"
        
        # Start metrics daemon
        start_metrics_daemon
        
        log_activity "Nexus services started"
    else
        echo -e "${RED}❌ Failed to start Nexus services${NC}"
        log_activity "Failed to start Nexus services"
    fi
    
    read -p "Press Enter to continue..."
}

# Stop Nexus services
stop_nexus_services() {
    echo -e "${CYAN}🛑 Stopping Nexus services...${NC}"
    
    if [[ ! -f "$WORKDIR/docker-compose.yml" ]]; then
        echo -e "${YELLOW}⚠️  Nexus not installed${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    cd "$WORKDIR" || return 1
    
    # Stop metrics daemon first
    stop_metrics_daemon
    
    echo -e "${CYAN}   Stopping containers...${NC}"
    if docker-compose down; then
        echo -e "${GREEN}✅ Nexus services stopped successfully${NC}"
        log_activity "Nexus services stopped"
    else
        echo -e "${RED}❌ Failed to stop Nexus services${NC}"
        log_activity "Failed to stop Nexus services"
    fi
    
    read -p "Press Enter to continue..."
}

# Restart Nexus services
restart_nexus_services() {
    echo -e "${CYAN}🔄 Restarting Nexus services...${NC}"
    
    stop_nexus_services
    sleep 3
    start_nexus_services
}

# View service logs
view_service_logs() {
    if [[ ! -f "$WORKDIR/docker-compose.yml" ]]; then
        echo -e "${RED}❌ Nexus not installed${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    cd "$WORKDIR" || return 1
    
    echo -e "${CYAN}📋 Service Logs${NC}"
    echo -e "${CYAN}═════════════${NC}"
    echo ""
    echo -e "  ${GREEN}[1]${NC} View All Logs"
    echo -e "  ${GREEN}[2]${NC} View Prover Logs"
    echo -e "  ${GREEN}[3]${NC} View Network Logs"
    echo -e "  ${GREEN}[4]${NC} Follow Live Logs"
    echo -e "  ${RED}[0]${NC} Back"
    echo ""
    
    read -p "$(echo -e "${YELLOW}Select option [0-4]: ${NC}")" log_choice
    
    case $log_choice in
        1)
            echo -e "${CYAN}Showing all service logs (last 50 lines):${NC}"
            docker-compose logs --tail=50
            ;;
        2)
            echo -e "${CYAN}Showing prover logs (last 50 lines):${NC}"
            docker-compose logs --tail=50 prover 2>/dev/null || echo "Prover service not found"
            ;;
        3)
            echo -e "${CYAN}Showing network logs (last 50 lines):${NC}"
            docker-compose logs --tail=50 nexus 2>/dev/null || echo "Network service not found"
            ;;
        4)
            echo -e "${CYAN}Following live logs (Ctrl+C to exit):${NC}"
            docker-compose logs -f
            ;;
        0)
            return 0
            ;;
        *)
            echo -e "${RED}❌ Invalid option${NC}"
            ;;
    esac
    
    read -p "Press Enter to continue..."
}

# Performance monitor
performance_monitor() {
    echo -e "${CYAN}📊 Performance Monitor${NC}"
    echo -e "${CYAN}════════════════════${NC}"
    
    while true; do
        clear_screen
        echo -e "${BOLD}${CYAN}Nexus Performance Dashboard${NC}"
        echo -e "${CYAN}═══════════════════════════${NC}"
        echo ""
        
        # System metrics
        show_system_metrics
        echo ""
        
        # Nexus metrics
        show_nexus_metrics
        echo ""
        
        # Operations metrics
        show_operations_metrics
        echo ""
        
        echo -e "${CYAN}Press [q] to quit, [r] to refresh, or wait 10s for auto-refresh${NC}"
        
        if read -t 10 -n 1 key; then
            case $key in
                q|Q) break ;;
                r|R) continue ;;
                *) ;;
            esac
        fi
    done
}

# Show system metrics
show_system_metrics() {
    echo -e "${CYAN}System Resources:${NC}"
    
    # CPU usage
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "N/A")
    echo -e "  🖥️  CPU Usage: ${cpu_usage}%"
    
    # Memory usage
    if command -v free >/dev/null 2>&1; then
        local memory_info
        memory_info=$(free -h | awk 'NR==2{printf "Used: %s / %s (%.1f%%)", $3, $2, $3*100/$2}' 2>/dev/null || echo "N/A")
        echo -e "  💾 Memory: $memory_info"
    fi
    
    # Disk usage
    local disk_usage
    disk_usage=$(df -h / 2>/dev/null | awk 'NR==2{print $5}' || echo "N/A")
    echo -e "  💿 Disk Usage: $disk_usage"
    
    # Load average
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' 2>/dev/null || echo "N/A")
    echo -e "  ⚖️  Load Average:$load_avg"
}

# Show Nexus metrics
show_nexus_metrics() {
    echo -e "${CYAN}Nexus Services:${NC}"
    
    # Container status
    local containers
    containers=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep nexus 2>/dev/null)
    
    if [[ -n "$containers" ]]; then
        echo "$containers" | while read -r line; do
            echo -e "  📦 $line"
        done
    else
        echo -e "  📦 No Nexus containers running"
    fi
    
    # Resource usage by containers
    if docker ps -q --filter "name=nexus" | head -1 >/dev/null 2>&1; then
        local stats
        stats=$(docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep nexus 2>/dev/null)
        
        if [[ -n "$stats" ]]; then
            echo -e "${CYAN}Container Resources:${NC}"
            echo "$stats" | while read -r line; do
                echo -e "  $line"
            done
        fi
    fi
}

# Show operations metrics
show_operations_metrics() {
    echo -e "${CYAN}Operations Metrics:${NC}"
    
    # Get current operations rate
    local ops_rate
    ops_rate=$(get_current_ops_rate 2>/dev/null || echo "0")
    echo -e "  ⚡ Current Ops/sec: $ops_rate"
    
    # Show operations progress bar
    if [[ "$ops_rate" != "0" && "$ops_rate" != "N/A" ]]; then
        local target_ops=100
        local progress=$((ops_rate * 100 / target_ops))
        if [[ $progress -gt 100 ]]; then
            progress=100
        fi
        
        echo -e "  📊 Performance: $(draw_progress_bar $progress 100 30)"
    fi
    
    # Network status
    if docker ps --format "table {{.Names}}" | grep -q "nexus"; then
        echo -e "  🌐 Network Status: $(draw_status "active" "Connected")"
    else
        echo -e "  🌐 Network Status: $(draw_status "stopped" "Disconnected")"
    fi
    
    # Uptime
    local start_time
    start_time=$(docker inspect --format='{{.State.StartedAt}}' nexus-prover 2>/dev/null | cut -d'T' -f1 || echo "N/A")
    if [[ "$start_time" != "N/A" ]]; then
        echo -e "  ⏱️  Started: $start_time"
    fi
}

# Service status detailed
service_status_detailed() {
    echo -e "${CYAN}📋 Detailed Service Status${NC}"
    echo -e "${CYAN}═════════════════════════${NC}"
    echo ""
    
    # Docker status
    echo -e "${BOLD}Docker Engine:${NC}"
    if docker info >/dev/null 2>&1; then
        echo -e "  $(draw_status "active" "Docker is running")"
        
        local docker_version
        docker_version=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')
        echo -e "  📋 Version: $docker_version"
    else
        echo -e "  $(draw_status "error" "Docker is not running")"
    fi
    echo ""
    
    # Docker Compose status
    echo -e "${BOLD}Docker Compose:${NC}"
    if command -v docker-compose >/dev/null 2>&1; then
        local compose_version
        compose_version=$(docker-compose --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')
        echo -e "  $(draw_status "active" "Docker Compose available")"
        echo -e "  📋 Version: $compose_version"
    elif docker compose version >/dev/null 2>&1; then
        local compose_version
        compose_version=$(docker compose version 2>/dev/null | cut -d' ' -f4)
        echo -e "  $(draw_status "active" "Docker Compose (plugin) available")"
        echo -e "  📋 Version: $compose_version"
    else
        echo -e "  $(draw_status "error" "Docker Compose not available")"
    fi
    echo ""
    
    # Nexus containers
    echo -e "${BOLD}Nexus Containers:${NC}"
    if docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep nexus; then
        echo ""
    else
        echo -e "  📦 No Nexus containers found"
        echo ""
    fi
    
    # Credentials status
    echo -e "${BOLD}Configuration:${NC}"
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        echo -e "  $(draw_status "active" "Credentials configured")"
        
        if command -v jq >/dev/null 2>&1; then
            local wallet_addr node_id
            wallet_addr=$(jq -r '.wallet_address // "Not set"' "$CREDENTIALS_FILE" 2>/dev/null)
            node_id=$(jq -r '.node_id // "Not set"' "$CREDENTIALS_FILE" 2>/dev/null)
            
            echo -e "  🏷️  Node ID: ${node_id:0:12}..."
            echo -e "  💰 Wallet: ${wallet_addr:0:8}...${wallet_addr: -4}"
        fi
    else
        echo -e "  $(draw_status "warning" "Credentials not configured")"
    fi
    
    read -p "Press Enter to continue..."
}

# Update Nexus system
update_nexus_system() {
    echo -e "${CYAN}🔄 Updating Nexus System${NC}"
    echo -e "${CYAN}═══════════════════════${NC}"
    echo ""
    
    echo -e "${YELLOW}⚠️  This will update Nexus files and restart services${NC}"
    read -p "Continue? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}Update cancelled${NC}"
        read -p "Press Enter to continue..."
        return 0
    fi
    
    # Stop services first
    echo -e "${CYAN}Stopping services...${NC}"
    stop_nexus_services
    
    # Backup current files
    echo -e "${CYAN}Creating backup...${NC}"
    local backup_dir="$WORKDIR/backup/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    if [[ -f "$WORKDIR/docker-compose.yml" ]]; then
        cp "$WORKDIR/docker-compose.yml" "$backup_dir/" 2>/dev/null
    fi
    
    # Download updated files
    echo -e "${CYAN}Downloading updates...${NC}"
    cd "$WORKDIR" || return 1
    
    local files=("docker-compose.yml" "run.sh")
    for file in "${files[@]}"; do
        echo -e "${CYAN}   Updating $file...${NC}"
        if curl -fsSL "$GITHUB_RAW/$file" -o "$file"; then
            echo -e "${GREEN}   ✅ $file updated${NC}"
            chmod +x "$file" 2>/dev/null || true
        else
            echo -e "${RED}   ❌ Failed to update $file${NC}"
        fi
    done
    
    # Restart services
    echo -e "${CYAN}Restarting services...${NC}"
    start_nexus_services
    
    echo -e "${GREEN}✅ Update completed${NC}"
    log_activity "Nexus system updated"
    
    read -p "Press Enter to continue..."
}

# Start metrics daemon for background reporting
start_metrics_daemon() {
    echo -e "${CYAN}   Starting metrics daemon...${NC}"
    
    # Create metrics script
    cat > "$WORKDIR/metrics-daemon.sh" << 'EOF'
#!/bin/bash
while true; do
    if [[ -f "/tmp/nexus-stop-metrics" ]]; then
        break
    fi
    
    # Get current ops rate and report to Nexus API
    if command -v docker >/dev/null 2>&1 && docker ps --format "table {{.Names}}" | grep -q "prover"; then
        ops_rate=$(docker logs nexus-prover --tail 10 2>/dev/null | grep -i "ops\|operations\|rate" | tail -1 | grep -o '[0-9]\+\(\.[0-9]\+\)\?' | tail -1 || echo "0")
        
        if [[ -n "$ops_rate" && "$ops_rate" != "0" ]]; then
            # Auto-report to Nexus API
            auto_report_to_nexus "$ops_rate" >/dev/null 2>&1 &
        fi
    fi
    
    sleep 30
done
EOF
    
    chmod +x "$WORKDIR/metrics-daemon.sh"
    
    # Start daemon in background
    rm -f /tmp/nexus-stop-metrics
    nohup bash "$WORKDIR/metrics-daemon.sh" >/dev/null 2>&1 &
    echo $! > "$WORKDIR/metrics-daemon.pid"
    
    echo -e "${GREEN}   ✅ Metrics daemon started${NC}"
}

# Stop metrics daemon
stop_metrics_daemon() {
    echo -e "${CYAN}   Stopping metrics daemon...${NC}"
    
    # Signal daemon to stop
    touch /tmp/nexus-stop-metrics
    
    # Kill daemon process if exists
    if [[ -f "$WORKDIR/metrics-daemon.pid" ]]; then
        local pid
        pid=$(cat "$WORKDIR/metrics-daemon.pid" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
        fi
        rm -f "$WORKDIR/metrics-daemon.pid"
    fi
    
    echo -e "${GREEN}   ✅ Metrics daemon stopped${NC}"
}

# Auto-report to Nexus API
auto_report_to_nexus() {
    local ops_rate="$1"
    
    if [[ ! -f "$CREDENTIALS_FILE" ]]; then
        return 1
    fi
    
    local wallet_addr node_id
    if command -v jq >/dev/null 2>&1; then
        wallet_addr=$(jq -r '.wallet_address // ""' "$CREDENTIALS_FILE" 2>/dev/null)
        node_id=$(jq -r '.node_id // ""' "$CREDENTIALS_FILE" 2>/dev/null)
    else
        wallet_addr=$(grep -o '"wallet_address":[^,}]*' "$CREDENTIALS_FILE" | cut -d'"' -f4 2>/dev/null || echo "")
        node_id=$(grep -o '"node_id":[^,}]*' "$CREDENTIALS_FILE" | cut -d'"' -f4 2>/dev/null || echo "")
    fi
    
    if [[ -n "$wallet_addr" && -n "$node_id" && -n "$ops_rate" ]]; then
        # Send to Nexus API
        curl -s -X POST "https://app.nexus.xyz/api/nodes/report" \
            -H "Content-Type: application/json" \
            -d "{
                \"wallet_address\": \"$wallet_addr\",
                \"node_id\": \"$node_id\",
                \"ops_per_second\": $ops_rate,
                \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
            }" >/dev/null 2>&1
    fi
}

# Export functions for use by other modules
export -f manage_nexus_system start_nexus_services stop_nexus_services
export -f performance_monitor start_metrics_daemon stop_metrics_daemon
