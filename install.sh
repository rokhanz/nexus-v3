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
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
NEXUS_VERSION="latest"
WORKDIR="$HOME/nexus"
NEXUS_CONFIG_DIR="$HOME/.nexus"
CREDENTIALS_FILE="$HOME/.nexus/credentials.json"
NEXUS_CLI_URL="https://cli.nexus.xyz/"
DOCKER_IMAGE="nexusxyz/nexus-cli"
LOG_FILE="$HOME/nexus-install.log"

# Installation mode (will be set based on compatibility)
INSTALL_MODE=""  # "native" or "docker"

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
    print_color "$CYAN" "║                    NEXUS V3 INSTALLATION                      ║"
    print_color "$CYAN" "║                                                               ║"
    print_color "$CYAN" "║  ██████╗  ██████╗ ██╗  ██╗██╗  ██╗ █████╗ ███╗   ██╗███████╗ ║"
    print_color "$CYAN" "║  ██╔══██╗██╔═══██╗██║ ██╔╝██║  ██║██╔══██╗████╗  ██║╚══███╔╝ ║"
    print_color "$CYAN" "║  ██████╔╝██║   ██║█████╔╝ ███████║███████║██╔██╗ ██║  ███╔╝  ║"
    print_color "$CYAN" "║  ██╔══██╗██║   ██║██╔═██╗ ██╔══██║██╔══██║██║╚██╗██║ ███╔╝   ║"
    print_color "$CYAN" "║  ██║  ██║╚██████╔╝██║  ██╗██║  ██║██║  ██║██║ ╚████║███████╗ ║"
    print_color "$CYAN" "║  ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝ ║"
    print_color "$CYAN" "║                                                               ║"
    print_color "$CYAN" "║          🚀 Nexus CLI Installer v3.0.0 • by Rokhanz 🇮🇩      ║"
    print_color "$CYAN" "╚═══════════════════════════════════════════════════════════════╝"
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

# Install Nexus CLI
install_nexus_cli() {
    print_color "$BLUE" "📥 Installing Nexus CLI..."
    
    # Check if nexus-network command already exists
    if command -v nexus-network >/dev/null 2>&1; then
        print_color "$YELLOW" "⚠️  Nexus CLI already installed, updating..."
        log "Nexus CLI found, proceeding with update"
    fi
    
    # Download and install Nexus CLI using official script
    if curl -fsSL "$NEXUS_CLI_URL" | sh; then
        print_color "$GREEN" "✅ Nexus CLI installed successfully"
        log "Nexus CLI installed from $NEXUS_CLI_URL"
        
        # Source shell configuration to make nexus-network available
        if [[ -f "$HOME/.bashrc" ]]; then
            # shellcheck disable=SC1091
            source "$HOME/.bashrc" 2>/dev/null || true
        fi
        if [[ -f "$HOME/.zshrc" ]]; then
            # shellcheck disable=SC1091
            source "$HOME/.zshrc" 2>/dev/null || true
        fi
        
        # Verify installation
        if command -v nexus-network >/dev/null 2>&1; then
            local version
            version=$(nexus-network --version 2>/dev/null || echo "unknown")
            print_color "$GREEN" "✅ Nexus CLI verified: $version"
            log "Nexus CLI verification successful: $version"
            INSTALL_MODE="native"
        else
            print_color "$YELLOW" "⚠️  CLI installed but may require shell restart"
            log "WARNING: CLI installed but command not immediately available"
            INSTALL_MODE="native"
        fi
    else
        print_color "$RED" "❌ Failed to install Nexus CLI"
        log "ERROR: Failed to install Nexus CLI from $NEXUS_CLI_URL"
        exit 1
    fi
}

