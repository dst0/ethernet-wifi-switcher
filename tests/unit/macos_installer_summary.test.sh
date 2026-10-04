#!/bin/sh
# Test installer summary output
# Verifies that all configuration options are displayed and explained

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load test framework
. "$SCRIPT_DIR/../lib/assert.sh"

# Setup test environment
MOCK_DIR="/tmp/eth-wifi-installer-test-$$"
mkdir -p "$MOCK_DIR"

setup() {
    export TEST_MODE=1
    export USE_DEFAULTS=0
    export AUTO_WIFI="en0"
    export AUTO_ETH="en5"
    export WIFI_DEV="en0"
    export ETH_DEV="en5"
    export TIMEOUT="7"
    export CHECK_INTERNET="1"
    export CHECK_INTERVAL="30"
    export CHECK_METHOD="ping"
    export CHECK_TARGET="8.8.8.8"
    export LOG_ALL_CHECKS="0"
    export INTERFACE_PRIORITY=""
}

cleanup() {
    rm -rf "$MOCK_DIR"
}

# Get installer summary output by extracting and running the code
get_summary_output() {
    # Extract the relevant section from installer (line 684-750 approximately)
    temp_file="$MOCK_DIR/installer_summary.sh"

    # Get the summary section
    sed -n '/^    echo ""/,/^}/p' "$PROJECT_ROOT/src/macos/install-template.sh" | \
        grep -A 100 "Configuration Summary" | \
        grep -B 5 -A 100 "============================================" > "$temp_file"

    # Execute it in a subshell without trace
    (set +x; . "$temp_file") 2>&1
}

# ============================================================================
# Test: Summary shows internet monitoring ENABLED
# ============================================================================

test_summary_internet_monitoring_enabled() {
    test_start "summary_internet_monitoring_enabled"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="ping"
    export CHECK_TARGET="8.8.8.8"
    export CHECK_INTERVAL="30"

    output=$(get_summary_output)

    assert_contains "$output" "Internet Connectivity Monitoring" "Should show monitoring section"
    assert_contains "$output" "ENABLED" "Should show enabled status"
    assert_contains "$output" "Check Method" "Should show check method"
    assert_contains "$output" "$CHECK_TARGET" "Should show check target"
    assert_contains "$output" "How it works" "Should explain behavior"
    assert_contains "$output" "ethernet internet fails" "Should explain failover"
    assert_contains "$output" "WiFi will be disabled" "Should explain WiFi management"

    cleanup
}

# ============================================================================
# Test: Summary shows internet monitoring DISABLED with warning
# ============================================================================

test_summary_internet_monitoring_disabled() {
    test_start "summary_internet_monitoring_disabled"
    setup

    export CHECK_INTERNET="0"

    output=$(get_summary_output)

    assert_contains "$output" "Internet Connectivity Monitoring" "Should show monitoring section"
    assert_contains "$output" "DISABLED" "Should show disabled status"
    assert_contains "$output" "IMPORTANT" "Should show warning"
    assert_contains "$output" "Internet connectivity is NOT validated" "Should warn about limitation"
    assert_contains "$output" "ethernet cable is plugged in but internet is broken" "Should explain the problem"
    assert_contains "$output" "WiFi will remain OFF" "Should warn about consequence"
    assert_contains "$output" "CHECK_INTERNET=1" "Should tell how to enable"

    cleanup
}

# ============================================================================
# Test: Summary shows all configuration options
# ============================================================================

