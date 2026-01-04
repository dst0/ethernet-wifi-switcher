#!/bin/sh
set -eu

# Event-driven Ethernet/Wi-Fi switcher for Linux
# Supports NetworkManager (nmcli) and ip/rfkill fallbacks

STATE_FILE="${STATE_FILE:-/tmp/eth-wifi-state}"
TIMEOUT="${TIMEOUT:-7}"
CHECK_INTERNET="${CHECK_INTERNET:-0}"
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"
CHECK_METHOD="${CHECK_METHOD:-gateway}"
CHECK_TARGET="${CHECK_TARGET:-}"
LOG_CHECK_ATTEMPTS="${LOG_CHECK_ATTEMPTS:-0}"
INTERFACE_PRIORITY="${INTERFACE_PRIORITY:-}"
LAST_CHECK_STATE_FILE="${STATE_FILE}.last_check"

# Detect and load appropriate network backend
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_LOADED=0

if command -v nmcli >/dev/null 2>&1; then
    # NetworkManager backend
    if [ -f "$SCRIPT_DIR/lib/network-nmcli.sh" ]; then
        . "$SCRIPT_DIR/lib/network-nmcli.sh"
        BACKEND_LOADED=1
        BACKEND_NAME="nmcli"
    fi
fi

if [ "$BACKEND_LOADED" = "0" ] && command -v ip >/dev/null 2>&1; then
    # IP command fallback backend
    if [ -f "$SCRIPT_DIR/lib/network-ip.sh" ]; then
        . "$SCRIPT_DIR/lib/network-ip.sh"
        BACKEND_LOADED=1
        BACKEND_NAME="ip"
    fi
fi

if [ "$BACKEND_LOADED" = "0" ]; then
    echo "ERROR: No supported network tools found (nmcli or ip command)" >&2
    echo "Please install NetworkManager (for nmcli) or iproute2 (for ip command)" >&2
    exit 1
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "Using backend: $BACKEND_NAME"

read_last_state(){
  # If file doesn't exist or can't be read, treat as disconnected
  if [ -f "$STATE_FILE" ]; then
    cat "$STATE_FILE" 2>/dev/null || echo "disconnected"
  else
    echo "disconnected"
  fi
}

write_state(){
  echo "$1" > "$STATE_FILE"
}

get_eth_dev() {
    # If INTERFACE_PRIORITY is set, use it; otherwise default behavior
    if [ -n "$INTERFACE_PRIORITY" ]; then
        # Parse priority list and return first available ethernet interface
        for iface in $(echo "$INTERFACE_PRIORITY" | tr ',' ' '); do
            iface=$(echo "$iface" | xargs) # trim whitespace
            if [ -n "$iface" ] && is_ethernet_iface "$iface"; then
                echo "$iface"
                return 0
            fi
        done
    fi
    # Default: get first ethernet interface
    get_first_ethernet_iface
}

get_wifi_dev() {
    # If INTERFACE_PRIORITY is set, check it for wifi interfaces
    if [ -n "$INTERFACE_PRIORITY" ]; then
        # Parse priority list and return first available wifi interface
        for iface in $(echo "$INTERFACE_PRIORITY" | tr ',' ' '); do
            iface=$(echo "$iface" | xargs) # trim whitespace
            if [ -n "$iface" ] && is_wifi_iface "$iface"; then
                echo "$iface"
                return 0
            fi
        done
    fi
    # Default: get first wifi interface
    get_first_wifi_iface
}

# Note: get_all_eth_devs, get_all_wifi_devs, get_all_network_devs
# are provided by the backend (network-nmcli.sh or network-ip.sh)

