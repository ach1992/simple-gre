#!/bin/bash

# ============================================
# GRE Tunnel Uninstall Script
# Version: 1.0
# Repository: https://github.com/ach1992/simple-gre
# ============================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_title() {
    echo ""
    echo "========================================"
    echo "       GRE TUNNEL UNINSTALLER           "
    echo "========================================"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Confirm uninstallation
confirm_uninstall() {
    print_warning "WARNING: This will remove all GRE tunnels and related configurations"
    echo ""
    echo "The following will be removed:"
    echo "  - All GRE tunnel interfaces (gre-ir, gre-fr, etc.)"
    echo "  - GRE tunnel systemd service"
    echo "  - Startup scripts"
    echo "  - Firewall rules for GRE"
    echo "  - Network routes for GRE"
    echo ""
    
    read -p "Are you sure you want to continue? [y/N]: " CONFIRM
    CONFIRM=${CONFIRM:-n}
    
    if [[ $CONFIRM != "y" && $CONFIRM != "Y" ]]; then
        print_info "Uninstallation cancelled"
        exit 0
    fi
}

# Stop and disable service
remove_service() {
    print_info "Stopping GRE tunnel service..."
    
    if systemctl is-active gre-tunnel &>/dev/null; then
        systemctl stop gre-tunnel
        print_success "Service stopped"
    else
        print_info "Service not running"
    fi
    
    if systemctl is-enabled gre-tunnel &>/dev/null; then
        systemctl disable gre-tunnel
        print_success "Service disabled"
    fi
    
    # Remove service file
    if [[ -f /etc/systemd/system/gre-tunnel.service ]]; then
        rm -f /etc/systemd/system/gre-tunnel.service
        print_success "Service file removed"
    fi
    
    systemctl daemon-reload
    print_success "Systemd reloaded"
}

