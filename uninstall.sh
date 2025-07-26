#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════════
#                              UNINSTALL MODULE
# ═══════════════════════════════════════════════════════════════════════════════
# Description: Clean removal of Nexus system and Docker components
# Dependencies: common.sh, tui.sh
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent double-loading
[[ -n "${NEXUS_UNINSTALL_LOADED:-}" ]] && return 0
readonly NEXUS_UNINSTALL_LOADED=1

# Source dependencies
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tui.sh"

# ═══════════════════════════════════════════════════════════════════════════════
#                            UNINSTALL FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Main uninstall interface
uninstall_nexus_system() {
    clear_screen
    echo -e "${RED}🗑️  Nexus Uninstall Wizard${NC}"
    echo -e "${RED}═══════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  This will remove Nexus components from your system${NC}"
    echo ""
    echo -e "What would you like to uninstall?"
    echo ""
    echo -e "  ${RED}[1]${NC} Remove Nexus only (keep Docker)"
    echo -e "  ${RED}[2]${NC} Remove Nexus and clean Docker images"
    echo -e "  ${RED}[3]${NC} Complete removal (Nexus + Docker)"
    echo -e "  ${GREEN}[4]${NC} Backup and remove"
    echo -e "  ${CYAN}[0]${NC} Cancel"
    echo ""
    
    read -p "$(echo -e "${YELLOW}Select option [0-4]: ${NC}")" choice
    
    case $choice in
        1) uninstall_nexus_only ;;
        2) uninstall_nexus_with_cleanup ;;
        3) uninstall_complete ;;
        4) backup_and_remove ;;
        0) 
            echo -e "${CYAN}Uninstall cancelled${NC}"
            return 0
            ;;
        *)
            echo -e "${RED}❌ Invalid option${NC}"
            sleep 2
            uninstall_nexus_system
            ;;
    esac
}

# Uninstall Nexus only (keep Docker)
uninstall_nexus_only() {
    echo -e "${CYAN}🗑️  Removing Nexus (keeping Docker)${NC}"
    echo -e "${CYAN}═══════════════════════════════════${NC}"
    echo ""
    
    confirm_uninstall "Nexus components" || return 0
    
    # Stop services first
    stop_nexus_containers
    
    # Remove Nexus containers and images
    remove_nexus_containers
    remove_nexus_images
    
    # Ask about project files
    echo ""
    read -p "$(echo -e "${YELLOW}Remove project files? [y/N]: ${NC}")" remove_files
    
    if [[ "$remove_files" =~ ^[Yy]$ ]]; then
        backup_credentials_before_removal
        remove_project_files
    fi
    
    echo -e "${GREEN}✅ Nexus uninstalled successfully${NC}"
    log_activity "Nexus uninstalled (Docker kept)"
    
    read -p "Press Enter to continue..."
}

# Uninstall Nexus with Docker cleanup
uninstall_nexus_with_cleanup() {
    echo -e "${CYAN}🗑️  Removing Nexus with Docker cleanup${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""
    
    confirm_uninstall "Nexus and unused Docker resources" || return 0
    
    # Stop services
    stop_nexus_containers
    
    # Remove Nexus components
    remove_nexus_containers
    remove_nexus_images
    
    # Docker cleanup
    cleanup_docker_resources
    
    # Remove project files
    backup_credentials_before_removal
    remove_project_files
    
    echo -e "${GREEN}✅ Nexus uninstalled with cleanup${NC}"
    log_activity "Nexus uninstalled with Docker cleanup"
    
    read -p "Press Enter to continue..."
}

