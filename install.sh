#!/bin/bash

# Nexus V3 Docker Installation Script
# Author: Rokhanz
# Version: 3.0.0

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
WORKDIR="$HOME/nexus"
NEXUS_CONFIG_DIR="$HOME/.nexus"
CREDENTIALS_FILE="$HOME/.nexus/credentials.json"
DOCKER_IMAGE="nexus-custom"
CONTAINER_PREFIX="nexus-node"
LOG_FILE="$HOME/nexus-install.log"

# Installation mode - always Docker for consistency
INSTALL_MODE="docker"

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

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_color "$RED" "⚠️  Warning: Running as root is not recommended!"
        print_color "$YELLOW" "Consider creating a dedicated user for Nexus operations."
        
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Display banner
display_banner() {
    clear
    print_color "$CYAN" "╔═══════════════════════════════════════════════════════════════╗"
    print_color "$CYAN" "║                    NEXUS V3 DOCKER INSTALLATION              ║"
    print_color "$CYAN" "║                                                               ║"
    print_color "$CYAN" "║  ██████╗  ██████╗ ██╗  ██╗██╗  ██╗ █████╗ ███╗   ██╗███████╗ ║"
    print_color "$CYAN" "║  ██╔══██╗██╔═══██╗██║ ██╔╝██║  ██║██╔══██╗████╗  ██║╚══███╔╝ ║"
    print_color "$CYAN" "║  ██████╔╝██║   ██║█████╔╝ ███████║███████║██╔██╗ ██║  ███╔╝  ║"
    print_color "$CYAN" "║  ██╔══██╗██║   ██║██╔═██╗ ██╔══██║██╔══██║██║╚██╗██║ ███╔╝   ║"
    print_color "$CYAN" "║  ██║  ██║╚██████╔╝██║  ██╗██║  ██║██║  ██║██║ ╚████║███████╗ ║"
    print_color "$CYAN" "║  ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝ ║"
    print_color "$CYAN" "║                                                               ║"
    print_color "$CYAN" "║       🐳 Docker-Based Nexus CLI v3.0.0 • by Rokhanz 🇮🇩     ║"
    print_color "$CYAN" "╚═══════════════════════════════════════════════════════════════╝"
    echo
    print_color "$BLUE" "🐳 This installation uses Docker for maximum VPS compatibility"
    print_color "$BLUE" "📊 Includes custom TUI for monitoring Nexus logs"
    echo
}

# Check system requirements
check_requirements() {
    print_color "$BLUE" "🔍 Checking system requirements..."
    
    local missing_tools=()
    
    # Check for curl or wget
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        missing_tools+=("curl or wget")
    fi
    
    # Check for basic tools
    for tool in git bash; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_color "$RED" "❌ Missing required tools: ${missing_tools[*]}"
        print_color "$YELLOW" "Please install the missing tools and run again."
        exit 1
    fi
    
    print_color "$GREEN" "✅ System requirements check passed"
    log "System requirements verified"
}

# Install Docker if needed
install_docker() {
    if command -v docker >/dev/null 2>&1; then
        local docker_version
        docker_version=$(docker --version 2>/dev/null | head -n1)
        print_color "$GREEN" "✅ Docker is already installed"
        log "Docker found: $docker_version"
        return 0
    fi
    
    print_color "$BLUE" "📦 Installing Docker..."
    
    # Install Docker using official script
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL https://get.docker.com -o get-docker.sh
    elif command -v wget >/dev/null 2>&1; then
        wget -O get-docker.sh https://get.docker.com
    fi
    
    if [[ -f get-docker.sh ]]; then
        sudo sh get-docker.sh
        rm get-docker.sh
        
        # Add current user to docker group
        sudo usermod -aG docker "$USER"
        
        print_color "$GREEN" "✅ Docker installed successfully"
        print_color "$YELLOW" "⚠️  You may need to log out and back in for docker permissions to take effect"
        log "Docker installed and user added to docker group"
    else
        print_color "$RED" "❌ Failed to download Docker installer"
        exit 1
    fi
}

