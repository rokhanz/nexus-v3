#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════════
#                              SETUP MODULE
# ═══════════════════════════════════════════════════════════════════════════════
# Description: System configuration and settings management
# Dependencies: common.sh, tui.sh
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent double-loading
[[ -n "${NEXUS_SETUP_LOADED:-}" ]] && return 0
readonly NEXUS_SETUP_LOADED=1

# Source dependencies
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tui.sh"

# ═══════════════════════════════════════════════════════════════════════════════
#                            SETUP FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Main setup interface
setup_nexus_system() {
    while true; do
        clear_screen
        echo -e "${CYAN}⚙️  Nexus System Setup${NC}"
        echo -e "${CYAN}════════════════════${NC}"
        echo ""
        
        echo -e "Configuration Options:"
        echo ""
        echo -e "  ${GREEN}[1]${NC} Network Configuration"
        echo -e "  ${GREEN}[2]${NC} Credentials Management"
        echo -e "  ${GREEN}[3]${NC} Performance Settings"
        echo -e "  ${GREEN}[4]${NC} Backup & Restore"
        echo -e "  ${GREEN}[5]${NC} System Information"
        echo -e "  ${GREEN}[6]${NC} Advanced Settings"
        echo -e "  ${RED}[0]${NC} Back to Main Menu"
        echo ""
        
        read -p "$(echo -e "${YELLOW}Select option [0-6]: ${NC}")" choice
        
        case $choice in
            1) network_configuration ;;
            2) credentials_management ;;
            3) performance_settings ;;
            4) backup_restore ;;
            5) system_information ;;
            6) advanced_settings ;;
            0) break ;;
            *)
                echo -e "${RED}❌ Invalid option. Please try again.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Network configuration
network_configuration() {
    clear_screen
    echo -e "${CYAN}🌐 Network Configuration${NC}"
    echo -e "${CYAN}══════════════════════${NC}"
    echo ""
    
    # Show current configuration
    show_current_network_config
    echo ""
    
    echo -e "Network Options:"
    echo ""
    echo -e "  ${GREEN}[1]${NC} Configure RPC Endpoint"
    echo -e "  ${GREEN}[2]${NC} Set Chain ID"
    echo -e "  ${GREEN}[3]${NC} Port Configuration"
    echo -e "  ${GREEN}[4]${NC} Test Network Connectivity"
    echo -e "  ${GREEN}[5]${NC} Reset to Defaults"
    echo -e "  ${RED}[0]${NC} Back"
    echo ""
    
    read -p "$(echo -e "${YELLOW}Select option [0-5]: ${NC}")" net_choice
    
    case $net_choice in
        1) configure_rpc_endpoint ;;
        2) configure_chain_id ;;
        3) configure_ports ;;
        4) test_network_connectivity ;;
        5) reset_network_defaults ;;
        0) return 0 ;;
        *)
            echo -e "${RED}❌ Invalid option${NC}"
            sleep 2
            network_configuration
            ;;
    esac
}

