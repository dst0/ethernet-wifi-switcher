#!/bin/sh
set -eu

# Universal Ethernet/Wi-Fi Auto Switcher for Linux
# This script is self-contained and includes the switcher logic and uninstaller.

# Parse command line flags
USE_DEFAULTS=0
for arg in "$@"; do
    case "$arg" in
        --auto|--defaults)
            USE_DEFAULTS=1
            AUTO_INSTALL_DEPS=1
            ;;
        --uninstall)
            # Handled at end of script - skips install() and calls uninstall()
            ;;
    esac
done

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
BACKEND_NMCLI_B64="__BACKEND_NMCLI_B64__"
BACKEND_IP_B64="__BACKEND_IP_B64__"
SWITCHER_B64="__SWITCHER_B64__"
UNINSTALLER_B64="__UNINSTALLER_B64__"

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    elif [ -f /etc/arch-release ]; then
        echo "arch"
    else
        echo "unknown"
    fi
}

get_install_cmd() {
    distro="$1"
    case "$distro" in
        ubuntu|debian|linuxmint|pop)
            echo "apt install -y"
            ;;
        fedora|rhel|centos|rocky|almalinux)
            echo "dnf install -y"
            ;;
        arch|manjaro|endeavouros)
            echo "pacman -S --noconfirm"
            ;;
        opensuse*|suse)
            echo "zypper install -y"
            ;;
        alpine)
            echo "apk add"
            ;;
        *)
            echo ""
            ;;
    esac
}

install_package() {
    pkg="$1"
    distro="$2"
    install_cmd="$3"

    case "$distro" in
        ubuntu|debian|linuxmint|pop)
            case "$pkg" in
                networkmanager) sudo apt update >/dev/null 2>&1; sudo $install_cmd network-manager ;;
                iproute2) sudo apt update >/dev/null 2>&1; sudo $install_cmd iproute2 ;;
                rfkill) sudo apt update >/dev/null 2>&1; sudo $install_cmd rfkill ;;
                ping) sudo apt update >/dev/null 2>&1; sudo $install_cmd iputils-ping ;;
                curl) sudo apt update >/dev/null 2>&1; sudo $install_cmd curl ;;
                systemd) echo "systemd should be pre-installed" ;;
            esac
            ;;
        fedora|rhel|centos|rocky|almalinux)
            case "$pkg" in
                networkmanager) sudo $install_cmd NetworkManager ;;
                iproute2) sudo $install_cmd iproute ;;
                rfkill) sudo $install_cmd util-linux ;;
                ping) sudo $install_cmd iputils ;;
                curl) sudo $install_cmd curl ;;
                systemd) echo "systemd should be pre-installed" ;;
            esac
            ;;
        arch|manjaro|endeavouros)
            case "$pkg" in
                networkmanager) sudo $install_cmd networkmanager ;;
                iproute2) sudo $install_cmd iproute2 ;;
                rfkill) sudo $install_cmd util-linux ;;
                ping) sudo $install_cmd iputils ;;
                curl) sudo $install_cmd curl ;;
                systemd) echo "systemd should be pre-installed" ;;
            esac
            ;;
        *)
            echo "⚠️  Unknown distribution, cannot auto-install $pkg"
            return 1
            ;;
    esac
}

