#!/bin/sh
# NetworkManager (nmcli) backend

# Check if interface is ethernet
is_ethernet_iface() {
    iface="$1"
    iface_type=$(nmcli device 2>/dev/null | grep "^$iface " | awk '{print $2}' || true)
    [ "$iface_type" = "ethernet" ]
}

# Check if interface is wifi
is_wifi_iface() {
    iface="$1"
    iface_type=$(nmcli device 2>/dev/null | grep "^$iface " | awk '{print $2}' || true)
    [ "$iface_type" = "wifi" ]
}

# Get first ethernet interface
get_first_ethernet_iface() {
    nmcli device 2>/dev/null | grep -E "ethernet" | awk '{print $1}' | head -n 1 || true
}

# Get first wifi interface
get_first_wifi_iface() {
    nmcli device 2>/dev/null | grep -E "wifi" | awk '{print $1}' | head -n 1 || true
}

# Get all ethernet devices
get_all_eth_devs() {
    nmcli device 2>/dev/null | grep -E "ethernet" | awk '{print $1}' || true
}

# Get all wifi devices
get_all_wifi_devs() {
    nmcli device 2>/dev/null | grep -E "wifi" | awk '{print $1}' || true
}

# Get all network devices
get_all_network_devs() {
    nmcli device 2>/dev/null | grep -E "(ethernet|wifi)" | awk '{print $1}' || true
}

# Get interface state (connected, disconnected, etc)
get_iface_state() {
    iface="$1"
    nmcli -t -f DEVICE,STATE device 2>/dev/null | grep "^$iface:" | cut -d: -f2 || echo "unknown"
}

# Get interface IP address
get_iface_ip() {
    iface="$1"
    nmcli -t -f IP4.ADDRESS device show "$iface" 2>/dev/null | cut -d: -f2 | cut -d/ -f1 | head -n 1 || true
}

# Check if wifi radio is enabled
is_wifi_enabled() {
    status=$(nmcli radio wifi 2>/dev/null || echo "unknown")
    [ "$status" = "enabled" ]
}

# Enable wifi radio
enable_wifi() {
    nmcli radio wifi on 2>/dev/null || return 1
}

# Disable wifi radio
disable_wifi() {
    nmcli radio wifi off 2>/dev/null || return 1
}

# Monitor network events
monitor_events() {
    nmcli monitor 2>/dev/null
}
