#!/bin/sh
set -eu

SERVICE_NAME="eth-wifi-auto"
DEFAULT_INSTALL_DIR="/usr/local/bin"

# Try to detect installation path from the systemd service file
if [ -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
    INSTALL_DIR=$(grep "ExecStart=" "/etc/systemd/system/$SERVICE_NAME.service" | sed 's|ExecStart=||' | xargs dirname)
    echo "Detected installation directory: $INSTALL_DIR"
else
    INSTALL_DIR="$DEFAULT_INSTALL_DIR"
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root (sudo)"
    exit 1
fi

echo "Uninstalling Ethernet/Wi-Fi Auto Switcher..."

if systemctl is-active --quiet "$SERVICE_NAME"; then
    systemctl stop "$SERVICE_NAME"
fi

pkill -f "eth-wifi-auto.sh" || true

if systemctl is-enabled --quiet "$SERVICE_NAME"; then
    systemctl disable "$SERVICE_NAME"
fi

rm -f "/etc/systemd/system/$SERVICE_NAME.service"
rm -f "$INSTALL_DIR/eth-wifi-auto.sh"

systemctl daemon-reload

echo "Uninstallation complete."
echo ""
