#!/bin/bash

# Nexus V3 Installation Script
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
NEXUS_VERSION="latest"
WORKDIR="$HOME/nexus"
NEXUS_CONFIG_DIR="$HOME/.nexus"
CREDENTIALS_FILE="$HOME/.nexus/credentials.json"
DOCKER_IMAGE="nexusxyz/nexus"
LOG_FILE="$HOME/nexus-install.log"

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
            print_color "$CYAN" "Exiting installation..."
            exit 1
        fi
    fi
}

# Check system requirements
check_requirements() {
    print_color "$BLUE" "🔍 Checking system requirements..."
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        print_color "$RED" "❌ Unable to detect OS. This script supports Linux only."
        exit 1
    fi
    
    # Check available disk space (at least 10GB)
    available_space=$(df "$HOME" | awk 'NR==2 {print $4}')
    required_space=10485760  # 10GB in KB
    
    if [[ $available_space -lt $required_space ]]; then
        print_color "$RED" "❌ Insufficient disk space. At least 10GB required."
        exit 1
    fi
    
    # Check memory (at least 2GB)
    total_mem=$(free -m | awk 'NR==2{print $2}')
    if [[ $total_mem -lt 1800 ]]; then
        print_color "$YELLOW" "⚠️  Warning: Less than 2GB RAM detected. Performance may be affected."
    fi
    
    print_color "$GREEN" "✅ System requirements check passed"
    log "System requirements verified"
}

# Install Docker if not present
install_docker() {
    if command -v docker &> /dev/null; then
        print_color "$GREEN" "✅ Docker is already installed"
        log "Docker found: $(docker --version)"
        return 0
    fi
    
    print_color "$BLUE" "🐳 Installing Docker..."
    log "Starting Docker installation"
    
    # Detect OS and install Docker accordingly
    if [[ -f /etc/debian_version ]]; then
        # Debian/Ubuntu
        sudo apt-get update
        sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
        
        # Add Docker's official GPG key
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        
        # Add Docker repository
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io
        
    elif [[ -f /etc/redhat-release ]]; then
        # CentOS/RHEL/Fedora
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        sudo yum install -y docker-ce docker-ce-cli containerd.io
        
    else
        print_color "$RED" "❌ Unsupported OS for automatic Docker installation"
        print_color "$YELLOW" "Please install Docker manually and run this script again"
        exit 1
    fi
    
    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Add user to docker group
    sudo usermod -aG docker "$USER"
    
    print_color "$GREEN" "✅ Docker installed successfully"
    print_color "$YELLOW" "⚠️  Please log out and log back in for Docker group changes to take effect"
    log "Docker installation completed"
}

# Create necessary directories
create_directories() {
    print_color "$BLUE" "📁 Creating directories..."
    
    mkdir -p "$WORKDIR"
    mkdir -p "$WORKDIR/data"
    mkdir -p "$WORKDIR/logs"
    mkdir -p "$WORKDIR/config"
    
    print_color "$GREEN" "✅ Directories created"
    log "Directory structure created at $WORKDIR"
}

# Pull Docker image
pull_docker_image() {
    print_color "$BLUE" "📥 Pulling Nexus Docker image..."
    
    if docker pull "$DOCKER_IMAGE:$NEXUS_VERSION"; then
        print_color "$GREEN" "✅ Docker image pulled successfully"
        log "Docker image $DOCKER_IMAGE:$NEXUS_VERSION pulled"
    else
        print_color "$RED" "❌ Failed to pull Docker image"
        log "ERROR: Failed to pull Docker image"
        exit 1
    fi
}

# Generate configuration files
generate_config() {
    print_color "$BLUE" "⚙️  Generating configuration files..."
    
    # Create docker-compose.yml
    cat > "$WORKDIR/docker-compose.yml" << EOF
version: '3.8'

services:
  nexus-node:
    image: $DOCKER_IMAGE:$NEXUS_VERSION
    container_name: nexus-node-1
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - ./data:/app/data
      - ./logs:/app/logs
    environment:
      - NODE_ENV=production
      - LOG_LEVEL=info
    networks:
      - nexus-network

networks:
  nexus-network:
    driver: bridge
EOF

    # Create .env file
    cat > "$WORKDIR/.env" << EOF
# Nexus Node Configuration
NEXUS_VERSION=$NEXUS_VERSION
NODE_NAME=nexus-node-1
NODE_PORT=8080

# Logging
LOG_LEVEL=info
LOG_FILE_SIZE=100MB
LOG_FILE_COUNT=5

# Network
NETWORK_NAME=nexus-network
EOF

    # Create startup script
    cat > "$WORKDIR/start-node.sh" << 'EOF'
#!/bin/bash

cd "$(dirname "$0")"

echo "Starting Nexus node..."
docker-compose up -d

echo "Waiting for node to start..."
sleep 10

echo "Node status:"
docker-compose ps

echo "Node logs:"
docker-compose logs --tail=20 nexus-node
EOF

    chmod +x "$WORKDIR/start-node.sh"
    
    # Create stop script
    cat > "$WORKDIR/stop-node.sh" << 'EOF'
#!/bin/bash

cd "$(dirname "$0")"

echo "Stopping Nexus node..."
docker-compose down

echo "Node stopped."
EOF

    chmod +x "$WORKDIR/stop-node.sh"
    
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
            print_color "$BLUE" "� Checking for existing credentials..."
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
                echo "• Run: nexus register-user"
                echo "• Run: nexus register-node"
            fi
            ;;
        2)
            print_color "$BLUE" "📝 Creating directory for credentials..."
            mkdir -p "$NEXUS_CONFIG_DIR"
            print_color "$CYAN" "Directory created: $NEXUS_CONFIG_DIR"
            print_color "$CYAN" "After installation, register with:"
            echo "• nexus register-user"
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

