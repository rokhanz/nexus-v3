#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════════
#                              INSTALLATION MODULE
# ═══════════════════════════════════════════════════════════════════════════════
# Description: Nexus network installation and dependency setup
# Dependencies: common.sh, tui.sh
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent double-loading
[[ -n "${NEXUS_INSTALL_LOADED:-}" ]] && return 0
readonly NEXUS_INSTALL_LOADED=1

# Source dependencies
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tui.sh"

# ═══════════════════════════════════════════════════════════════════════════════
#                            INSTALLATION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Main installation orchestrator
install_nexus_system() {
    echo -e "${CYAN}🚀 Starting Nexus V3 Installation${NC}"
    echo -e "${CYAN}══════════════════════════════════${NC}"
    
    # Pre-installation checks
    if ! pre_installation_checks; then
        echo -e "${RED}❌ Pre-installation checks failed${NC}"
        return 1
    fi
    
    # Setup directory structure
    setup_directory_structure
    
    # Install dependencies
    install_dependencies
    
    # Install Docker if needed
    install_docker_if_needed
    
    # Download and setup Nexus
    download_nexus_files
    
    # Configure system
    configure_nexus_system
    
    echo -e "${GREEN}✅ Nexus installation completed successfully!${NC}"
    log_activity "Nexus installation completed"
    
    return 0
}

# Pre-installation system checks
pre_installation_checks() {
    echo -e "${CYAN}🔍 Running pre-installation checks...${NC}"
    
    local checks_passed=true
    
    # Check if running as root
    check_root_user
    
    # Check system requirements
    if ! check_system_requirements; then
        checks_passed=false
    fi
    
    # Check available disk space
    if ! check_disk_space; then
        checks_passed=false
    fi
    
    # Check network connectivity
    if ! check_network_connectivity; then
        checks_passed=false
    fi
    
    if [[ "$checks_passed" == "true" ]]; then
        echo -e "${GREEN}✅ All pre-installation checks passed${NC}"
        return 0
    else
        echo -e "${RED}❌ Some pre-installation checks failed${NC}"
        return 1
    fi
}

# Check system requirements
check_system_requirements() {
    echo -e "${CYAN}   Checking system requirements...${NC}"
    
    # Check architecture
    local arch
    arch=$(uname -m)
    if [[ "$arch" != "x86_64" && "$arch" != "amd64" ]]; then
        echo -e "${RED}   ❌ Unsupported architecture: $arch${NC}"
        echo -e "${YELLOW}   Required: x86_64 or amd64${NC}"
        return 1
    fi
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        echo -e "${YELLOW}   ⚠️  Could not detect OS version${NC}"
    fi
    
    # Check for basic tools
    local required_tools=("curl" "wget" "tar" "ps")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo -e "${RED}   ❌ Missing required tool: $tool${NC}"
            return 1
        fi
    done
    
    echo -e "${GREEN}   ✅ System requirements met${NC}"
    return 0
}

# Check available disk space
check_disk_space() {
    echo -e "${CYAN}   Checking disk space...${NC}"
    
    local required_gb=5
    local available_gb
    
    if command -v df >/dev/null 2>&1; then
        available_gb=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//' 2>/dev/null || echo "0")
        
        if [[ "$available_gb" -lt "$required_gb" ]]; then
            echo -e "${RED}   ❌ Insufficient disk space${NC}"
            echo -e "${YELLOW}   Required: ${required_gb}GB, Available: ${available_gb}GB${NC}"
            return 1
        fi
        
        echo -e "${GREEN}   ✅ Sufficient disk space (${available_gb}GB available)${NC}"
    else
        echo -e "${YELLOW}   ⚠️  Could not check disk space${NC}"
    fi
    
    return 0
}

# Check network connectivity
check_network_connectivity() {
    echo -e "${CYAN}   Checking network connectivity...${NC}"
    
    local test_hosts=("github.com" "docker.com")
    
    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
            echo -e "${GREEN}   ✅ Network connectivity verified${NC}"
            return 0
        fi
    done
    
    echo -e "${RED}   ❌ Network connectivity issues${NC}"
    echo -e "${YELLOW}   Please check your internet connection${NC}"
    return 1
}

# Install system dependencies
install_dependencies() {
    echo -e "${CYAN}🔧 Installing system dependencies...${NC}"
    
    # Detect package manager
    if command -v apt-get >/dev/null 2>&1; then
        install_apt_dependencies
    elif command -v yum >/dev/null 2>&1; then
        install_yum_dependencies
    elif command -v pacman >/dev/null 2>&1; then
        install_pacman_dependencies
    else
        echo -e "${YELLOW}⚠️  Could not detect package manager${NC}"
        echo -e "${CYAN}Please install curl, wget, jq manually${NC}"
    fi
}

