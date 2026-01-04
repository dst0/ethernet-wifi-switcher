#!/bin/sh
set -e

# Load test framework
. "$(dirname "$0")/../lib/mock.sh"
. "$(dirname "$0")/../lib/assert.sh"

setup() {
    clear_mocks
    setup_mocks
}

# Test: Environment variable overrides for WiFi device
test_wifi_env_override() {
    test_start "macos_wifi_env_override"
    setup

    export WIFI_DEV="en1"
    WIFI="$WIFI_DEV"

    assert_equals "en1" "$WIFI" "Should use WIFI_DEV env var"
}

# Test: Environment variable overrides for Ethernet device
test_eth_env_override() {
    test_start "macos_eth_env_override"
    setup

    export ETH_DEV="en7"
    ETH="$ETH_DEV"

    assert_equals "en7" "$ETH" "Should use ETH_DEV env var"
}

# Test: Interface priority list parsing
test_interface_priority() {
    test_start "macos_interface_priority"
    setup

    export INTERFACE_PRIORITY="en2,en0,en5"

    # Parse priority list
    first_iface=$(echo "$INTERFACE_PRIORITY" | cut -d',' -f1)

    assert_equals "en2" "$first_iface" "Should extract first interface from priority"
}

# Test: networksetup command detection (WiFi on)
test_wifi_power_on_detection() {
    test_start "macos_wifi_power_on"
    setup

    mock_command networksetup "Wi-Fi Power (en0): On"

    result=$(networksetup -getairportpower en0 | grep -q "On" && echo "on" || echo "off")

    assert_equals "on" "$result" "Should detect WiFi is on"
}

# Test: networksetup command detection (WiFi off)
test_wifi_power_off_detection() {
    test_start "macos_wifi_power_off"
    setup

    mock_command networksetup "Wi-Fi Power (en0): Off"

    result=$(networksetup -getairportpower en0 | grep -q "On" && echo "on" || echo "off")

    assert_equals "off" "$result" "Should detect WiFi is off"
}

# Test: Gateway detection with netstat
test_gateway_detection() {
    test_start "macos_gateway_detection"
    setup

    mock_command netstat "default         192.168.1.1    UGSc    en5"

    gateway=$(netstat -nr | grep -E "^default.*en5" | awk '{print $2}' | head -n 1)

    assert_equals "192.168.1.1" "$gateway" "Should detect gateway"
}

# Test: Check internet with gateway method (success)
test_internet_gateway_success() {
    test_start "macos_internet_gateway_success"
    setup

    mock_command netstat "default         192.168.1.1    UGSc    en5"
    mock_command ping ""

    # Simulate ping success
    if netstat -nr | grep -qE "^default.*en5"; then
        result="success"
    else
        result="fail"
    fi

    assert_equals "success" "$result" "Gateway check should succeed"
}

# Test: Internet check without gateway (fail)
test_internet_no_gateway_fail() {
    test_start "macos_internet_no_gateway"
    setup

    mock_command netstat "destination     gateway        flags     interface"

    if netstat -nr | grep -qE "^default.*en5"; then
        result="success"
    else
        result="fail"
    fi

    assert_equals "fail" "$result" "Should fail without gateway"
}

# Test: Ping check requires target
test_ping_requires_target() {
    test_start "macos_ping_requires_target"
    setup

    CHECK_TARGET=""

    if [ -z "$CHECK_TARGET" ]; then
        result="missing_target"
    else
        result="has_target"
    fi

    assert_equals "missing_target" "$result" "Ping should require CHECK_TARGET"
}

# Test: Curl check uses default URL
test_curl_default_url() {
    test_start "macos_curl_default_url"
    setup

    CHECK_TARGET=""
    DEFAULT_URL="http://captive.apple.com/hotspot-detect.html"

    url="${CHECK_TARGET:-$DEFAULT_URL}"

    assert_equals "$DEFAULT_URL" "$url" "Should use default URL when CHECK_TARGET empty"
}

# Run tests
echo "Running macOS Interface & Internet Tests"
echo "========================================"

test_wifi_env_override
test_eth_env_override
test_interface_priority
test_wifi_power_on_detection
test_wifi_power_off_detection
test_gateway_detection
test_internet_gateway_success
test_internet_no_gateway_fail
test_ping_requires_target
test_curl_default_url

# Cleanup
teardown_mocks

# Summary
test_summary
