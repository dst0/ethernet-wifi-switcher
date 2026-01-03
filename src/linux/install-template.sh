#!/bin/sh
set -eu

# Universal Ethernet/Wi-Fi Auto Switcher for Linux
# This script is self-contained and includes the switcher logic and uninstaller.

DEFAULT_INSTALL_DIR="/opt/eth-wifi-auto"
SERVICE_NAME="eth-wifi-auto"

# Embedded components (Base64)
SWITCHER_B64="__SWITCHER_B64__"
UNINSTALLER_B64="__UNINSTALLER_B64__"

stop_helper_processes() {
    helper_pids=$(pgrep -f "eth-wifi-auto.sh" || true)
    if [ -n "$helper_pids" ]; then
        echo "Stopping helper processes..."
        for pid in $helper_pids; do
            pname=$(ps -p "$pid" -o comm= 2>/dev/null || echo "eth-wifi-auto.sh")
            kill "$pid" 2>/dev/null || true
            sleep 0.1
            if ! ps -p "$pid" >/dev/null 2>&1; then
                echo "    process $pid $pname stopped"
            else
                echo "    process $pid $pname failed to stop"
            fi
        done
    fi
}

install() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Please run as root (sudo)"
        exit 1
    fi

    # Cleanup existing installation if found
    if [ -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
        echo "Old installation detected at: /etc/systemd/system/$SERVICE_NAME.service"
        OLD_INSTALL_DIR=$(grep "ExecStart=" "/etc/systemd/system/$SERVICE_NAME.service" | sed 's|ExecStart=||' | xargs dirname || true)

        if [ -n "$OLD_INSTALL_DIR" ]; then
            echo "  Installation directory: $OLD_INSTALL_DIR"
        fi

        if [ -n "$OLD_INSTALL_DIR" ] && [ -f "$OLD_INSTALL_DIR/uninstall.sh" ]; then
            echo "  Running existing uninstaller..."
            sh "$OLD_INSTALL_DIR/uninstall.sh" || true
        else
            if [ -z "$OLD_INSTALL_DIR" ]; then
                echo "  Install folder not found. Performing manual cleanup..."
            else
                echo "  No uninstaller found. Performing manual cleanup..."
            fi
            systemctl stop "$SERVICE_NAME" 2>/dev/null || true
            systemctl disable "$SERVICE_NAME" 2>/dev/null || true
            stop_helper_processes
            rm -f "/etc/systemd/system/$SERVICE_NAME.service"
            systemctl daemon-reload
        fi
    else
        echo "No old installation detected."
    fi

    INSTALL_DIR="$DEFAULT_INSTALL_DIR"
    if [ -t 0 ]; then
        printf "Enter installation directory [%s]: " "$DEFAULT_INSTALL_DIR"
        read -r input_dir
        INSTALL_DIR=${input_dir:-$DEFAULT_INSTALL_DIR}
    fi

    echo ""
    # Detect interfaces
    AUTO_ETH=$(nmcli device | grep -E "ethernet" | awk '{print $1}' | head -n 1 || true)
    AUTO_WIFI=$(nmcli device | grep -E "wifi" | awk '{print $1}' | head -n 1 || true)

    if [ -t 0 ]; then
        echo ""
        echo "Available network interfaces:"
        nmcli device
        echo ""

        ETH_PROMPT=${AUTO_ETH:-"Not set"}
        printf "Enter Ethernet interface [%s]: " "$ETH_PROMPT"
        read -r input_eth
        ETH_DEV=${input_eth:-$AUTO_ETH}

        WIFI_PROMPT=${AUTO_WIFI:-"Not set"}
        printf "Enter Wi-Fi interface [%s]: " "$WIFI_PROMPT"
        read -r input_wifi
        WIFI_DEV=${input_wifi:-$AUTO_WIFI}
    else
        ETH_DEV="$AUTO_ETH"
        WIFI_DEV="$AUTO_WIFI"
    fi

    if [ -z "$ETH_DEV" ] || [ -z "$WIFI_DEV" ]; then
        echo "ERROR: Both Ethernet and Wi-Fi interfaces must be specified."
        exit 1
    fi

    echo "Installation directory: $INSTALL_DIR"
    echo ""

    mkdir -p "$INSTALL_DIR"

    # Set up paths (matching macOS naming convention)
    WORK_UNINSTALL="$INSTALL_DIR/uninstall.sh"

    # Extract switcher
    echo "$SWITCHER_B64" | base64 -d > "$INSTALL_DIR/eth-wifi-auto.sh"
    chmod +x "$INSTALL_DIR/eth-wifi-auto.sh"

    # Extract uninstaller
    echo "$UNINSTALLER_B64" | base64 -d > "$WORK_UNINSTALL"
    chmod +x "$WORK_UNINSTALL"

    # Create systemd service
    cat <<EOF > "/etc/systemd/system/$SERVICE_NAME.service"
[Unit]
Description=Ethernet/Wi-Fi Auto Switcher
After=network.target

[Service]
ExecStart=$INSTALL_DIR/eth-wifi-auto.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"

    echo ""
    echo "✅ Installation complete."
    echo ""
    echo "The service is now running. It will automatically:"
    echo "  • Turn Wi-Fi off when Ethernet is connected"
    echo "  • Turn Wi-Fi on when Ethernet is disconnected"
    echo "  • Continue working after OS reboot"
    echo ""
    echo "To uninstall, run:"
    echo "  sudo sh \"$WORK_UNINSTALL\""
}

uninstall() {
    echo "$UNINSTALLER_B64" | base64 -d | sh
}

if [ "${1:-}" = "--uninstall" ]; then
    uninstall
else
    install
fi