# Show current network configuration
show_current_network_config() {
    echo -e "${BOLD}Current Network Configuration:${NC}"
    echo -e "${CYAN}─────────────────────────────${NC}"
    
    local env_file="$WORKDIR/.env"
    if [[ -f "$env_file" ]]; then
        local current_rpc current_chain_id
        current_rpc=$(grep "^RPC_HTTP=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "$RPC_HTTP")
        current_chain_id=$(grep "^CHAIN_ID=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "$CHAIN_ID")
        
        echo -e "  🌐 RPC Endpoint: $current_rpc"
        echo -e "  🔗 Chain ID: $current_chain_id"
    else
        echo -e "  🌐 RPC Endpoint: $RPC_HTTP (default)"
        echo -e "  🔗 Chain ID: $CHAIN_ID (default)"
    fi
    
    # Show port information
    local ports
    ports=$(get_available_ports 3 10000)
    echo -e "  🔌 Available Ports: $ports"
}

# Configure RPC endpoint
configure_rpc_endpoint() {
    echo -e "${CYAN}🌐 Configure RPC Endpoint${NC}"
    echo -e "${CYAN}═══════════════════════${NC}"
    echo ""
    
    echo -e "Current RPC: $RPC_HTTP"
    echo ""
    echo -e "Common RPC endpoints:"
    echo -e "  • http://localhost:8545 (local)"
    echo -e "  • https://mainnet.infura.io/v3/YOUR_PROJECT_ID"
    echo -e "  • https://eth.llamarpc.com"
    echo ""
    
    read -p "$(echo -e "${YELLOW}Enter new RPC endpoint (or press Enter to keep current): ${NC}")" new_rpc
    
    if [[ -n "$new_rpc" ]]; then
        new_rpc=$(sanitize_input "$new_rpc")
        
        if [[ "$new_rpc" =~ ^https?://.*$ ]]; then
            update_env_variable "RPC_HTTP" "$new_rpc"
            echo -e "${GREEN}✅ RPC endpoint updated to: $new_rpc${NC}"
            log_activity "RPC endpoint updated to $new_rpc"
        else
            echo -e "${RED}❌ Invalid RPC format. Please use http:// or https://${NC}"
        fi
    else
        echo -e "${CYAN}RPC endpoint unchanged${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

# Configure Chain ID
configure_chain_id() {
    echo -e "${CYAN}🔗 Configure Chain ID${NC}"
    echo -e "${CYAN}══════════════════${NC}"
    echo ""
    
    echo -e "Current Chain ID: $CHAIN_ID"
    echo ""
    echo -e "Common Chain IDs:"
    echo -e "  • 1 (Ethereum Mainnet)"
    echo -e "  • 5 (Goerli Testnet)"
    echo -e "  • 1337 (Local/Private)"
    echo ""
    
    read -p "$(echo -e "${YELLOW}Enter new Chain ID (or press Enter to keep current): ${NC}")" new_chain_id
    
    if [[ -n "$new_chain_id" ]]; then
        new_chain_id=$(sanitize_input "$new_chain_id")
        
        if [[ "$new_chain_id" =~ ^[0-9]+$ ]]; then
            update_env_variable "CHAIN_ID" "$new_chain_id"
            echo -e "${GREEN}✅ Chain ID updated to: $new_chain_id${NC}"
            log_activity "Chain ID updated to $new_chain_id"
        else
            echo -e "${RED}❌ Invalid Chain ID. Please enter a number.${NC}"
        fi
    else
        echo -e "${CYAN}Chain ID unchanged${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

# Configure ports
configure_ports() {
    echo -e "${CYAN}🔌 Port Configuration${NC}"
    echo -e "${CYAN}══════════════════${NC}"
    echo ""
    
    # Show currently used ports
    echo -e "Currently used ports:"
    if command -v netstat >/dev/null 2>&1; then
        netstat -tuln | grep LISTEN | head -10
    elif command -v ss >/dev/null 2>&1; then
        ss -tuln | grep LISTEN | head -10
    else
        echo -e "  (Port scanning tool not available)"
    fi
    
    echo ""
    local available_ports
    available_ports=$(get_available_ports 5 10000)
    echo -e "Available ports: $available_ports"
    
    read -p "Press Enter to continue..."
}

# Test network connectivity
test_network_connectivity() {
    echo -e "${CYAN}🔍 Testing Network Connectivity${NC}"
    echo -e "${CYAN}════════════════════════════${NC}"
    echo ""
    
    # Test basic connectivity
    echo -e "Testing basic connectivity..."
    local test_hosts=("google.com" "github.com" "docker.com")
    
    for host in "${test_hosts[@]}"; do
        echo -n "  Testing $host... "
        if ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ OK${NC}"
        else
            echo -e "${RED}❌ Failed${NC}"
        fi
    done
    
    echo ""
    
    # Test RPC endpoint if configured
    local env_file="$WORKDIR/.env"
    if [[ -f "$env_file" ]]; then
        local current_rpc
        current_rpc=$(grep "^RPC_HTTP=" "$env_file" 2>/dev/null | cut -d'=' -f2)
        
        if [[ -n "$current_rpc" && "$current_rpc" != "http://localhost:8545" ]]; then
            echo -e "Testing RPC endpoint: $current_rpc"
            echo -n "  RPC connectivity... "
            
            if curl -s --max-time 10 "$current_rpc" >/dev/null 2>&1; then
                echo -e "${GREEN}✅ OK${NC}"
            else
                echo -e "${RED}❌ Failed${NC}"
            fi
        fi
    fi
    
    # Test Docker connectivity
    echo ""
    echo -e "Testing Docker connectivity..."
    echo -n "  Docker Hub... "
    if curl -s --max-time 10 "https://hub.docker.com" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ OK${NC}"
    else
        echo -e "${RED}❌ Failed${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

# Reset network defaults
reset_network_defaults() {
    echo -e "${YELLOW}⚠️  Reset Network Configuration to Defaults?${NC}"
    read -p "This will reset RPC and Chain ID. Continue? [y/N]: " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        update_env_variable "RPC_HTTP" "$RPC_HTTP"
        update_env_variable "CHAIN_ID" "$CHAIN_ID"
        echo -e "${GREEN}✅ Network configuration reset to defaults${NC}"
        log_activity "Network configuration reset to defaults"
    else
        echo -e "${CYAN}Reset cancelled${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

# Credentials management
credentials_management() {
    clear_screen
    echo -e "${CYAN}🔐 Credentials Management${NC}"
    echo -e "${CYAN}═══════════════════════${NC}"
    echo ""
    
    # Show current credentials status
    show_credentials_status
    echo ""
    
    echo -e "Credentials Options:"
    echo ""
    echo -e "  ${GREEN}[1]${NC} View Credentials"
    echo -e "  ${GREEN}[2]${NC} Generate New Credentials"
    echo -e "  ${GREEN}[3]${NC} Import Credentials"
    echo -e "  ${GREEN}[4]${NC} Backup Credentials"
    echo -e "  ${GREEN}[5]${NC} Validate Credentials"
    echo -e "  ${RED}[0]${NC} Back"
    echo ""
    
    read -p "$(echo -e "${YELLOW}Select option [0-5]: ${NC}")" cred_choice
    
    case $cred_choice in
        1) view_credentials ;;
        2) generate_new_credentials ;;
        3) import_credentials ;;
        4) backup_credentials_manual ;;
        5) validate_credentials ;;
        0) return 0 ;;
        *)
            echo -e "${RED}❌ Invalid option${NC}"
            sleep 2
            credentials_management
            ;;
    esac
}

# Show credentials status
show_credentials_status() {
    echo -e "${BOLD}Credentials Status:${NC}"
    echo -e "${CYAN}─────────────────${NC}"
    
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        echo -e "  $(draw_status "active" "Credentials file exists")"
        
        if command -v jq >/dev/null 2>&1; then
            local wallet_addr node_id
            wallet_addr=$(jq -r '.wallet_address // "Not set"' "$CREDENTIALS_FILE" 2>/dev/null)
            node_id=$(jq -r '.node_id // "Not set"' "$CREDENTIALS_FILE" 2>/dev/null)
            
            echo -e "  🏷️  Node ID: ${node_id:0:12}..."
            echo -e "  💰 Wallet: ${wallet_addr:0:8}...${wallet_addr: -4}"
        else
            echo -e "  📄 File size: $(du -h "$CREDENTIALS_FILE" 2>/dev/null | cut -f1 || echo "Unknown")"
        fi
        
        # Check file permissions
        local perms
        perms=$(stat -c %a "$CREDENTIALS_FILE" 2>/dev/null || echo "Unknown")
        echo -e "  🔒 Permissions: $perms"
    else
        echo -e "  $(draw_status "warning" "No credentials found")"
    fi
}

# View credentials
view_credentials() {
    echo -e "${CYAN}👁️  View Credentials${NC}"
    echo -e "${CYAN}═══════════════${NC}"
    echo ""
    
    if [[ ! -f "$CREDENTIALS_FILE" ]]; then
        echo -e "${RED}❌ No credentials file found${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    echo -e "${YELLOW}⚠️  This will display sensitive information${NC}"
    read -p "Continue? [y/N]: " view_confirm
    
    if [[ ! "$view_confirm" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}View cancelled${NC}"
        read -p "Press Enter to continue..."
        return 0
    fi
    
    echo ""
    echo -e "${BOLD}Credentials:${NC}"
    echo -e "${CYAN}──────────${NC}"
    
    if command -v jq >/dev/null 2>&1; then
        jq '.' "$CREDENTIALS_FILE" 2>/dev/null || cat "$CREDENTIALS_FILE"
    else
        cat "$CREDENTIALS_FILE"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Generate new credentials
generate_new_credentials() {
    echo -e "${CYAN}🔄 Generate New Credentials${NC}"
    echo -e "${CYAN}════════════════════════${NC}"
    echo ""
    
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        echo -e "${YELLOW}⚠️  Existing credentials will be backed up${NC}"
        read -p "Continue with new generation? [y/N]: " gen_confirm
        
        if [[ ! "$gen_confirm" =~ ^[Yy]$ ]]; then
            echo -e "${CYAN}Generation cancelled${NC}"
            read -p "Press Enter to continue..."
            return 0
        fi
        
        # Backup existing credentials
        backup_existing_credentials
    fi
    
    echo -e "${CYAN}Generating new credentials...${NC}"
    
    cd "$WORKDIR" || return 1
    
    if [[ -f "credentials-generator.sh" ]]; then
        if bash credentials-generator.sh; then
            echo -e "${GREEN}✅ New credentials generated successfully${NC}"
            log_activity "New credentials generated"
        else
            echo -e "${RED}❌ Failed to generate credentials${NC}"
        fi
    else
        echo -e "${RED}❌ Credentials generator not found${NC}"
        echo -e "${CYAN}Please reinstall Nexus to get the generator${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

# Import credentials
import_credentials() {
    echo -e "${CYAN}📥 Import Credentials${NC}"
    echo -e "${CYAN}══════════════════${NC}"
    echo ""
    
    echo -e "Import options:"
    echo -e "  ${GREEN}[1]${NC} Import from file path"
    echo -e "  ${GREEN}[2]${NC} Import from backup directory"
    echo -e "  ${RED}[0]${NC} Cancel"
    echo ""
    
    read -p "$(echo -e "${YELLOW}Select option [0-2]: ${NC}")" import_choice
    
    case $import_choice in
        1) import_from_path ;;
        2) import_from_backup ;;
        0) return 0 ;;
        *)
            echo -e "${RED}❌ Invalid option${NC}"
            sleep 2
            import_credentials
            ;;
    esac
}

