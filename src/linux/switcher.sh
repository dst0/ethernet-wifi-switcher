#!/bin/sh
set -eu

# Event-driven Ethernet/Wi-Fi switcher for Linux (NetworkManager)
# Uses 'nmcli monitor' to wait for events, consuming 0% CPU while idle.

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

get_eth_dev() {
    nmcli device | grep -E "ethernet" | awk '{print $1}' | head -n 1
}

get_wifi_dev() {
    nmcli device | grep -E "wifi" | awk '{print $1}' | head -n 1
}

check_and_switch() {
    eth_dev=$(get_eth_dev)
    wifi_dev=$(get_wifi_dev)

    if [ -z "$eth_dev" ] || [ -z "$wifi_dev" ]; then
        return
    fi

    eth_state=$(nmcli -t -f DEVICE,STATE device | grep "^$eth_dev:" | cut -d: -f2)

    if [ "$eth_state" = "connected" ]; then
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