# Complete uninstall (Nexus + Docker)
uninstall_complete() {
    echo -e "${RED}🗑️  Complete Removal (Nexus + Docker)${NC}"
    echo -e "${RED}═══════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  This will remove Docker completely from your system${NC}"
    echo -e "${YELLOW}   All Docker containers and images will be lost!${NC}"
    echo ""
    
    confirm_uninstall "ALL Docker components and Nexus" || return 0
    
    # Additional confirmation for Docker removal
    echo ""
    read -p "$(echo -e "${RED}Are you ABSOLUTELY sure you want to remove Docker? [y/N]: ${NC}")" docker_confirm
    
    if [[ ! "$docker_confirm" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}Complete removal cancelled${NC}"
        return 0
    fi
    
    # Stop all Docker services
    stop_all_docker_services
    
    # Remove Nexus first
    remove_nexus_containers
    remove_nexus_images
    
    # Remove Docker completely
    remove_docker_engine
    
    # Remove project files
    backup_credentials_before_removal
    remove_project_files
    
    echo -e "${GREEN}✅ Complete uninstall finished${NC}"
    log_activity "Complete uninstall performed (Docker removed)"
    
    read -p "Press Enter to continue..."
}

# Backup and remove
backup_and_remove() {
    echo -e "${CYAN}💾 Backup and Remove${NC}"
    echo -e "${CYAN}══════════════════${NC}"
    echo ""
    
    # Create comprehensive backup
    create_comprehensive_backup
    
    # Proceed with Nexus removal
    confirm_uninstall "Nexus (after backup)" || return 0
    
    stop_nexus_containers
    remove_nexus_containers
    remove_nexus_images
    remove_project_files
    
    echo -e "${GREEN}✅ Backup created and Nexus removed${NC}"
    log_activity "Nexus removed with backup"
    
    read -p "Press Enter to continue..."
}

# Confirmation helper
confirm_uninstall() {
    local components="$1"
    
    echo -e "${YELLOW}⚠️  You are about to remove: ${components}${NC}"
    echo ""
    read -p "$(echo -e "${RED}Type 'yes' to confirm: ${NC}")" confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        echo -e "${CYAN}Uninstall cancelled${NC}"
        return 1
    fi
    
    return 0
}

# Stop Nexus containers
stop_nexus_containers() {
    echo -e "${CYAN}   Stopping Nexus containers...${NC}"
    
    # Stop metrics daemon first
    if [[ -f "$WORKDIR/metrics-daemon.pid" ]]; then
        source "$(dirname "${BASH_SOURCE[0]}")/manage.sh"
        stop_metrics_daemon
    fi
    
    # Stop using docker-compose if available
    if [[ -f "$WORKDIR/docker-compose.yml" ]]; then
        cd "$WORKDIR" && docker-compose down >/dev/null 2>&1
    fi
    
    # Force stop any remaining Nexus containers
    local nexus_containers
    nexus_containers=$(docker ps -q --filter "name=nexus" 2>/dev/null)
    
    if [[ -n "$nexus_containers" ]]; then
        echo "$nexus_containers" | xargs -r docker stop >/dev/null 2>&1
        echo -e "${GREEN}   ✅ Nexus containers stopped${NC}"
    else
        echo -e "${GREEN}   ✅ No running Nexus containers${NC}"
    fi
}

# Remove Nexus containers
remove_nexus_containers() {
    echo -e "${CYAN}   Removing Nexus containers...${NC}"
    
    # Remove all Nexus containers (running and stopped)
    local nexus_containers
    nexus_containers=$(docker ps -aq --filter "name=nexus" 2>/dev/null)
    
    if [[ -n "$nexus_containers" ]]; then
        echo "$nexus_containers" | xargs -r docker rm -f >/dev/null 2>&1
        echo -e "${GREEN}   ✅ Nexus containers removed${NC}"
    else
        echo -e "${GREEN}   ✅ No Nexus containers to remove${NC}"
    fi
}

# Remove Nexus images
remove_nexus_images() {
    echo -e "${CYAN}   Removing Nexus images...${NC}"
    
    # Remove Nexus-related images
    local nexus_images
    nexus_images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -i nexus 2>/dev/null)
    
    if [[ -n "$nexus_images" ]]; then
        echo "$nexus_images" | xargs -r docker rmi -f >/dev/null 2>&1
        echo -e "${GREEN}   ✅ Nexus images removed${NC}"
    else
        echo -e "${GREEN}   ✅ No Nexus images to remove${NC}"
    fi
    
    # Remove dangling images
    local dangling_images
    dangling_images=$(docker images -f "dangling=true" -q 2>/dev/null)
    
    if [[ -n "$dangling_images" ]]; then
        echo "$dangling_images" | xargs -r docker rmi >/dev/null 2>&1
        echo -e "${GREEN}   ✅ Dangling images cleaned${NC}"
    fi
}

# Cleanup Docker resources
cleanup_docker_resources() {
    echo -e "${CYAN}   Cleaning up Docker resources...${NC}"
    
    # Remove unused volumes
    docker volume prune -f >/dev/null 2>&1
    echo -e "${GREEN}   ✅ Unused volumes removed${NC}"
    
    # Remove unused networks
    docker network prune -f >/dev/null 2>&1
    echo -e "${GREEN}   ✅ Unused networks removed${NC}"
    
    # Remove build cache
    docker builder prune -f >/dev/null 2>&1
    echo -e "${GREEN}   ✅ Build cache cleaned${NC}"
}

# Stop all Docker services
stop_all_docker_services() {
    echo -e "${CYAN}   Stopping all Docker services...${NC}"
    
    # Stop all containers
    local all_containers
    all_containers=$(docker ps -q 2>/dev/null)
    
    if [[ -n "$all_containers" ]]; then
        echo "$all_containers" | xargs -r docker stop >/dev/null 2>&1
        echo -e "${GREEN}   ✅ All containers stopped${NC}"
    fi
    
    # Stop Docker daemon
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl stop docker >/dev/null 2>&1
        sudo systemctl disable docker >/dev/null 2>&1
    elif command -v service >/dev/null 2>&1; then
        sudo service docker stop >/dev/null 2>&1
    fi
    
    echo -e "${GREEN}   ✅ Docker daemon stopped${NC}"
}

