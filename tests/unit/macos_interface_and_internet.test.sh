#!/bin/sh
# Real unit tests for macOS interface detection and environment variable handling
# Tests actual interface detection and config from src/macos/switcher.sh
#
# NOTE: Interface detection (ETH_DEV/WIFI_DEV) happens at install time via build script.
# The switcher uses pre-configured values. These tests verify the configuration works.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../lib/mock.sh"

# Setup test environment
setup() {
    MOCK_DIR="/tmp/macos-iface-env-test-$$"
    mkdir -p "$MOCK_DIR/bin" "$MOCK_DIR/state"
    export PATH="$MOCK_DIR/bin:$PATH"

    # Set default devices (as installer would configure)
    export WIFI_DEV="en0"
    export ETH_DEV="en5"
    export STATE_DIR="$MOCK_DIR/state"
    export STATE_FILE="$STATE_DIR/eth-wifi-state"
    export LAST_CHECK_STATE_FILE="$STATE_FILE.last_check"
    export TIMEOUT="2"
    export CHECK_INTERNET="1"
    export LOG_ALL_CHECKS="0"
    export INTERFACE_PRIORITY=""
    export CHECK_INTERVAL="30"
    export CHECK_METHOD="gateway"
    export CHECK_TARGET=""
    export ETH_CONNECT_TIMEOUT="5"
    export ETH_CONNECT_RETRIES="1"
    export ETH_RETRY_INTERVAL="1"

    export NETWORKSETUP="$MOCK_DIR/bin/networksetup"
    export DATE="date"
    export IPCONFIG="$MOCK_DIR/bin/ipconfig"
    export IFCONFIG="$MOCK_DIR/bin/ifconfig"

    rm -f "$STATE_FILE" "$LAST_CHECK_STATE_FILE" 2>/dev/null || true
}

source_switcher() {
    . "$PROJECT_ROOT/src/macos/switcher.sh"
}

cleanup() {
    rm -rf "$MOCK_DIR"
}

# ============================================================================
# Test: Configured devices are used
# ============================================================================

test_configured_eth_dev() {
    test_start "configured_eth_dev"
    setup
    export ETH_DEV="en5"

    source_switcher

    eth=$(get_eth_dev)
    assert_equals "en5" "$eth" "Should use configured ETH_DEV"
    cleanup
}

test_configured_wifi_dev() {
    test_start "configured_wifi_dev"
    setup
    export WIFI_DEV="en0"

    source_switcher

    wifi=$(get_wifi_dev)
    assert_equals "en0" "$wifi" "Should use configured WIFI_DEV"
    cleanup
}

test_custom_eth_dev() {
    test_start "custom_eth_dev"
    setup
    export ETH_DEV="en8"

    source_switcher

    eth=$(get_eth_dev)
    assert_equals "en8" "$eth" "Should use custom ETH_DEV=en8"
    cleanup
}

# ============================================================================
# Test: CHECK_METHOD environment variable
# ============================================================================

test_check_method_gateway() {
    test_start "check_method_gateway"
    setup
    export CHECK_METHOD="gateway"

    cat > "$MOCK_DIR/bin/netstat" << 'EOF'
#!/bin/sh
echo "default            192.168.1.1        UGSc           en5"
EOF
    chmod +x "$MOCK_DIR/bin/netstat"

    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    source_switcher

    if check_internet "en5" 1; then
        result="success"
    else
        result="fail"
    fi

    assert_equals "success" "$result" "CHECK_METHOD=gateway should work"
    cleanup
}

test_check_method_ping() {
    test_start "check_method_ping"
    setup
    export CHECK_METHOD="ping"
    export CHECK_TARGET="1.1.1.1"

    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    source_switcher

    if check_internet "en5" 1; then
        result="success"
    else
        result="fail"
    fi

    assert_equals "success" "$result" "CHECK_METHOD=ping should work"
    cleanup
}

test_check_method_curl() {
    test_start "check_method_curl"
    setup
    export CHECK_METHOD="curl"
    export CHECK_TARGET="http://example.com"

    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    source_switcher

    if check_internet "en5" 1; then
        result="success"
    else
        result="fail"
    fi

    assert_equals "success" "$result" "CHECK_METHOD=curl should work"
    cleanup
}

# ============================================================================
# Test: STATE_DIR environment variable
# ============================================================================

test_state_dir_custom_path() {
    test_start "state_dir_custom_path"
    setup
    CUSTOM_STATE_DIR="$MOCK_DIR/custom/state/path"
    mkdir -p "$CUSTOM_STATE_DIR"
    export STATE_DIR="$CUSTOM_STATE_DIR"
    export STATE_FILE="$STATE_DIR/eth-wifi-state"

    source_switcher

    write_state "TEST_STATE"

    assert_true "[ -d '$CUSTOM_STATE_DIR' ]" "Custom STATE_DIR should exist"
    assert_true "[ -f '$STATE_FILE' ]" "State file should be in custom dir"

    content=$(cat "$STATE_FILE")
    assert_equals "TEST_STATE" "$content" "State should be written to custom path"
    cleanup
}

# ============================================================================
# Test: CHECK_INTERNET environment variable
# ============================================================================

test_check_internet_setting() {
    test_start "check_internet_setting"
    setup
    export CHECK_INTERNET="1"

    cat > "$MOCK_DIR/bin/netstat" << 'EOF'
#!/bin/sh
echo "default            192.168.1.1        UGSc           en5"
EOF
    chmod +x "$MOCK_DIR/bin/netstat"

    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    source_switcher

    if check_internet "en5" 1; then
        result="success"
    else
        result="fail"
    fi

    assert_equals "success" "$result" "CHECK_INTERNET=1 should enable checks"
    cleanup
}

# ============================================================================
# Test: TIMEOUT environment variable affects behavior
# ============================================================================

test_timeout_setting() {
    test_start "timeout_setting"
    setup
    export TIMEOUT="5"

    source_switcher

    # Verify TIMEOUT is set correctly after sourcing
    assert_equals "5" "$TIMEOUT" "TIMEOUT should be set to 5"
    cleanup
}

# ============================================================================
# Test: Default values
# ============================================================================

test_default_values_applied() {
    test_start "default_values_applied"
    setup

    # Unset to test defaults
    unset ETH_DEV
    unset WIFI_DEV

    source_switcher

    # Script has defaults: ETH_DEV="${ETH_DEV:-en5}" and WIFI_DEV="${WIFI_DEV:-en0}"
    assert_equals "en5" "$ETH_DEV" "Default ETH_DEV should be en5"
    assert_equals "en0" "$WIFI_DEV" "Default WIFI_DEV should be en0"
    cleanup
}

# ============================================================================
# Run all tests
# ============================================================================

echo "============================================"
echo "macOS Interface and Environment Real Unit Tests"
echo "============================================"
echo "Testing ACTUAL interface config and env vars from src/macos/switcher.sh"
echo ""

test_configured_eth_dev
test_configured_wifi_dev
test_custom_eth_dev
test_check_method_gateway
test_check_method_ping
test_check_method_curl
test_state_dir_custom_path
test_check_internet_setting
test_timeout_setting
test_default_values_applied

test_summary
