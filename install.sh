#!/bin/bash

# ============================================
# GRE Tunnel Auto-Setup Script
# Version: 2.0
# Repository: https://github.com/ach1992/simple-gre
# ============================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
fi

# Function to install dependencies
install_dependencies() {
    log "Installing system dependencies..."
    
    if command -v apt &> /dev/null; then
        apt update
        apt install -y iproute2 iptables iptables-persistent net-tools iperf3 tcpdump curl wget
    elif command -v yum &> /dev/null; then
        yum install -y iproute iptables iptables-services net-tools iperf3 tcpdump curl wget
    elif command -v dnf &> /dev/null; then
        dnf install -y iproute iptables iptables-services net-tools iperf3 tcpdump curl wget
    else
        warn "Package manager not detected, please install dependencies manually"
    fi
    
    # Load GRE module
    modprobe ip_gre
    echo "ip_gre" >> /etc/modules-load.d/gre.conf
    
    log "Dependencies installed successfully"
}

# Function to get network info
get_network_info() {
    log "Getting network information..."
    
    # Get public IP
    PUBLIC_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || echo "unknown")
    log "Server Public IP: $PUBLIC_IP"
    
    # Get default interface
    DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    log "Default Interface: $DEFAULT_IFACE"
    
    # Detect server location
    log "Detecting server location..."
    COUNTRY_CODE=$(curl -s ipinfo.io/country || echo "unknown")
    if [[ "$COUNTRY_CODE" == "IR" ]]; then
        SERVER_LOCATION="iran"
        log "Location: Iran Server"
    else
        SERVER_LOCATION="foreign"
        log "Location: Foreign Server"
    fi
}

# Function to configure tunnel
configure_tunnel() {
    clear
    echo "========================================"
    echo "    GRE Tunnel Configuration Wizard     "
    echo "========================================"
    echo ""
    
    echo "Select server role:"
    echo "1) Source Server (Iran - Server A)"
    echo "2) Destination Server (Foreign - Server B)"
    read -p "Your choice [1/2]: " SERVER_ROLE
    
    if [[ $SERVER_ROLE == "1" ]]; then
        # Source Server (Iran)
        ROLE="source"
        LOCAL_TUN_IP="10.100.100.1"
        REMOTE_TUN_IP="10.100.100.2"
        TUNNEL_NAME="gre-ir"
        log "Role: Source Server (Iran) - Local IP: $LOCAL_TUN_IP"
    elif [[ $SERVER_ROLE == "2" ]]; then
        # Destination Server (Foreign)
        ROLE="destination"
        LOCAL_TUN_IP="10.100.100.2"
        REMOTE_TUN_IP="10.100.100.1"
        TUNNEL_NAME="gre-fr"
        log "Role: Destination Server (Foreign) - Local IP: $LOCAL_TUN_IP"
    else
        error "Invalid choice. Please select 1 or 2"
    fi
    
    # Get remote server IP
    if [[ $SERVER_ROLE == "1" ]]; then
        read -p "Enter Foreign Server Public IP: " REMOTE_SERVER_IP
    else
        read -p "Enter Iran Server Public IP: " REMOTE_SERVER_IP
    fi
    
    if [[ -z "$REMOTE_SERVER_IP" ]]; then
        error "Remote server IP cannot be empty"
    fi
    
    # Get local server IP
    read -p "Enter this server's public IP [$PUBLIC_IP]: " LOCAL_SERVER_IP
    LOCAL_SERVER_IP=${LOCAL_SERVER_IP:-$PUBLIC_IP}
    
    # Select MTU
    read -p "Enter MTU value [default: 1476]: " MTU_INPUT
    MTU=${MTU_INPUT:-1476}
    
    # Ask for optimization
    read -p "Enable advanced optimization? [y/N]: " OPTIMIZE
    OPTIMIZE=${OPTIMIZE:-n}
    
    # Ask for persistent config
    read -p "Make configuration persistent after reboot? [Y/n]: " PERSISTENT
    PERSISTENT=${PERSISTENT:-y}
    
    # Ask for firewall rules
    read -p "Configure firewall rules? [Y/n]: " FIREWALL
    FIREWALL=${FIREWALL:-y}
    
    # Summary
    echo ""
    echo "========================================"
    echo "          Configuration Summary         "
    echo "========================================"
    echo "Server Role: $([ "$SERVER_ROLE" == "1" ] && echo "Source (Iran)" || echo "Destination (Foreign)")"
    echo "Local GRE IP: $LOCAL_TUN_IP"
    echo "Remote GRE IP: $REMOTE_TUN_IP"
    echo "Remote Server IP: $REMOTE_SERVER_IP"
    echo "Local Server IP: $LOCAL_SERVER_IP"
    echo "Tunnel Name: $TUNNEL_NAME"
    echo "MTU: $MTU"
    echo "Optimization: $([ "$OPTIMIZE" == "y" ] && echo "Enabled" || echo "Disabled")"
    echo "Persistent: $([ "$PERSISTENT" == "y" ] && echo "Enabled" || echo "Disabled")"
    echo "Firewall: $([ "$FIREWALL" == "y" ] && echo "Enabled" || echo "Disabled")"
    echo "========================================"
    
    read -p "Continue with setup? [Y/n]: " CONFIRM
    CONFIRM=${CONFIRM:-y}
    
    if [[ $CONFIRM != "y" && $CONFIRM != "Y" ]]; then
        error "Setup cancelled by user"
    fi
}

