#!/bin/bash
# =============================================================================
# Site Analysis Tool
# Comprehensive network and connectivity assessment for on-site visits
# =============================================================================

set -euo pipefail

REPORT_DIR="$(dirname "$0")/reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SITE_NAME="${1:-unknown-site}"
HOSTNAME=$(hostname)
REPORT_FILE="$REPORT_DIR/${SITE_NAME}_${HOSTNAME}_${TIMESTAMP}.txt"
DEV_SERVER="jason@10.0.10.21"
DEV_SERVER_PATH="~/site-reports/"

mkdir -p "$REPORT_DIR"

# Colors for terminal output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()   { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[-]${NC} $1"; }

section() {
    {
        echo ""
        echo "============================================================================="
        echo "  $1"
        echo "============================================================================="
        echo ""
    } | tee -a "$REPORT_FILE"
}

run_cmd() {
    local desc="$1"
    shift
    echo "--- $desc ---" >> "$REPORT_FILE"
    if "$@" >> "$REPORT_FILE" 2>&1; then
        log "$desc"
    else
        warn "$desc (command returned non-zero or not available)"
    fi
    echo "" >> "$REPORT_FILE"
}

run_sudo_cmd() {
    local desc="$1"
    shift
    echo "--- $desc ---" >> "$REPORT_FILE"
    if sudo "$@" >> "$REPORT_FILE" 2>&1; then
        log "$desc"
    else
        warn "$desc (requires sudo or not available)"
    fi
    echo "" >> "$REPORT_FILE"
}

# =============================================================================
# Header
# =============================================================================

{
    echo "============================================================================="
    echo "  SITE ANALYSIS REPORT"
    echo "  Site: $SITE_NAME"
    echo "  Host: $HOSTNAME"
    echo "  Date: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "  Analyst: $(whoami)"
    echo "============================================================================="
} | tee "$REPORT_FILE"

# =============================================================================
# 1. System Info
# =============================================================================

section "1. SYSTEM INFORMATION"
run_cmd "Hostname & OS" hostnamectl
run_cmd "Kernel" uname -a
run_cmd "Uptime" uptime

# =============================================================================
# 2. Network Interfaces
# =============================================================================

section "2. NETWORK INTERFACES"
run_cmd "All interfaces" ip addr
run_cmd "Interface link states" ip link show
run_cmd "Interface statistics" ip -s link

# Ethtool on active wired interfaces (if ethtool is installed)
if command -v ethtool &>/dev/null; then
    for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -v lo); do
        run_cmd "Ethtool: $iface" ethtool "$iface" || true
    done
else
    echo "--- Ethtool ---" >> "$REPORT_FILE"
    echo "ethtool not installed" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

# =============================================================================
# 3. Routing & Gateway
# =============================================================================

section "3. ROUTING & GATEWAY"
run_cmd "Routing table" ip route
run_cmd "Default gateway" ip route show default
run_cmd "ARP table" ip neigh

# =============================================================================
# 4. DNS Configuration
# =============================================================================

section "4. DNS CONFIGURATION"
run_cmd "Resolv.conf" cat /etc/resolv.conf
run_cmd "Systemd-resolved status" resolvectl status || true
run_cmd "DNS lookup: google.com" dig google.com +short
run_cmd "DNS lookup: cloudflare.com" dig cloudflare.com +short
run_cmd "Reverse DNS: gateway" dig -x "$(ip route show default | awk '{print $3}' | head -1)" +short || true

# DNS response time
{
    echo "--- DNS Response Times ---"
    for server in 8.8.8.8 1.1.1.1 9.9.9.9; do
        echo -n "  $server: "
        dig @"$server" google.com +stats 2>/dev/null | grep "Query time" || echo "failed"
    done
    echo ""
} >> "$REPORT_FILE"
log "DNS response times"

# =============================================================================
# 5. Public IP & ISP
# =============================================================================

section "5. PUBLIC IP & ISP INFORMATION"
run_cmd "Public IP (ifconfig.me)" curl -s --max-time 10 ifconfig.me
echo "" >> "$REPORT_FILE"
run_cmd "ISP details (ipinfo.io)" curl -s --max-time 10 ipinfo.io
run_cmd "Whois on public IP" bash -c 'whois $(curl -s --max-time 10 ifconfig.me) 2>/dev/null | head -40'

