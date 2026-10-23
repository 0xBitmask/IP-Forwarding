#!/bin/bash
# IP Forwarding Script for Orange Pi Zero 3
# Routes traffic from Tailscale to local LAN (Raspberry Pi web server)
#
# Usage:
#   ./ip_forward.sh enable    - Enable IP forwarding
#   ./ip_forward.sh disable   - Disable IP forwarding
#   ./ip_forward.sh status    - Check forwarding status
#   ./ip_forward.sh advertise - Advertise LAN subnet via Tailscale
#   ./ip_forward.sh test      - Run connectivity test

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.conf"
LOG_FILE="/var/log/ip_forwarding.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "$msg"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

die() {
    log "${RED}ERROR: $1${NC}"
    exit 1
}

load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        die "Config file not found: $CONFIG_FILE"
    fi
    # shellcheck source=config.conf
    source "$CONFIG_FILE"
}

check_root() {
    [[ $EUID -eq 0 ]] || die "Must run as root"
}

# Check if an IP belongs to a subnet (supports /24 home LANs via first 3 octets)
ip_in_subnet() {
    local ip="$1" cidr="$2" cidr_prefix
    cidr_prefix="${cidr%/*}"
    [[ "${ip%.*}" == "${cidr_prefix%.*}" ]]
}

# Find the interface that has an IP inside LAN_SUBNET
resolve_lan_if() {
    local iface ip
    if [[ -n "${LAN_IF:-}" && -d "/sys/class/net/$LAN_IF" ]]; then
        ip=$(ip -4 addr show "$LAN_IF" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1 || true)
        if [[ -n "$ip" ]] && ip_in_subnet "$ip" "$LAN_SUBNET"; then
            echo "$LAN_IF"
            return 0
        fi
        log "${YELLOW}  note: $LAN_IF has no IP in $LAN_SUBNET, auto-detecting...${NC}"
    fi
    for iface in /sys/class/net/*; do
        iface="${iface##*/}"
        [[ "$iface" == "lo" || "$iface" == "$TAILSCALE_IF" ]] && continue
        ip=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1 || true)
        if [[ -n "$ip" ]] && ip_in_subnet "$ip" "$LAN_SUBNET"; then
            echo "$iface"
            return 0
        fi
    done
    return 1
}

enable_forwarding() {
    check_root
    load_config

    LAN_IF_LABEL="$(resolve_lan_if)" || die "Cannot find a network interface with IP in $LAN_SUBNET. Check config.conf"
    LAN_IF="$LAN_IF_LABEL"

    log "${YELLOW}Enabling IP forwarding...${NC}"
    log "  LAN interface:       $LAN_IF"
    log "  LAN subnet:          $LAN_SUBNET"
    log "  Target server:       ${TARGET_SERVER:-}"

    # Enable kernel IP forwarding
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
    log "  kernel IPv4 forwarding: ON"

    # Ensure iptables FORWARD chain is ACCEPT
    iptables -P FORWARD ACCEPT 2>/dev/null || true

    # Flush existing rules we might have set (idempotent)
    while iptables -D FORWARD -i "$TAILSCALE_IF" -o "$LAN_IF" -j ACCEPT 2>/dev/null; do :; done
    while iptables -D FORWARD -i "$LAN_IF" -o "$TAILSCALE_IF" -j ACCEPT 2>/dev/null; do :; done
    while iptables -t nat -D POSTROUTING -s 100.64.0.0/10 -o "$LAN_IF" -j MASQUERADE 2>/dev/null; do :; done

    # Allow forwarding between Tailscale and LAN
    iptables -A FORWARD -i "$TAILSCALE_IF" -o "$LAN_IF" -j ACCEPT
    iptables -A FORWARD -i "$LAN_IF" -o "$TAILSCALE_IF" -j ACCEPT

    # Masquerade traffic coming from Tailscale (100.x.x.x) leaving via LAN
    iptables -t nat -A POSTROUTING -s 100.64.0.0/10 -o "$LAN_IF" -j MASQUERADE

    log "${GREEN}IP forwarding enabled${NC}"
    log "  From laptop: http://${TARGET_SERVER:-<target ip>}"
}

disable_forwarding() {
    check_root
    load_config

    LAN_IF_LABEL="$(resolve_lan_if)" || die "Cannot find a network interface with IP in $LAN_SUBNET. Check config.conf"
    LAN_IF="$LAN_IF_LABEL"

    log "${YELLOW}Disabling IP forwarding...${NC}"

    # Remove our iptables rules
    while iptables -D FORWARD -i "$TAILSCALE_IF" -o "$LAN_IF" -j ACCEPT 2>/dev/null; do :; done
    while iptables -D FORWARD -i "$LAN_IF" -o "$TAILSCALE_IF" -j ACCEPT 2>/dev/null; do :; done
    while iptables -t nat -D POSTROUTING -s 100.64.0.0/10 -o "$LAN_IF" -j MASQUERADE 2>/dev/null; do :; done

    # Disable kernel IP forwarding
    sysctl -w net.ipv4.ip_forward=0 > /dev/null
    log "  kernel IPv4 forwarding: OFF"

    log "${GREEN}IP forwarding disabled${NC}"
}