check_internet() {
    iface="$1"
    result=1

    case "$CHECK_METHOD" in
        gateway)
            # Ping gateway - most reliable and safest method
            # Get the gateway for this interface
            gateway=$(ip route show dev "$iface" | grep default | awk '{print $3}' | head -n 1)
            if [ -z "$gateway" ]; then
                if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
                    log "No gateway found for $iface"
                fi
                return 1
            fi
            # Ping gateway with short timeout
            if ping -I "$iface" -c 1 -W 2 "$gateway" >/dev/null 2>&1; then
                result=0
            fi
            if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
                if [ $result -eq 0 ]; then
                    log "Internet check: gateway ping to $gateway via $iface succeeded"
                else
                    log "Internet check: gateway ping to $gateway via $iface failed"
                fi
            fi
            ;;

        ping)
            # Ping domain/IP - requires CHECK_TARGET to be set
            if [ -z "$CHECK_TARGET" ]; then
                log "CHECK_TARGET not set for ping method"
                return 1
            fi
            if ping -I "$iface" -c 1 -W 3 "$CHECK_TARGET" >/dev/null 2>&1; then
                result=0
            fi
            if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
                if [ $result -eq 0 ]; then
                    log "Internet check: ping to $CHECK_TARGET via $iface succeeded"
                else
                    log "Internet check: ping to $CHECK_TARGET via $iface failed"
                fi
            fi
            ;;

        curl)
            # HTTP/HTTPS check using curl - may be blocked by providers
            if [ -z "$CHECK_TARGET" ]; then
                CHECK_TARGET="http://captive.apple.com/hotspot-detect.html"
            fi
            if command -v curl >/dev/null 2>&1; then
                if curl --interface "$iface" --connect-timeout 5 --max-time 10 -s -f "$CHECK_TARGET" >/dev/null 2>&1; then
                    result=0
                fi
            elif command -v wget >/dev/null 2>&1; then
                # Get IP address for wget binding
                iface_ip=$(get_iface_ip "$iface")
                if [ -n "$iface_ip" ]; then
                    if wget --bind-address="$iface_ip" --timeout=10 --tries=1 -q -O /dev/null "$CHECK_TARGET" 2>/dev/null; then
                        result=0
                    fi
                fi
            fi
            if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
                if [ $result -eq 0 ]; then
                    log "Internet check: HTTP check to $CHECK_TARGET via $iface succeeded"
                else
                    log "Internet check: HTTP check to $CHECK_TARGET via $iface failed"
                fi
            fi
            ;;

        *)
            log "Unknown CHECK_METHOD: $CHECK_METHOD"
            return 1
            ;;
    esac

    # Log state changes (always logged regardless of LOG_CHECK_ATTEMPTS)
    last_check_state=$(cat "$LAST_CHECK_STATE_FILE" 2>/dev/null || echo "unknown")
    current_check_state="success"
    if [ $result -ne 0 ]; then
        current_check_state="failed"
    fi

    if [ "$last_check_state" != "$current_check_state" ]; then
        if [ "$current_check_state" = "success" ]; then
            log "Internet check: $iface is now reachable (recovered from failure)"
        else
            log "Internet check: $iface is now unreachable (was working before)"
        fi
        echo "$current_check_state" > "$LAST_CHECK_STATE_FILE"
    fi

    return $result
}

eth_is_connecting() {
    eth_dev="$1"
    eth_state=$(get_iface_state "$eth_dev")
    [ "$eth_state" = "connecting" ] || [ "$eth_state" = "connected (externally)" ]
}

eth_is_connected() {
    eth_dev="$1"
    eth_state=$(get_iface_state "$eth_dev")
    [ "$eth_state" = "connected" ]
}

eth_is_connected_with_retry() {
    eth_dev="$1"

    # Try immediate check
    if eth_is_connected "$eth_dev"; then
        return 0
    fi

    # Check if interface is connecting but no IP yet
    if eth_is_connecting "$eth_dev"; then
        log "Ethernet interface active but no IP yet, waiting..."
    fi

    # Poll every second until timeout
    elapsed=0
    while [ "$elapsed" -lt "$TIMEOUT" ]; do
        sleep 1
        elapsed=$((elapsed + 1))

        if eth_is_connected "$eth_dev"; then
            log "Ethernet acquired connection after ${elapsed}s"
            return 0
        fi
    done

    return 1
}

ensure_wifi_on_and_wait() {
    iface="$1"
    # Check if wifi is disabled or not connected
    if [ "$wifi_enabled" = "disabled" ] || [ "$(get_iface_state "$iface")" != "connected" ]; then
        if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
            log "  Enabling WiFi ($iface) to check for internet..."
        fi
        enable_wifi

        if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
           log "  Waiting for IP address on $iface..."
        fi

        wait_retries=0
        max_wait_retries=15
        while [ $wait_retries -lt $max_wait_retries ]; do
             if [ "$(get_iface_state "$iface")" = "connected" ]; then
                 break
             fi
             sleep 1
             wait_retries=$((wait_retries + 1))
        done
    fi
}

