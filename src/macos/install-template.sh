#!/bin/sh
set -eu

# =========================================================
# Eth/Wi-Fi Auto Switcher (macOS Installer Template)
# =========================================================

# Parse command line flags
USE_DEFAULTS=0
WORKDIR=""
for arg in "$@"; do
    case "$arg" in
        --auto|--defaults)
            USE_DEFAULTS=1
            AUTO_INSTALL_DEPS=1
            ;;
        --uninstall)
            # Handled at end of script - skips main() and calls uninstall()
            ;;
        *)
            # Assume it's the workdir
            if [ -z "$WORKDIR" ] && [ "$arg" != "--auto" ] && [ "$arg" != "--defaults" ]; then
                WORKDIR="$arg"
            fi
            ;;
    esac
done

DAEMON_LABEL="com.ethwifiauto.watch"

# System install paths
SYS_HELPER_PATH="/usr/local/sbin/eth-wifi-auto.sh"
SYS_WATCHER_BIN="/usr/local/sbin/ethwifiauto-watch"
SYS_PLIST_PATH="/Library/LaunchDaemons/${DAEMON_LABEL}.plist"

DEFAULT_WORKDIR="${HOME}/.ethernet-wifi-auto-switcher"
IS_TEST="${TEST_MODE:-0}"

# If no workdir provided and interactive, ask user (but not during uninstall)
if [ -z "$WORKDIR" ] && [ -t 0 ] && [ "$USE_DEFAULTS" = "0" ] && [ "${1:-}" != "--uninstall" ]; then
  printf "Enter installation directory [%s]: " "$DEFAULT_WORKDIR"
  read -r input_dir
  WORKDIR=${input_dir:-$DEFAULT_WORKDIR}
elif [ "$USE_DEFAULTS" = "1" ] && [ -z "$WORKDIR" ]; then
  echo "Using default installation directory: $DEFAULT_WORKDIR"
fi

WORKDIR="${WORKDIR:-$DEFAULT_WORKDIR}"

# PLACEHOLDERS (Filled by build-macos.sh)
WATCHER_BASE64="__WATCHER_BINARY_B64__"
HELPER_CONTENT_B64="__HELPER_SCRIPT_B64__"
UNINSTALL_CONTENT_B64="__UNINSTALL_SCRIPT_B64__"
PLIST_CONTENT_B64="__PLIST_TEMPLATE_B64__"

die(){ echo "ERROR: $*" >&2; exit 1; }
need_macos(){ [ "$(uname -s)" = "Darwin" ] || die "macOS only."; }