# Function to create tunnel
create_tunnel() {
    log "Creating GRE tunnel..."
    
    # Remove existing tunnel if any
    ip link delete $TUNNEL_NAME 2>/dev/null || true
    
    # Create GRE tunnel
    ip tunnel add $TUNNEL_NAME mode gre remote $REMOTE_SERVER_IP local $LOCAL_SERVER_IP ttl 255
    ip addr add $LOCAL_TUN_IP/30 dev $TUNNEL_NAME
    ip link set $TUNNEL_NAME up mtu $MTU
    
    # Add route
    ip route add 10.100.100.0/30 dev $TUNNEL_NAME
    
    log "Tunnel $TUNNEL_NAME created successfully"
}

# Function to optimize network
optimize_network() {
    if [[ $OPTIMIZE != "y" ]]; then
        return
    fi
    
    log "Optimizing network settings..."
    
    # Kernel optimization
    cat >> /etc/sysctl.conf << EOF

# GRE Tunnel Optimization
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.$TUNNEL_NAME.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    
    sysctl -p
    
    # TCP optimization for GRE
    iptables -t mangle -A FORWARD -o $TUNNEL_NAME -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
    
    log "Network optimization completed"
}

# Function to configure firewall
configure_firewall() {
    if [[ $FIREWALL != "y" ]]; then
        return
    fi
    
    log "Configuring firewall rules..."
    
    # Allow GRE protocol
    iptables -A INPUT -p gre -j ACCEPT
    
    # Allow tunnel traffic
    iptables -A INPUT -i $TUNNEL_NAME -j ACCEPT
    iptables -A FORWARD -i $TUNNEL_NAME -j ACCEPT
    iptables -A FORWARD -o $TUNNEL_NAME -j ACCEPT
    
    # NAT for source server (Iran)
    if [[ $SERVER_ROLE == "1" ]]; then
        iptables -t nat -A POSTROUTING -s 10.100.100.0/30 -o $DEFAULT_IFACE -j MASQUERADE
        log "NAT masquerade enabled for source server"
    fi
    
    # Save iptables rules if available
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save
    elif command -v iptables-save &> /dev/null; then
        iptables-save > /etc/iptables/rules.v4
    fi
    
    log "Firewall configuration completed"
}