# Test Nexus CLI compatibility
test_nexus_compatibility() {
    print_color "$BLUE" "🧪 Testing Nexus CLI compatibility..."
    
    if [[ "$INSTALL_MODE" != "native" ]]; then
        print_color "$YELLOW" "⚠️  Skipping compatibility test - CLI not installed natively"
        return 0
    fi
    
    # Test if nexus-network can run without crashing
    local test_result=0
    if timeout 10s nexus-network --help >/dev/null 2>&1; then
        print_color "$GREEN" "✅ Nexus CLI compatibility test passed"
        log "Nexus CLI compatibility test successful"
        INSTALL_MODE="native"
    else
        test_result=$?
        print_color "$YELLOW" "⚠️  Nexus CLI compatibility test failed (exit code: $test_result)"
        print_color "$YELLOW" "This VPS may not support native Nexus CLI (common on some cloud providers)"
        log "WARNING: Nexus CLI compatibility test failed - using Docker fallback"
        
        # Ask user preference
        echo
        print_color "$CYAN" "Available options:"
        echo "1. Use Docker-based Nexus CLI (Recommended for VPS compatibility)"
        echo "2. Continue with native CLI (may have issues)"
        echo "3. Exit installation"
        echo
        
        read -p "Choose option (1-3): " compat_choice
        
        case $compat_choice in
            1)
                print_color "$BLUE" "🐳 Switching to Docker-based installation..."
                INSTALL_MODE="docker"
                install_docker_nexus
                ;;
            2)
                print_color "$YELLOW" "⚠️  Continuing with native CLI (may experience crashes)"
                INSTALL_MODE="native"
                ;;
            3)
                print_color "$CYAN" "Installation cancelled by user"
                exit 0
                ;;
            *)
                print_color "$YELLOW" "Invalid choice. Defaulting to Docker-based installation."
                INSTALL_MODE="docker"
                install_docker_nexus
                ;;
        esac
    fi
}