# Create systemd service (optional)
create_service() {
    print_color "$BLUE" "🔧 Creating systemd service..."
    
    read -p "Create systemd service for auto-start? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo tee /etc/systemd/system/nexus-node.service > /dev/null << EOF
[Unit]
Description=Nexus Node Service
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$WORKDIR
ExecStart=$WORKDIR/start-node.sh
ExecStop=$WORKDIR/stop-node.sh
User=$USER
Group=$USER

[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable nexus-node.service
        
        print_color "$GREEN" "✅ Systemd service created and enabled"
        log "Systemd service created"
    else
        print_color "$CYAN" "Skipping systemd service creation"
    fi
}

# Verify installation
verify_installation() {
    print_color "$BLUE" "🔍 Verifying installation..."
    
    local errors=0
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_color "$RED" "❌ Docker not found"
        ((errors++))
    fi
    
    # Check directories
    if [[ ! -d "$WORKDIR" ]]; then
        print_color "$RED" "❌ Working directory not found"
        ((errors++))
    fi
    
    # Check configuration files
    if [[ ! -f "$WORKDIR/docker-compose.yml" ]]; then
        print_color "$RED" "❌ Docker compose file not found"
        ((errors++))
    fi
    
    # Check Docker image
    if ! docker image inspect "$DOCKER_IMAGE:$NEXUS_VERSION" &> /dev/null; then
        print_color "$RED" "❌ Docker image not found"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        print_color "$GREEN" "✅ Installation verification passed"
        log "Installation verification successful"
        return 0
    else
        print_color "$RED" "❌ Installation verification failed ($errors errors)"
        log "Installation verification failed with $errors errors"
        return 1
    fi
}

# Start the node
start_node() {
    print_color "$BLUE" "🚀 Starting Nexus node..."
    
    cd "$WORKDIR"
    
    if ./start-node.sh; then
        print_color "$GREEN" "✅ Nexus node started successfully"
        log "Nexus node started"
        
        echo
        print_color "$CYAN" "Node information:"
        echo "• Working directory: $WORKDIR"
        echo "• Container name: nexus-node-1"
        echo "• Port: 8080"
        echo "• Status: $(docker ps --filter "name=nexus-node-1" --format "table {{.Status}}" | tail -n +2)"
        
    else
        print_color "$RED" "❌ Failed to start Nexus node"
        log "ERROR: Failed to start Nexus node"
        return 1
    fi
}

# Main installation process
main() {
    print_color "$MAGENTA" "🚀 Nexus V3 Installation Script"
    print_color "$CYAN" "Author: Rokhanz | Version: 3.0.0"
    echo
    
    log "Starting Nexus V3 installation"
    
    # Installation steps
    check_root
    check_requirements
    install_docker
    create_directories
    pull_docker_image
    generate_config
    setup_wallet
    create_service
    
    if verify_installation; then
        print_color "$GREEN" "🎉 Installation completed successfully!"
        
        read -p "Start the node now? (Y/n): " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            start_node
        fi
        
        echo
        print_color "$CYAN" "📋 Next steps:"
        echo "• Use './start-node.sh' to start the node"
        echo "• Use './stop-node.sh' to stop the node"
        echo "• Check logs with 'docker-compose logs nexus-node'"
        echo "• Access dashboard at http://localhost:8080"
        echo "• Use the main dashboard to manage your installation"
        
        log "Installation completed successfully"
        
    else
        print_color "$RED" "❌ Installation failed. Check the log file: $LOG_FILE"
        log "Installation failed"
        exit 1
    fi
}

# Error handling
trap 'print_color "$RED" "❌ Installation interrupted"; log "Installation interrupted"; exit 1' INT TERM

# Run main function
main "$@"