# =============================================================================
# 6. INTERNET SPEED TEST
# =============================================================================

section "6. INTERNET SPEED TEST"
if command -v speedtest-cli &>/dev/null; then
    run_cmd "Speedtest (speedtest-cli)" speedtest-cli --simple
else
    warn "speedtest-cli not installed, skipping"
    echo "speedtest-cli not installed - run: sudo pacman -S speedtest-cli" >> "$REPORT_FILE"
fi

# =============================================================================
# 7. WiFi ANALYSIS
# =============================================================================

section "7. WiFi ANALYSIS"

WIFI_IFACE=$(iw dev 2>/dev/null | awk '/Interface/{print $2}' | head -1)

if [ -n "$WIFI_IFACE" ]; then
    run_cmd "WiFi interface info" iw dev "$WIFI_IFACE" info
    run_cmd "WiFi link quality" iw dev "$WIFI_IFACE" link
    run_cmd "WiFi station stats" iw dev "$WIFI_IFACE" station dump

    # Current connection details via nmcli (if available) or iwctl
    if command -v nmcli &>/dev/null; then
        run_cmd "Active WiFi connection (nmcli)" nmcli -f all dev wifi show
        run_cmd "WiFi connection details (nmcli)" nmcli dev show "$WIFI_IFACE"
        {
            echo "--- WiFi Networks Summary (nmcli) ---"
            nmcli -f SSID,BSSID,MODE,CHAN,FREQ,RATE,SIGNAL,BARS,SECURITY dev wifi list 2>/dev/null || echo "nmcli not available"
            echo ""
        } >> "$REPORT_FILE"
        log "WiFi networks summary (nmcli)"
    fi

    if command -v iwctl &>/dev/null; then
        run_cmd "WiFi connection details (iwctl)" iwctl station "$WIFI_IFACE" show
    fi

    # Scan for all nearby networks (try without sudo first via cached scan dump)
    log "Scanning for nearby WiFi networks..."
    run_cmd "WiFi network scan (cached)" iw dev "$WIFI_IFACE" scan dump
    # If running as root, do a fresh scan
    if [ "$(id -u)" -eq 0 ]; then
        run_cmd "WiFi network scan (live)" iw dev "$WIFI_IFACE" scan
    fi

    # WiFi channel utilization
    run_cmd "WiFi regulatory domain" iw reg get
else
    warn "No WiFi interface detected"
    echo "No WiFi interface found on this system." >> "$REPORT_FILE"
fi

# =============================================================================
# 8. LATENCY & CONNECTIVITY
# =============================================================================

section "8. LATENCY & CONNECTIVITY TESTS"

GATEWAY=$(ip route show default | awk '{print $3}' | head -1)

# Ping tests
for target in "$GATEWAY" 8.8.8.8 1.1.1.1 google.com; do
    run_cmd "Ping: $target (10 packets)" ping -c 10 -W 2 "$target"
done

# MTR tests
for target in 8.8.8.8 google.com; do
    run_cmd "MTR: $target (10 cycles)" mtr -rwbc 10 "$target"
done

# =============================================================================
# 9. TRACEROUTE
# =============================================================================

section "9. TRACEROUTE"
run_cmd "Traceroute: 8.8.8.8" traceroute -w 2 -m 20 8.8.8.8
run_cmd "Traceroute: google.com" traceroute -w 2 -m 20 google.com

# =============================================================================
# 10. LOCAL NETWORK DISCOVERY
# =============================================================================

section "10. LOCAL NETWORK DISCOVERY"

SUBNET=$(ip -o -4 addr show | grep -v '127.0.0.1' | head -1 | awk '{print $4}')

if [ -n "$SUBNET" ]; then
    run_sudo_cmd "ARP scan: $SUBNET" arp-scan --localnet
    run_cmd "Nmap host discovery: $SUBNET" nmap -sn "$SUBNET"
else
    warn "Could not determine local subnet"