# Install Docker-based Nexus CLI
install_docker_nexus() {
    print_color "$BLUE" "🐳 Setting up Docker-based Nexus CLI..."
    
    # Ensure Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        print_color "$RED" "❌ Docker is required for Docker-based installation"
        exit 1
    fi
    
    # Create Docker wrapper script
    cat > "$HOME/.nexus/bin/nexus-cli" << 'EOF'
#!/bin/bash

# Docker-based Nexus CLI wrapper
DOCKER_IMAGE="nexusxyz/nexus-cli:latest"

# Ensure docker image is available
if ! docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then
    echo "⬇️  Pulling Nexus CLI Docker image..."
    docker pull "$DOCKER_IMAGE" || {
        echo "❌ Failed to pull Docker image. Using fallback method..."
        # Create a minimal Docker image if official doesn't exist
        docker run --rm -v "$HOME/.nexus:/root/.nexus" ubuntu:22.04 bash -c "
            apt-get update -qq && apt-get install -y curl
            cd /root/.nexus
            curl -fsSL https://cli.nexus.xyz/ | sh
        "
        DOCKER_IMAGE="ubuntu:22.04"
    fi
fi

# Mount nexus config directory and run command
docker run --rm -it \
    -v "$HOME/.nexus:/root/.nexus" \
    -v "$HOME/nexus:/root/nexus" \
    --network host \
    "$DOCKER_IMAGE" \
    nexus-cli "$@"
EOF
    
    chmod +x "$HOME/.nexus/bin/nexus-cli"
    
    # Create nexus-network alias
    ln -sf "$HOME/.nexus/bin/nexus-cli" "$HOME/.nexus/bin/nexus-network"
    
    print_color "$GREEN" "✅ Docker-based Nexus CLI installed"
    log "Docker-based Nexus CLI installation completed"
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

# Installation info
INSTALL_DATE=$(date '+%Y-%m-%d %H:%M:%S')
INSTALL_METHOD=$INSTALL_MODE
CLI_VERSION=latest
EOF
    
    # Create startup script with mode detection
    cat > "$WORKDIR/start-nexus.sh" << 'EOF'
#!/bin/bash

# Nexus Network Startup Script
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}🚀 Starting Nexus Network CLI...${NC}"

# Detect installation mode
INSTALL_MODE="native"
if [[ -f "$HOME/nexus/.env" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/nexus/.env" 2>/dev/null || true
    if [[ "$INSTALL_METHOD" == "docker" ]]; then
        INSTALL_MODE="docker"
        echo -e "${BLUE}ℹ️  Using Docker-based Nexus CLI${NC}"
    fi
fi

# Check if nexus-network is available
if ! command -v nexus-network >/dev/null 2>&1; then
    echo -e "${RED}❌ nexus-network command not found${NC}"
    if [[ "$INSTALL_MODE" == "docker" ]]; then
        echo -e "${YELLOW}Ensure Docker is running and try again${NC}"
    else
        echo -e "${YELLOW}Please restart your terminal or run: source ~/.bashrc${NC}"
    fi
    exit 1
fi

# Check if user is registered
if [[ -f "$HOME/.nexus/credentials.json" ]]; then
    echo -e "${GREEN}✅ Credentials found, starting node...${NC}"
    
    # Test compatibility before starting
    if nexus-network --help >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Starting Nexus proving...${NC}"
        nexus-network start
    else
        echo -e "${RED}❌ Nexus CLI compatibility issue detected${NC}"
        echo -e "${YELLOW}This VPS may not support native Nexus CLI${NC}"
        if [[ "$INSTALL_MODE" != "docker" ]]; then
            echo -e "${YELLOW}Consider reinstalling with Docker mode${NC}"
        fi
        exit 1
    fi
else
    echo -e "${YELLOW}⚠️  No credentials found${NC}"
    echo -e "${YELLOW}Please register first:${NC}"
    echo "  nexus-network register-user --wallet-address <your-wallet-address>"
    echo "  nexus-network register-node"
    echo "  nexus-network start"
fi
EOF
    
    chmod +x "$WORKDIR/start-nexus.sh"
    
    # Create stop script
    cat > "$WORKDIR/stop-nexus.sh" << 'EOF'
#!/bin/bash

# Nexus Network Stop Script
echo "🛑 Stopping Nexus Network CLI..."

# Check if nexus-network is available
if command -v nexus-network >/dev/null 2>&1; then
    nexus-network stop
    echo "✅ Nexus Network CLI stopped"
else
    echo "❌ nexus-network command not found"
    exit 1
fi
EOF
    
    chmod +x "$WORKDIR/stop-nexus.sh"
    
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
                echo "• Run: nexus-network register-user --wallet-address <your-wallet-address>"
                echo "• Run: nexus-network register-node"
            fi
            ;;
        2)
            print_color "$BLUE" "📝 Creating directory for credentials..."
            mkdir -p "$NEXUS_CONFIG_DIR"
            print_color "$CYAN" "Directory created: $NEXUS_CONFIG_DIR"
            print_color "$CYAN" "After installation, register with:"
            echo "• nexus-network register-user --wallet-address <your-wallet-address>"
            echo "• nexus-network register-node"
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

# Quick Nexus CLI commands
echo "🚀 Nexus Network CLI Commands:"
echo
echo "Registration:"
echo "  nexus-network register-user --wallet-address <your-wallet-address>"
echo "  nexus-network register-node"
echo
echo "Node operations:"
echo "  nexus-network start     # Start proving"
echo "  nexus-network stop      # Stop proving"
echo "  nexus-network status    # Check status"
echo "  nexus-network logout    # Clear credentials"
echo
echo "Quick scripts:"
echo "  ./start-nexus.sh        # Start with credential check"
echo "  ./stop-nexus.sh         # Stop proving"
echo
echo "View credentials:"
echo "  cat ~/.nexus/credentials.json"
EOF
    
    chmod +x "$WORKDIR/nexus-commands.sh"
    
    # Update .bashrc to include nexus in PATH if not already done
    if ! grep -q "nexus-network" "$HOME/.bashrc" 2>/dev/null; then
        echo "" >> "$HOME/.bashrc"
        echo "# Nexus Network CLI" >> "$HOME/.bashrc"
        echo "export PATH=\"\$HOME/.nexus:\$PATH\"" >> "$HOME/.bashrc"
    fi
    
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
    print_color "$CYAN" "🔧 Installation mode: $INSTALL_MODE"
    echo
    print_color "$YELLOW" "Next steps:"
    echo "1. Restart your terminal or run: source ~/.bashrc"
    echo "2. Register your wallet: nexus-network register-user --wallet-address <your-address>"
    echo "3. Register your node: nexus-network register-node"
    echo "4. Start proving: nexus-network start"
    echo "5. Or run: $WORKDIR/start-nexus.sh"
    echo
    if [[ "$INSTALL_MODE" == "docker" ]]; then
        print_color "$BLUE" "🐳 Note: Using Docker-based Nexus CLI for VPS compatibility"
    fi
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
        # Don't remove directories in case user has other data
        log "Cleanup completed - directories preserved"
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
    install_nexus_cli
    test_nexus_compatibility
    generate_config
    setup_wallet
    post_install
    display_completion
    
    log "Nexus V3 installation completed successfully"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
