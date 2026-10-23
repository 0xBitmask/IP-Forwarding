#!/bin/bash
# Install script for IP Forwarding on Orange Pi Zero 3
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/ip_forwarding"
SERVICE_FILE="ip-forwarding.service"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

[[ $EUID -eq 0 ]] || { echo -e "${RED}Must run as root${NC}"; exit 1; }

echo "=== Installing IP Forwarding ==="

# Create install directory
mkdir -p "$INSTALL_DIR"

# Copy files
cp "$SCRIPT_DIR/ip_forward.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/config.conf" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/ip_forward.sh"

# Install systemd service
cp "$SCRIPT_DIR/$SERVICE_FILE" /etc/systemd/system/
systemctl daemon-reload

# Enable Tailscale IP forwarding setting
mkdir -p /etc/sysctl.d
cat > /etc/sysctl.d/99-ip-forwarding.conf <<EOF
net.ipv4.ip_forward = 1
EOF
sysctl --system > /dev/null 2>&1 || true

echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "Files installed to: $INSTALL_DIR"
echo ""
echo "Quick start:"
echo "  Edit config:    nano $INSTALL_DIR/config.conf"
echo "  Enable:         systemctl start ip-forwarding"
echo "  Disable:        systemctl stop ip-forwarding"
echo "  Auto-start:     systemctl enable ip-forwarding"
echo "  Status:         $INSTALL_DIR/ip_forward.sh status"
echo "  Advertise:      $INSTALL_DIR/ip_forward.sh advertise"
echo "  Test:           $INSTALL_DIR/ip_forward.sh test"
echo ""
echo "Step-by-step:"
echo "  1. Edit $INSTALL_DIR/config.conf (set LAN_IF or leave empty for auto-detect; set TARGET_SERVER)"
echo "  2. Run: $INSTALL_DIR/ip_forward.sh test   (verify Orange Pi can reach the web server)"
echo "  3. Run: $INSTALL_DIR/ip_forward.sh advertise"
echo "  4. Approve route in Tailscale admin: https://login.tailscale.com/admin/machines"
echo "  5. On your laptop: sudo tailscale up --accept-routes"
echo "  6. Open http://192.168.1.40 in your browser"
echo "  7. Run: systemctl enable --now ip-forwarding"