check_dependencies() {
    echo "Checking system dependencies..."
    echo ""

    HAS_NMCLI=0
    HAS_IP=0
    HAS_RFKILL=0
    HAS_SYSTEMD=0
    HAS_PING=0
    HAS_CURL=0

    MISSING_CRITICAL=""
    MISSING_OPTIONAL=""

    DISTRO=$(detect_distro)
    INSTALL_CMD=$(get_install_cmd "$DISTRO")

    # Check for network tools
    if command -v nmcli >/dev/null 2>&1; then
        echo "✅ NetworkManager (nmcli) found - Full functionality available"
        HAS_NMCLI=1
    fi
    if command -v ip >/dev/null 2>&1; then
        echo "✅ iproute2 (ip command) found"
        HAS_IP=1
    fi

    # Check rfkill
    if command -v rfkill >/dev/null 2>&1; then
        echo "✅ rfkill found - WiFi radio control available"
        HAS_RFKILL=1
    fi

    # Check systemd
    if command -v systemctl >/dev/null 2>&1; then
        echo "✅ systemd found"
        HAS_SYSTEMD=1
    fi

    # Check ping
    if command -v ping >/dev/null 2>&1; then
        echo "✅ ping found"
        HAS_PING=1
    fi

    # Check curl
    if command -v curl >/dev/null 2>&1; then
        echo "✅ curl found - HTTP connectivity checks available"
        HAS_CURL=1
    fi

    echo ""

    # Determine what's missing
    if [ $HAS_NMCLI -eq 0 ] && [ $HAS_IP -eq 0 ]; then
        MISSING_CRITICAL="${MISSING_CRITICAL}networkmanager iproute2 "
        echo "❌ CRITICAL: No supported network tools found!"
        echo "   Need either NetworkManager (nmcli) or iproute2 (ip command)"
    fi

    # rfkill is CRITICAL if nmcli is missing (ip backend needs it for wifi control)
    if [ $HAS_NMCLI -eq 0 ] && [ $HAS_RFKILL -eq 0 ]; then
        MISSING_CRITICAL="${MISSING_CRITICAL}rfkill "
        echo "❌ CRITICAL: rfkill not found (required when NetworkManager is not available)"
    elif [ $HAS_NMCLI -eq 1 ] && [ $HAS_RFKILL -eq 0 ]; then
        echo "ℹ️  rfkill not found (not needed with NetworkManager)"
    fi

    if [ $HAS_SYSTEMD -eq 0 ]; then
        MISSING_CRITICAL="${MISSING_CRITICAL}systemd "
        echo "❌ CRITICAL: systemd not found (required for service management)"
    fi

    if [ $HAS_PING -eq 0 ]; then
        MISSING_OPTIONAL="${MISSING_OPTIONAL}ping "
        echo "⚠️  WARNING: ping not found (needed for internet monitoring)"
    fi

    if [ $HAS_CURL -eq 0 ]; then
        echo "ℹ️  curl not found (optional - needed for HTTP connectivity checks)"
    fi

    echo ""

    # Handle missing dependencies
    if [ -n "$MISSING_CRITICAL" ] || [ -n "$MISSING_OPTIONAL" ]; then
        if [ -n "$MISSING_CRITICAL" ]; then
            echo "❌ Critical dependencies missing: $MISSING_CRITICAL"
        fi
        if [ -n "$MISSING_OPTIONAL" ]; then
            echo "⚠️  Optional dependencies missing: $MISSING_OPTIONAL"
        fi
        echo ""

        if [ -n "$INSTALL_CMD" ] && [ -t 0 ]; then
            printf "Would you like to install missing dependencies automatically? (y/N): "
            read -r install_deps

            if [ "$install_deps" = "y" ] || [ "$install_deps" = "Y" ]; then
                echo ""
                echo "Installing dependencies..."

                # Install critical dependencies
                for pkg in $MISSING_CRITICAL; do
                    # Special handling: offer choice between networkmanager and iproute2
                    if [ "$pkg" = "networkmanager" ] || [ "$pkg" = "iproute2" ]; then
                        if echo "$MISSING_CRITICAL" | grep -q "networkmanager"; then
                            echo ""
                            echo "Choose network backend:"
                            echo "  1) NetworkManager (recommended - full functionality)"
                            echo "  2) iproute2 + rfkill (minimal)"
                            printf "Enter choice [1]: "
                            read -r net_choice
                            net_choice=${net_choice:-1}

                            if [ "$net_choice" = "1" ]; then
                                echo "Installing NetworkManager..."
                                install_package "networkmanager" "$DISTRO" "$INSTALL_CMD"
                                # Remove rfkill from critical if we're installing networkmanager
                                MISSING_CRITICAL=$(echo "$MISSING_CRITICAL" | sed 's/rfkill //')
                            else
                                echo "Installing iproute2..."
                                install_package "iproute2" "$DISTRO" "$INSTALL_CMD"
                                if echo "$MISSING_CRITICAL" | grep -q "rfkill"; then
                                    echo "Installing rfkill..."
                                    install_package "rfkill" "$DISTRO" "$INSTALL_CMD"
                                fi
                            fi
                            # Skip processing these packages again
                            MISSING_CRITICAL=$(echo "$MISSING_CRITICAL" | sed 's/networkmanager //' | sed 's/iproute2 //')
                            continue
                        fi
                    fi

                    if [ -n "$pkg" ]; then
                        echo "Installing $pkg..."
                        install_package "$pkg" "$DISTRO" "$INSTALL_CMD"
                    fi
                done

                # Install optional dependencies
                for pkg in $MISSING_OPTIONAL; do
                    if [ -n "$pkg" ]; then
                        echo "Installing $pkg..."
                        install_package "$pkg" "$DISTRO" "$INSTALL_CMD"
                    fi
                done

                echo ""
                echo "✅ Dependencies installed. Re-checking..."
                echo ""

                # Re-check after installation
                if ! command -v nmcli >/dev/null 2>&1 && ! command -v ip >/dev/null 2>&1; then
                    echo "❌ Failed to install network tools. Cannot continue."
                    exit 1
                fi
                if ! command -v systemctl >/dev/null 2>&1; then
                    echo "❌ Failed to install systemd. Cannot continue."
                    exit 1
                fi
                if ! command -v nmcli >/dev/null 2>&1 && ! command -v rfkill >/dev/null 2>&1; then
                    echo "❌ Failed to install rfkill (required for ip backend). Cannot continue."
                    exit 1
                fi

                echo "✅ All critical dependencies satisfied!"
                echo ""
            else
                # User declined installation
                if [ -n "$MISSING_CRITICAL" ]; then
                    echo ""
                    echo "❌ Cannot continue without critical dependencies."
                    echo "   Critical: $MISSING_CRITICAL"
                    echo ""
                    echo "Please install manually or re-run and accept automatic installation."
                    exit 1
                else
                    # Only optional missing
                    echo ""
                    echo "Continuing with optional dependencies missing."
                    echo "Some features may be limited."
                    echo ""
                fi
            fi
        else
            # Non-interactive mode - check for AUTO_INSTALL_DEPS
            if [ "${AUTO_INSTALL_DEPS:-0}" = "1" ] && [ -n "$INSTALL_CMD" ]; then
                echo "Non-interactive mode with AUTO_INSTALL_DEPS=1: Installing dependencies..."
                echo ""

                # Install critical dependencies
                for pkg in $MISSING_CRITICAL; do
                    # Special handling for network tools
                    if [ "$pkg" = "networkmanager" ] || [ "$pkg" = "iproute2" ]; then
                        if echo "$MISSING_CRITICAL" | grep -q "networkmanager"; then
                            # Default to NetworkManager in non-interactive mode
                            echo "Installing NetworkManager..."
                            install_package "networkmanager" "$DISTRO" "$INSTALL_CMD"
                            MISSING_CRITICAL=$(echo "$MISSING_CRITICAL" | sed 's/rfkill //')
                            MISSING_CRITICAL=$(echo "$MISSING_CRITICAL" | sed 's/networkmanager //' | sed 's/iproute2 //')
                            continue
                        fi
                    fi

                    if [ -n "$pkg" ]; then
                        echo "Installing $pkg..."
                        install_package "$pkg" "$DISTRO" "$INSTALL_CMD"
                    fi
                done

                # Install optional dependencies
                for pkg in $MISSING_OPTIONAL; do
                    if [ -n "$pkg" ]; then
                        echo "Installing $pkg..."
                        install_package "$pkg" "$DISTRO" "$INSTALL_CMD"
                    fi
                done

                echo ""
                echo "✅ Dependencies installed."
                echo ""
            elif [ -n "$MISSING_CRITICAL" ]; then
                echo "❌ Cannot continue: Critical dependencies missing."
                echo "   Please install: $MISSING_CRITICAL"
                echo "   Or run with: sudo AUTO_INSTALL_DEPS=1 sh install.sh"
                exit 1
            else
                echo "⚠️  Continuing with optional dependencies missing."
                echo ""
            fi
        fi
    else
        echo "✅ All dependencies satisfied!"
        echo ""
    fi
}

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

    # Check dependencies before proceeding
    check_dependencies

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
    if [ -t 0 ] && [ "$USE_DEFAULTS" = "0" ]; then
        printf "Enter installation directory [%s]: " "$DEFAULT_INSTALL_DIR"
        read -r input_dir
        INSTALL_DIR=${input_dir:-$DEFAULT_INSTALL_DIR}
    elif [ "$USE_DEFAULTS" = "1" ]; then
        echo "Using default installation directory: $DEFAULT_INSTALL_DIR"
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
    # Only auto-detect if not already set from environment variables
    if command -v nmcli > /dev/null 2>&1; then
        if [ -z "$AUTO_WIFI" ]; then
            AUTO_WIFI=$(nmcli device | grep -E "wifi" | awk '{print $1}' | head -n 1 || true)
        fi
        if [ -z "$AUTO_ETH" ]; then
            # Method 1: Find ethernet interface that is connected (has IP)
            AUTO_ETH=$(nmcli device | grep -E "ethernet.*connected" | awk '{print $1}' | head -n 1 || true)
            # Method 2: Fallback to any ethernet interface
            if [ -z "$AUTO_ETH" ]; then
                AUTO_ETH=$(nmcli device | grep -E "ethernet" | awk '{print $1}' | head -n 1 || true)
            fi
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

    if [ -t 0 ] && [ "$USE_DEFAULTS" = "0" ]; then
        echo ""
        echo "Available network interfaces:"
        if command -v nmcli > /dev/null 2>&1; then
            nmcli device
        elif command -v ip > /dev/null 2>&1; then
            # Show interfaces with type detection for ip command
            ip -brief link show | grep -v "lo" | while read -r iface state mac; do
                # Detect interface type by name pattern and /sys/class/net properties
                iface_type="unknown"
                if echo "$iface" | grep -qE '^(wlan|wlp)'; then
                    iface_type="wifi"
                elif echo "$iface" | grep -qE '^(eth|enp|eno|ens)'; then
                    iface_type="ethernet"
                elif [ -d "/sys/class/net/$iface/wireless" ]; then
                    iface_type="wifi"
                elif [ -f "/sys/class/net/$iface/type" ]; then
                    # type 1 = ethernet, type 801 = wireless
                    net_type=$(cat "/sys/class/net/$iface/type" 2>/dev/null || echo "0")
                    if [ "$net_type" = "1" ]; then
                        iface_type="ethernet"
                    elif [ "$net_type" = "801" ]; then
                        iface_type="wifi"
                    fi
                fi
                printf "  %s (%s) %s\n" "$iface" "$iface_type" "$state"
            done
        else
            # Fallback to /sys/class/net with type detection
            if [ -d /sys/class/net ]; then
                for iface_path in /sys/class/net/*; do
                    iface=$(basename "$iface_path")
                    [ "$iface" = "lo" ] && continue

                    iface_type="unknown"
                    if [ -d "$iface_path/wireless" ]; then
                        iface_type="wifi"
                    elif echo "$iface" | grep -qE '^(wlan|wlp)'; then
                        iface_type="wifi"
                    elif echo "$iface" | grep -qE '^(eth|enp|eno|ens)'; then
                        iface_type="ethernet"
                    elif [ -f "$iface_path/type" ]; then
                        net_type=$(cat "$iface_path/type" 2>/dev/null || echo "0")
                        if [ "$net_type" = "1" ]; then
                            iface_type="ethernet"
                        elif [ "$net_type" = "801" ]; then
                            iface_type="wifi"
                        fi
                    fi

                    printf "  %s (%s)\n" "$iface" "$iface_type"
                done
            else
                echo "Unable to list interfaces"
            fi
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

        echo ""
        echo "Periodic Internet Connectivity Monitoring (Optional):"
        echo "  Enable active monitoring of actual internet availability, not just link status."
        echo "  The system will periodically check and switch to WiFi if Ethernet has no internet"
        echo "  and to Ethernet if WiFi has no internet."
        echo "  Uses minimal resources with timer-based checks (not continuous polling)."
        echo ""
        printf "Enable periodic internet monitoring? (y/N): "
        read -r input_check_internet
        if [ "$input_check_internet" = "y" ] || [ "$input_check_internet" = "Y" ]; then
            CHECK_INTERNET=1

            echo ""
            echo "Select connectivity check method:"
            echo "  1) Ping to gateway (recommended - most reliable and provider-safe)"
            echo "  2) Ping to domain/IP address"
            echo "  3) HTTP/HTTPS check (curl) - May be blocked by ISP/firewall"
            echo ""
            printf "Enter choice [1]: "
            read -r input_check_method
            input_check_method=${input_check_method:-1}

            case "$input_check_method" in
                1)
                    CHECK_METHOD="gateway"
                    CHECK_TARGET=""
                    echo "Selected: Gateway ping (auto-detected per interface)"
                    ;;
                2)
                    CHECK_METHOD="ping"
                    printf "Enter domain/IP to ping [8.8.8.8]: "
                    read -r input_check_target
                    CHECK_TARGET=${input_check_target:-8.8.8.8}
                    echo "Selected: Ping to $CHECK_TARGET"
                    ;;
                3)
                    CHECK_METHOD="curl"
                    echo ""
                    echo "⚠️  WARNING: HTTP/HTTPS checks may be blocked by:"
                    echo "   - Corporate firewalls"
                    echo "   - ISP content filtering"
                    echo "   - Captive portals (ironically)"
                    echo "   - Deep packet inspection systems"
                    echo ""
                    printf "Enter URL to check [http://captive.apple.com/hotspot-detect.html]: "
                    read -r input_check_target
                    CHECK_TARGET=${input_check_target:-http://captive.apple.com/hotspot-detect.html}
                    echo "Selected: HTTP check to $CHECK_TARGET"
                    ;;
                *)
                    echo "Invalid choice, using gateway ping (default)"
                    CHECK_METHOD="gateway"
                    CHECK_TARGET=""
                    ;;
            esac

            echo ""
            printf "Check interval in seconds [30]: "
            read -r input_check_interval
            CHECK_INTERVAL=${input_check_interval:-30}
            echo "Enabled: Will check internet connectivity every ${CHECK_INTERVAL} seconds using $CHECK_METHOD"

            echo ""
            printf "Log every check attempt? (y/N) [logs only state changes by default]: "
            read -r input_log_checks
            if [ "$input_log_checks" = "y" ] || [ "$input_log_checks" = "Y" ]; then
                LOG_CHECK_ATTEMPTS=1
                echo "Enabled: Will log every check attempt"
            else
                LOG_CHECK_ATTEMPTS=0
                echo "Default: Will log only state changes (failure/recovery)"
            fi
        else
            CHECK_INTERNET=0
            CHECK_INTERVAL=0
            CHECK_METHOD="gateway"
            CHECK_TARGET=""
            LOG_CHECK_ATTEMPTS=0
            echo "Disabled: Event-driven checks only (no periodic monitoring)"
        fi

        echo ""
        echo "Multi-Interface Configuration (Optional):"
        echo "  Configure priority for multiple ethernet or wifi interfaces."
        echo ""
        printf "Configure interface priority? (y/N): "
        read -r input_config_priority
        if [ "$input_config_priority" = "y" ] || [ "$input_config_priority" = "Y" ]; then
            echo ""
            echo "Available interfaces:"
            if command -v nmcli > /dev/null 2>&1; then
                nmcli device | grep -E "(ethernet|wifi)" | awk '{printf "  %s (%s)\n", $1, $2}'
            elif command -v ip > /dev/null 2>&1; then
                # Show with type detection for ip command
                ip -brief link show | grep -v "lo" | while read -r iface state mac; do
                    iface_type="unknown"
                    if echo "$iface" | grep -qE '^(wlan|wlp)'; then
                        iface_type="wifi"
                    elif echo "$iface" | grep -qE '^(eth|enp|eno|ens)'; then
                        iface_type="ethernet"
                    elif [ -d "/sys/class/net/$iface/wireless" ]; then
                        iface_type="wifi"
                    elif [ -f "/sys/class/net/$iface/type" ]; then
                        net_type=$(cat "/sys/class/net/$iface/type" 2>/dev/null || echo "0")
                        if [ "$net_type" = "1" ]; then
                            iface_type="ethernet"
                        elif [ "$net_type" = "801" ]; then
                            iface_type="wifi"
                        fi
                    fi
                    printf "  %s (%s)\n" "$iface" "$iface_type"
                done
            else
                # Fallback to /sys/class/net
                if [ -d /sys/class/net ]; then
                    for iface_path in /sys/class/net/*; do
                        iface=$(basename "$iface_path")
                        [ "$iface" = "lo" ] && continue

                        iface_type="unknown"
                        if [ -d "$iface_path/wireless" ]; then
                            iface_type="wifi"
                        elif echo "$iface" | grep -qE '^(wlan|wlp)'; then
                            iface_type="wifi"
                        elif echo "$iface" | grep -qE '^(eth|enp|eno|ens)'; then
                            iface_type="ethernet"
                        fi

                        printf "  %s (%s)\n" "$iface" "$iface_type"
                    done
                fi
            fi
            echo ""
            echo "Enter interfaces in priority order (comma-separated, highest first):"
            echo "Example: eth0,eth1,wlan0"
            DEFAULT_PRIORITY="${ETH_DEV},${WIFI_DEV}"
            printf "Interface priority [%s]: " "$DEFAULT_PRIORITY"
            read -r input_interface_priority
            INTERFACE_PRIORITY="${input_interface_priority:-$DEFAULT_PRIORITY}"
            if [ -n "$INTERFACE_PRIORITY" ]; then
                echo "Priority configured: $INTERFACE_PRIORITY"
            fi
        else
            INTERFACE_PRIORITY=""
        fi
    elif [ "$USE_DEFAULTS" = "1" ]; then
        echo "Auto-install mode: Using detected interfaces and recommended defaults..."
        ETH_DEV="$AUTO_ETH"
        WIFI_DEV="$AUTO_WIFI"
        TIMEOUT="${TIMEOUT:-7}"
        CHECK_INTERNET="${CHECK_INTERNET:-1}"
        CHECK_INTERVAL="${CHECK_INTERVAL:-30}"
        CHECK_METHOD="${CHECK_METHOD:-ping}"
        CHECK_TARGET="${CHECK_TARGET:-8.8.8.8}"
        LOG_CHECK_ATTEMPTS="${LOG_CHECK_ATTEMPTS:-0}"
        INTERFACE_PRIORITY="${INTERFACE_PRIORITY:-}"
        echo "  Ethernet: $ETH_DEV"
        echo "  Wi-Fi: $WIFI_DEV"
        echo "  Internet monitoring: Enabled (ping to 8.8.8.8 every 30s)"
    else
        ETH_DEV="$AUTO_ETH"
        WIFI_DEV="$AUTO_WIFI"
        TIMEOUT="${TIMEOUT:-7}"
        CHECK_INTERNET="${CHECK_INTERNET:-0}"
        CHECK_INTERVAL="${CHECK_INTERVAL:-30}"
        CHECK_METHOD="${CHECK_METHOD:-gateway}"
        CHECK_TARGET="${CHECK_TARGET:-}"
        LOG_CHECK_ATTEMPTS="${LOG_CHECK_ATTEMPTS:-0}"
        INTERFACE_PRIORITY="${INTERFACE_PRIORITY:-}"
    fi

    if [ -z "$ETH_DEV" ] || [ -z "$WIFI_DEV" ]; then
        echo "ERROR: Both Ethernet and Wi-Fi interfaces must be specified."
        exit 1
    fi

    echo "Installation directory: $INSTALL_DIR"
    echo ""
    echo "Using configuration:"
    echo "  Ethernet:         $ETH_DEV"
    echo "  Wi-Fi:            $WIFI_DEV"
    echo "  DHCP Timeout:     ${TIMEOUT}s"
    echo "  Internet Check:   $CHECK_INTERNET"
    if [ "$CHECK_INTERNET" = "1" ]; then
        echo "  Check Method:     $CHECK_METHOD"
        if [ -n "$CHECK_TARGET" ]; then
            echo "  Check Target:     $CHECK_TARGET"
        fi
        echo "  Check Interval:   ${CHECK_INTERVAL}s"
        echo "  Log All Checks:   $LOG_CHECK_ATTEMPTS"
    fi
    if [ -n "$INTERFACE_PRIORITY" ]; then
        echo "  Interface Priority: $INTERFACE_PRIORITY"
    fi

    mkdir -p "$INSTALL_DIR"

    # Set up paths (matching macOS naming convention)
    WORK_UNINSTALL="$INSTALL_DIR/uninstall.sh"

    # Extract backend libraries
    mkdir -p "$INSTALL_DIR/lib"
    echo "$BACKEND_NMCLI_B64" | base64 -d > "$INSTALL_DIR/lib/network-nmcli.sh"
    echo "$BACKEND_IP_B64" | base64 -d > "$INSTALL_DIR/lib/network-ip.sh"
    chmod +x "$INSTALL_DIR/lib/network-nmcli.sh"
    chmod +x "$INSTALL_DIR/lib/network-ip.sh"

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
Environment="CHECK_INTERNET=$CHECK_INTERNET"
Environment="CHECK_INTERVAL=$CHECK_INTERVAL"
Environment="CHECK_METHOD=$CHECK_METHOD"
Environment="CHECK_TARGET=$CHECK_TARGET"
Environment="LOG_CHECK_ATTEMPTS=$LOG_CHECK_ATTEMPTS"
Environment="INTERFACE_PRIORITY=$INTERFACE_PRIORITY"
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