# Create necessary directories
create_directories() {
    print_color "$BLUE" "📁 Creating directories..."
    
    mkdir -p "$WORKDIR"
    mkdir -p "$WORKDIR/data"
    mkdir -p "$WORKDIR/logs"
    mkdir -p "$WORKDIR/config"
    mkdir -p "$NEXUS_CONFIG_DIR"
    
    print_color "$GREEN" "✅ Directories created"
    log "Directory structure created at $WORKDIR"
}

# Build custom Docker image with Nexus CLI
build_docker_image() {
    print_color "$BLUE" "🐳 Building custom Nexus Docker image..."
    
    # Create Dockerfile
    cat > "$WORKDIR/Dockerfile" << 'EOF'
FROM ubuntu:22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/root/.nexus/bin:$PATH"

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create nexus directory
RUN mkdir -p /root/.nexus

# Download and install Nexus CLI
RUN curl -fsSL https://cli.nexus.xyz/ | sh

# Create wrapper script for better logging
RUN cat > /root/.nexus/nexus-wrapper.sh << 'WRAPPER_EOF'
#!/bin/bash
set -euo pipefail

# Colors for logging
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
log_nexus() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a /root/.nexus/nexus.log
}

# Handle different commands
case "${1:-}" in
    "register-user")
        log_nexus "Starting user registration"
        /root/.nexus/bin/nexus-cli "$@"
        ;;
    "register-node")
        log_nexus "Starting node registration"
        /root/.nexus/bin/nexus-cli "$@"
        ;;
    "start")
        log_nexus "Starting Nexus proving process"
        echo -e "${GREEN}🚀 Nexus Prover Starting...${NC}"
        /root/.nexus/bin/nexus-cli "$@" 2>&1 | while IFS= read -r line; do
            echo "$(date '+%Y-%m-%d %H:%M:%S') - $line" | tee -a /root/.nexus/nexus.log
        done
        ;;
    "stop")
        log_nexus "Stopping Nexus proving process"
        /root/.nexus/bin/nexus-cli "$@"
        ;;
    "status")
        log_nexus "Checking Nexus status"
        /root/.nexus/bin/nexus-cli "$@"
        ;;
    "logout")
        log_nexus "Clearing credentials"
        /root/.nexus/bin/nexus-cli "$@"
        ;;
    *)
        /root/.nexus/bin/nexus-cli "$@"
        ;;
esac
WRAPPER_EOF

RUN chmod +x /root/.nexus/nexus-wrapper.sh

# Create log file
RUN touch /root/.nexus/nexus.log

# Set working directory
WORKDIR /root/.nexus

# Default command
CMD ["/root/.nexus/nexus-wrapper.sh"]
EOF

    # Build Docker image
    print_color "$BLUE" "🔨 Building Docker image (this may take a few minutes)..."
    if docker build -t "$DOCKER_IMAGE" "$WORKDIR/"; then
        print_color "$GREEN" "✅ Docker image built successfully: $DOCKER_IMAGE"
        log "Custom Nexus Docker image built successfully"
    else
        print_color "$RED" "❌ Failed to build Docker image"
        log "ERROR: Failed to build Docker image"
        exit 1
    fi
}

