#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════════
#                           NEXUS V3 MAIN ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════════
# Description: Nexus Docker Manager
# Version: 3.1.0 
# Author: rokhanz
# ═══════════════════════════════════════════════════════════════════════════════

# Script metadata
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="$SCRIPT_DIR/lib"
readonly VERSION="3.1.0-modular"

# Check if lib directory exists
if [[ ! -d "$LIB_DIR" ]]; then
    echo "❌ Error: lib/ directory not found"
    echo "Please ensure the complete nexus-v3 package is extracted"
    exit 1
fi

# Source required modules
source_modules() {
    local modules=(
        "common.sh"     # Common utilities and configurations
        "tui.sh"        # TUI system and dashboard
        "setup.sh"      # Setup and configuration functions
        "install.sh"    # Installation functions
        "manage.sh"     # Management and monitoring functions
        "uninstall.sh"  # Uninstall functions
    )
    
    for module in "${modules[@]}"; do
        local module_path="$LIB_DIR/$module"
        if [[ -f "$module_path" ]]; then
            # shellcheck source=/dev/null
            source "$module_path"
        else
            echo "❌ Error: Required module $module not found"
            echo "Expected location: $module_path"
            exit 1
        fi
    done
}

# Initialize modules
initialize() {
    echo "🚀 Nexus v3 Modular Manager - v$VERSION"
    echo "📂 Loading modules..."
    
    # Source all required modules
    source_modules
    
    # Initialize common functions
    init_common
    
    echo "✅ All modules loaded successfully"
}

# Main menu system
show_main_menu() {
    while true; do
        # Display enhanced dashboard
        draw_enhanced_dashboard
        
        echo -e "${CYAN}Main Menu Options:${NC}"
        echo -e "${CYAN}═════════════════${NC}"
        echo ""
        echo -e "  ${GREEN}[1]${NC} Install Nexus"
        echo -e "  ${GREEN}[2]${NC} Manage Services"
        echo -e "  ${GREEN}[3]${NC} System Settings"
        echo -e "  ${RED}[4]${NC} Uninstall"
        echo -e "  ${YELLOW}[0]${NC} Exit"
        echo ""
        
        read -p "$(echo -e "${YELLOW}Select option [0-4]: ${NC}")" choice
        
        case $choice in
            1)
                clear_screen
                install_nexus_system
                ;;
            2)
                if is_nexus_installed; then
                    manage_nexus_system
                else
                    echo -e "${RED}❌ Nexus is not installed yet${NC}"
                    echo -e "${CYAN}Please install Nexus first (option 1)${NC}"
                    read -p "Press Enter to continue..."
                fi
                ;;
            3)
                setup_nexus_system
                ;;
            4)
                uninstall_nexus_system
                ;;
            0)
                echo -e "${CYAN}👋 Thank you for using Nexus Manager!${NC}"
                log_activity "Nexus Manager exited normally"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Invalid option. Please try again.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Main execution
main() {
    # Initialize the system
    initialize
    
    # Check root user
    check_root_user
    
    # Setup directory structure
    setup_directory_structure
    
    # Initialize logging
    log_activity "Nexus Modular Manager started"
    
    # Start main menu
    show_main_menu
}

# Ensure script is executed, not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