check_and_switch() {
    eth_dev=$(get_eth_dev)
    wifi_dev=$(get_wifi_dev)

    if [ -z "$eth_dev" ] || [ -z "$wifi_dev" ]; then
        return
    fi

    last_state=$(read_last_state)

    # Determine current active interface (the one we're currently using)
    active_iface=""

    # Check ethernet first (higher priority)
    if eth_is_connected "$eth_dev"; then
        active_iface="$eth_dev"
        active_type="ethernet"
    elif is_wifi_enabled; then
        # Check if wifi is connected
        wifi_state=$(get_iface_state "$wifi_dev")
        if [ "$wifi_state" = "connected" ]; then
            active_iface="$wifi_dev"
            active_type="wifi"
        fi
    fi

    # If internet checking is enabled, validate the ACTIVE connection
    if [ "$CHECK_INTERNET" = "1" ] && [ -n "$active_iface" ]; then
        active_has_internet=0
        if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
            log "Checking internet on active interface: $active_iface ($active_type)"
        fi

        if check_internet "$active_iface"; then
            active_has_internet=1
            if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
                log "✓ Active interface $active_iface has internet"
            fi
        fi

        # Always check higher priority interfaces (whether active has internet or not)
        found_higher_priority=""
        if [ -n "$INTERFACE_PRIORITY" ]; then
            # Find position of active interface in priority list
            active_position=0
            position=0
            for iface in $(echo "$INTERFACE_PRIORITY" | tr ',' ' '); do
                position=$((position + 1))
                iface=$(echo "$iface" | xargs)
                if [ "$iface" = "$active_iface" ]; then
                    active_position=$position
                    break
                fi
            done

            # Check all HIGHER priority interfaces
            if [ $active_position -gt 1 ]; then
                if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
                    log "Checking higher priority interfaces for recovery..."
                fi

                position=0
                for iface in $(echo "$INTERFACE_PRIORITY" | tr ',' ' '); do
                    position=$((position + 1))
                    iface=$(echo "$iface" | xargs)

                    # Only check interfaces with higher priority (lower position number)
                    if [ $position -ge $active_position ]; then
                        break
                    fi

                    if [ -z "$iface" ]; then
                        continue
                    fi

                    # Check if this is a WiFi interface and WiFi is disabled, enable it to check
                    if is_wifi_iface "$iface" && ! is_wifi_enabled; then
                        ensure_wifi_on_and_wait "$iface"
                    fi

                    # Check if interface is connected
                    iface_state=$(get_iface_state "$iface")
                    if [ "$iface_state" = "connected" ]; then
                        if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
                            log "  Checking $iface..."
                        fi
                        if check_internet "$iface"; then
                            log "✓ Higher priority interface $iface has internet, switching..."
                            found_higher_priority="$iface"
                            break
                        else
                            if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
                                log "  No internet on $iface"
                            fi
                        fi
                    else
                        if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
                            log "  Interface $iface is not connected (state: ${iface_state:-unknown})"
                        fi
                    fi
                done
            fi

            # If higher priority interface found, switch to it
            if [ -n "$found_higher_priority" ]; then
                if is_ethernet_iface "$found_higher_priority"; then
                    log "→ Switching to Ethernet ($found_higher_priority)"
                    write_state "connected"
                    disable_wifi
                elif is_wifi_iface "$found_higher_priority"; then
                    log "→ Switching to WiFi ($found_higher_priority)"
                    write_state "disconnected"
                    enable_wifi
                fi
                return
            fi
        fi

        # If active interface has internet and no higher priority available, we're done
        if [ $active_has_internet -eq 1 ]; then
            # Ensure WiFi state matches the active interface type
            if [ "$active_type" = "ethernet" ]; then
                write_state "connected"
                if wifi_is_on; then
                    log "eth up with internet, turning wifi off"
                    set_wifi off
                fi
            elif [ "$active_type" = "wifi" ]; then
                write_state "disconnected"
                # WiFi should be on (it is, since it's active)
            fi
            return
        fi

        # Active interface has NO internet and no higher priority works - try lower priority
        log "⚠️  Active interface $active_iface has NO internet, searching for alternatives..."
        found_working_iface=""

        if [ -n "$INTERFACE_PRIORITY" ]; then
            # Try all interfaces in priority order (will skip higher priority ones we already checked)
            for iface in $(echo "$INTERFACE_PRIORITY" | tr ',' ' '); do
                iface=$(echo "$iface" | xargs)
                if [ -z "$iface" ] || [ "$iface" = "$active_iface" ]; then
                    continue
                fi

                # Skip if this was the higher priority we already checked
                if [ "$iface" = "$found_higher_priority" ]; then
                    continue
                fi

                # Check if this is a WiFi interface and WiFi is disabled, enable it to check
                if is_wifi_iface "$iface" && ! is_wifi_enabled; then
                    ensure_wifi_on_and_wait "$iface"
                fi

                # Check if interface is connected
                iface_state=$(get_iface_state "$iface")
                if [ "$iface_state" = "connected" ]; then
                    if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
                        log "  Checking $iface..."
                    fi
                    if check_internet "$iface"; then
                        log "✓ Found working internet on $iface"
                        found_working_iface="$iface"
                        break
                    else
                        log "  No internet on $iface"
                    fi
                else
                    if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
                        log "  Interface $iface is not connected (state: ${iface_state:-unknown})"
                    fi
                fi
            done
        else
            # No priority list - try ethernet then wifi
            if [ "$active_type" = "wifi" ] && eth_is_connected "$eth_dev"; then
                if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
                    log "  Checking $eth_dev (ethernet)..."
                fi
                if check_internet "$eth_dev"; then
                    log "✓ Found working internet on $eth_dev"
                    found_working_iface="$eth_dev"
                fi
            elif [ "$active_type" = "ethernet" ]; then
                # Current ethernet has no internet, try wifi
                if [ "$wifi_enabled" = "disabled" ]; then
                    ensure_wifi_on_and_wait "$wifi_dev"
                fi
                wifi_state=$(get_iface_state "$wifi_dev")
                if [ "$wifi_state" = "connected" ]; then
                    if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
                        log "  Checking $wifi_dev (wifi)..."
                    fi
                    if check_internet "$wifi_dev"; then
                        log "✓ Found working internet on $wifi_dev"
                        found_working_iface="$wifi_dev"
                    fi
                fi
            fi
        fi

        # Switch to the working interface if found
        if [ -n "$found_working_iface" ]; then
            if is_ethernet_iface "$found_working_iface"; then
                log "→ Switching to Ethernet ($found_working_iface)"
                write_state "connected"
                disable_wifi
            elif is_wifi_iface "$found_working_iface"; then
                log "→ Switching to WiFi ($found_working_iface)"
                write_state "disconnected"
                enable_wifi
            fi
            if [ -n "$INTERFACE_PRIORITY" ]; then
                log "   Periodic checks will continue monitoring higher priority interfaces for recovery"
            fi
            return
        else
            log "⚠️  No interface with working internet found, keeping current: $active_iface"
            log "   Will continue checking all interfaces every ${CHECK_INTERVAL}s until internet is restored"
            # Keep current interface even without internet (better than nothing)
            return
        fi
    fi

    # Standard logic when not checking internet or internet is OK
    # Quick check without retry
    if eth_is_connected "$eth_dev"; then
        current_state="connected"
    else
        current_state="disconnected"
    fi

    # If state changed from connected to disconnected, enable wifi immediately
    if [ "$last_state" = "connected" ] && [ "$current_state" = "disconnected" ]; then
        log "Ethernet disconnected, enabling Wi-Fi immediately"
        write_state "disconnected"
        if [ "$wifi_enabled" = "disabled" ]; then
            enable_wifi
        fi
        return
    fi

    # If currently disconnected, use retry logic to wait for IP
    if [ "$last_state" = "disconnected" ] && [ "$current_state" = "disconnected" ]; then
        # Try with retry for new connection
        if eth_is_connected_with_retry "$eth_dev"; then
            current_state="connected"
        fi
    fi

    # Update state and manage wifi
    write_state "$current_state"

    if [ "$current_state" = "connected" ]; then
        if is_wifi_enabled; then
            log "Ethernet connected ($eth_dev). Disabling Wi-Fi..."
            disable_wifi
        fi
    else
        if ! is_wifi_enabled; then
            log "Ethernet disconnected ($eth_dev). Enabling Wi-Fi..."
            enable_wifi
        fi
    fi
}

# Initial check
check_and_switch

# Start periodic internet check in background if enabled
if [ "$CHECK_INTERNET" = "1" ]; then
    (
        while true; do
            sleep "$CHECK_INTERVAL"
            check_and_switch
        done
    ) &
    CHECKER_PID=$!
    log "Started periodic internet checker (PID: $CHECKER_PID, interval: ${CHECK_INTERVAL}s)"
    if [ -n "$INTERFACE_PRIORITY" ]; then
        log "Priority-based monitoring: Will continuously check all interfaces for internet recovery"
        log "Higher priority interfaces will be preferred when multiple have connectivity"
    else
        log "Will continuously monitor and switch between ethernet and wifi based on connectivity"
    fi
fi

# Monitor events
log "Starting event monitor..."
monitor_events | while read -r line; do
    if echo "$line" | grep -qE "(connected|disconnected|connectivity|Connectivity)"; then
        check_and_switch
    fi
done
