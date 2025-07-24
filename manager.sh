#!/bin/bash

# Nexus V3 Node Manager Script
# Author: Rokhanz
# Version: 3.0.0

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
WORKDIR="$HOME/nexus"
NEXUS_CONFIG_DIR="$HOME/.nexus"
CREDENTIALS_FILE="$HOME/.nexus/credentials.json"
DOCKER_IMAGE="nexusxyz/nexus"
LOG_FILE="$HOME/nexus-manager.log"
MAX_NODES=10

# Nexus Network Configuration (Testnet 3)
CHAIN_ID="3940"
RPC_HTTP="https://testnet3.rpc.nexus.xyz"
RPC_WEBSOCKET="wss://testnet3.rpc.nexus.xyz"
EXPLORER_URL="https://testnet3.explorer.nexus.xyz"
FAUCET_URL="https://faucets.alchemy.com/faucets/nexus-testnet"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Clear screen and show header
show_header() {
    clear
    print_color "$MAGENTA" "═══════════════════════════════════════════════════════════"
    print_color "$CYAN" "           🤖 Nexus V3 Node Manager v3.0.0"
    print_color "$CYAN" "                 Author: Rokhanz 🇮🇩"
    print_color "$MAGENTA" "═══════════════════════════════════════════════════════════"
    echo
}

# Check if Docker is installed and running
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_color "$RED" "❌ Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_color "$RED" "❌ Docker is not running. Please start Docker service."
        exit 1
    fi
}

# Check if installation exists
check_installation() {
    if [[ ! -d "$WORKDIR" ]]; then
        print_color "$RED" "❌ Nexus installation not found at $WORKDIR"
        print_color "$CYAN" "Please run install.sh first."
        exit 1
    fi
    
    if [[ ! -f "$WORKDIR/docker-compose.yml" ]]; then
        print_color "$RED" "❌ Docker compose configuration not found."
        print_color "$CYAN" "Please run install.sh to set up the installation."
        exit 1
    fi
}

# Check if credentials exist
check_credentials() {
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        return 0
    else
        return 1
    fi
}

# Show credential status
show_credential_status() {
    if check_credentials; then
        print_color "$GREEN" "✅ Credentials found at: $CREDENTIALS_FILE"
        
        # Try to extract basic info from credentials
        if command -v jq &> /dev/null; then
            local user_id node_id
            user_id=$(jq -r '.user_id // "Not available"' "$CREDENTIALS_FILE" 2>/dev/null)
            node_id=$(jq -r '.node_id // "Not available"' "$CREDENTIALS_FILE" 2>/dev/null)
            print_color "$CYAN" "User ID: $user_id"
            print_color "$CYAN" "Node ID: $node_id"
        else
            print_color "$YELLOW" "Install 'jq' to view credential details"
        fi
    else
        print_color "$YELLOW" "⚠️  No credentials found. Please register user and node first."
        print_color "$CYAN" "Credentials should be at: $CREDENTIALS_FILE"
    fi
}

# Clear credentials
clear_credentials() {
    print_color "$YELLOW" "⚠️  WARNING: This will clear your Nexus credentials"
    print_color "$RED" "You will need to register your user and node again!"
    echo
    read -p "Are you sure you want to clear credentials? (yes/no): " confirm
    
    if [[ "$confirm" == "yes" ]]; then
        if [[ -f "$CREDENTIALS_FILE" ]]; then
            rm -f "$CREDENTIALS_FILE"
            print_color "$GREEN" "✅ Credentials cleared successfully"
            log "Credentials cleared from $CREDENTIALS_FILE"
        else
            print_color "$CYAN" "No credentials file found to clear"
        fi
        
        # Also clear the entire .nexus directory if empty
        if [[ -d "$NEXUS_CONFIG_DIR" ]] && [[ -z "$(ls -A "$NEXUS_CONFIG_DIR")" ]]; then
            rmdir "$NEXUS_CONFIG_DIR"
            print_color "$CYAN" "Removed empty .nexus directory"
        fi
    else
        print_color "$CYAN" "Credential clearing cancelled"
    fi
}

# Show network information
show_network_info() {
    print_color "$BLUE" "🌐 Nexus Network Information (Testnet 3):"
    echo
    print_color "$CYAN" "Chain ID: $CHAIN_ID"
    print_color "$CYAN" "Native Token: Nexus Token (NEX)"
    print_color "$CYAN" "RPC (HTTP): $RPC_HTTP"
    print_color "$CYAN" "RPC (WebSocket): $RPC_WEBSOCKET"
    print_color "$CYAN" "Explorer: $EXPLORER_URL"
    print_color "$CYAN" "Faucet: $FAUCET_URL"
    echo
    
    show_credential_status
    echo
}

# Get list of all Nexus containers
get_nexus_containers() {
    docker ps -a --filter "name=nexus-node" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.CreatedAt}}" 2>/dev/null || true
}

