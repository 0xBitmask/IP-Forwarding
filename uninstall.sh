#!/bin/bash
# Uninstall script for IP Forwarding
set -euo pipefail

INSTALL_DIR="/opt/ip_forwarding"

[[ $EUID -eq 0 ]] || { echo "Must run as root"; exit 1; }

echo "=== Uninstalling IP Forwarding ==="

# Stop and disable service
systemctl stop ip-forwarding 2>/dev/null || true
systemctl disable ip-forwarding 2>/dev/null || true

# Remove files
rm -f /etc/systemd/system/ip-forwarding.service
rm -f /etc/sysctl.d/99-ip-forwarding.conf
rm -rf "$INSTALL_DIR"

systemctl daemon-reload
sysctl --system > /dev/null 2>&1 || true

echo "Uninstall complete."