# Generate configuration files
generate_config() {
    print_color "$BLUE" "⚙️  Generating configuration files..."
    
    # Create environment file for dashboard integration
    cat > "$WORKDIR/.env" << EOF
# Nexus Network Configuration
NEXUS_NETWORK=testnet3
CHAIN_ID=$CHAIN_ID
RPC_HTTP=$RPC_HTTP
RPC_WEBSOCKET=$RPC_WEBSOCKET
EXPLORER_URL=$EXPLORER_URL
FAUCET_URL=$FAUCET_URL

# Paths
WORKDIR=$WORKDIR
NEXUS_CONFIG_DIR=$NEXUS_CONFIG_DIR
CREDENTIALS_FILE=$CREDENTIALS_FILE

# Docker Configuration
DOCKER_IMAGE=$DOCKER_IMAGE
CONTAINER_PREFIX=$CONTAINER_PREFIX

# Installation info
INSTALL_DATE=$(date '+%Y-%m-%d %H:%M:%S')
INSTALL_METHOD=$INSTALL_MODE
CLI_VERSION=latest
EOF
    
    # Create Docker wrapper script for easy CLI access
    cat > "$WORKDIR/nexus" << 'EOF'
#!/bin/bash

# Nexus Docker CLI Wrapper with Multi-Node Support
set -euo pipefail

# Load configuration
if [[ -f "$HOME/nexus/.env" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/nexus/.env"
fi

# Default values
DOCKER_IMAGE="${DOCKER_IMAGE:-nexus-custom}"
CONTAINER_PREFIX="${CONTAINER_PREFIX:-nexus-node}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Function to get next available node ID
get_next_node_id() {
    local max_id=0
    local container_list
    container_list=$(docker ps -a --filter "name=$CONTAINER_PREFIX-" --format "{{.Names}}" 2>/dev/null || true)
    
    if [[ -n "$container_list" ]]; then
        while IFS= read -r container; do
            if [[ $container =~ $CONTAINER_PREFIX-([0-9]+) ]]; then
                local id="${BASH_REMATCH[1]}"
                if [[ $id -gt $max_id ]]; then
                    max_id=$id
                fi
            fi
        done <<< "$container_list"
    fi
    
    echo $((max_id + 1))
}

# Function to get container name by node ID
get_container_name() {
    local node_id="${1:-}"
    if [[ -n "$node_id" ]]; then
        echo "$CONTAINER_PREFIX-$node_id"
    else
        # Get the first available or create new
        local existing
        existing=$(docker ps -a --filter "name=$CONTAINER_PREFIX-" --format "{{.Names}}" 2>/dev/null | head -1)
        if [[ -n "$existing" ]]; then
            echo "$existing"
        else
            echo "$CONTAINER_PREFIX-1"
        fi
    fi
}

# Function to run Docker command for specific node
run_nexus_docker() {
    local node_id="${1:-}"
    shift || true
    local cmd="$*"
    
    local container_name
    if [[ -n "$node_id" && "$node_id" =~ ^[0-9]+$ ]]; then
        container_name="$CONTAINER_PREFIX-$node_id"
    else
        # If no node ID provided, create new node
        local next_id
        next_id=$(get_next_node_id)
        container_name="$CONTAINER_PREFIX-$next_id"
        echo -e "${BLUE}ℹ️  Creating new node: $container_name${NC}"
    fi
    
    # Stop existing container if running
    if docker ps --filter "name=$container_name" --format "{{.Names}}" | grep -q "$container_name"; then
        docker stop "$container_name" >/dev/null 2>&1 || true
    fi
    
    # Remove existing container
    docker rm "$container_name" >/dev/null 2>&1 || true
    
    # Create node-specific log directory
    mkdir -p "$HOME/nexus/logs/$container_name"
    
    # Run new container
    docker run -d \
        --name "$container_name" \
        -v "$HOME/.nexus:/root/.nexus" \
        -v "$HOME/nexus/logs/$container_name:/root/.nexus/logs" \
        --restart unless-stopped \
        "$DOCKER_IMAGE" \
        /root/.nexus/nexus-wrapper.sh $cmd
    
    echo -e "${GREEN}✅ Node $container_name started${NC}"
    return 0
}

# Function to show logs for specific node
show_logs() {
    local node_id="${1:-}"
    local container_name
    container_name=$(get_container_name "$node_id")
    
    if docker ps --filter "name=$container_name" --format "{{.Names}}" | grep -q "$container_name"; then
        echo -e "${BLUE}📋 Showing logs for $container_name${NC}"
        docker logs -f "$container_name"
    else
        echo -e "${RED}❌ Container $container_name is not running${NC}"
        return 1
    fi
}

# Function to stop specific node or all nodes
stop_container() {
    local node_id="${1:-}"
    
    if [[ "$node_id" == "all" ]]; then
        echo -e "${YELLOW}🛑 Stopping all Nexus nodes...${NC}"
        local containers
        containers=$(docker ps --filter "name=$CONTAINER_PREFIX-" --format "{{.Names}}" 2>/dev/null || true)
        if [[ -n "$containers" ]]; then
            while IFS= read -r container; do
                echo -e "${YELLOW}Stopping $container...${NC}"
                docker stop "$container" >/dev/null 2>&1 || true
            done <<< "$containers"
            echo -e "${GREEN}✅ All Nexus nodes stopped${NC}"
        else
            echo -e "${YELLOW}⚠️  No running Nexus nodes found${NC}"
        fi
    else
        local container_name
        container_name=$(get_container_name "$node_id")
        if docker ps --filter "name=$container_name" --format "{{.Names}}" | grep -q "$container_name"; then
            echo -e "${YELLOW}🛑 Stopping $container_name...${NC}"
            docker stop "$container_name"
            echo -e "${GREEN}✅ Node $container_name stopped${NC}"
        else
            echo -e "${YELLOW}⚠️  Container $container_name is not running${NC}"
        fi
    fi
}

# Function to check status of all nodes
check_status() {
    local node_id="${1:-}"
    
    if [[ -n "$node_id" ]]; then
        # Check specific node
        local container_name
        container_name=$(get_container_name "$node_id")
        if docker ps --filter "name=$container_name" --format "{{.Names}}" | grep -q "$container_name"; then
            echo -e "${GREEN}✅ Node $container_name is running${NC}"
            echo "Started: $(docker inspect --format='{{.State.StartedAt}}' "$container_name" 2>/dev/null)"
        else
            echo -e "${RED}❌ Node $container_name is not running${NC}"
        fi
    else
        # Check all nodes
        echo -e "${CYAN}📊 Nexus Nodes Status:${NC}"
        local all_containers
        all_containers=$(docker ps -a --filter "name=$CONTAINER_PREFIX-" --format "table {{.Names}}\t{{.Status}}\t{{.CreatedAt}}" 2>/dev/null || true)
        if [[ -n "$all_containers" ]]; then
            echo "$all_containers"
        else
            echo -e "${YELLOW}⚠️  No Nexus nodes found${NC}"
        fi
        
        # Summary
        local running stopped
        running=$(docker ps --filter "name=$CONTAINER_PREFIX-" --format "{{.Names}}" 2>/dev/null | wc -l)
        stopped=$(docker ps -a --filter "name=$CONTAINER_PREFIX-" --filter "status=exited" --format "{{.Names}}" 2>/dev/null | wc -l)
        echo
        echo -e "${GREEN}Running: $running${NC} | ${YELLOW}Stopped: $stopped${NC}"
    fi
}

# Function to remove specific node or all nodes
remove_node() {
    local node_id="${1:-}"
    
    if [[ "$node_id" == "all" ]]; then
        echo -e "${RED}🗑️  Removing all Nexus nodes...${NC}"
        read -p "Are you sure? This will remove all Nexus containers and logs. (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Stop all containers first
            stop_container "all"
            
            # Remove all containers
            local containers
            containers=$(docker ps -a --filter "name=$CONTAINER_PREFIX-" --format "{{.Names}}" 2>/dev/null || true)
            if [[ -n "$containers" ]]; then
                while IFS= read -r container; do
                    echo -e "${YELLOW}Removing $container...${NC}"
                    docker rm "$container" >/dev/null 2>&1 || true
                    # Remove log directory
                    rm -rf "$HOME/nexus/logs/$container" 2>/dev/null || true
                done <<< "$containers"
                echo -e "${GREEN}✅ All Nexus nodes removed${NC}"
            fi
        else
            echo -e "${CYAN}Operation cancelled${NC}"
        fi
    else
        local container_name
        container_name=$(get_container_name "$node_id")
        echo -e "${RED}🗑️  Removing node $container_name...${NC}"
        read -p "Are you sure? This will remove the container and its logs. (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Stop container first
            stop_container "$node_id"
            # Remove container
            docker rm "$container_name" >/dev/null 2>&1 || true
            # Remove log directory
            rm -rf "$HOME/nexus/logs/$container_name" 2>/dev/null || true
            echo -e "${GREEN}✅ Node $container_name removed${NC}"
        else
            echo -e "${CYAN}Operation cancelled${NC}"
        fi
}

# Main command handling
case "${1:-}" in
    "register-user")
        shift
        echo -e "${GREEN}🔐 Registering user...${NC}"
        run_nexus_docker "" "register-user" "$@"
        ;;
    "register-node")
        shift
        local node_id="${1:-}"
        echo -e "${GREEN}🖥️  Registering node...${NC}"
        run_nexus_docker "$node_id" "register-node"
        ;;
    "start")
        shift
        local node_id="${1:-}"
        echo -e "${GREEN}🚀 Starting Nexus proving...${NC}"
        run_nexus_docker "$node_id" "start"
        echo -e "${YELLOW}Use 'nexus logs $node_id' to view output${NC}"
        ;;
    "stop")
        shift
        local node_id="${1:-all}"
        stop_container "$node_id"
        ;;
    "status")
        shift
        local node_id="${1:-}"
        check_status "$node_id"
        ;;
    "logs")
        shift
        local node_id="${1:-}"
        show_logs "$node_id"
        ;;
    "remove")
        shift
        local node_id="${1:-}"
        if [[ -z "$node_id" ]]; then
            echo -e "${RED}❌ Please specify node ID or 'all'${NC}"
            echo "Usage: nexus remove <node_id|all>"
            exit 1
        fi
        remove_node "$node_id"
        ;;
    "logout")
        shift
        local node_id="${1:-}"
        echo -e "${YELLOW}🔐 Clearing credentials...${NC}"
        run_nexus_docker "$node_id" "logout"
        ;;
    "shell")
        shift
        local node_id="${1:-1}"
        local container_name
        container_name=$(get_container_name "$node_id")
        echo -e "${BLUE}🐚 Opening shell in $container_name...${NC}"
        docker run -it --rm \
            -v "$HOME/.nexus:/root/.nexus" \
            -v "$HOME/nexus/logs/$container_name:/root/.nexus/logs" \
            "$DOCKER_IMAGE" \
            /bin/bash
        ;;
    *)
        echo "🚀 Nexus Docker CLI Commands (Multi-Node Support):"
        echo
        echo "Registration:"
        echo "  nexus register-user --wallet-address <your-wallet-address>"
        echo "  nexus register-node [node_id]        # Register specific node"
        echo
        echo "Node operations:"
        echo "  nexus start [node_id]                # Start proving (creates new if no ID)"
        echo "  nexus stop [node_id|all]             # Stop specific node or all"
        echo "  nexus status [node_id]               # Check status (all if no ID)"
        echo "  nexus logs [node_id]                 # View live logs (first node if no ID)"
        echo "  nexus remove <node_id|all>           # Remove node(s) and logs"
        echo "  nexus logout [node_id]               # Clear credentials"
        echo
        echo "Advanced:"
        echo "  nexus shell [node_id]                # Open shell in container"
        echo
        echo "Examples:"
        echo "  nexus start                          # Start nexus-node-1 (or create)"
        echo "  nexus start 2                        # Start nexus-node-2"
        echo "  nexus logs 1                         # View logs for nexus-node-1"
        echo "  nexus stop all                       # Stop all nodes"
        echo "  nexus remove all                     # Remove all nodes"
        echo
        ;;