# Get running Nexus containers
get_running_containers() {
    docker ps --filter "name=nexus-node" --format "{{.Names}}" 2>/dev/null || true
}

# Get stopped Nexus containers
get_stopped_containers() {
    docker ps -a --filter "name=nexus-node" --filter "status=exited" --format "{{.Names}}" 2>/dev/null || true
}

# Show current node status
show_node_status() {
    print_color "$BLUE" "📊 Current Node Status:"
    echo
    
    local containers
    containers=$(get_nexus_containers)
    
    if [[ -z "$containers" ]]; then
        print_color "$YELLOW" "⚠️  No Nexus nodes found."
        return
    fi
    
    echo "$containers"
    echo
    
    local running_count
    local stopped_count
    running_count=$(get_running_containers | wc -l)
    stopped_count=$(get_stopped_containers | wc -l)
    
    print_color "$GREEN" "🟢 Running nodes: $running_count"
    print_color "$RED" "🔴 Stopped nodes: $stopped_count"
    echo
}

# Start specific node
start_node() {
    local node_name=$1
    
    print_color "$BLUE" "🚀 Starting node: $node_name"
    
    if docker start "$node_name" &> /dev/null; then
        print_color "$GREEN" "✅ Node $node_name started successfully"
        log "Started node: $node_name"
        
        # Wait a moment and show status
        sleep 3
        local status
        status=$(docker ps --filter "name=$node_name" --format "{{.Status}}" 2>/dev/null || true)
        if [[ -n "$status" ]]; then
            print_color "$CYAN" "Status: $status"
        fi
    else
        print_color "$RED" "❌ Failed to start node: $node_name"
        log "ERROR: Failed to start node: $node_name"
    fi
}

# Stop specific node
stop_node() {
    local node_name=$1
    
    print_color "$BLUE" "🛑 Stopping node: $node_name"
    
    if docker stop "$node_name" &> /dev/null; then
        print_color "$GREEN" "✅ Node $node_name stopped successfully"
        log "Stopped node: $node_name"
    else
        print_color "$RED" "❌ Failed to stop node: $node_name"
        log "ERROR: Failed to stop node: $node_name"
    fi
}

# Restart specific node
restart_node() {
    local node_name=$1
    
    print_color "$BLUE" "🔄 Restarting node: $node_name"
    
    if docker restart "$node_name" &> /dev/null; then
        print_color "$GREEN" "✅ Node $node_name restarted successfully"
        log "Restarted node: $node_name"
        
        # Wait a moment and show status
        sleep 3
        local status
        status=$(docker ps --filter "name=$node_name" --format "{{.Status}}" 2>/dev/null || true)
        if [[ -n "$status" ]]; then
            print_color "$CYAN" "Status: $status"
        fi
    else
        print_color "$RED" "❌ Failed to restart node: $node_name"
        log "ERROR: Failed to restart node: $node_name"
    fi
}

# Remove specific node
remove_node() {
    local node_name=$1
    
    print_color "$YELLOW" "⚠️  WARNING: This will permanently remove node: $node_name"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_color "$BLUE" "🗑️  Removing node: $node_name"
        
        # Stop the container first
        docker stop "$node_name" &> /dev/null || true
        
        # Remove the container
        if docker rm "$node_name" &> /dev/null; then
            print_color "$GREEN" "✅ Node $node_name removed successfully"
            log "Removed node: $node_name"
        else
            print_color "$RED" "❌ Failed to remove node: $node_name"
            log "ERROR: Failed to remove node: $node_name"
        fi
    else
        print_color "$CYAN" "Node removal cancelled"
    fi
}

# Create new node
create_new_node() {
    print_color "$BLUE" "➕ Creating new Nexus node..."
    
    # Get next node number
    local existing_nodes
    existing_nodes=$(docker ps -a --filter "name=nexus-node" --format "{{.Names}}" | grep -o '[0-9]\+$' | sort -n | tail -1)
    local next_number=1
    
    if [[ -n "$existing_nodes" ]]; then
        next_number=$((existing_nodes + 1))
    fi
    
    if [[ $next_number -gt $MAX_NODES ]]; then
        print_color "$RED" "❌ Maximum number of nodes ($MAX_NODES) reached"
        return 1
    fi
    
    local node_name="nexus-node-$next_number"
    local port=$((8080 + next_number - 1))
    
    print_color "$CYAN" "Node name: $node_name"
    print_color "$CYAN" "Port: $port"
    
    read -p "Proceed with creation? (Y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        print_color "$CYAN" "Node creation cancelled"
        return 0
    fi
    
    # Create the container
    if docker run -d \
        --name "$node_name" \
        --restart unless-stopped \
        -p "$port:8080" \
        -v "$WORKDIR/data:/app/data" \
        -v "$WORKDIR/logs:/app/logs" \
        -e "NODE_ENV=production" \
        -e "LOG_LEVEL=info" \
        "$DOCKER_IMAGE:latest" &> /dev/null; then
        
        print_color "$GREEN" "✅ Node $node_name created and started successfully"
        print_color "$CYAN" "Access the node at: http://localhost:$port"
        log "Created new node: $node_name on port $port"
        
        # Wait a moment and show status
        sleep 5
        local status
        status=$(docker ps --filter "name=$node_name" --format "{{.Status}}" 2>/dev/null || true)
        if [[ -n "$status" ]]; then
            print_color "$CYAN" "Status: $status"
        fi
    else
        print_color "$RED" "❌ Failed to create node: $node_name"
        log "ERROR: Failed to create node: $node_name"
    fi
}

