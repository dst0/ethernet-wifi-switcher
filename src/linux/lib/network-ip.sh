#!/bin/sh
# Fallback backend using ip command and rfkill

SYS_CLASS_NET="${SYS_CLASS_NET:-/sys/class/net}"

# Check if interface is ethernet
is_ethernet_iface() {
    iface="$1"
    ip link show "$iface" >/dev/null 2>&1 && [ ! -d "$SYS_CLASS_NET/$iface/wireless" ]
}

# Check if interface is wifi
is_wifi_iface() {
    iface="$1"
    [ -d "$SYS_CLASS_NET/$iface/wireless" ]
}

# Get first ethernet interface
get_first_ethernet_iface() {
    for iface in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -vE '^(lo|wlan|wlp)'); do
        if [ ! -d "$SYS_CLASS_NET/$iface/wireless" ]; then
            echo "$iface"
            return 0
        fi
    done
}

# Get first wifi interface
get_first_wifi_iface() {
    for iface in "$SYS_CLASS_NET"/*; do
        if [ -d "$iface/wireless" ]; then
            basename "$iface"
            return 0
        fi
    done
}

# Get all ethernet devices
get_all_eth_devs() {
    for iface in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}'); do
        if [ ! -d "$SYS_CLASS_NET/$iface/wireless" ] && [ "$iface" != "lo" ]; then
            echo "$iface"
        fi
    done
}

# Get all wifi devices
get_all_wifi_devs() {
    for iface in "$SYS_CLASS_NET"/*; do
        if [ -d "$iface/wireless" ]; then
            basename "$iface"
        fi
    done
}

# Get all network devices
get_all_network_devs() {
    get_all_eth_devs
    get_all_wifi_devs
}

# Get interface state (up/down based on carrier and operstate)
get_iface_state() {
    iface="$1"
    if [ ! -d "$SYS_CLASS_NET/$iface" ]; then
        echo "unavailable"
        return
    fi

    operstate=$(cat "$SYS_CLASS_NET/$iface/operstate" 2>/dev/null || echo "unknown")
    carrier=$(cat "$SYS_CLASS_NET/$iface/carrier" 2>/dev/null || echo "0")

    if [ "$operstate" = "up" ] && [ "$carrier" = "1" ]; then
        echo "connected"
    elif [ "$operstate" = "up" ]; then
        echo "disconnected"
    else
        echo "unavailable"
    fi
}

# Get interface IP address
get_iface_ip() {
    iface="$1"
    ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1 || true
}

# Check if wifi radio is enabled (using rfkill if available)
is_wifi_enabled() {
    if command -v rfkill >/dev/null 2>&1; then
        # Check if any wlan device is not blocked
        ! rfkill list wlan 2>/dev/null | grep -q "Soft blocked: yes"
    else
        # Assume enabled if we can't check
        return 0
    fi
}

# Enable wifi radio
enable_wifi() {
    if command -v rfkill >/dev/null 2>&1; then
        rfkill unblock wlan 2>/dev/null || return 1
    else
        # Can't enable without rfkill
        log "Warning: rfkill not available, cannot enable wifi radio"
        return 1
    fi
}

# Disable wifi radio
disable_wifi() {
    if command -v rfkill >/dev/null 2>&1; then
        rfkill block wlan 2>/dev/null || return 1
    else
        # Can't disable without rfkill
        log "Warning: rfkill not available, cannot disable wifi radio"
        return 1
    fi
}

# Monitor network events (polling-based since we don't have nmcli monitor)
monitor_events() {
    log "Using polling mode (nmcli not available)"
    while true; do
        sleep "${CHECK_INTERVAL:-30}"
        echo "Connectivity:changed"
    done
}