esac
EOF
    
    chmod +x "$WORKDIR/nexus"
    
    # Create symlink for easy access
    if [[ ! -f "/usr/local/bin/nexus" ]]; then
        sudo ln -sf "$WORKDIR/nexus" /usr/local/bin/nexus 2>/dev/null || {
            print_color "$YELLOW" "⚠️  Could not create global symlink (sudo required)"
            print_color "$CYAN" "Add to PATH: export PATH=\"$WORKDIR:\$PATH\""
        }
    fi
    
    print_color "$GREEN" "✅ Configuration files generated"
    log "Configuration files created in $WORKDIR"
}

# Setup wallet configuration
setup_wallet() {
    print_color "$BLUE" "💳 Setting up wallet configuration..."
    
    echo
    print_color "$CYAN" "🌐 Nexus Network Information (Testnet 3):"
    echo "• Chain ID: $CHAIN_ID"
    echo "• RPC: $RPC_HTTP"
    echo "• Explorer: $EXPLORER_URL"
    echo "• Faucet: $FAUCET_URL"
    echo
    print_color "$CYAN" "Wallet setup options:"
    echo "1. Use existing registered credentials"
    echo "2. Set up for manual registration later"
    echo "3. Skip wallet setup (configure later)"
    echo
    
    read -p "Choose option (1-3): " wallet_option
    
    case $wallet_option in
        1)
            print_color "$BLUE" "🔍 Checking for existing credentials..."
            if [[ -f "$CREDENTIALS_FILE" ]]; then
                print_color "$GREEN" "✅ Found existing credentials at $CREDENTIALS_FILE"
                
                if command -v jq >/dev/null 2>&1; then
                    local user_id node_id
                    user_id=$(jq -r '.user_id // "Not available"' "$CREDENTIALS_FILE" 2>/dev/null)
                    node_id=$(jq -r '.node_id // "Not available"' "$CREDENTIALS_FILE" 2>/dev/null)
                    print_color "$CYAN" "User ID: $user_id"
                    print_color "$CYAN" "Node ID: $node_id"
                else
                    print_color "$CYAN" "Credentials file found. Install 'jq' to view details."
                fi
            else
                print_color "$YELLOW" "⚠️  No existing credentials found at $CREDENTIALS_FILE"
                print_color "$CYAN" "You'll need to register your user and node after installation:"
                echo "• Run: nexus register-user --wallet-address <your-wallet-address>"
                echo "• Run: nexus register-node"
            fi
            ;;
        2)
            print_color "$BLUE" "📝 Creating directory for credentials..."
            mkdir -p "$NEXUS_CONFIG_DIR"
            print_color "$CYAN" "Directory created: $NEXUS_CONFIG_DIR"
            print_color "$CYAN" "After installation, register with:"
            echo "• nexus register-user --wallet-address <your-wallet-address>"
            echo "• nexus register-node"
            echo "• Credentials will be saved to: $CREDENTIALS_FILE"
            ;;
        3)
            print_color "$CYAN" "⏭️  Skipping wallet setup"
            ;;
        *)
            print_color "$YELLOW" "Invalid option. Skipping wallet setup."
            ;;
    esac
    
    log "Wallet setup option $wallet_option selected"
}