# Show node logs
show_node_logs() {
    local node_name=$1
    local lines=${2:-50}
    
    print_color "$BLUE" "📋 Showing logs for node: $node_name (last $lines lines)"
    echo
    
    if docker logs --tail="$lines" "$node_name" 2>/dev/null; then
        log "Displayed logs for node: $node_name"
    else
        print_color "$RED" "❌ Failed to get logs for node: $node_name"
    fi
    
    echo
    read -p "Press Enter to continue..."
}

# Show detailed node info
show_node_info() {
    local node_name=$1
    
    print_color "$BLUE" "ℹ️  Detailed information for node: $node_name"
    echo
    
    # Basic container info
    print_color "$CYAN" "Container Information:"
    docker inspect "$node_name" --format "
ID: {{.Id}}
Status: {{.State.Status}}
Started: {{.State.StartedAt}}
Image: {{.Config.Image}}
Ports: {{range .NetworkSettings.Ports}}{{.}}{{end}}" 2>/dev/null || {
        print_color "$RED" "❌ Failed to get information for node: $node_name"
        return 1
    }
    
    echo
    
    # Resource usage
    print_color "$CYAN" "Resource Usage:"
    docker stats "$node_name" --no-stream --format "
CPU: {{.CPUPerc}}
Memory: {{.MemUsage}}
Network I/O: {{.NetIO}}
Block I/O: {{.BlockIO}}" 2>/dev/null || {
        print_color "$YELLOW" "⚠️  Could not get resource usage"
    }
    
    echo
    read -p "Press Enter to continue..."
}

# Start all nodes
start_all_nodes() {
    print_color "$BLUE" "🚀 Starting all Nexus nodes..."
    
    local stopped_nodes
    stopped_nodes=$(get_stopped_containers)
    
    if [[ -z "$stopped_nodes" ]]; then
        print_color "$CYAN" "All nodes are already running"
        return 0
    fi
    
    local started=0
    local failed=0
    
    while IFS= read -r node_name; do
        if [[ -n "$node_name" ]]; then
            if docker start "$node_name" &> /dev/null; then
                print_color "$GREEN" "✅ Started: $node_name"
                ((started++))
            else
                print_color "$RED" "❌ Failed: $node_name"
                ((failed++))
            fi
        fi
    done <<< "$stopped_nodes"
    
    echo
    print_color "$CYAN" "Summary: $started started, $failed failed"
    log "Started all nodes: $started successful, $failed failed"
}

# Stop all nodes
stop_all_nodes() {
    print_color "$BLUE" "🛑 Stopping all Nexus nodes..."
    
    local running_nodes
    running_nodes=$(get_running_containers)
    
    if [[ -z "$running_nodes" ]]; then
        print_color "$CYAN" "No running nodes found"
        return 0
    fi
    
    read -p "Stop all running nodes? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_color "$CYAN" "Operation cancelled"
        return 0
    fi
    
    local stopped=0
    local failed=0
    
    while IFS= read -r node_name; do
        if [[ -n "$node_name" ]]; then
            if docker stop "$node_name" &> /dev/null; then
                print_color "$GREEN" "✅ Stopped: $node_name"
                ((stopped++))
            else
                print_color "$RED" "❌ Failed: $node_name"
                ((failed++))
            fi
        fi
    done <<< "$running_nodes"
    
    echo
    print_color "$CYAN" "Summary: $stopped stopped, $failed failed"
    log "Stopped all nodes: $stopped successful, $failed failed"
}

