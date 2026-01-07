#!/bin/sh
set -eu

SERVICE_NAME="eth-wifi-auto"
DEFAULT_INSTALL_DIR="/usr/local/bin"
IS_TEST="${TEST_MODE:-0}"

if [ "$IS_TEST" = "1" ]; then
    SERVICE_NAME="eth-wifi-auto-test"
    DEFAULT_INSTALL_DIR="/tmp/eth-wifi-auto-test"
fi

# Try to detect installation path from the systemd service file
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
if [ "$IS_TEST" = "1" ]; then
    SERVICE_FILE="/tmp/$SERVICE_NAME.service"
fi

if [ -f "$SERVICE_FILE" ]; then
    INSTALL_DIR=$(grep "ExecStart=" "$SERVICE_FILE" | sed 's|ExecStart=||' | xargs dirname)
    echo "Detected installation directory: $INSTALL_DIR"
else
    INSTALL_DIR="$DEFAULT_INSTALL_DIR"
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root (sudo)"
    exit 1
fi

echo "Uninstalling Ethernet/Wi-Fi Auto Switcher..."

# Stop service and clean up files
if [ "$IS_TEST" != "1" ]; then
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        systemctl stop "$SERVICE_NAME"
    fi
fi

pkill -f "eth-wifi-auto.sh" || true

if [ "$IS_TEST" != "1" ]; then
    if systemctl is-enabled --quiet "$SERVICE_NAME"; then
        systemctl disable "$SERVICE_NAME"
    fi
fi

# Remove files (both TEST_MODE and normal)
rm -f "$SERVICE_FILE"
rm -f "$INSTALL_DIR/eth-wifi-auto.sh"
rm -f "$INSTALL_DIR/uninstall.sh"
rm -rf "$INSTALL_DIR"

if [ "$IS_TEST" != "1" ]; then
    systemctl daemon-reload
fi

echo "Uninstallation complete."
echo ""