# Import from path
import_from_path() {
    echo ""
    read -p "$(echo -e "${YELLOW}Enter credentials file path: ${NC}")" cred_path
    
    cred_path=$(sanitize_input "$cred_path")
    
    if [[ ! -f "$cred_path" ]]; then
        echo -e "${RED}❌ File not found: $cred_path${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    # Validate JSON format
    if command -v jq >/dev/null 2>&1; then
        if ! jq '.' "$cred_path" >/dev/null 2>&1; then
            echo -e "${RED}❌ Invalid JSON format${NC}"
            read -p "Press Enter to continue..."
            return 1
        fi
    fi
    
    # Backup existing if present
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        backup_existing_credentials
    fi
    
    # Copy new credentials
    if cp "$cred_path" "$CREDENTIALS_FILE"; then
        echo -e "${GREEN}✅ Credentials imported successfully${NC}"
        log_activity "Credentials imported from $cred_path"
    else
        echo -e "${RED}❌ Failed to import credentials${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

# Import from backup
import_from_backup() {
    echo ""
    echo -e "Searching for backup files..."
    
    local backup_files=()
    
    # Search common backup locations
    local search_paths=(
        "$HOME/backup"
        "$WORKDIR/backup"
        "$HOME"
    )
    
    for path in "${search_paths[@]}"; do
        if [[ -d "$path" ]]; then
            while IFS= read -r -d '' file; do
                backup_files+=("$file")
            done < <(find "$path" -name "*credentials*.json" -type f -print0 2>/dev/null)
        fi
    done
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  No backup files found${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    echo -e "Found backup files:"
    for i in "${!backup_files[@]}"; do
        echo -e "  ${GREEN}[$((i+1))]${NC} ${backup_files[i]}"
    done
    echo ""
    
    read -p "$(echo -e "${YELLOW}Select backup file [1-${#backup_files[@]}]: ${NC}")" backup_choice
    
    if [[ "$backup_choice" =~ ^[0-9]+$ ]] && [[ "$backup_choice" -ge 1 ]] && [[ "$backup_choice" -le ${#backup_files[@]} ]]; then
        local selected_file="${backup_files[$((backup_choice-1))]}"
        import_from_path "$selected_file"
    else
        echo -e "${RED}❌ Invalid selection${NC}"
        read -p "Press Enter to continue..."
    fi
}

# Backup credentials manually
backup_credentials_manual() {
    echo -e "${CYAN}💾 Backup Credentials${NC}"
    echo -e "${CYAN}═══════════════════${NC}"
    echo ""
    
    if [[ ! -f "$CREDENTIALS_FILE" ]]; then
        echo -e "${RED}❌ No credentials to backup${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="credentials_backup_${timestamp}.json"
    
    echo -e "Backup locations:"
    echo -e "  ${GREEN}[1]${NC} Home backup directory ($HOME/backup/)"
    echo -e "  ${GREEN}[2]${NC} Project backup directory ($WORKDIR/backup/)"
    echo -e "  ${GREEN}[3]${NC} Custom location"
    echo -e "  ${RED}[0]${NC} Cancel"
    echo ""
    
    read -p "$(echo -e "${YELLOW}Select backup location [0-3]: ${NC}")" backup_loc_choice
    
    local backup_path=""
    
    case $backup_loc_choice in
        1) backup_path="$HOME/backup/$backup_name" ;;
        2) backup_path="$WORKDIR/backup/$backup_name" ;;
        3)
            read -p "$(echo -e "${YELLOW}Enter custom path: ${NC}")" custom_path
            backup_path="$custom_path/$backup_name"
            ;;
        0) return 0 ;;
        *)
            echo -e "${RED}❌ Invalid option${NC}"
            read -p "Press Enter to continue..."
            return 1
            ;;
    esac
    
    # Create backup directory if needed
    mkdir -p "$(dirname "$backup_path")" 2>/dev/null
    
    if cp "$CREDENTIALS_FILE" "$backup_path" 2>/dev/null; then
        echo -e "${GREEN}✅ Credentials backed up to: $backup_path${NC}"
        log_activity "Credentials manually backed up to $backup_path"
    else
        echo -e "${RED}❌ Failed to create backup${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

# Validate credentials
validate_credentials() {
    echo -e "${CYAN}🔍 Validate Credentials${NC}"
    echo -e "${CYAN}════════════════════${NC}"
    echo ""
    
    if [[ ! -f "$CREDENTIALS_FILE" ]]; then
        echo -e "${RED}❌ No credentials file found${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    echo -e "Validating credentials file..."
    
    # Check JSON format
    if command -v jq >/dev/null 2>&1; then
        if jq '.' "$CREDENTIALS_FILE" >/dev/null 2>&1; then
            echo -e "  $(draw_status "active" "JSON format valid")"
        else
            echo -e "  $(draw_status "error" "Invalid JSON format")"
            read -p "Press Enter to continue..."
            return 1
        fi
        
        # Check required fields
        local wallet_addr node_id
        wallet_addr=$(jq -r '.wallet_address // ""' "$CREDENTIALS_FILE" 2>/dev/null)
        node_id=$(jq -r '.node_id // ""' "$CREDENTIALS_FILE" 2>/dev/null)
        
        if [[ -n "$wallet_addr" ]]; then
            if validate_wallet_address "$wallet_addr"; then
                echo -e "  $(draw_status "active" "Wallet address valid")"
            else
                echo -e "  $(draw_status "error" "Invalid wallet address format")"
            fi
        else
            echo -e "  $(draw_status "warning" "Wallet address not found")"
        fi
        
        if [[ -n "$node_id" ]]; then
            echo -e "  $(draw_status "active" "Node ID present")"
        else
            echo -e "  $(draw_status "warning" "Node ID not found")"
        fi
    else
        echo -e "  $(draw_status "warning" "Cannot validate JSON (jq not available)")"
    fi
    
    # Check file permissions
    local perms
    perms=$(stat -c %a "$CREDENTIALS_FILE" 2>/dev/null)
    if [[ "$perms" == "600" || "$perms" == "644" ]]; then
        echo -e "  $(draw_status "active" "File permissions secure ($perms)")"
    else
        echo -e "  $(draw_status "warning" "File permissions: $perms (consider 600)")"
    fi
    
    echo -e "${GREEN}✅ Validation completed${NC}"
    read -p "Press Enter to continue..."
}

# Performance settings
performance_settings() {
    echo -e "${CYAN}⚡ Performance Settings${NC}"
    echo -e "${CYAN}══════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Performance settings are handled automatically${NC}"
    echo -e "${CYAN}The system optimizes based on available resources${NC}"
    
    read -p "Press Enter to continue..."
}

# Backup and restore
backup_restore() {
    echo -e "${CYAN}💾 Backup & Restore${NC}"
    echo -e "${CYAN}══════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Backup functionality is integrated into other operations${NC}"
    echo -e "${CYAN}Credentials are automatically backed up during critical operations${NC}"
    
    read -p "Press Enter to continue..."
}

# System information
system_information() {
    clear_screen
    echo -e "${CYAN}ℹ️  System Information${NC}"
    echo -e "${CYAN}═══════════════════${NC}"
    echo ""
    
    # Enhanced system information display
    get_enhanced_system_info
    echo ""
    get_enhanced_docker_info
    echo ""
    get_enhanced_nexus_info
    
    read -p "Press Enter to continue..."
}

# Advanced settings
advanced_settings() {
    echo -e "${CYAN}🔧 Advanced Settings${NC}"
    echo -e "${CYAN}═══════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Advanced settings are managed through environment files${NC}"
    echo -e "${CYAN}Check $WORKDIR/.env for configuration options${NC}"
    
    read -p "Press Enter to continue..."
}

# Helper functions
backup_existing_credentials() {
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        local timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_path="$WORKDIR/backup/credentials_${timestamp}.json"
        
        mkdir -p "$(dirname "$backup_path")"
        cp "$CREDENTIALS_FILE" "$backup_path" 2>/dev/null && \
            echo -e "${GREEN}   ✅ Existing credentials backed up${NC}"
    fi
}

# Update environment variable
update_env_variable() {
    local var_name="$1"
    local var_value="$2"
    local env_file="$WORKDIR/.env"
    
    # Create .env file if it doesn't exist
    if [[ ! -f "$env_file" ]]; then
        touch "$env_file"
    fi
    
    # Update or add the variable
    if grep -q "^${var_name}=" "$env_file"; then
        sed -i "s|^${var_name}=.*|${var_name}=${var_value}|" "$env_file"
    else
        echo "${var_name}=${var_value}" >> "$env_file"
    fi
}

# Export functions for use by other modules
export -f setup_nexus_system credentials_management network_configuration