# Post-installation steps
post_install() {
    print_color "$BLUE" "🎯 Completing installation..."
    
    # Create quick access commands
    cat > "$WORKDIR/nexus-commands.sh" << 'EOF'
#!/bin/bash

# Quick Nexus Docker CLI commands (Multi-Node Support)
echo "🚀 Nexus Docker CLI Commands (Multi-Node Support):"
echo
echo "Registration:"
echo "  nexus register-user --wallet-address <your-wallet-address>"
echo "  nexus register-node [node_id]        # Register specific node"
echo
echo "Node operations:"
echo "  nexus start [node_id]                # Start proving (creates new if no ID)"
echo "  nexus stop [node_id|all]             # Stop specific node or all"
echo "  nexus status [node_id]               # Check status (all if no ID)"
echo "  nexus logs [node_id]                 # View live logs (first node if no ID)"
echo "  nexus remove <node_id|all>           # Remove node(s) and logs"
echo "  nexus logout [node_id]               # Clear credentials"
echo
echo "Advanced:"
echo "  nexus shell [node_id]                # Open shell in container"
echo
echo "Examples:"
echo "  nexus start                          # Start nexus-node-1 (or create)"
echo "  nexus start 2                        # Start nexus-node-2"
echo "  nexus logs 1                         # View logs for nexus-node-1"
echo "  nexus stop all                       # Stop all nodes"
echo "  nexus remove all                     # Remove all nodes"
echo
echo "View credentials:"
echo "  cat ~/.nexus/credentials.json"
echo
echo "Check Docker containers:"
echo "  docker ps | grep nexus-node"
EOF
    
    chmod +x "$WORKDIR/nexus-commands.sh"
    
    print_color "$GREEN" "✅ Installation completed successfully!"
    log "Post-installation completed"
}