# Remove Docker engine
remove_docker_engine() {
    echo -e "${CYAN}   Removing Docker engine...${NC}"
    
    # Remove all containers and images first
    docker system prune -af >/dev/null 2>&1
    
    # Detect package manager and remove Docker
    if command -v apt-get >/dev/null 2>&1; then
        remove_docker_apt
    elif command -v yum >/dev/null 2>&1; then
        remove_docker_yum
    elif command -v pacman >/dev/null 2>&1; then
        remove_docker_pacman
    else
        echo -e "${YELLOW}   ⚠️  Please remove Docker manually${NC}"
    fi
    
    # Remove Docker directories
    sudo rm -rf /var/lib/docker >/dev/null 2>&1
    sudo rm -rf /etc/docker >/dev/null 2>&1
    sudo rm -rf /var/run/docker >/dev/null 2>&1
    
    echo -e "${GREEN}   ✅ Docker engine removed${NC}"
}

# Remove Docker using apt
remove_docker_apt() {
    sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1
    sudo apt-get autoremove -y >/dev/null 2>&1
    sudo apt-get autoclean >/dev/null 2>&1
    
    # Remove Docker repository
    sudo rm -f /etc/apt/sources.list.d/docker.list >/dev/null 2>&1
    sudo rm -f /usr/share/keyrings/docker-archive-keyring.gpg >/dev/null 2>&1
}

# Remove Docker using yum
remove_docker_yum() {
    sudo yum remove -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1
    sudo yum autoremove -y >/dev/null 2>&1
    
    # Remove Docker repository
    sudo rm -f /etc/yum.repos.d/docker-ce.repo >/dev/null 2>&1
}

# Remove Docker using pacman
remove_docker_pacman() {
    sudo pacman -Rs --noconfirm docker docker-compose >/dev/null 2>&1
}

# Backup credentials before removal
backup_credentials_before_removal() {
    echo -e "${CYAN}   Creating credentials backup...${NC}"
    
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        local timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)
        
        # Try multiple backup locations
        local backup_locations=(
            "$HOME/backup/credentials_${timestamp}.json"
            "$HOME/.nexus_backup_${timestamp}.json"
            "/tmp/nexus_credentials_${timestamp}.json"
        )
        
        for location in "${backup_locations[@]}"; do
            if cp "$CREDENTIALS_FILE" "$location" 2>/dev/null; then
                echo -e "${GREEN}   ✅ Credentials backed up to: $location${NC}"
                break
            fi
        done
    fi
}

# Remove project files
remove_project_files() {
    echo -e "${CYAN}   Removing project files...${NC}"
    
    if [[ -d "$WORKDIR" ]]; then
        rm -rf "$WORKDIR" >/dev/null 2>&1
        echo -e "${GREEN}   ✅ Project directory removed${NC}"
    fi
    
    # Remove any temporary files
    rm -f /tmp/nexus-stop-metrics >/dev/null 2>&1
    rm -rf /tmp/nexus-* >/dev/null 2>&1
    
    echo -e "${GREEN}   ✅ Temporary files cleaned${NC}"
}

# Create comprehensive backup
create_comprehensive_backup() {
    echo -e "${CYAN}📦 Creating comprehensive backup...${NC}"
    
    local backup_base="$HOME/nexus-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_base"
    
    # Backup credentials
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        cp "$CREDENTIALS_FILE" "$backup_base/credentials.json" 2>/dev/null
        echo -e "${GREEN}   ✅ Credentials backed up${NC}"
    fi
    
    # Backup configuration files
    if [[ -f "$WORKDIR/docker-compose.yml" ]]; then
        cp "$WORKDIR/docker-compose.yml" "$backup_base/" 2>/dev/null
        echo -e "${GREEN}   ✅ Docker Compose file backed up${NC}"
    fi
    
    # Backup logs
    if [[ -d "$WORKDIR/logs" ]]; then
        cp -r "$WORKDIR/logs" "$backup_base/" 2>/dev/null
        echo -e "${GREEN}   ✅ Logs backed up${NC}"
    fi
    
    # Create restore instructions
    cat > "$backup_base/restore-instructions.txt" << EOF
Nexus Backup Created: $(now_jakarta)

To restore:
1. Install Nexus using the installer
2. Stop Nexus services
3. Copy credentials.json to the Nexus directory
4. Copy docker-compose.yml if you have customizations
5. Start Nexus services

Backup location: $backup_base
EOF
    
    echo -e "${GREEN}   ✅ Backup created at: $backup_base${NC}"
}

# Export functions for use by other modules
export -f uninstall_nexus_system backup_credentials_before_removal