# Install dependencies using apt (Debian/Ubuntu)
install_apt_dependencies() {
    echo -e "${CYAN}   Using apt package manager...${NC}"
    
    # Update package list
    if sudo apt-get update -y >/dev/null 2>&1; then
        echo -e "${GREEN}   ✅ Package list updated${NC}"
    else
        echo -e "${YELLOW}   ⚠️  Could not update package list${NC}"
    fi
    
    # Install packages
    local packages=("curl" "wget" "jq" "ca-certificates" "gnupg" "lsb-release")
    
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            echo -e "${CYAN}   Installing $package...${NC}"
            if sudo apt-get install -y "$package" >/dev/null 2>&1; then
                echo -e "${GREEN}   ✅ $package installed${NC}"
            else
                echo -e "${YELLOW}   ⚠️  Could not install $package${NC}"
            fi
        else
            echo -e "${GREEN}   ✅ $package already installed${NC}"
        fi
    done
}

# Install dependencies using yum (RHEL/CentOS)
install_yum_dependencies() {
    echo -e "${CYAN}   Using yum package manager...${NC}"
    
    local packages=("curl" "wget" "jq" "ca-certificates")
    
    for package in "${packages[@]}"; do
        if ! rpm -q "$package" >/dev/null 2>&1; then
            echo -e "${CYAN}   Installing $package...${NC}"
            if sudo yum install -y "$package" >/dev/null 2>&1; then
                echo -e "${GREEN}   ✅ $package installed${NC}"
            else
                echo -e "${YELLOW}   ⚠️  Could not install $package${NC}"
            fi
        else
            echo -e "${GREEN}   ✅ $package already installed${NC}"
        fi
    done
}

# Install dependencies using pacman (Arch Linux)
install_pacman_dependencies() {
    echo -e "${CYAN}   Using pacman package manager...${NC}"
    
    local packages=("curl" "wget" "jq" "ca-certificates")
    
    # Update package database
    if sudo pacman -Sy >/dev/null 2>&1; then
        echo -e "${GREEN}   ✅ Package database updated${NC}"
    fi
    
    for package in "${packages[@]}"; do
        if ! pacman -Q "$package" >/dev/null 2>&1; then
            echo -e "${CYAN}   Installing $package...${NC}"
            if sudo pacman -S --noconfirm "$package" >/dev/null 2>&1; then
                echo -e "${GREEN}   ✅ $package installed${NC}"
            else
                echo -e "${YELLOW}   ⚠️  Could not install $package${NC}"
            fi
        else
            echo -e "${GREEN}   ✅ $package already installed${NC}"
        fi
    done
}

# Install Docker if needed
install_docker_if_needed() {
    echo -e "${CYAN}🐳 Checking Docker installation...${NC}"
    
    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Docker is already installed and running${NC}"
            check_docker_compose
            return 0
        else
            echo -e "${YELLOW}⚠️  Docker is installed but not running${NC}"
            start_docker_service
        fi
    else
        echo -e "${CYAN}Installing Docker...${NC}"
        install_docker_engine
    fi
    
    check_docker_compose
}

# Install Docker engine
install_docker_engine() {
    if command -v apt-get >/dev/null 2>&1; then
        install_docker_apt
    elif command -v yum >/dev/null 2>&1; then
        install_docker_yum
    else
        install_docker_generic
    fi
}

# Install Docker using apt
install_docker_apt() {
    echo -e "${CYAN}   Installing Docker via apt...${NC}"
    
    # Add Docker GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    
    # Update and install
    sudo apt-get update >/dev/null 2>&1
    if sudo apt-get install -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1; then
        echo -e "${GREEN}   ✅ Docker installed successfully${NC}"
        setup_docker_permissions
        start_docker_service
    else
        echo -e "${RED}   ❌ Docker installation failed${NC}"
        return 1
    fi
}

# Install Docker using yum
install_docker_yum() {
    echo -e "${CYAN}   Installing Docker via yum...${NC}"
    
    # Add Docker repository
    sudo yum install -y yum-utils >/dev/null 2>&1
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >/dev/null 2>&1
    
    # Install Docker
    if sudo yum install -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1; then
        echo -e "${GREEN}   ✅ Docker installed successfully${NC}"
        setup_docker_permissions
        start_docker_service
    else
        echo -e "${RED}   ❌ Docker installation failed${NC}"
        return 1
    fi
}

# Generic Docker installation
install_docker_generic() {
    echo -e "${CYAN}   Installing Docker via generic script...${NC}"
    
    if curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh >/dev/null 2>&1; then
        echo -e "${GREEN}   ✅ Docker installed successfully${NC}"
        setup_docker_permissions
        start_docker_service
        rm -f get-docker.sh
    else
        echo -e "${RED}   ❌ Docker installation failed${NC}"
        return 1
    fi
}

# Setup Docker permissions
setup_docker_permissions() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${CYAN}   Setting up Docker permissions...${NC}"
        sudo usermod -aG docker "$USER" 2>/dev/null || true
        echo -e "${YELLOW}   ⚠️  Please log out and log back in to use Docker without sudo${NC}"
    fi
}