# Display completion message
display_completion() {
    echo
    print_color "$GREEN" "╔═══════════════════════════════════════════════════════════════╗"
    print_color "$GREEN" "║                    INSTALLATION COMPLETE! 🎉                 ║"
    print_color "$GREEN" "╚═══════════════════════════════════════════════════════════════╝"
    echo
    print_color "$CYAN" "📍 Installation directory: $WORKDIR"
    print_color "$CYAN" "📱 Credentials location: $CREDENTIALS_FILE"
    print_color "$CYAN" "📋 Log file: $LOG_FILE"
    print_color "$CYAN" "🐳 Docker image: $DOCKER_IMAGE"
    print_color "$CYAN" "🔧 Installation mode: $INSTALL_MODE"
    print_color "$CYAN" "📦 Container prefix: $CONTAINER_PREFIX"
    echo
    print_color "$YELLOW" "Next steps:"
    echo "1. Register your wallet: nexus register-user --wallet-address <your-address>"
    echo "2. Register your node: nexus register-node [node_id]"
    echo "3. Start proving: nexus start [node_id]"
    echo "4. View logs: nexus logs [node_id]"
    echo "5. Check status: nexus status"
    echo
    print_color "$BLUE" "🚀 Multi-Node Support:"
    echo "• Each node runs in separate container: nexus-node-1, nexus-node-2, etc."
    echo "• Independent logs: ~/nexus/logs/nexus-node-X/"
    echo "• Easy management: start, stop, remove individual nodes"
    echo "• Use 'nexus status' to see all nodes"
    echo
    print_color "$BLUE" "🐳 All operations run in Docker containers for maximum compatibility"
    print_color "$BLUE" "📚 Quick reference: $WORKDIR/nexus-commands.sh"
    print_color "$CYAN" "🌐 Network: Nexus Testnet 3 (Chain ID: $CHAIN_ID)"
    echo
}

# Error handler
cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        print_color "$RED" "❌ Installation failed with exit code: $exit_code"
        log "Installation failed with exit code: $exit_code"
        
        print_color "$YELLOW" "Cleaning up partial installation..."
        # Clean up Docker image if build failed
        docker rmi "$DOCKER_IMAGE" 2>/dev/null || true
        log "Cleanup completed"
    fi
    exit $exit_code
}

# Main installation function
main() {
    trap cleanup_on_error ERR
    
    display_banner
    check_root
    check_requirements
    install_docker
    create_directories
    build_docker_image
    generate_config
    setup_wallet
    post_install
    display_completion
    
    log "Nexus V3 Docker installation completed successfully"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
