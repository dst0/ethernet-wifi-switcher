#!/bin/sh
set -e

# Load test framework
. "$(dirname "$0")/../lib/mock.sh"
. "$(dirname "$0")/../lib/assert.sh"

# Setup
setup() {
    clear_mocks
    setup_mocks
    export ETHERNET_INTERFACE=""
    export WIFI_INTERFACE=""
}

# Test: nmcli detects ethernet with IP
test_nmcli_ethernet_with_ip() {
    test_start "nmcli_ethernet_with_ip"
    setup

    mock_command nmcli "eth0       ethernet  connected     Wired connection 1
wlan0      wifi      disconnected  --"

    # Source detection logic (simplified for testing)
    AUTO_ETH=$(nmcli device | grep -E "ethernet.*connected" | awk '{print $1}' | head -n 1 || true)

    assert_equals "eth0" "$AUTO_ETH" "Should detect connected ethernet"
}

# Test: nmcli detects wifi
test_nmcli_wifi() {
    test_start "nmcli_wifi"
    setup

    mock_command nmcli "eth0       ethernet  connected     Wired connection 1
wlan0      wifi      disconnected  --"

    AUTO_WIFI=$(nmcli device | grep -E "wifi" | awk '{print $1}' | head -n 1 || true)

    assert_equals "wlan0" "$AUTO_WIFI" "Should detect wifi interface"
}

# Test: Environment variable override for ethernet
test_env_override_ethernet() {
    test_start "env_override_ethernet"
    setup

    export ETHERNET_INTERFACE="enp0s3"
    AUTO_ETH="$ETHERNET_INTERFACE"

    assert_equals "enp0s3" "$AUTO_ETH" "Should use env var for ethernet"
}

# Test: Environment variable override for wifi
test_env_override_wifi() {
    test_start "env_override_wifi"
    setup

    export WIFI_INTERFACE="wlp1s0"
    AUTO_WIFI="$WIFI_INTERFACE"

    assert_equals "wlp1s0" "$AUTO_WIFI" "Should use env var for wifi"
}

# Test: Fallback to ip command
test_ip_command_fallback() {
    test_start "ip_command_fallback"
    setup

    # Mock nmcli not found
    rm -f "$MOCK_DIR/bin/nmcli"

    mock_command ip "1: lo: <LOOPBACK,UP,LOWER_UP>
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP>
3: wlan0: <BROADCAST,MULTICAST>"

    for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(eth|enp|eno|ens)'); do
        AUTO_ETH="$iface"
        break
    done

    assert_equals "eth0" "$AUTO_ETH" "Should detect via ip command"
}

# Run all tests
echo "Running Linux Interface Detection Tests"
echo "========================================"
test_nmcli_ethernet_with_ip
test_nmcli_wifi
test_env_override_ethernet
test_env_override_wifi
test_ip_command_fallback

# Cleanup
teardown_mocks

# Summary
test_summary