# Function to make persistent
make_persistent() {
    if [[ $PERSISTENT != "y" ]]; then
        return
    fi
    
    log "Creating persistent configuration..."
    
    # Create systemd service
    cat > /etc/systemd/system/gre-tunnel.service << EOF
[Unit]
Description=GRE Tunnel Service
After=network.target
Wants=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/gre-tunnel-start.sh
ExecStop=/usr/local/bin/gre-tunnel-stop.sh

[Install]
WantedBy=multi-user.target
EOF
    
    # Create start script
    cat > /usr/local/bin/gre-tunnel-start.sh << EOF
#!/bin/bash
ip tunnel add $TUNNEL_NAME mode gre remote $REMOTE_SERVER_IP local $LOCAL_SERVER_IP ttl 255
ip addr add $LOCAL_TUN_IP/30 dev $TUNNEL_NAME
ip link set $TUNNEL_NAME up mtu $MTU
ip route add 10.100.100.0/30 dev $TUNNEL_NAME
EOF
    
    # Create stop script
    cat > /usr/local/bin/gre-tunnel-stop.sh << EOF
#!/bin/bash
ip link delete $TUNNEL_NAME 2>/dev/null || true
EOF
    
    chmod +x /usr/local/bin/gre-tunnel-start.sh /usr/local/bin/gre-tunnel-stop.sh
    systemctl daemon-reload
    systemctl enable gre-tunnel.service
    
    # Also add to rc.local for compatibility
    echo "/usr/local/bin/gre-tunnel-start.sh" >> /etc/rc.local
    chmod +x /etc/rc.local
    
    log "Persistent configuration saved"
    log "Service will auto-start on boot: systemctl enable gre-tunnel"
}

# Function to test tunnel
test_tunnel() {
    log "Testing tunnel connection..."
    
    # Wait for tunnel stabilization
    sleep 2
    
    # Test connectivity
    if ping -c 3 -I $TUNNEL_NAME $REMOTE_TUN_IP &> /dev/null; then
        log "✅ Tunnel is active and reachable"
        
        # Measure latency
        PING_RESULT=$(ping -c 5 -I $TUNNEL_NAME $REMOTE_TUN_IP | grep rtt)
        log "Network latency: $PING_RESULT"
        
        # Optional bandwidth test
        read -p "Perform bandwidth test? [y/N]: " TEST_BW
        if [[ $TEST_BW == "y" || $TEST_BW == "Y" ]]; then
            log "Starting bandwidth test (10 seconds)..."
            iperf3 -s -D  # Start server in background
            sleep 1
            iperf3 -c $REMOTE_TUN_IP -t 10 -i 1
            pkill iperf3
        fi
    else
        warn "Tunnel is not responding. Please check configuration"
        
        # Debug information
        echo ""
        info "Debug Information:"
        ip addr show $TUNNEL_NAME
        ip route show
        echo ""
        warn "Please verify:"
        warn "1. Remote server IP is correct"
        warn "2. Port 47 is open in firewall"
        warn "3. Remote server has tunnel configured"
    fi
}