# Remove GRE tunnels
remove_tunnels() {
    print_info "Removing GRE tunnels..."
    
    # Find all GRE interfaces
    GRE_INTERFACES=$(ip link show 2>/dev/null | grep -o "gre[^:]*" | sort -u)
    
    if [[ -z "$GRE_INTERFACES" ]]; then
        print_info "No GRE tunnels found"
        return
    fi
    
    for IFACE in $GRE_INTERFACES; do
        print_info "Removing tunnel: $IFACE"
        
        # Get tunnel info before removal
        TUNNEL_IP=$(ip addr show dev $IFACE 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
        
        # Remove tunnel
        if ip link delete $IFACE 2>/dev/null; then
            print_success "Tunnel $IFACE removed"
            [[ -n "$TUNNEL_IP" ]] && print_info "  IP was: $TUNNEL_IP"
        else
            print_error "Failed to remove tunnel $IFACE"
        fi
    done
}

# Remove routes
remove_routes() {
    print_info "Cleaning up routes..."
    
    # Remove GRE-specific routes
    GRE_ROUTES=$(ip route show 2>/dev/null | grep -E "gre|10\.100\.100")
    
    if [[ -n "$GRE_ROUTES" ]]; then
        while read ROUTE; do
            ip route del $ROUTE 2>/dev/null && print_success "Removed route: $ROUTE"
        done <<< "$GRE_ROUTES"
    else
        print_info "No GRE routes found"
    fi
}

# Remove firewall rules
remove_firewall_rules() {
    print_info "Cleaning up firewall rules..."
    
    if ! command -v iptables &>/dev/null; then
        print_info "iptables not found, skipping firewall cleanup"
        return
    fi
    
    # Count rules before
    GRE_RULES_BEFORE=$(iptables -L -n 2>/dev/null | grep -c "gre")
    
    if [[ $GRE_RULES_BEFORE -eq 0 ]]; then
        print_info "No GRE firewall rules found"
        return
    fi
    
    # Remove GRE rules from INPUT chain
    while iptables -L INPUT -n --line-numbers | grep -q "gre"; do
        LINE_NUM=$(iptables -L INPUT -n --line-numbers | grep "gre" | head -1 | awk '{print $1}')
        iptables -D INPUT $LINE_NUM 2>/dev/null
    done
    
    # Remove GRE rules from FORWARD chain
    while iptables -L FORWARD -n --line-numbers | grep -q "gre"; do
        LINE_NUM=$(iptables -L FORWARD -n --line-numbers | grep "gre" | head -1 | awk '{print $1}')
        iptables -D FORWARD $LINE_NUM 2>/dev/null
    done
    
    # Remove NAT rules
    while iptables -t nat -L POSTROUTING -n --line-numbers | grep -q "10\.100\.100"; do
        LINE_NUM=$(iptables -t nat -L POSTROUTING -n --line-numbers | grep "10\.100\.100" | head -1 | awk '{print $1}')
        iptables -t nat -D POSTROUTING $LINE_NUM 2>/dev/null
    done
    
    print_success "Firewall rules cleaned up"
    
    # Save rules if iptables-persistent is installed
    if command -v netfilter-persistent &>/dev/null; then
        netfilter-persistent save
        print_success "Firewall rules saved persistently"
    elif [[ -d /etc/iptables ]]; then
        iptables-save > /etc/iptables/rules.v4 2>/dev/null && print_success "Rules saved to /etc/iptables/rules.v4"
    fi
}

# Remove configuration files
remove_config_files() {
    print_info "Removing configuration files..."
    
    # Remove scripts
    SCRIPT_FILES=(
        "/usr/local/bin/gre-tunnel-start.sh"
        "/usr/local/bin/gre-tunnel-stop.sh"
        "/usr/local/bin/gre-status"
        "/usr/local/bin/gre-uninstall"
    )
    
    for FILE in "${SCRIPT_FILES[@]}"; do
        if [[ -f "$FILE" ]]; then
            rm -f "$FILE"
            print_success "Removed: $FILE"
        fi
    done
    
    # Remove from rc.local
    if [[ -f /etc/rc.local ]]; then
        sed -i '/gre-tunnel-start.sh/d' /etc/rc.local
        sed -i '/gre-tunnel-stop.sh/d' /etc/rc.local
        print_success "Cleaned up /etc/rc.local"
    fi
    
    # Remove kernel module config
    if [[ -f /etc/modules-load.d/gre.conf ]]; then
        rm -f /etc/modules-load.d/gre.conf
        print_success "Removed kernel module config"
    fi
    
    # Remove sysctl optimizations (optional - commented out by default)
    # print_info "Note: System optimizations in /etc/sysctl.conf are kept"
    # print_info "      Remove manually if needed"
}

# Clean sysctl modifications (optional)
clean_sysctl() {
    read -p "Remove GRE optimizations from sysctl? [y/N]: " CLEAN_SYSCTL
    CLEAN_SYSCTL=${CLEAN_SYSCTL:-n}
    
    if [[ $CLEAN_SYSCTL == "y" || $CLEAN_SYSCTL == "Y" ]]; then
        print_info "Cleaning sysctl modifications..."
        
        # Backup original sysctl
        cp /etc/sysctl.conf /etc/sysctl.conf.backup-$(date +%Y%m%d-%H%M%S)
        
        # Remove GRE-related optimizations
        sed -i '/# GRE Tunnel Optimization/,/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
        sed -i '/^net.ipv4.ip_forward/d' /etc/sysctl.conf
        sed -i '/^net.ipv4.conf.all.rp_filter/d' /etc/sysctl.conf
        sed -i '/^net.ipv4.conf.default.rp_filter/d' /etc/sysctl.conf
        
        sysctl -p &>/dev/null
        print_success "Sysctl optimizations removed"
    fi
}

# Verify cleanup
verify_cleanup() {
    print_info "Verifying cleanup..."
    
    echo ""
    echo "Verification Results:"
    echo "--------------------"
    
    # Check for remaining GRE interfaces
    REMAINING_TUNNELS=$(ip link show 2>/dev/null | grep -c "gre")
    if [[ $REMAINING_TUNNELS -eq 0 ]]; then
        print_success "✓ No GRE tunnels remaining"
    else
        print_error "✗ $REMAINING_TUNNELS GRE tunnel(s) still exist"
    fi
    
    # Check for service
    if systemctl list-unit-files | grep -q gre-tunnel; then
        print_error "✗ gre-tunnel.service still exists"
    else
        print_success "✓ Service removed"
    fi
    
    # Check for scripts
    if [[ -f /usr/local/bin/gre-tunnel-start.sh ]]; then
        print_error "✗ Scripts still exist"
    else
        print_success "✓ Scripts removed"
    fi
    
    # Check for routes
    REMAINING_ROUTES=$(ip route show 2>/dev/null | grep -c "10\.100\.100")
    if [[ $REMAINING_ROUTES -eq 0 ]]; then
        print_success "✓ No GRE routes remaining"
    else
        print_error "✗ GRE routes still exist"
    fi
    
    echo ""
}

# Show next steps
show_next_steps() {
    print_success "Uninstallation complete!"
    echo ""
    echo "Next steps:"
    echo "-----------"
    echo "1. If you want to reinstall:"
    echo "   curl -s https://raw.githubusercontent.com/ach1992/simple-gre/main/install.sh | bash"
    echo ""
    echo "2. Check if any processes are still using GRE:"
    echo "   ps aux | grep -E 'gre|tunnel'"
    echo ""
    echo "3. Restart network service if needed:"
    echo "   systemctl restart networking"
    echo ""
    echo "4. Reboot to ensure complete cleanup:"
    echo "   reboot"
    echo ""
    print_info "Thank you for using GRE Tunnel Setup!"
}

# Main function
main() {
    print_title
    check_root
    confirm_uninstall
    
    # Perform uninstallation steps
    remove_service
    remove_tunnels
    remove_routes
    remove_firewall_rules
    remove_config_files
    clean_sysctl
    
    echo ""
    print_info "Cleaning up temporary files..."
    rm -f /tmp/gre-opposite-config.txt 2>/dev/null
    rm -f /tmp/gre-setup.log 2>/dev/null
    
    verify_cleanup
    show_next_steps
}

# Handle command line arguments
case "${1:-}" in
    "--help"|"-h")
        echo "Usage: $0 [OPTION]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help"
        echo "  --force, -f    Force uninstall without confirmation"
        echo ""
        echo "Examples:"
        echo "  $0             Interactive uninstall"
        echo "  $0 --force     Force uninstall"
        exit 0
        ;;
    "--force"|"-f")
        # Force mode - skip confirmation
        print_warning "Force mode enabled - skipping confirmation"
        print_title
        check_root
        
        # Set CONFIRM to y for force mode
        CONFIRM="y"
        
        # Perform uninstallation
        remove_service
        remove_tunnels
        remove_routes
        remove_firewall_rules
        remove_config_files
        
        verify_cleanup
        show_next_steps
        exit 0
        ;;
    *)
        main
        ;;
esac