# Restart all nodes
restart_all_nodes() {
    print_color "$BLUE" "🔄 Restarting all Nexus nodes..."
    
    local all_nodes
    all_nodes=$(docker ps -a --filter "name=nexus-node" --format "{{.Names}}" 2>/dev/null || true)
    
    if [[ -z "$all_nodes" ]]; then
        print_color "$YELLOW" "⚠️  No Nexus nodes found"
        return 0
    fi
    
    read -p "Restart all nodes? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_color "$CYAN" "Operation cancelled"
        return 0
    fi
    
    local restarted=0
    local failed=0
    
    while IFS= read -r node_name; do
        if [[ -n "$node_name" ]]; then
            if docker restart "$node_name" &> /dev/null; then
                print_color "$GREEN" "✅ Restarted: $node_name"
                ((restarted++))
            else
                print_color "$RED" "❌ Failed: $node_name"
                ((failed++))
            fi
        fi
    done <<< "$all_nodes"
    
    echo
    print_color "$CYAN" "Summary: $restarted restarted, $failed failed"
    log "Restarted all nodes: $restarted successful, $failed failed"
}

# Select node for operations
select_node() {
    local all_nodes
    all_nodes=$(docker ps -a --filter "name=nexus-node" --format "{{.Names}}" 2>/dev/null || true)
    
    if [[ -z "$all_nodes" ]]; then
        print_color "$YELLOW" "⚠️  No Nexus nodes found"
        return 1
    fi
    
    print_color "$CYAN" "Available nodes:"
    echo
    
    local -a node_array
    local i=1
    while IFS= read -r node_name; do
        if [[ -n "$node_name" ]]; then
            node_array[$i]="$node_name"
            local status
            status=$(docker ps --filter "name=$node_name" --format "{{.Status}}" 2>/dev/null || echo "Stopped")
            if [[ -n "$status" ]]; then
                print_color "$GREEN" "$i. $node_name (Running: $status)"
            else
                print_color "$RED" "$i. $node_name (Stopped)"
            fi
            ((i++))
        fi
    done <<< "$all_nodes"
    
    echo
    read -p "Select node number (1-$((i-1))): " choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -lt "$i" ]]; then
        echo "${node_array[$choice]}"
        return 0
    else
        print_color "$RED" "❌ Invalid selection"
        return 1
    fi
}

# Show main menu
show_menu() {
    print_color "$YELLOW" "🔧 Node Management Options:"
    echo
    print_color "$CYAN" "  1. 📊 Show node status"
    print_color "$CYAN" "  2. 🚀 Start specific node"
    print_color "$CYAN" "  3. 🛑 Stop specific node"
    print_color "$CYAN" "  4. 🔄 Restart specific node"
    print_color "$CYAN" "  5. ➕ Create new node"
    print_color "$CYAN" "  6. 🗑️  Remove node"
    print_color "$CYAN" "  7. 📋 View node logs"
    print_color "$CYAN" "  8. ℹ️  Node information"
    echo
    print_color "$YELLOW" "🎛️  Bulk Operations:"
    print_color "$CYAN" "  9. 🚀 Start all nodes"
    print_color "$CYAN" " 10. 🛑 Stop all nodes"
    print_color "$CYAN" " 11. 🔄 Restart all nodes"
    echo
    print_color "$YELLOW" "🌐 Network & Credentials:"
    print_color "$CYAN" " 12. 📡 Show network info"
    print_color "$CYAN" " 13. 🗑️  Clear credentials"
    echo
    print_color "$RED" "  0. 🚪 Exit"
    echo
}

# Handle menu choices
handle_choice() {
    local choice=$1
    
    case $choice in
        1)
            show_node_status
            ;;
        2)
            if node=$(select_node); then
                start_node "$node"
            fi
            ;;
        3)
            if node=$(select_node); then
                stop_node "$node"
            fi
            ;;
        4)
            if node=$(select_node); then
                restart_node "$node"
            fi
            ;;
        5)
            create_new_node
            ;;
        6)
            if node=$(select_node); then
                remove_node "$node"
            fi
            ;;
        7)
            if node=$(select_node); then
                echo
                read -p "Number of log lines to show (default 50): " lines
                lines=${lines:-50}
                show_node_logs "$node" "$lines"
            fi
            ;;
        8)
            if node=$(select_node); then
                show_node_info "$node"
            fi
            ;;
        9)
            start_all_nodes
            ;;
        10)
            stop_all_nodes
            ;;
        11)
            restart_all_nodes
            ;;
        12)
            show_network_info
            ;;
        13)
            clear_credentials
            ;;
        0)
            print_color "$CYAN" "👋 Goodbye!"
            log "Node manager session ended"
            exit 0
            ;;
        *)
            print_color "$RED" "❌ Invalid option. Please try again."
            ;;
    esac
    
    echo
    read -p "Press Enter to continue..."
}

# Main function
main() {
    log "Node manager session started"
    
    # Initial checks
    check_docker
    check_installation
    
    # Main loop
    while true; do
        show_header
        show_node_status
        show_menu
        
        read -p "Enter your choice: " choice
        echo
        
        handle_choice "$choice"
    done
}

# Error handling
trap 'print_color "$RED" "❌ Manager interrupted"; log "Manager interrupted"; exit 1' INT TERM

# Run main function
main "$@"
