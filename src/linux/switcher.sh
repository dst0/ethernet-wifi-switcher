#!/bin/sh
set -eu

# Event-driven Ethernet/Wi-Fi switcher for Linux (NetworkManager)
# Uses 'nmcli monitor' to wait for events, consuming 0% CPU while idle.

STATE_FILE="${STATE_FILE:-/tmp/eth-wifi-state}"
TIMEOUT="${TIMEOUT:-7}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

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
    nmcli device | grep -E "ethernet" | awk '{print $1}' | head -n 1
}

get_wifi_dev() {
    nmcli device | grep -E "wifi" | awk '{print $1}' | head -n 1
}

eth_is_connecting() {
    eth_dev="$1"
    eth_state=$(nmcli -t -f DEVICE,STATE device | grep "^$eth_dev:" | cut -d: -f2)
    [ "$eth_state" = "connecting" ] || [ "$eth_state" = "connected (externally)" ]
}

eth_is_connected() {
    eth_dev="$1"
    eth_state=$(nmcli -t -f DEVICE,STATE device | grep "^$eth_dev:" | cut -d: -f2)
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

check_and_switch() {
    eth_dev=$(get_eth_dev)
    wifi_dev=$(get_wifi_dev)

    if [ -z "$eth_dev" ] || [ -z "$wifi_dev" ]; then
        return
    fi

    last_state=$(read_last_state)

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
        wifi_enabled=$(nmcli radio wifi)
        if [ "$wifi_enabled" = "disabled" ]; then
            nmcli radio wifi on
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
        wifi_enabled=$(nmcli radio wifi)
        if [ "$wifi_enabled" = "enabled" ]; then
            log "Ethernet connected ($eth_dev). Disabling Wi-Fi..."
            nmcli radio wifi off
        fi
    else
        wifi_enabled=$(nmcli radio wifi)
        if [ "$wifi_enabled" = "disabled" ]; then
            log "Ethernet disconnected ($eth_dev). Enabling Wi-Fi..."
            nmcli radio wifi on
        fi
    fi
}

# Initial check
check_and_switch

# Monitor events
log "Starting event monitor..."
nmcli monitor | while read -r line; do
    if echo "$line" | grep -qE "(connected|disconnected|connectivity)"; then
        check_and_switch
    fi
done
