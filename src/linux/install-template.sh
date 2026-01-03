#!/bin/sh
set -eu

# Universal Ethernet/Wi-Fi Auto Switcher for Linux
# This script is self-contained and includes the switcher logic and uninstaller.

DEFAULT_INSTALL_DIR="/opt/eth-wifi-auto"
SERVICE_NAME="eth-wifi-auto"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
IS_TEST="${TEST_MODE:-0}"

if [ "$IS_TEST" = "1" ]; then
    DEFAULT_INSTALL_DIR="/tmp/eth-wifi-auto-test"
    SERVICE_NAME="eth-wifi-auto-test"
    SERVICE_FILE="/tmp/$SERVICE_NAME.service"
fi

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
    if [ -f "$SERVICE_FILE" ]; then
        echo "Old installation detected at: $SERVICE_FILE"
        OLD_INSTALL_DIR=$(grep "ExecStart=" "$SERVICE_FILE" | sed 's|ExecStart=||' | xargs dirname || true)

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
            rm -f "$SERVICE_FILE"
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
    # Detect interfaces - prioritize connected interfaces with IP addresses
    AUTO_WIFI=""
    AUTO_ETH=""
    if [ -n "${ETHERNET_INTERFACE:-}" ]; then
        AUTO_ETH="$ETHERNET_INTERFACE"
    fi
    if [ -n "${WIFI_INTERFACE:-}" ]; then
        AUTO_WIFI="$WIFI_INTERFACE"
    fi

    # Try nmcli first (NetworkManager - most common on desktop Linux)
    if command -v nmcli > /dev/null 2>&1; then
        AUTO_WIFI=$(nmcli device | grep -E "wifi" | awk '{print $1}' | head -n 1 || true)
        # Method 1: Find ethernet interface that is connected (has IP)
        AUTO_ETH=$(nmcli device | grep -E "ethernet.*connected" | awk '{print $1}' | head -n 1 || true)
        # Method 2: Fallback to any ethernet interface
        if [ -z "$AUTO_ETH" ]; then
            AUTO_ETH=$(nmcli device | grep -E "ethernet" | awk '{print $1}' | head -n 1 || true)
        fi
    fi

    # Fallback to ip command (more universal)
    if [ -z "$AUTO_ETH" ] && command -v ip > /dev/null 2>&1; then
        # Method 3: Find ethernet with IP using 'ip' command
        for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(eth|enp|eno|ens)'); do
            # Check if interface has an IPv4 address
            if ip addr show "$iface" 2>/dev/null | grep -q "inet "; then
                AUTO_ETH="$iface"
                break
            fi
        done

        # Method 4: Any ethernet-like interface
        if [ -z "$AUTO_ETH" ]; then
            AUTO_ETH=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(eth|enp|eno|ens)' | head -n 1 || true)
        fi

        # Detect Wi-Fi
        if [ -z "$AUTO_WIFI" ]; then
            AUTO_WIFI=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(wlan|wlp)' | head -n 1 || true)
        fi
    fi

    # Final fallback to /sys/class/net
    if [ -z "$AUTO_ETH" ] && [ -d /sys/class/net ]; then
        # Method 5: Find ethernet with IP from /sys
        for iface in /sys/class/net/*; do
            iface_name=$(basename "$iface")
            if echo "$iface_name" | grep -qE '^(eth|enp|eno|ens)'; then
                # Check if interface has carrier (cable connected)
                if [ -f "$iface/carrier" ] && [ "$(cat "$iface/carrier" 2>/dev/null)" = "1" ]; then
                    AUTO_ETH="$iface_name"
                    break
                fi
            fi
        done

        # Method 6: Any ethernet-like interface from /sys
        if [ -z "$AUTO_ETH" ]; then
            for iface in /sys/class/net/*; do
                iface_name=$(basename "$iface")
                if echo "$iface_name" | grep -qE '^(eth|enp|eno|ens)'; then
                    AUTO_ETH="$iface_name"
                    break
                fi
            done
        fi

        # Detect Wi-Fi from /sys
        if [ -z "$AUTO_WIFI" ]; then
            for iface in /sys/class/net/*; do
                iface_name=$(basename "$iface")
                if echo "$iface_name" | grep -qE '^(wlan|wlp)' && [ -d "$iface/wireless" ]; then
                    AUTO_WIFI="$iface_name"
                    break
                fi
            done
        fi
    fi

    if [ -t 0 ]; then
        echo ""
        echo "Available network interfaces:"
        if command -v nmcli > /dev/null 2>&1; then
            nmcli device
        elif command -v ip > /dev/null 2>&1; then
            ip -brief link show
        else
            ls /sys/class/net/ 2>/dev/null || echo "Unable to list interfaces"
        fi
        echo ""

        ETH_PROMPT=${AUTO_ETH:-"Not set"}
        printf "Enter Ethernet interface [%s]: " "$ETH_PROMPT"
        read -r input_eth
        ETH_DEV=${input_eth:-$AUTO_ETH}

        WIFI_PROMPT=${AUTO_WIFI:-"Not set"}
        printf "Enter Wi-Fi interface [%s]: " "$WIFI_PROMPT"
        read -r input_wifi
        WIFI_DEV=${input_wifi:-$AUTO_WIFI}

        echo ""
        echo "DHCP Timeout Configuration:"
        echo "  When ethernet connects, the interface becomes active but may not"
        echo "  have an IP address yet (DHCP negotiation in progress)."
        echo "  This timeout controls how long to wait for IP acquisition."
        echo "  Increase for slow routers/DHCP servers (typical: 3-10 seconds)."
        echo ""
        printf "Enter DHCP timeout in seconds [7]: "
        read -r input_timeout
        TIMEOUT=${input_timeout:-7}
    else
        ETH_DEV="$AUTO_ETH"
        WIFI_DEV="$AUTO_WIFI"
        TIMEOUT="${TIMEOUT:-7}"
    fi

    if [ -z "$ETH_DEV" ] || [ -z "$WIFI_DEV" ]; then
        echo "ERROR: Both Ethernet and Wi-Fi interfaces must be specified."
        exit 1
    fi

    echo "Installation directory: $INSTALL_DIR"
    echo ""
    echo "Using configuration:"
    echo "  Ethernet: $ETH_DEV"
    echo "  Wi-Fi:    $WIFI_DEV"
    echo "  Timeout:  ${TIMEOUT}s"

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
    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Ethernet/Wi-Fi Auto Switcher
After=network.target

[Service]
ExecStart=$INSTALL_DIR/eth-wifi-auto.sh
Environment="TIMEOUT=$TIMEOUT"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    if [ "$IS_TEST" = "1" ]; then
        echo "TEST_MODE=1: skipping systemd enable/start."
    else
        systemctl daemon-reload
        systemctl enable "$SERVICE_NAME"
        systemctl start "$SERVICE_NAME"
    fi

    echo ""
    echo "✅ Installation complete."
    echo ""
    echo "The service is now running. It will automatically:"
    echo "  • Turn Wi-Fi off when Ethernet is connected"
    echo "  • Turn Wi-Fi on when Ethernet is disconnected"
    echo "  • Continue working after OS reboot"
    echo "Logs: sudo journalctl -u $SERVICE_NAME -f"
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