fi

# =============================================================================
# 11. PORT & SERVICE SCAN (LOCAL GATEWAY)
# =============================================================================

section "11. GATEWAY & COMMON SERVICES"
if [ -n "$GATEWAY" ]; then
    run_cmd "Gateway port scan" nmap -T4 -F "$GATEWAY"
fi

# Common port reachability
{
    echo "--- External Port Reachability ---"
    for port in 80 443 53 22; do
        echo -n "  Port $port (8.8.8.8): "
        nc -zw2 8.8.8.8 "$port" 2>&1 && echo "OPEN" || echo "CLOSED/FILTERED"
    done
    echo ""
} >> "$REPORT_FILE"
log "External port reachability"

# =============================================================================
# 12. DHCP INFORMATION
# =============================================================================

section "12. DHCP INFORMATION"
run_cmd "DHCP lease files" bash -c 'cat /var/lib/dhclient/*.leases 2>/dev/null || cat /var/lib/NetworkManager/*.lease 2>/dev/null || echo "No DHCP lease files found (may use systemd-networkd or internal NM state)"'
if command -v nmcli &>/dev/null; then
    run_cmd "NetworkManager connections" nmcli connection show --active
elif command -v iwctl &>/dev/null; then
    run_cmd "IWD known networks" iwctl known-networks list
fi
run_cmd "Networkctl status" networkctl status 2>/dev/null || true

# =============================================================================
# 13. FIREWALL STATUS
# =============================================================================

section "13. FIREWALL STATUS (LOCAL)"
run_sudo_cmd "UFW status" ufw status verbose
run_sudo_cmd "iptables rules" iptables -L -n -v
run_sudo_cmd "nftables rules" nft list ruleset

# =============================================================================
# 14. BANDWIDTH TEST (iperf3)
# =============================================================================

section "14. BANDWIDTH TEST (iperf3)"
{
    echo "iperf3 requires a remote server to test against."
    echo "To run manually:"
    echo "  Server: iperf3 -s"
    echo "  Client: iperf3 -c <server-ip>"
    echo ""
    echo "Public iperf3 servers can be found at: https://iperf3serverlist.net"
    echo ""
} >> "$REPORT_FILE"

# Try a known public iperf3 server
if command -v iperf3 &>/dev/null; then
    run_cmd "iperf3: bouygues.iperf.fr" iperf3 -c bouygues.iperf.fr -t 5 || true
fi

# =============================================================================
# 15. ADDITIONAL DIAGNOSTICS
# =============================================================================

section "15. ADDITIONAL DIAGNOSTICS"
run_cmd "Open TCP connections" ss -tunap
run_cmd "Listening services" ss -tlnp
run_cmd "Network namespaces" ip netns list || true
run_cmd "Bridge devices" bridge link show 2>/dev/null || true

# Check for packet loss / network quality over 30 seconds
{
    echo "--- Network Quality (30s continuous ping to gateway) ---"
    ping -c 30 -i 0.2 -W 1 "$GATEWAY" 2>/dev/null | tail -3
    echo ""
} >> "$REPORT_FILE"
log "Network quality test (30s)"

# =============================================================================
# Summary
# =============================================================================

section "END OF REPORT"
{
    echo "Report generated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "Report file: $REPORT_FILE"
    echo "File size: $(du -h "$REPORT_FILE" | cut -f1)"
} | tee -a "$REPORT_FILE"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} Report saved to: $REPORT_FILE${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# =============================================================================
# Send to dev server
# =============================================================================

read -rp "Send report to dev server ($DEV_SERVER)? [y/N] " send
if [[ "$send" =~ ^[Yy]$ ]]; then
    ssh "$DEV_SERVER" "mkdir -p $DEV_SERVER_PATH" 2>/dev/null
    if scp "$REPORT_FILE" "$DEV_SERVER:$DEV_SERVER_PATH"; then
        log "Report sent to $DEV_SERVER:$DEV_SERVER_PATH"
    else
        err "Failed to send report. You can send manually with:"
        echo "  scp $REPORT_FILE $DEV_SERVER:$DEV_SERVER_PATH"
    fi
fi
