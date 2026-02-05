#!/bin/bash

# ============================================
# GRE Tunnel Status Check Script
# Version: 1.0
# Repository: https://github.com/ach1992/simple-gre
# ============================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_section() {
    echo ""
    echo "========================================"
    echo "         GRE TUNNEL STATUS              "
    echo "========================================"
    echo ""
}

print_subsection() {
    echo ""
    echo "$1"
    echo "$(printf '=%.0s' $(seq 1 ${#1}))"
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

# Check if script is run as root (for full info)
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_warning "Some information may be limited. Run as root for full details."
        return 1
    fi
    return 0
}

# Detect GRE interfaces
detect_gre_interfaces() {
    print_subsection "GRE TUNNELS DETECTION"
    
    GRE_INTERFACES=$(ip link show 2>/dev/null | grep -o "gre[^:]*" | sort -u)
    
    if [[ -z "$GRE_INTERFACES" ]]; then
        print_error "No GRE tunnels found"
        return 1
    fi
    
    print_success "Found GRE tunnel(s): $(echo $GRE_INTERFACES | tr '\n' ' ')"
    
    for IFACE in $GRE_INTERFACES; do
        echo ""
        print_info "Interface: $IFACE"
        
        # Get interface details
        if ip link show dev $IFACE &>/dev/null; then
            # State
            STATE=$(ip link show dev $IFACE 2>/dev/null | grep -o "state [A-Z]*" | cut -d' ' -f2)
            case $STATE in
                UP) print_success "State: $STATE" ;;
                DOWN) print_error "State: $STATE" ;;
                *) print_warning "State: $STATE" ;;
            esac
            
            # MTU
            MTU=$(ip link show dev $IFACE 2>/dev/null | grep -o "mtu [0-9]*" | cut -d' ' -f2)
            [[ -n "$MTU" ]] && echo "  MTU: $MTU"
            
            # IP Address
            IP_ADDR=$(ip addr show dev $IFACE 2>/dev/null | grep "inet " | awk '{print $2}')
            if [[ -n "$IP_ADDR" ]]; then
                print_success "IP Address: $IP_ADDR"
            else
                print_error "No IP address assigned"
            fi
            
            # Remote IP (from link info)
            REMOTE_IP=$(ip addr show dev $IFACE 2>/dev/null | grep "link/gre" | grep -o "remote [0-9.]*" | cut -d' ' -f2)
            [[ -n "$REMOTE_IP" ]] && echo "  Remote: $REMOTE_IP"
        else
            print_error "Interface $IFACE not accessible"
        fi
    done
    
    return 0
}

# Check routing
check_routing() {
    print_subsection "ROUTING INFORMATION"
    
    # Check for GRE routes
    GRE_ROUTES=$(ip route show 2>/dev/null | grep -E "gre|10\.100\.100")
    
    if [[ -z "$GRE_ROUTES" ]]; then
        print_warning "No GRE-specific routes found"
    else
        print_success "GRE routes configured:"
        echo "$GRE_ROUTES" | while read ROUTE; do
            echo "  $ROUTE"
        done
    fi
    
    # Check default route
    DEFAULT_ROUTE=$(ip route show default 2>/dev/null)
    if [[ -n "$DEFAULT_ROUTE" ]]; then
        echo ""
        print_info "Default Route:"
        echo "  $DEFAULT_ROUTE"
    fi
}

# Check service status
check_service_status() {
    print_subsection "SERVICE STATUS"
    
    if systemctl list-unit-files | grep -q gre-tunnel; then
        SERVICE_STATUS=$(systemctl is-active gre-tunnel 2>/dev/null)
        case $SERVICE_STATUS in
            active) print_success "gre-tunnel.service: ACTIVE" ;;
            inactive) print_error "gre-tunnel.service: INACTIVE" ;;
            failed) print_error "gre-tunnel.service: FAILED" ;;
            *) print_warning "gre-tunnel.service: $SERVICE_STATUS" ;;
        esac
        
        # Show service details if active
        if [[ "$SERVICE_STATUS" == "active" ]]; then
            ENABLED=$(systemctl is-enabled gre-tunnel 2>/dev/null)
            [[ "$ENABLED" == "enabled" ]] && echo "  Autostart: Enabled" || echo "  Autostart: Disabled"
        fi
    else
        print_warning "gre-tunnel.service not found"
    fi
}

# Check connectivity
check_connectivity() {
    print_subsection "CONNECTIVITY TEST"
    
    # Test standard GRE IPs
    declare -A TEST_IPS=(
        ["10.100.100.1"]="Source Server (Iran)"
        ["10.100.100.2"]="Destination Server (Foreign)"
    )
    
    for IP in "${!TEST_IPS[@]}"; do
        DESCRIPTION="${TEST_IPS[$IP]}"
        
        # Try ping
        if timeout 2 ping -c 1 $IP &>/dev/null; then
            print_success "$DESCRIPTION ($IP): REACHABLE"
            
            # Measure latency
            if command -v ping &>/dev/null; then
                LATENCY=$(ping -c 2 -W 1 $IP 2>/dev/null | grep rtt | awk -F'/' '{print $5}' || echo "N/A")
                echo "  Latency: ${LATENCY}ms"
            fi
        else
            print_error "$DESCRIPTION ($IP): NOT REACHABLE"
        fi
    done
    
    # Additional connectivity check through GRE interface
    for IFACE in $(ip link show 2>/dev/null | grep -o "gre[^:]*"); do
        IP=$(ip addr show dev $IFACE 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
        if [[ -n "$IP" ]]; then
            REMOTE_IP=$(echo $IP | sed 's/\.1$/.2/; s/\.2$/.1/')
            if timeout 2 ping -c 1 -I $IFACE $REMOTE_IP &>/dev/null 2>&1; then
                print_success "Tunnel $IFACE: Working correctly"
            else
                print_error "Tunnel $IFACE: No connectivity"
            fi
        fi
    done
}

# Check system configuration
check_system_config() {
    print_subsection "SYSTEM CONFIGURATION"
    
    # IP Forwarding
    IP_FORWARD=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)
    if [[ "$IP_FORWARD" == "1" ]]; then
        print_success "IP Forwarding: ENABLED"
    else
        print_error "IP Forwarding: DISABLED"
    fi
    
    # Check GRE module
    if lsmod | grep -q "ip_gre"; then
        print_success "GRE Kernel Module: LOADED"
    else
        print_warning "GRE Kernel Module: NOT LOADED"
    fi
    
    # Check firewall rules
    if command -v iptables &>/dev/null; then
        GRE_RULES=$(iptables -L -n 2>/dev/null | grep -c "gre")
        if [[ $GRE_RULES -gt 0 ]]; then
            print_success "Firewall: $GRE_RULES GRE rule(s) found"
        else
            print_warning "Firewall: No GRE-specific rules"
        fi
    fi
    
    # Check BBR congestion control (if optimized)
    TCP_CONGESTION=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
    if [[ "$TCP_CONGESTION" == "bbr" ]]; then
        print_success "TCP Congestion Control: BBR (Optimized)"
    else
        echo "  TCP Congestion Control: $TCP_CONGESTION"
    fi
}