show_status() {
    load_config

    echo "=== IP Forwarding Status ==="
    echo ""

    # Kernel forwarding
    local fwd
    fwd=$(sysctl -n net.ipv4.ip_forward)
    if [[ "$fwd" == "1" ]]; then
        echo -e "  Kernel IPv4 forwarding: ${GREEN}ENABLED${NC}"
    else
        echo -e "  Kernel IPv4 forwarding: ${RED}DISABLED${NC}"
    fi

    # Interface check
    echo ""
    echo "  Interfaces:"
    if ip link show "$TAILSCALE_IF" &>/dev/null; then
        echo -e "    $TAILSCALE_IF: ${GREEN}UP${NC}"
    else
        echo -e "    $TAILSCALE_IF: ${RED}DOWN${NC}"
    fi

    local lan_if=""
    lan_if="$(resolve_lan_if 2>/dev/null || true)"
    if [[ -n "$lan_if" ]]; then
        local lan_ip
        lan_ip=$(ip -4 addr show "$lan_if" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        echo -e "    $lan_if (LAN, IP: ${lan_ip:-?}): ${GREEN}UP${NC}"
    else
        echo -e "    (LAN) : ${RED}no interface found on $LAN_SUBNET${NC}"
    fi

    # iptables rules check
    echo ""
    echo "  iptables FORWARD rules:"
    if [[ -n "$lan_if" ]]; then
        iptables -L FORWARD -n 2>/dev/null | grep -E "($TAILSCALE_IF|$lan_if)" | sed 's/^/    /' || echo "    (none)"
    else
        echo "    (lan iface not resolved)"
    fi

    echo ""
    echo "  iptables NAT POSTROUTING rules:"
    iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -E "100.64.0.0/10" | sed 's/^/    /' || echo "    (none)"

    # Tailscale status
    echo ""
    if command -v tailscale &>/dev/null; then
        echo "  Tailscale status:"
        tailscale status 2>/dev/null | head -5 | sed 's/^/    /' || echo "    (not running)"
    fi
}

advertise_routes() {
    check_root
    load_config

    log "${YELLOW}Advertising LAN subnet via Tailscale...${NC}"

    if ! command -v tailscale &>/dev/null; then
        die "tailscale command not found"
    fi

    tailscale up --advertise-routes="$LAN_SUBNET" --accept-routes
    log "${GREEN}LAN subnet $LAN_SUBNET advertised via Tailscale${NC}"
    log "Approve the route in the Tailscale admin console:"
    log "  https://login.tailscale.com/admin/machines"
}

test_forwarding() {
    load_config

    echo "=== Connectivity Test ==="
    echo ""

    echo "1) Orange Pi -> LAN web server"
    local lan_if=""
    lan_if="$(resolve_lan_if 2>/dev/null || true)"
    if [[ -n "$lan_if" ]]; then
        echo -e "   LAN interface: $lan_if"
    else
        echo -e "   LAN interface: ${RED}not found on $LAN_SUBNET${NC}"
    fi

    if [[ -n "${TARGET_SERVER:-}" ]]; then
        if ping -c 2 -W 2 "$TARGET_SERVER" &>/dev/null; then
            echo -e "   Ping $TARGET_SERVER: ${GREEN}OK${NC}"
        else
            echo -e "   Ping $TARGET_SERVER: ${RED}FAIL${NC} (server unreachable from LAN)"
        fi
    fi

    echo ""
    echo "2) Tailscale"
    if command -v tailscale &>/dev/null; then
        tailscale status 2>/dev/null | head -3 | sed 's/^/   /' || echo "   (not running)"
    else
        echo "   tailscale not installed"
    fi

    echo ""
    echo "3) From your LAPTOP, do:"
    echo "   sudo tailscale up --accept-routes"
    echo ""
    echo "   Then open in browser:"
    echo "   http://${TARGET_SERVER:-<target server ip>}"
    echo ""
    echo "If Ping above is OK but laptop still can't connect,"
    echo "approve the route at: https://login.tailscale.com/admin/machines"
}

usage() {
    echo "Usage: $0 {enable|disable|status|advertise|test}"
    echo ""
    echo "  enable    - Enable IP forwarding from Tailscale to LAN"
    echo "  disable   - Disable IP forwarding"
    echo "  status    - Show current forwarding status"
    echo "  advertise - Advertise LAN subnet route to Tailscale"
    echo "  test      - Run connectivity test"
    echo ""
    echo "Configuration: $CONFIG_FILE"
    echo "Log file:      $LOG_FILE"
}

case "${1:-}" in
    enable)
        enable_forwarding
        ;;
    disable)
        disable_forwarding
        ;;
    status)
        show_status
        ;;
    advertise)
        advertise_routes
        ;;
    test)
        test_forwarding
        ;;
    *)
        usage
        exit 1
        ;;
esac