# Function to generate configuration for opposite server
generate_opposite_config() {
    log "Generating configuration for opposite server..."
    
    CONFIG_FILE="/tmp/gre-opposite-config.txt"
    
    cat > $CONFIG_FILE << EOF
# Configuration for Opposite Server
# =================================

SERVER ROLE: $([ "$SERVER_ROLE" == "1" ] && echo "DESTINATION (Foreign)" || echo "SOURCE (Iran)")

Your Server Configuration:
- Public IP: $LOCAL_SERVER_IP
- Local GRE IP: $LOCAL_TUN_IP
- Tunnel Name: $TUNNEL_NAME

Opposite Server Should Use:
- Public IP: $REMOTE_SERVER_IP
- Local GRE IP: $REMOTE_TUN_IP
- Tunnel Name: $([ "$SERVER_ROLE" == "1" ] && echo "gre-fr" || echo "gre-ir")

Quick Setup Command for Opposite Server:
bash <(curl -s https://raw.githubusercontent.com/ach1992/simple-gre/main/install.sh)

Manual Configuration:
1. Install dependencies:
   apt update && apt install -y iproute2 iptables

2. Create tunnel:
   ip tunnel add $([ "$SERVER_ROLE" == "1" ] && echo "gre-fr" || echo "gre-ir") \\
     mode gre remote $LOCAL_SERVER_IP local $REMOTE_SERVER_IP ttl 255
   
   ip addr add $REMOTE_TUN_IP/30 dev $([ "$SERVER_ROLE" == "1" ] && echo "gre-fr" || echo "gre-ir")
   ip link set $([ "$SERVER_ROLE" == "1" ] && echo "gre-fr" || echo "gre-ir") up mtu $MTU
   ip route add 10.100.100.0/30 dev $([ "$SERVER_ROLE" == "1" ] && echo "gre-fr" || echo "gre-ir")

3. Enable forwarding:
   echo 1 > /proc/sys/net/ipv4/ip_forward

4. Test connection:
   ping $LOCAL_TUN_IP
EOF
    
    log "Configuration saved to: $CONFIG_FILE"
    cat $CONFIG_FILE
}

# Function to show management commands
show_management_commands() {
    echo ""
    echo "========================================"
    echo "      Management Commands              "
    echo "========================================"
    echo ""
    echo "📡 Tunnel Status:"
    echo "   ip addr show $TUNNEL_NAME"
    echo "   ip -s link show $TUNNEL_NAME"
    echo ""
    echo "🔄 Connection Test:"
    echo "   ping -I $TUNNEL_NAME $REMOTE_TUN_IP"
    echo "   traceroute -n -i $TUNNEL_NAME $REMOTE_TUN_IP"
    echo ""
    echo "📊 Traffic Monitoring:"
    echo "   tcpdump -i $TUNNEL_NAME -n"
    echo "   iftop -i $TUNNEL_NAME"
    echo "   bmon -p $TUNNEL_NAME"
    echo ""
    echo "⚡ Service Management:"
    echo "   systemctl status gre-tunnel"
    echo "   systemctl restart gre-tunnel"
    echo "   systemctl stop gre-tunnel"
    echo ""
    echo "🗑️  Remove Tunnel:"
    echo "   ip link delete $TUNNEL_NAME"
    echo "   systemctl disable gre-tunnel"
    echo ""
    
    # Proxy configuration tips
    if [[ $SERVER_ROLE == "2" ]]; then
        echo "🚀 For Proxy Setup (on Foreign Server):"
        echo "   You can run Xray/V2Ray on IP: $LOCAL_TUN_IP"
        echo "   Recommended port: 2082, 2083, 2086"
        echo ""
        echo "Example Xray config:"
        echo "   \"listen\": \"$LOCAL_TUN_IP\","
        echo "   \"port\": 2082,"
    fi
    
    echo "========================================"
}

# Main execution
main() {
    echo "========================================"
    echo "    GRE Tunnel Auto-Setup Script       "
    echo "    For Iran-Foreign Server Connection "
    echo "========================================"
    echo ""
    
    # Check dependencies
    if ! command -v ip &> /dev/null; then
        install_dependencies
    fi
    
    # Get network info
    get_network_info
    
    # Configure tunnel
    configure_tunnel
    
    # Create tunnel
    create_tunnel
    
    # Optimize network
    optimize_network
    
    # Configure firewall
    configure_firewall
    
    # Make persistent
    make_persistent
    
    # Test tunnel
    test_tunnel
    
    # Generate config for opposite server
    generate_opposite_config
    
    # Show management commands
    show_management_commands
    
    log "✅ Setup completed successfully!"
    echo ""
    info "Next step: Configure the opposite server using the instructions above"
    info "Repository: https://github.com/ach1992/simple-gre"
}

# Run main function
main "$@"
