#!/bin/bash

# Nexus V3 Uninstallation Script
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
DOCKER_IMAGE="nexusxyz/nexus"
LOG_FILE="$HOME/nexus-uninstall.log"
BACKUP_DIR="$HOME/nexus-backup-$(date +%Y%m%d-%H%M%S)"

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

# Show warning and get confirmation
show_warning() {
    print_color "$RED" "⚠️  WARNING: NEXUS UNINSTALLATION"
    print_color "$YELLOW" "This will permanently remove:"
    echo "• All Nexus nodes and containers"
    echo "• Docker images"
    echo "• Configuration files"
    echo "• Log files"
    echo "• Node data (blockchain data)"
    echo
    print_color "$CYAN" "Backup will be created at: $BACKUP_DIR"
    echo
    
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        print_color "$CYAN" "Uninstallation cancelled."
        exit 0
    fi
    
    echo
    read -p "Type 'DELETE' to confirm permanent removal: " final_confirm
    
    if [[ "$final_confirm" != "DELETE" ]]; then
        print_color "$CYAN" "Uninstallation cancelled."
        exit 0
    fi
    
    log "User confirmed uninstallation"
}

# Create backup before removal
create_backup() {
    print_color "$BLUE" "📦 Creating backup..."
    
    if [[ -d "$WORKDIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        
        # Backup configuration files
        if [[ -f "$WORKDIR/.env" ]]; then
            cp "$WORKDIR/.env" "$BACKUP_DIR/"
            log "Backed up .env file"
        fi
        
        if [[ -f "$WORKDIR/docker-compose.yml" ]]; then
            cp "$WORKDIR/docker-compose.yml" "$BACKUP_DIR/"
            log "Backed up docker-compose.yml"
        fi
        
        # Backup wallet configuration (if exists)
        if [[ -f "$WORKDIR/wallet.txt" ]]; then
            cp "$WORKDIR/wallet.txt" "$BACKUP_DIR/"
            log "Backed up wallet configuration"
        fi
        
        # Backup logs
        if [[ -d "$WORKDIR/logs" ]]; then
            cp -r "$WORKDIR/logs" "$BACKUP_DIR/"
            log "Backed up log files"
        fi
        
        # Create backup info file
        cat > "$BACKUP_DIR/backup-info.txt" << EOF
Nexus V3 Backup Information
Created: $(date)
Original location: $WORKDIR
Backup reason: Uninstallation

Contents:
- Configuration files (.env, docker-compose.yml)
- Wallet configuration (if exists)
- Log files
- This info file

To restore:
1. Copy files back to $WORKDIR
2. Run install.sh to reinstall system
3. Start nodes with docker-compose up -d
EOF
        
        print_color "$GREEN" "✅ Backup created at $BACKUP_DIR"
        log "Backup created successfully"
    else
        print_color "$YELLOW" "⚠️  No installation found to backup"
        log "No installation directory found"
    fi
}

# Stop all running containers
stop_containers() {
    print_color "$BLUE" "🛑 Stopping Nexus containers..."
    
    # Stop containers using docker-compose if compose file exists
    if [[ -f "$WORKDIR/docker-compose.yml" ]]; then
        cd "$WORKDIR"
        if docker-compose ps -q | grep -q .; then
            print_color "$YELLOW" "Stopping containers with docker-compose..."
            docker-compose down
            log "Stopped containers using docker-compose"
        else
            print_color "$CYAN" "No running containers found in compose"
        fi
    fi
    
    # Stop any remaining Nexus containers
    nexus_containers=$(docker ps -q --filter "name=nexus" 2>/dev/null || true)
    if [[ -n "$nexus_containers" ]]; then
        print_color "$YELLOW" "Stopping remaining Nexus containers..."
        echo "$nexus_containers" | xargs docker stop
        log "Stopped additional Nexus containers"
    fi
    
    print_color "$GREEN" "✅ All containers stopped"
}

# Remove containers
remove_containers() {
    print_color "$BLUE" "🗑️  Removing Nexus containers..."
    
    # Remove containers using docker-compose
    if [[ -f "$WORKDIR/docker-compose.yml" ]]; then
        cd "$WORKDIR"
        docker-compose rm -f
        log "Removed containers using docker-compose"
    fi
    
    # Remove any remaining Nexus containers
    nexus_containers=$(docker ps -aq --filter "name=nexus" 2>/dev/null || true)
    if [[ -n "$nexus_containers" ]]; then
        print_color "$YELLOW" "Removing remaining Nexus containers..."
        echo "$nexus_containers" | xargs docker rm -f
        log "Removed additional Nexus containers"
    fi
    
    print_color "$GREEN" "✅ All containers removed"
}

# Remove Docker images
remove_images() {
    print_color "$BLUE" "🗑️  Removing Nexus Docker images..."
    
    read -p "Remove Nexus Docker images? This will require re-download on reinstall (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Remove Nexus images
        nexus_images=$(docker images --filter "reference=nexusxyz/*" -q 2>/dev/null || true)
        if [[ -n "$nexus_images" ]]; then
            echo "$nexus_images" | xargs docker rmi -f
            log "Removed Nexus Docker images"
            print_color "$GREEN" "✅ Docker images removed"
        else
            print_color "$CYAN" "No Nexus images found"
        fi
        
        # Clean up dangling images
        dangling=$(docker images -f "dangling=true" -q 2>/dev/null || true)
        if [[ -n "$dangling" ]]; then
            echo "$dangling" | xargs docker rmi
            log "Cleaned up dangling images"
        fi
    else
        print_color "$CYAN" "Keeping Docker images"
        log "User chose to keep Docker images"
    fi
}

# Remove Docker networks
remove_networks() {
    print_color "$BLUE" "🗑️  Removing Nexus networks..."
    
    # Remove networks created by docker-compose
    if [[ -f "$WORKDIR/docker-compose.yml" ]]; then
        cd "$WORKDIR"
        # Extract network names from compose file
        networks=$(docker network ls --filter "name=nexus" --format "{{.Name}}" 2>/dev/null || true)
        if [[ -n "$networks" ]]; then
            echo "$networks" | xargs docker network rm 2>/dev/null || true
            log "Removed Nexus networks"
        fi
    fi
    
    print_color "$GREEN" "✅ Networks cleaned up"
}

# Remove volumes
remove_volumes() {
    print_color "$BLUE" "🗑️  Removing Docker volumes..."
    
    read -p "Remove Docker volumes? This will delete all blockchain data (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Remove named volumes
        nexus_volumes=$(docker volume ls --filter "name=nexus" --format "{{.Name}}" 2>/dev/null || true)
        if [[ -n "$nexus_volumes" ]]; then
            echo "$nexus_volumes" | xargs docker volume rm
            log "Removed Nexus volumes"
        fi
        
        # Remove anonymous volumes
        dangling_volumes=$(docker volume ls -f "dangling=true" -q 2>/dev/null || true)
        if [[ -n "$dangling_volumes" ]]; then
            echo "$dangling_volumes" | xargs docker volume rm
            log "Removed dangling volumes"
        fi
        
        print_color "$GREEN" "✅ Docker volumes removed"
    else
        print_color "$CYAN" "Keeping Docker volumes"
        log "User chose to keep Docker volumes"
    fi
}

# Remove installation directory
remove_installation() {
    print_color "$BLUE" "🗑️  Removing installation directory..."
    
    if [[ -d "$WORKDIR" ]]; then
        # Double check with user
        echo "About to remove: $WORKDIR"
        read -p "Confirm removal of installation directory? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$WORKDIR"
            log "Removed installation directory: $WORKDIR"
            print_color "$GREEN" "✅ Installation directory removed"
        else
            print_color "$CYAN" "Keeping installation directory"
            log "User chose to keep installation directory"
        fi
    else
        print_color "$CYAN" "Installation directory not found"
    fi
}

# Remove systemd service
remove_service() {
    print_color "$BLUE" "🗑️  Removing systemd service..."
    
    if [[ -f /etc/systemd/system/nexus-node.service ]]; then
        # Stop and disable service
        sudo systemctl stop nexus-node.service 2>/dev/null || true
        sudo systemctl disable nexus-node.service 2>/dev/null || true
        
        # Remove service file
        sudo rm -f /etc/systemd/system/nexus-node.service
        sudo systemctl daemon-reload
        
        log "Removed systemd service"
        print_color "$GREEN" "✅ Systemd service removed"
    else
        print_color "$CYAN" "No systemd service found"
    fi
}

# Clean up user configuration
cleanup_user_config() {
    print_color "$BLUE" "🧹 Cleaning up user configuration..."
    
    # Remove from docker group (optional)
    read -p "Remove user from docker group? This affects other Docker usage (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo gpasswd -d "$USER" docker 2>/dev/null || true
        log "Removed user from docker group"
        print_color "$YELLOW" "⚠️  Log out and back in for group changes to take effect"
    fi
    
    # Remove log files
    if [[ -f "$HOME/nexus-install.log" ]]; then
        rm -f "$HOME/nexus-install.log"
        log "Removed installation log"
    fi
    
    print_color "$GREEN" "✅ User configuration cleaned"
}

# Optional Docker removal
remove_docker() {
    print_color "$BLUE" "🐳 Docker removal (optional)..."
    
    read -p "Remove Docker completely? This affects all Docker usage on this system (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_color "$YELLOW" "⚠️  This will remove Docker and all containers/images/volumes!"
        read -p "Are you absolutely sure? Type 'REMOVE DOCKER' to confirm: " docker_confirm
        
        if [[ "$docker_confirm" == "REMOVE DOCKER" ]]; then
            # Detect OS and remove Docker
            if [[ -f /etc/debian_version ]]; then
                # Debian/Ubuntu
                sudo apt-get purge -y docker-ce docker-ce-cli containerd.io
                sudo apt-get autoremove -y
                sudo rm -rf /var/lib/docker
                sudo rm -rf /var/lib/containerd
                
            elif [[ -f /etc/redhat-release ]]; then
                # CentOS/RHEL/Fedora
                sudo yum remove -y docker-ce docker-ce-cli containerd.io
                sudo rm -rf /var/lib/docker
                sudo rm -rf /var/lib/containerd
            fi
            
            log "Docker completely removed"
            print_color "$GREEN" "✅ Docker removed completely"
        else
            print_color "$CYAN" "Docker removal cancelled"
        fi
    else
        print_color "$CYAN" "Keeping Docker installation"
    fi
}

# Verify removal
verify_removal() {
    print_color "$BLUE" "🔍 Verifying removal..."
    
    local items_remaining=0
    
    # Check for containers
    if docker ps -a --filter "name=nexus" --format "{{.Names}}" 2>/dev/null | grep -q nexus; then
        print_color "$YELLOW" "⚠️  Some Nexus containers still exist"
        ((items_remaining++))
    fi
    
    # Check for images
    if docker images --filter "reference=nexusxyz/*" --format "{{.Repository}}" 2>/dev/null | grep -q nexusxyz; then
        print_color "$YELLOW" "⚠️  Some Nexus images still exist"
        ((items_remaining++))
    fi
    
    # Check for directory
    if [[ -d "$WORKDIR" ]]; then
        print_color "$YELLOW" "⚠️  Installation directory still exists"
        ((items_remaining++))
    fi
    
    # Check for service
    if [[ -f /etc/systemd/system/nexus-node.service ]]; then
        print_color "$YELLOW" "⚠️  Systemd service still exists"
        ((items_remaining++))
    fi
    
    if [[ $items_remaining -eq 0 ]]; then
        print_color "$GREEN" "✅ Removal verification passed"
        log "Removal verification successful"
        return 0
    else
        print_color "$YELLOW" "⚠️  Some items may still exist ($items_remaining warnings)"
        log "Removal verification completed with $items_remaining warnings"
        return 1
    fi
}

# Show final summary
show_summary() {
    print_color "$MAGENTA" "📋 Uninstallation Summary"
    echo
    print_color "$GREEN" "✅ Completed tasks:"
    echo "• Stopped all Nexus containers"
    echo "• Removed containers and networks"
    echo "• Created backup at: $BACKUP_DIR"
    echo "• Cleaned up user configuration"
    echo "• Removed systemd service (if existed)"
    
    if [[ -d "$WORKDIR" ]]; then
        echo "• Installation directory preserved"
    else
        echo "• Removed installation directory"
    fi
    
    echo
    print_color "$CYAN" "💡 Notes:"
    echo "• Backup created for recovery purposes"
    echo "• Docker installation preserved (unless specifically removed)"
    echo "• To reinstall: download and run install.sh"
    echo "• To restore data: copy backup files to installation directory"
    
    if [[ -d "$BACKUP_DIR" ]]; then
        echo
        print_color "$BLUE" "📦 Backup location: $BACKUP_DIR"
        echo "Contains: configuration files, logs, and restore instructions"
    fi
    
    log "Uninstallation completed successfully"
}

# Main uninstallation process
main() {
    print_color "$MAGENTA" "🗑️  Nexus V3 Uninstallation Script"
    print_color "$CYAN" "Author: Rokhanz | Version: 3.0.0"
    echo
    
    log "Starting Nexus V3 uninstallation"
    
    # Uninstallation steps
    show_warning
    create_backup
    stop_containers
    remove_containers
    remove_images
    remove_networks
    remove_volumes
    remove_service
    remove_installation
    cleanup_user_config
    remove_docker
    
    verify_removal
    show_summary
    
    print_color "$GREEN" "🎉 Uninstallation completed!"
    echo
    print_color "$CYAN" "Thank you for using Nexus V3 Dashboard!"
}

# Error handling
trap 'print_color "$RED" "❌ Uninstallation interrupted"; log "Uninstallation interrupted"; exit 1' INT TERM

# Run main function
main "$@"