# Start Docker service
start_docker_service() {
    echo -e "${CYAN}   Starting Docker service...${NC}"
    
    if sudo systemctl start docker >/dev/null 2>&1 && sudo systemctl enable docker >/dev/null 2>&1; then
        echo -e "${GREEN}   ✅ Docker service started${NC}"
    elif sudo service docker start >/dev/null 2>&1; then
        echo -e "${GREEN}   ✅ Docker service started${NC}"
    else
        echo -e "${YELLOW}   ⚠️  Please start Docker service manually${NC}"
    fi
}

# Check Docker Compose
check_docker_compose() {
    echo -e "${CYAN}   Checking Docker Compose...${NC}"
    
    if command -v docker-compose >/dev/null 2>&1; then
        echo -e "${GREEN}   ✅ Docker Compose (standalone) available${NC}"
    elif docker compose version >/dev/null 2>&1; then
        echo -e "${GREEN}   ✅ Docker Compose (plugin) available${NC}"
    else
        install_docker_compose
    fi
}

# Install Docker Compose
install_docker_compose() {
    echo -e "${CYAN}   Installing Docker Compose...${NC}"
    
    local compose_version="2.20.0"
    local arch
    arch=$(uname -m)
    
    if curl -L "https://github.com/docker/compose/releases/download/v${compose_version}/docker-compose-$(uname -s)-${arch}" -o /tmp/docker-compose 2>/dev/null; then
        sudo mv /tmp/docker-compose /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        echo -e "${GREEN}   ✅ Docker Compose installed${NC}"
    else
        echo -e "${YELLOW}   ⚠️  Could not install Docker Compose${NC}"
        echo -e "${CYAN}   Docker Compose plugin should work with newer Docker versions${NC}"
    fi
}

# Download Nexus files
download_nexus_files() {
    echo -e "${CYAN}📥 Downloading Nexus files...${NC}"
    
    # Create working directory
    mkdir -p "$WORKDIR"
    cd "$WORKDIR" || return 1
    
    # Download main files
    local files=(
        "docker-compose.yml"
        "run.sh"
        "uninstall.sh"
        "credentials-generator.sh"
    )
    
    for file in "${files[@]}"; do
        echo -e "${CYAN}   Downloading $file...${NC}"
        if curl -fsSL "$GITHUB_RAW/$file" -o "$file"; then
            echo -e "${GREEN}   ✅ $file downloaded${NC}"
            chmod +x "$file" 2>/dev/null || true
        else
            echo -e "${RED}   ❌ Failed to download $file${NC}"
            return 1
        fi
    done
    
    echo -e "${GREEN}✅ All files downloaded successfully${NC}"
    return 0
}

# Configure Nexus system
configure_nexus_system() {
    echo -e "${CYAN}⚙️  Configuring Nexus system...${NC}"
    
    # Generate credentials if they don't exist
    if [[ ! -f "$CREDENTIALS_FILE" ]]; then
        echo -e "${CYAN}   Generating new credentials...${NC}"
        generate_credentials
    else
        echo -e "${GREEN}   ✅ Using existing credentials${NC}"
    fi
    
    # Setup environment
    setup_environment_config
    
    echo -e "${GREEN}✅ Nexus system configured${NC}"
    return 0
}

# Generate credentials
generate_credentials() {
    if [[ -f "$WORKDIR/credentials-generator.sh" ]]; then
        cd "$WORKDIR" || return 1
        if bash credentials-generator.sh; then
            echo -e "${GREEN}   ✅ Credentials generated${NC}"
            
            # Backup credentials
            backup_credentials
        else
            echo -e "${RED}   ❌ Failed to generate credentials${NC}"
            return 1
        fi
    else
        echo -e "${RED}   ❌ Credentials generator not found${NC}"
        return 1
    fi
}

# Backup credentials
backup_credentials() {
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        # Try home backup first
        if cp "$CREDENTIALS_FILE" "$HOME/backup/credentials.json" 2>/dev/null; then
            echo -e "${GREEN}   ✅ Credentials backed up to $HOME/backup/${NC}"
        elif cp "$CREDENTIALS_FILE" "$WORKDIR/backup/credentials.json" 2>/dev/null; then
            echo -e "${GREEN}   ✅ Credentials backed up to project backup${NC}"
        else
            echo -e "${YELLOW}   ⚠️  Could not backup credentials${NC}"
        fi
    fi
}

# Setup environment configuration
setup_environment_config() {
    echo -e "${CYAN}   Setting up environment configuration...${NC}"
    
    # Create environment file if needed
    local env_file="$WORKDIR/.env"
    
    cat > "$env_file" << EOF
# Nexus V3 Environment Configuration
CHAIN_ID=$CHAIN_ID
RPC_HTTP=$RPC_HTTP

# Generated on: $(now_jakarta)
EOF
    
    echo -e "${GREEN}   ✅ Environment configured${NC}"
}

# Export functions for use by other modules
export -f install_nexus_system pre_installation_checks