check_dependencies() {
    echo "Checking system dependencies..."
    echo ""

    HAS_NETWORKSETUP=0
    HAS_IPCONFIG=0
    HAS_SWIFT=0
    HAS_LAUNCHCTL=0
    HAS_PING=0
    HAS_CURL=0

    MISSING_CRITICAL=""
    MISSING_OPTIONAL=""

    # Check for networksetup (should be built-in on macOS)
    if command -v networksetup >/dev/null 2>&1; then
        echo "✅ networksetup found"
        HAS_NETWORKSETUP=1
    else
        echo "❌ CRITICAL: networksetup not found!"
        MISSING_CRITICAL="${MISSING_CRITICAL}networksetup "
    fi

    # Check for ipconfig (should be built-in)
    if command -v ipconfig >/dev/null 2>&1; then
        echo "✅ ipconfig found"
        HAS_IPCONFIG=1
    else
        echo "❌ CRITICAL: ipconfig not found!"
        MISSING_CRITICAL="${MISSING_CRITICAL}ipconfig "
    fi

    # Check for Swift (needed to compile the watcher)
    if command -v swift >/dev/null 2>&1 || command -v swiftc >/dev/null 2>&1; then
        echo "✅ Swift compiler found"
        HAS_SWIFT=1
    else
        echo "❌ CRITICAL: Swift compiler not found!"
        MISSING_CRITICAL="${MISSING_CRITICAL}xcode-cli-tools "
    fi

    # Check for ping (should be built-in)
    if command -v ping >/dev/null 2>&1; then
        echo "✅ ping found"
        HAS_PING=1
    else
        echo "⚠️  WARNING: ping not found"
        MISSING_OPTIONAL="${MISSING_OPTIONAL}ping "
    fi

    # Check for curl (usually built-in on modern macOS)
    if command -v curl >/dev/null 2>&1; then
        echo "✅ curl found - HTTP connectivity checks available"
        HAS_CURL=1
    else
        echo "ℹ️  curl not found (optional - needed for HTTP connectivity checks)"
    fi

    # Check for launchctl (should be built-in)
    if command -v launchctl >/dev/null 2>&1; then
        echo "✅ launchctl found"
        HAS_LAUNCHCTL=1
    else
        echo "❌ CRITICAL: launchctl not found!"
        MISSING_CRITICAL="${MISSING_CRITICAL}launchctl "
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

        if [ -t 0 ]; then
            # Check if we can install anything
            CAN_INSTALL=0
            if echo "$MISSING_CRITICAL" | grep -q "xcode-cli-tools"; then
                CAN_INSTALL=1
            fi

            if [ $CAN_INSTALL -eq 1 ]; then
                if [ "$USE_DEFAULTS" = "1" ]; then
                    install_deps="y"
                    echo "Auto-install mode: Installing dependencies automatically..."
                else
                    printf "Would you like to install missing dependencies automatically? (y/N): "
                    read -r install_deps
                fi

                if [ "$install_deps" = "y" ] || [ "$install_deps" = "Y" ]; then
                    echo ""
                    echo "Installing dependencies..."

                    # Install Xcode Command Line Tools (includes Swift)
                    if echo "$MISSING_CRITICAL" | grep -q "xcode-cli-tools"; then
                        echo ""
                        echo "Installing Xcode Command Line Tools..."
                        echo "A dialog will appear. Please click 'Install' and wait for completion."
                        echo ""

                        # Trigger Xcode CLI tools installation
                        xcode-select --install 2>/dev/null || true

                        echo ""
                        echo "⏳ Waiting for Xcode Command Line Tools installation..."
                        echo "   This may take several minutes. Please complete the installation in the dialog."
                        echo ""
                        printf "Press Enter once the installation is complete..."
                        read -r _wait

                        # Verify Swift is now available
                        if command -v swift >/dev/null 2>&1 || command -v swiftc >/dev/null 2>&1; then
                            echo "✅ Swift compiler installed successfully!"
                            HAS_SWIFT=1
                        else
                            echo "❌ Swift compiler still not found after installation."
                            echo "   The Xcode Command Line Tools installation may have failed."
                            echo ""

                            # Offer Homebrew as alternative
                            if [ "$USE_DEFAULTS" = "1" ]; then
                                try_brew="y"
                                echo "Auto-install mode: Will try Homebrew installation..."
                            else
                                printf "Would you like to try installing Swift via Homebrew instead? (Y/n): "
                                read -r try_brew
                            fi

                            if [ "$try_brew" != "n" ] && [ "$try_brew" != "N" ]; then
                                echo ""
                                # Check if Homebrew is installed
                                if ! command -v brew >/dev/null 2>&1; then
                                    echo "Homebrew is not installed."
                                    if [ "$USE_DEFAULTS" = "1" ]; then
                                        install_brew="y"
                                        echo "Auto-install mode: Installing Homebrew..."
                                    else
                                        printf "Install Homebrew now? (Y/n): "
                                        read -r install_brew
                                    fi

                                    if [ "$install_brew" != "n" ] && [ "$install_brew" != "N" ]; then
                                        echo ""
                                        echo "Installing Homebrew..."
                                        echo "This may take several minutes and requires sudo access."
                                        echo ""

                                        # Install Homebrew (as the real user, not root)
                                        if [ -n "${SUDO_USER:-}" ]; then
                                            sudo -u "$SUDO_USER" /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                                        else
                                            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                                        fi

                                        # Check if brew is now available
                                        if ! command -v brew >/dev/null 2>&1; then
                                            # Try common Homebrew paths
                                            if [ -x "/opt/homebrew/bin/brew" ]; then
                                                export PATH="/opt/homebrew/bin:$PATH"
                                            elif [ -x "/usr/local/bin/brew" ]; then
                                                export PATH="/usr/local/bin:$PATH"
                                            fi
                                        fi

                                        if command -v brew >/dev/null 2>&1; then
                                            echo "✅ Homebrew installed successfully!"
                                        else
                                            echo "❌ Homebrew installation failed."
                                            echo "   Please install manually: https://brew.sh"
                                            exit 1
                                        fi
                                    else
                                        echo "Homebrew installation declined. Cannot proceed without Swift compiler."
                                        exit 1
                                    fi
                                fi

                                # Now install Swift via Homebrew
                                echo ""
                                echo "Installing Swift via Homebrew..."
                                if [ -n "${SUDO_USER:-}" ]; then
                                    sudo -u "$SUDO_USER" brew install swift
                                else
                                    brew install swift
                                fi

                                # Verify Swift is now available
                                if command -v swift >/dev/null 2>&1 || command -v swiftc >/dev/null 2>&1; then
                                    echo "✅ Swift compiler installed successfully via Homebrew!"
                                    HAS_SWIFT=1
                                else
                                    echo "❌ Swift installation via Homebrew failed."
                                    echo "   Please try manually: brew install swift"
                                    exit 1
                                fi
                            else
                                echo ""
                                echo "Installation cancelled. Swift compiler is required to continue."
                                echo ""
                                echo "Manual installation options:"
                                echo "  1. Retry: xcode-select --install"
                                echo "  2. Install Homebrew and Swift:"
                                echo "     /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                                echo "     brew install swift"
                                exit 1
                            fi
                        fi
                    fi

                    echo ""

                    # Re-check critical dependencies
                    if [ -n "$MISSING_CRITICAL" ]; then
                        # Check for built-in tools that should never be missing
                        if echo "$MISSING_CRITICAL" | grep -qE "networksetup|ipconfig|launchctl"; then
                            echo "❌ Critical macOS system tools are missing."
                            echo "   Your macOS installation may be corrupted."
                            echo -n "   Tools missing:"
                            echo "$MISSING_CRITICAL" | grep -qw "networksetup" && echo -n " networksetup"
                            echo "$MISSING_CRITICAL" | grep -qw "ipconfig" && echo -n " ipconfig"
                            echo "$MISSING_CRITICAL" | grep -qw "launchctl" && echo -n " launchctl"
                            echo ""
                            exit 1
                        fi
                    fi

                    if [ -n "$MISSING_OPTIONAL" ]; then
                        if echo "$MISSING_OPTIONAL" | grep -q "ping"; then
                            echo "⚠️  Note: ping is still not available"
                            echo "   Internet connectivity monitoring will be limited to basic checks"
                        fi
                    fi

                    echo ""
                    echo "✅ Critical dependencies satisfied!"
                    echo ""
                else
                    # User declined installation
                    if [ -n "$MISSING_CRITICAL" ]; then
                        echo ""
                        echo "❌ Cannot continue without critical dependencies."
                        if echo "$MISSING_CRITICAL" | grep -q "xcode-cli-tools"; then
                            echo ""
                            echo "Swift compiler is required to build the network watcher."
                            echo "Please install Xcode Command Line Tools:"
                            echo "  xcode-select --install"
                        fi
                        if echo "$MISSING_CRITICAL" | grep -qE "networksetup|ipconfig|launchctl"; then
                            echo ""
                            echo -n "Missing critical macOS system tools:"
                            echo "$MISSING_CRITICAL" | grep -qw "networksetup" && echo -n " networksetup"
                            echo "$MISSING_CRITICAL" | grep -qw "ipconfig" && echo -n " ipconfig"
                            echo "$MISSING_CRITICAL" | grep -qw "launchctl" && echo -n " launchctl"
                            echo ""
                            echo "Your macOS installation may be corrupted."
                        fi
                        exit 1
                    else
                        # Only optional missing
                        echo ""
                        echo "Continuing with optional dependencies missing."
                        echo ""
                        if echo "$MISSING_OPTIONAL" | grep -q "ping"; then
                            echo "⚠️  Limited functionality:"
                            echo "   • Internet connectivity monitoring will use basic checks only"
                            echo "   • Gateway ping and custom ping targets won't be available"
                        fi
                        echo ""
                    fi
                fi
            else
                # Cannot auto-install anything
                if [ -n "$MISSING_CRITICAL" ]; then
                    echo "❌ Cannot continue: Critical dependencies missing."
                    echo "   Your macOS system tools appear to be corrupted."
                    exit 1
                else
                    printf "Continue with limited functionality? (y/N): "
                    read -r continue_install
                    if [ "$continue_install" != "y" ] && [ "$continue_install" != "Y" ]; then
                        echo "Installation cancelled."
                        exit 0
                    fi
                    echo ""
                fi
            fi
        else
            # Non-interactive mode - check for AUTO_INSTALL_DEPS
            if [ "${AUTO_INSTALL_DEPS:-0}" = "1" ]; then
                echo "Non-interactive mode with AUTO_INSTALL_DEPS=1"

                if echo "$MISSING_CRITICAL" | grep -q "xcode-cli-tools"; then
                    echo ""
                    echo "⚠️  Cannot auto-install Xcode Command Line Tools in non-interactive mode."
                    echo "   This requires manual interaction with a dialog."
                    echo ""
                    echo "Options:"
                    echo "  1. Run interactively: sudo sh install.sh"
                    echo "  2. Pre-install: xcode-select --install (then re-run installer)"
                    echo "  3. Use Homebrew: brew install swift (if you can't use App Store)"
                    exit 1
                fi

                if echo "$MISSING_CRITICAL" | grep -qE "networksetup|ipconfig|launchctl"; then
                    echo "❌ Critical macOS system tools are missing."
                    echo -n "   Tools missing:"
                    echo "$MISSING_CRITICAL" | grep -qw "networksetup" && echo -n " networksetup"
                    echo "$MISSING_CRITICAL" | grep -qw "ipconfig" && echo -n " ipconfig"
                    echo "$MISSING_CRITICAL" | grep -qw "launchctl" && echo -n " launchctl"
                    echo ""
                    echo "   Your macOS installation may be corrupted."
                    exit 1
                fi

                echo "⚠️  Continuing with optional dependencies missing."
                echo ""
            elif [ -n "$MISSING_CRITICAL" ]; then
                echo "❌ Cannot continue: Critical dependencies missing."
                if echo "$MISSING_CRITICAL" | grep -q "xcode-cli-tools"; then
                    echo "   Please install: xcode-select --install"
                    echo "   Or use Homebrew: brew install swift"
                    echo "   Or run with: sudo AUTO_INSTALL_DEPS=1 sh install.sh (interactive)"
                fi
                if echo "$MISSING_CRITICAL" | grep -qE "networksetup|ipconfig|launchctl"; then
                    echo -n "   System tools missing:"
                    echo "$MISSING_CRITICAL" | grep -qw "networksetup" && echo -n " networksetup"
                    echo "$MISSING_CRITICAL" | grep -qw "ipconfig" && echo -n " ipconfig"
                    echo "$MISSING_CRITICAL" | grep -qw "launchctl" && echo -n " launchctl"
                    echo ""
                fi
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

ensure_root(){
  if [ "$(id -u)" -ne 0 ]; then
    echo "Re-running with sudo..."
    exec sudo -E sh "$0" "$WORKDIR"
  fi
}

real_user_home(){
  if [ -n "${SUDO_USER:-}" ]; then
    dscl . -read "/Users/${SUDO_USER}" NFSHomeDirectory 2>/dev/null | awk '{print $2}'
  else
    echo "$HOME"
  fi
}

detect_interfaces() {
    echo "Detecting network interfaces..."

    # Detect Wi-Fi
    AUTO_WIFI=$(networksetup -listallhardwareports | awk '/Hardware Port: (Wi-Fi|AirPort)/ {getline; print $2}' | head -n 1) || AUTO_WIFI=""

    # Detect Ethernet - prioritize USB LAN adapters, then other Ethernet/LAN, then any enX interface
    AUTO_ETH=""

    # Method 1: Prefer USB LAN adapters (e.g., "USB 10/100/1G/2.5G LAN")
    AUTO_ETH=$(networksetup -listallhardwareports | awk '
        /Hardware Port:.*USB.*LAN/ {
            getline;
            if ($1 == "Device:") {
                print $2;
                exit
            }
        }
    ')

    # Method 2: If no USB found, try other Ethernet/LAN interfaces with IP addresses
    if [ -z "$AUTO_ETH" ]; then
        networksetup -listallhardwareports | awk '
            /Hardware Port:.*Ethernet|Hardware Port:.*LAN/ {
                if ($0 !~ /Thunderbolt Bridge|USB/) {
                    getline;
                    if ($1 == "Device:") {
                        print $2
                    }
                }
            }
        ' | while read -r iface; do
            if [ -n "$iface" ] && [ "$iface" != "$AUTO_WIFI" ]; then
                ip=$(/usr/sbin/ipconfig getifaddr "$iface" 2>/dev/null || true)
                if [ -n "$ip" ]; then
                    AUTO_ETH="$iface"
                    echo "$iface" > /tmp/auto_eth_detected.$$
                    break
                fi
            fi
        done

        if [ -f /tmp/auto_eth_detected.$$ ]; then
            AUTO_ETH=$(cat /tmp/auto_eth_detected.$$)
            rm -f /tmp/auto_eth_detected.$$
        fi
    fi

    # Method 3: If still not found, try any Ethernet/LAN interface by name pattern (without IP check)
    if [ -z "$AUTO_ETH" ]; then
        AUTO_ETH=$(networksetup -listallhardwareports | awk '
            /Hardware Port:.*Ethernet|Hardware Port:.*LAN/ {
                if ($0 !~ /Thunderbolt Bridge|USB/) {
                    getline;
                    if ($1 == "Device:") {
                        print $2;
                        exit
                    }
                }
            }
        ')
    fi

    # Method 4: Fallback to any enX interface that's not Wi-Fi and has IP
    if [ -z "$AUTO_ETH" ]; then
        for iface in $(networksetup -listallhardwareports | awk '/Device: en/ {print $2}'); do
            if [ "$iface" != "$AUTO_WIFI" ]; then
                ip=$(/usr/sbin/ipconfig getifaddr "$iface" 2>/dev/null || true)
                if [ -n "$ip" ]; then
                    AUTO_ETH="$iface"
                    break
                fi
            fi
        done
    fi

    if [ -n "${ETHERNET_INTERFACE:-}" ]; then
        AUTO_ETH="$ETHERNET_INTERFACE"
    fi
    if [ -n "${WIFI_INTERFACE:-}" ]; then
        AUTO_WIFI="$WIFI_INTERFACE"
    fi

    # Method 5: Final fallback - any enX that's not Wi-Fi
    if [ -z "$AUTO_ETH" ]; then
        AUTO_ETH=$(networksetup -listallhardwareports | awk '/Device: en/ {print $2}' | grep -v "^${AUTO_WIFI}$" | head -n 1) || AUTO_ETH=""
    fi

    if [ -t 0 ] && [ "$USE_DEFAULTS" = "0" ]; then
        echo ""
        echo "Available network interfaces:"
        networksetup -listallhardwareports
        echo ""

        WIFI_PROMPT=${AUTO_WIFI:-"Not set"}
        printf "Enter Wi-Fi interface [%s]: " "$WIFI_PROMPT"
        read -r input_wifi
        WIFI_DEV=${input_wifi:-$AUTO_WIFI}

        ETH_PROMPT=${AUTO_ETH:-"Not set"}
        printf "Enter Ethernet interface [%s]: " "$ETH_PROMPT"
        read -r input_eth
        ETH_DEV=${input_eth:-$AUTO_ETH}

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
            CHECK_METHOD="gateway"
            CHECK_TARGET=""
            LOG_CHECK_ATTEMPTS=0
            CHECK_INTERVAL=0
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
            networksetup -listallhardwareports | awk '
                /Hardware Port:/ {
                    port = $0
                    sub(/^Hardware Port: /, "", port)
                    getline
                    if ($1 == "Device:") {
                        device = $2
                        print "  " device " (" port ")"
                    }
                }
            '
            echo ""
            echo "Enter interfaces in priority order (comma-separated, highest first):"
            echo "Example: en5,en6,en0"
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
        WIFI_DEV="$AUTO_WIFI"
        ETH_DEV="$AUTO_ETH"
        TIMEOUT="${TIMEOUT:-7}"
        CHECK_INTERNET="${CHECK_INTERNET:-1}"
        CHECK_INTERVAL="${CHECK_INTERVAL:-30}"
        CHECK_METHOD="${CHECK_METHOD:-ping}"
        CHECK_TARGET="${CHECK_TARGET:-8.8.8.8}"
        LOG_CHECK_ATTEMPTS="${LOG_CHECK_ATTEMPTS:-0}"
        INTERFACE_PRIORITY="${INTERFACE_PRIORITY:-}"
        echo "  Wi-Fi: $WIFI_DEV"
        echo "  Ethernet: $ETH_DEV"
        echo "  Internet monitoring: Enabled (ping to 8.8.8.8 every 30s)"
    else
        WIFI_DEV="$AUTO_WIFI"
        ETH_DEV="$AUTO_ETH"
        TIMEOUT="${TIMEOUT:-7}"
        CHECK_INTERNET="${CHECK_INTERNET:-0}"
        CHECK_INTERVAL="${CHECK_INTERVAL:-0}"
        CHECK_METHOD="${CHECK_METHOD:-gateway}"
        CHECK_TARGET="${CHECK_TARGET:-}"
        LOG_CHECK_ATTEMPTS="${LOG_CHECK_ATTEMPTS:-0}"
        INTERFACE_PRIORITY="${INTERFACE_PRIORITY:-}"
    fi

    echo ""
    echo "Using configuration:"
    echo "  Wi-Fi:            ${WIFI_DEV:-not found}"
    echo "  Ethernet:         ${ETH_DEV:-not found}"
    echo "  DHCP Timeout:     ${TIMEOUT}s"
    echo "  Internet Check:   $CHECK_INTERNET"
    if [ "$CHECK_INTERNET" = "1" ]; then
        echo "  Check Method:     $CHECK_METHOD"
        if [ -n "$CHECK_TARGET" ]; then
            echo "  Check Target:     $CHECK_TARGET"
        fi
        echo "  Log All Checks:   $LOG_CHECK_ATTEMPTS"

        # Verify curl is available (required for multi-interface checking on macOS)
        if ! command -v curl >/dev/null 2>&1; then
            echo ""
            echo "⚠️  WARNING: curl is not installed but required for checking inactive interfaces"
            echo "   on macOS. Install curl or internet checking will only work for the active"
            echo "   interface. Curl is standard on macOS, this is unexpected."
            echo ""
        fi
    fi
    if [ -n "$INTERFACE_PRIORITY" ]; then
        echo "  Interface Priority: $INTERFACE_PRIORITY"
    fi

    if [ -z "$WIFI_DEV" ] || [ -z "$ETH_DEV" ]; then
        die "Both Wi-Fi and Ethernet interfaces must be specified to continue."
    fi
}

stop_processes_by_pattern() {
    pattern="$1"
    label="$2"
    pids=$(pgrep -f "$pattern" || true)

    if [ -n "$pids" ]; then
        echo "Stopping $label processes..."
        for pid in $pids; do
            pname=$(ps -p "$pid" -o comm= 2>/dev/null || echo "$pattern")
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

cleanup_existing() {
    found_old_install=0

    # 1. Look for the standard plist
    if [ -f "$SYS_PLIST_PATH" ]; then
        found_old_install=1
        echo "Old installation detected at: $SYS_PLIST_PATH"

        # Use plutil to safely extract values (handles binary plists)
        OLD_WORKDIR=$(plutil -extract WorkingDirectory raw -o - "$SYS_PLIST_PATH" 2>/dev/null || true)

        if [ -z "$OLD_WORKDIR" ]; then
            OLD_LOGPATH=$(plutil -extract StandardOutPath raw -o - "$SYS_PLIST_PATH" 2>/dev/null || true)
            if [ -n "$OLD_LOGPATH" ]; then
                OLD_WORKDIR=$(dirname "$OLD_LOGPATH")
            fi
        fi

        if [ -n "$OLD_WORKDIR" ]; then
            echo "  Workspace directory: $OLD_WORKDIR"
        fi

        if [ -n "$OLD_WORKDIR" ] && [ -f "$OLD_WORKDIR/uninstall.sh" ]; then
            echo "  Running existing uninstaller..."
            sh "$OLD_WORKDIR/uninstall.sh" || true
        else
            if [ -z "$OLD_WORKDIR" ]; then
                echo "  Workspace directory not found. Performing manual cleanup..."
            else
                echo "  No uninstaller found. Performing manual cleanup..."
            fi
            stop_processes_by_pattern "ethwifiauto-watch" "watcher"
            stop_processes_by_pattern "eth-wifi-auto.sh" "helper"
            launchctl bootout system "$SYS_PLIST_PATH" 2>/dev/null || true
            launchctl unload "$SYS_PLIST_PATH" 2>/dev/null || true
            rm -f "$SYS_PLIST_PATH" "$SYS_HELPER_PATH" "$SYS_WATCHER_BIN"
        fi
    fi

    # 2. Extra safety: check for any other plists that might be ours
    for extra_plist in /Library/LaunchDaemons/com.eth-wifi-auto*.plist /Library/LaunchDaemons/com.ethwifiauto*.plist; do
        if [ -f "$extra_plist" ]; then
            # Skip the one we are about to install if it's already there (handled above)
            [ "$extra_plist" = "$SYS_PLIST_PATH" ] && continue

            found_old_install=1
            echo "Old installation detected at: $extra_plist"
            echo "  Removing legacy configuration..."
            stop_processes_by_pattern "ethwifiauto-watch" "watcher"
            stop_processes_by_pattern "eth-wifi-auto.sh" "helper"
            launchctl bootout system "$extra_plist" 2>/dev/null || true
            launchctl unload "$extra_plist" 2>/dev/null || true
            rm -f "$extra_plist"
        fi
    done

    # 3. Report status
    if [ "$found_old_install" -eq 0 ]; then
        echo "No old installation detected."
    fi
}

main(){
  need_macos
  if [ "$IS_TEST" = "1" ]; then
    echo "TEST_MODE=1: skipping macOS install steps."
    exit 0
  fi

  # Check dependencies before proceeding
  check_dependencies

  ensure_root
  cleanup_existing
  echo ""
  detect_interfaces

  if [ "$WORKDIR" = "$DEFAULT_WORKDIR" ] && [ -n "${SUDO_USER:-}" ]; then
    WORKDIR="$(real_user_home)/.ethernet-wifi-auto-switcher"
  fi

  WORKDIR="$(python3 -c 'import os,sys; print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "$WORKDIR")"

  mkdir -p "$WORKDIR"
  chmod 755 "$WORKDIR" || true

  SRC_DIR="${WORKDIR}/src"
  BIN_DIR="${WORKDIR}/bin"
  STATE_DIR="${WORKDIR}/state"
  mkdir -p "$SRC_DIR" "$BIN_DIR" "$STATE_DIR"
  chmod 755 "$SRC_DIR" "$BIN_DIR" "$STATE_DIR" || true

  WATCH_LOG="${WORKDIR}/watch.log"
  WATCH_ERR="${WORKDIR}/watch.err"
  HELPER_LOG="${WORKDIR}/helper.log"
  HELPER_ERR="${WORKDIR}/helper.err"

  WORK_HELPER="${WORKDIR}/eth-wifi-auto.sh"
  WORK_BIN="${BIN_DIR}/ethwifiauto-watch"
  WORK_PLIST="${WORKDIR}/${DAEMON_LABEL}.plist"
  WORK_UNINSTALL="${WORKDIR}/uninstall.sh"

  echo "Installation directory: $WORKDIR"
  echo ""

  echo "Extracting helper script..."
  echo "$HELPER_CONTENT_B64" | base64 -d > "$WORK_HELPER"
  sed -i '' "s|WIFI_DEV=\"\${WIFI_DEV:-en0}\"|WIFI_DEV=\"$WIFI_DEV\"|g" "$WORK_HELPER"
  sed -i '' "s|ETH_DEV=\"\${ETH_DEV:-en5}\"|ETH_DEV=\"$ETH_DEV\"|g" "$WORK_HELPER"
  sed -i '' "s|STATE_DIR=\"\${STATE_DIR:-/tmp}\"|STATE_DIR=\"$STATE_DIR\"|g" "$WORK_HELPER"
  sed -i '' "s|TIMEOUT=\"\${TIMEOUT:-7}\"|TIMEOUT=\"$TIMEOUT\"|g" "$WORK_HELPER"
  sed -i '' "s|CHECK_INTERNET=\"\${CHECK_INTERNET:-0}\"|CHECK_INTERNET=\"$CHECK_INTERNET\"|g" "$WORK_HELPER"
  sed -i '' "s|CHECK_METHOD=\"\${CHECK_METHOD:-gateway}\"|CHECK_METHOD=\"$CHECK_METHOD\"|g" "$WORK_HELPER"
  sed -i '' "s|CHECK_TARGET=\"\${CHECK_TARGET:-}\"| CHECK_TARGET=\"$CHECK_TARGET\"|g" "$WORK_HELPER"
  sed -i '' "s|LOG_CHECK_ATTEMPTS=\"\${LOG_CHECK_ATTEMPTS:-0}\"|LOG_CHECK_ATTEMPTS=\"$LOG_CHECK_ATTEMPTS\"|g" "$WORK_HELPER"
  sed -i '' "s|INTERFACE_PRIORITY=\"\${INTERFACE_PRIORITY:-}\"|INTERFACE_PRIORITY=\"$INTERFACE_PRIORITY\"|g" "$WORK_HELPER"
  chmod +x "$WORK_HELPER"

  echo "Extracting watcher binary..."
  echo "$WATCHER_BASE64" | base64 -d > "$WORK_BIN"
  chmod +x "$WORK_BIN"
  /usr/bin/codesign -s - "$WORK_BIN" >/dev/null 2>&1 || true

  echo "Installing system binaries..."
  mkdir -p /usr/local/sbin
  cp -f "$WORK_HELPER" "$SYS_HELPER_PATH"
  cp -f "$WORK_BIN" "$SYS_WATCHER_BIN"
  chmod +x "$SYS_HELPER_PATH" "$SYS_WATCHER_BIN"

  echo "Generating LaunchDaemon plist..."
  echo "$PLIST_CONTENT_B64" | base64 -d > "$WORK_PLIST"
  sed -i '' "s|\$DAEMON_LABEL|$DAEMON_LABEL|g" "$WORK_PLIST"
  sed -i '' "s|\$SYS_WATCHER_BIN|$SYS_WATCHER_BIN|g" "$WORK_PLIST"
  sed -i '' "s|\$SYS_HELPER_PATH|$SYS_HELPER_PATH|g" "$WORK_PLIST"
  sed -i '' "s|\$HELPER_LOG|$HELPER_LOG|g" "$WORK_PLIST"
  sed -i '' "s|\$HELPER_ERR|$HELPER_ERR|g" "$WORK_PLIST"
  sed -i '' "s|\$WATCH_LOG|$WATCH_LOG|g" "$WORK_PLIST"
  sed -i '' "s|\$WATCH_ERR|$WATCH_ERR|g" "$WORK_PLIST"
  sed -i '' "s|\$WIFI_DEV|$WIFI_DEV|g" "$WORK_PLIST"
  sed -i '' "s|\$ETH_DEV|$ETH_DEV|g" "$WORK_PLIST"
  sed -i '' "s|\$CHECK_INTERVAL|$CHECK_INTERVAL|g" "$WORK_PLIST"
  sed -i '' "s|\$WORKDIR|$WORKDIR|g" "$WORK_PLIST"

  cp -f "$WORK_PLIST" "$SYS_PLIST_PATH"
  chown root:wheel "$SYS_PLIST_PATH"
  chmod 644 "$SYS_PLIST_PATH"

  echo "Extracting uninstall script..."
  echo "$UNINSTALL_CONTENT_B64" | base64 -d > "$WORK_UNINSTALL"
  sed -i '' "s|SYS_PLIST_PATH_PLACEHOLDER|$SYS_PLIST_PATH|g" "$WORK_UNINSTALL"
  sed -i '' "s|SYS_HELPER_PATH_PLACEHOLDER|$SYS_HELPER_PATH|g" "$WORK_UNINSTALL"
  sed -i '' "s|SYS_WATCHER_BIN_PLACEHOLDER|$SYS_WATCHER_BIN|g" "$WORK_UNINSTALL"
  sed -i '' "s|WORKDIR_PLACEHOLDER|$WORKDIR|g" "$WORK_UNINSTALL"
  chmod +x "$WORK_UNINSTALL"

  echo "Loading LaunchDaemon..."
  launchctl bootout system "$SYS_PLIST_PATH" >/dev/null 2>&1 || true
  launchctl bootstrap system "$SYS_PLIST_PATH" >/dev/null 2>&1 || true

  echo ""
  echo "✅ Installation complete."
  echo ""
  echo "The service is now running. It will automatically:"
  echo "  • Turn Wi-Fi off when Ethernet is connected"
  echo "  • Turn Wi-Fi on when Ethernet is disconnected"
  echo "  • Continue working after OS reboot"
  echo "Logs: $WATCH_LOG (watcher) and $HELPER_LOG (helper). Tail with: tail -f \"$WATCH_LOG\" \"$HELPER_LOG\""
  echo ""
  echo "To uninstall, run:"
  echo "  sudo sh \"$WORK_UNINSTALL\""
}

uninstall() {
  if [ "$IS_TEST" = "1" ]; then
    echo "TEST_MODE=1: skipping macOS uninstall steps."
    exit 0
  fi
  ensure_root
  echo "Uninstalling..."
  # Try to detect WORKDIR from installed uninstaller if not set
  if [ -z "$WORKDIR" ] && [ -f "$DEFAULT_WORKDIR/uninstall.sh" ]; then
    WORKDIR="$DEFAULT_WORKDIR"
  fi
  # We need to extract the uninstaller script to run it
  # or we can just embed the logic here.
  # Since we already have UNINSTALL_CONTENT_B64, let's use it.
  echo "$UNINSTALL_CONTENT_B64" | base64 -d | \
    sed "s|SYS_PLIST_PATH_PLACEHOLDER|$SYS_PLIST_PATH|g" | \
    sed "s|SYS_HELPER_PATH_PLACEHOLDER|$SYS_HELPER_PATH|g" | \
    sed "s|SYS_WATCHER_BIN_PLACEHOLDER|$SYS_WATCHER_BIN|g" | \
    sed "s|WORKDIR_PLACEHOLDER|$WORKDIR|g" | sh
}

if [ "${1:-}" = "--uninstall" ]; then
  uninstall
else
  main "$@"
fi