# Check traffic statistics
check_traffic_stats() {
    print_subsection "TRAFFIC STATISTICS"
    
    GRE_INTERFACES=$(ip link show 2>/dev/null | grep -o "gre[^:]*")
    
    if [[ -z "$GRE_INTERFACES" ]]; then
        print_warning "No GRE interfaces for statistics"
        return
    fi
    
    for IFACE in $GRE_INTERFACES; do
        STATS=$(ip -s link show dev $IFACE 2>/dev/null | tail -n 3)
        if [[ -n "$STATS" ]]; then
            print_info "Interface $IFACE:"
            echo "$STATS" | awk '{print "  "$0}'
        fi
    done
}

# Show quick help
show_quick_help() {
    print_subsection "QUICK COMMANDS"
    
    cat << EOF
  Check tunnel:      ip addr show | grep -A2 gre
  Test connectivity: ping 10.100.100.1
  Monitor traffic:   sudo tcpdump -i gre-ir -n
  Restart service:   sudo systemctl restart gre-tunnel
  View logs:         sudo journalctl -u gre-tunnel -f
  Remove tunnel:     sudo ip link delete gre-ir
EOF
}

# Generate report
generate_report() {
    print_section
    
    echo "Generated: $(date)"
    echo "Hostname: $(hostname)"
    echo "Public IP: $(curl -s ifconfig.me 2>/dev/null || echo "Unknown")"
    echo ""
    
    # Run all checks
    check_root
    detect_gre_interfaces
    check_routing
    check_service_status
    check_connectivity
    check_system_config
    check_traffic_stats
    show_quick_help
    
    echo ""
    echo "========================================"
    echo "        STATUS CHECK COMPLETE           "
    echo "========================================"
    echo ""
    
    # Summary
    print_subsection "SUMMARY"
    
    GRE_COUNT=$(ip link show 2>/dev/null | grep -c "gre[^:]")
    if [[ $GRE_COUNT -gt 0 ]]; then
        print_success "$GRE_COUNT GRE tunnel(s) detected"
        
        # Check if any tunnel is down
        DOWN_COUNT=$(ip link show 2>/dev/null | grep "gre" | grep -c "state DOWN")
        if [[ $DOWN_COUNT -gt 0 ]]; then
            print_warning "$DOWN_COUNT tunnel(s) are DOWN"
        fi
    else
        print_error "No active GRE tunnels"
    fi
}

# Main function
main() {
    # Check if ip command exists
    if ! command -v ip &>/dev/null; then
        echo "Error: 'ip' command not found. Install iproute2 package."
        exit 1
    fi
    
    # Parse arguments
    case "${1:-}" in
        "--help"|"-h")
            echo "Usage: $0 [OPTION]"
            echo ""
            echo "Options:"
            echo "  --help, -h     Show this help"
            echo "  --quick, -q    Quick status only"
            echo "  --json         Output in JSON format"
            echo ""
            echo "Examples:"
            echo "  $0             Full status report"
            echo "  $0 --quick     Quick tunnel check"
            exit 0
            ;;
        "--quick"|"-q")
            echo "Quick GRE Tunnel Status:"
            echo "-----------------------"
            ip link show | grep "gre" | while read LINE; do
                IFACE=$(echo $LINE | awk -F: '{print $2}' | xargs)
                STATE=$(echo $LINE | grep -o "state [A-Z]*" | cut -d' ' -f2)
                if [[ "$STATE" == "UP" ]]; then
                    echo -e "${GREEN}✓${NC} $IFACE: $STATE"
                else
                    echo -e "${RED}✗${NC} $IFACE: $STATE"
                fi
            done
            exit 0
            ;;
        "--json")
            # JSON output for automation
            echo "{"
            echo "  \"timestamp\": \"$(date -Iseconds)\","
            echo "  \"gre_tunnels\": ["
            ip link show 2>/dev/null | grep "gre" | while read LINE; do
                IFACE=$(echo $LINE | awk -F: '{print $2}' | xargs)
                STATE=$(echo $LINE | grep -o "state [A-Z]*" | cut -d' ' -f2)
                echo "    {\"interface\": \"$IFACE\", \"state\": \"$STATE\"},"
            done | sed '$ s/,$//'
            echo "  ]"
            echo "}"
            exit 0
            ;;
    esac
    
    # Generate full report
    generate_report
}

# Run main function
main "$@"
