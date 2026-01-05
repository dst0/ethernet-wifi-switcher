#!/bin/sh
# Real unit tests for macOS multi-interface detection functionality
# Tests actual get_eth_dev, get_wifi_dev with INTERFACE_PRIORITY from src/macos/switcher.sh
#
# NOTE: The switcher script expects ETH_DEV and WIFI_DEV to be configured at install time.
# These tests verify the INTERFACE_PRIORITY feature and basic device selection.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../lib/mock.sh"

# Setup test environment
setup() {
    MOCK_DIR="/tmp/macos-multi-iface-test-$$"
    mkdir -p "$MOCK_DIR/bin" "$MOCK_DIR/state"
    export PATH="$MOCK_DIR/bin:$PATH"

    # Set default devices (as installer would)
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
# Test: get_eth_dev returns configured device
# ============================================================================

test_get_eth_dev_returns_configured() {
    test_start "get_eth_dev_returns_configured"
    setup
    export ETH_DEV="en5"
    export INTERFACE_PRIORITY=""

    source_switcher

    eth_dev=$(get_eth_dev)
    assert_equals "en5" "$eth_dev" "Should return configured ETH_DEV"
    cleanup
}

test_get_eth_dev_different_device() {
    test_start "get_eth_dev_different_device"
    setup
    export ETH_DEV="en8"
    export INTERFACE_PRIORITY=""

    source_switcher

    eth_dev=$(get_eth_dev)
    assert_equals "en8" "$eth_dev" "Should return configured ETH_DEV=en8"
    cleanup
}

# ============================================================================
# Test: get_wifi_dev returns configured device
# ============================================================================

test_get_wifi_dev_returns_configured() {
    test_start "get_wifi_dev_returns_configured"
    setup
    export WIFI_DEV="en0"
    export INTERFACE_PRIORITY=""

    source_switcher

    wifi_dev=$(get_wifi_dev)
    assert_equals "en0" "$wifi_dev" "Should return configured WIFI_DEV"
    cleanup
}

test_get_wifi_dev_different_device() {
    test_start "get_wifi_dev_different_device"
    setup
    export WIFI_DEV="en1"
    export INTERFACE_PRIORITY=""

    source_switcher

    wifi_dev=$(get_wifi_dev)
    assert_equals "en1" "$wifi_dev" "Should return configured WIFI_DEV=en1"
    cleanup
}

# ============================================================================
# Test: INTERFACE_PRIORITY selects first available ethernet
# ============================================================================

test_interface_priority_selects_first_available() {
    test_start "interface_priority_selects_first_available"
    setup
    export INTERFACE_PRIORITY="en7,en5"
    export ETH_DEV="en5"

    # Mock ifconfig to show en7 as available
    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
case "$1" in
    en7)
        echo "en7: flags=8863<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST>"
        echo "        status: active"
        ;;
    en5)
        echo "en5: flags=8863<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST>"
        echo "        status: active"
        ;;
    *)
        exit 1
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    source_switcher

    eth_dev=$(get_eth_dev)
    assert_equals "en7" "$eth_dev" "INTERFACE_PRIORITY should select en7 first"
    cleanup
}

test_interface_priority_skips_unavailable() {
    test_start "interface_priority_skips_unavailable"
    setup
    export INTERFACE_PRIORITY="en9,en7,en5"
    export ETH_DEV="en5"

    # Mock ifconfig: en9 doesn't exist, en7 exists
    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
case "$1" in
    en7)
        echo "en7: flags=8863<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST>"
        echo "        status: active"
        ;;
    en5)
        echo "en5: flags=8863<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST>"
        echo "        status: active"
        ;;
    *)
        exit 1
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    source_switcher

    eth_dev=$(get_eth_dev)
    assert_equals "en7" "$eth_dev" "Should skip unavailable en9 and select en7"
    cleanup
}

test_interface_priority_skips_wifi_device() {
    test_start "interface_priority_skips_wifi_device"
    setup
    export INTERFACE_PRIORITY="en0,en5"
    export WIFI_DEV="en0"
    export ETH_DEV="en5"

    # Mock ifconfig: both exist
    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
case "$1" in
    en0)
        echo "en0: flags=8863<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST>"
        echo "        status: active"
        ;;
    en5)
        echo "en5: flags=8863<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST>"
        echo "        status: active"
        ;;
    *)
        exit 1
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    source_switcher

    eth_dev=$(get_eth_dev)
    # Should skip en0 (WIFI_DEV) and return en5
    assert_equals "en5" "$eth_dev" "Should skip wifi device in priority list"
    cleanup
}

# ============================================================================
# Test: INTERFACE_PRIORITY for wifi selection
# ============================================================================

test_interface_priority_wifi_selection() {
    test_start "interface_priority_wifi_selection"
    setup
    export INTERFACE_PRIORITY="en0,en1"
    export WIFI_DEV="en1"

    source_switcher

    wifi_dev=$(get_wifi_dev)
    # When INTERFACE_PRIORITY contains WIFI_DEV, it should be returned
    assert_equals "en1" "$wifi_dev" "Should return WIFI_DEV from priority list"
    cleanup
}

# ============================================================================
# Test: Default fallback values
# ============================================================================

test_default_eth_dev_fallback() {
    test_start "default_eth_dev_fallback"
    setup
    unset ETH_DEV
    export INTERFACE_PRIORITY=""

    source_switcher

    # Script has default fallback: ETH_DEV="${ETH_DEV:-en5}"
    eth_dev=$(get_eth_dev)
    assert_equals "en5" "$eth_dev" "Should fallback to default en5 when ETH_DEV unset"
    cleanup
}

test_default_wifi_dev_fallback() {
    test_start "default_wifi_dev_fallback"
    setup
    unset WIFI_DEV
    export INTERFACE_PRIORITY=""

    source_switcher

    # Script has default fallback: WIFI_DEV="${WIFI_DEV:-en0}"
    wifi_dev=$(get_wifi_dev)
    assert_equals "en0" "$wifi_dev" "Should fallback to default en0 when WIFI_DEV unset"
    cleanup
}

# ============================================================================
# Run all tests
# ============================================================================

echo "============================================"
echo "macOS Multi-Interface Real Unit Tests"
echo "============================================"
echo "Testing ACTUAL interface selection from src/macos/switcher.sh"
echo ""

test_get_eth_dev_returns_configured
test_get_eth_dev_different_device
test_get_wifi_dev_returns_configured
test_get_wifi_dev_different_device
test_interface_priority_selects_first_available
test_interface_priority_skips_unavailable
test_interface_priority_skips_wifi_device
test_interface_priority_wifi_selection
test_default_eth_dev_fallback
test_default_wifi_dev_fallback

test_summary