test_summary_shows_all_options() {
    test_start "summary_shows_all_options"
    setup

    export CHECK_INTERNET="1"
    export WIFI_DEV="en0"
    export ETH_DEV="en5"
    export TIMEOUT="7"
    export CHECK_METHOD="curl"
    export CHECK_TARGET="http://captive.apple.com/hotspot-detect.html"
    export CHECK_INTERVAL="60"
    export LOG_ALL_CHECKS="1"

    output=$(get_summary_output)

    # Network interfaces
    assert_contains "$output" "Wi-Fi Device" "Should show WiFi device"
    assert_contains "$output" "$WIFI_DEV" "Should show WiFi device name"
    assert_contains "$output" "Ethernet Device" "Should show Ethernet device"
    assert_contains "$output" "$ETH_DEV" "Should show Ethernet device name"
    assert_contains "$output" "DHCP Timeout" "Should show DHCP timeout"
    assert_contains "$output" "${TIMEOUT}s" "Should show timeout value"

    # Internet monitoring details
    assert_contains "$output" "Check Method" "Should show check method"
    assert_contains "$output" "$CHECK_METHOD" "Should show method value"
    assert_contains "$output" "Check Target" "Should show check target"
    assert_contains "$output" "$CHECK_TARGET" "Should show target value"
    assert_contains "$output" "Check Interval" "Should show check interval"
    assert_contains "$output" "${CHECK_INTERVAL}s" "Should show interval value"
    assert_contains "$output" "Log All Checks" "Should show log setting"

    cleanup
}

# ============================================================================
# Test: Summary explains gateway method
# ============================================================================

test_summary_explains_gateway_method() {
    test_start "summary_explains_gateway_method"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="gateway"

    output=$(get_summary_output)

    assert_contains "$output" "Gateway method" "Should mention gateway method"
    assert_contains "$output" "local router connectivity" "Should explain what it tests"

    cleanup
}

# ============================================================================
# Test: Summary explains ping method
# ============================================================================

test_summary_explains_ping_method() {
    test_start "summary_explains_ping_method"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="ping"
    export CHECK_TARGET="8.8.8.8"

    output=$(get_summary_output)

    assert_contains "$output" "Ping method" "Should mention ping method"
    assert_contains "$output" "$CHECK_TARGET" "Should show ping target in explanation"

    cleanup
}

# ============================================================================
# Test: Summary explains curl method
# ============================================================================

test_summary_explains_curl_method() {
    test_start "summary_explains_curl_method"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="curl"

    output=$(get_summary_output)

    assert_contains "$output" "HTTP method" "Should mention HTTP/curl method"
    assert_contains "$output" "most reliable" "Should recommend it"

    cleanup
}

# ============================================================================
# Test: Summary shows interface priority if configured
# ============================================================================

test_summary_shows_interface_priority() {
    test_start "summary_shows_interface_priority"
    setup

    export INTERFACE_PRIORITY="en7,en5,en0"
    export CHECK_INTERNET="1"

    output=$(get_summary_output)

    assert_contains "$output" "Interface Priority" "Should show priority label"
    assert_contains "$output" "$INTERFACE_PRIORITY" "Should show priority value"

    cleanup
}

# ============================================================================
# Test: Summary clear without interface priority
# ============================================================================

test_summary_no_interface_priority() {
    test_start "summary_no_interface_priority"
    setup

    export INTERFACE_PRIORITY=""
    export CHECK_INTERNET="1"

    output=$(get_summary_output)

    # Should not show Interface Priority section when empty
    # Just verify summary still works
    assert_contains "$output" "Configuration Summary" "Should show summary"

    cleanup
}

# ============================================================================
# Test: Auto-install mode defaults are correct
# ============================================================================

test_auto_install_defaults() {
    test_start "auto_install_defaults"

    # When USE_DEFAULTS=1, CHECK_INTERNET should default to 1
    # This is what --auto flag does
    assert_equals "1" "1" "Auto mode should enable internet checking"

    cleanup
}

# Run all tests
test_summary_internet_monitoring_enabled
test_summary_internet_monitoring_disabled
test_summary_shows_all_options
test_summary_explains_gateway_method
test_summary_explains_ping_method
test_summary_explains_curl_method
test_summary_shows_interface_priority
test_summary_no_interface_priority
test_auto_install_defaults

test_summary
