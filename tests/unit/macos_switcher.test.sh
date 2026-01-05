#!/bin/sh
# Real unit tests for macOS switcher - tests actual functions from source
# These tests source the real code and use mocked external commands

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load test frameworks
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../lib/mock.sh"

# Setup test environment
setup() {
    clear_mocks
    setup_mocks
    mock_state_dir

    # Set default test environment variables
    export WIFI_DEV="en0"
    export ETH_DEV="en5"
    export STATE_DIR="$MOCK_DIR/state"
    export STATE_FILE="$STATE_DIR/eth-wifi-state"
    export LAST_CHECK_STATE_FILE="$STATE_FILE.last_check"
    export TIMEOUT="2"
    export CHECK_INTERNET="0"
    export CHECK_METHOD="gateway"
    export CHECK_TARGET=""
    export LOG_ALL_CHECKS="0"
    export INTERFACE_PRIORITY=""
    export CHECK_INTERVAL="30"

    # Mock system binaries to use our controlled versions
    export NETWORKSETUP="$MOCK_DIR/bin/networksetup"
    export DATE="date"  # Use real date
    export IPCONFIG="$MOCK_DIR/bin/ipconfig"
    export IFCONFIG="$MOCK_DIR/bin/ifconfig"
}

# Source the macOS switcher functions (without executing main)
source_switcher() {
    . "$PROJECT_ROOT/src/macos/switcher.sh"
}

# ============================================================================
# Test: read_last_state function
# ============================================================================

test_read_last_state_file_exists() {
    test_start "read_last_state_file_exists"
    setup
    source_switcher

    # Create state file with known content
    echo "connected" > "$STATE_FILE"

    # Call REAL function from source
    result=$(read_last_state)

    assert_equals "connected" "$result" "Should read 'connected' from state file"
}

test_read_last_state_file_missing() {
    test_start "read_last_state_file_missing"
    setup
    source_switcher

    # Ensure state file doesn't exist
    rm -f "$STATE_FILE"

    # Call REAL function from source
    result=$(read_last_state)

    assert_equals "disconnected" "$result" "Should return 'disconnected' when file missing"
}

test_read_last_state_disconnected() {
    test_start "read_last_state_disconnected"
    setup
    source_switcher

    echo "disconnected" > "$STATE_FILE"

    result=$(read_last_state)

    assert_equals "disconnected" "$result" "Should read 'disconnected' from state file"
}

# ============================================================================
# Test: write_state function
# ============================================================================

test_write_state_connected() {
    test_start "write_state_connected"
    setup
    source_switcher

    # Call REAL function from source
    write_state "connected"

    result=$(cat "$STATE_FILE")
    assert_equals "connected" "$result" "Should write 'connected' to state file"
}

test_write_state_disconnected() {
    test_start "write_state_disconnected"
    setup
    source_switcher

    write_state "disconnected"

    result=$(cat "$STATE_FILE")
    assert_equals "disconnected" "$result" "Should write 'disconnected' to state file"
}

# ============================================================================
# Test: get_eth_dev function with INTERFACE_PRIORITY
# ============================================================================

test_get_eth_dev_default() {
    test_start "get_eth_dev_default"
    setup
    export INTERFACE_PRIORITY=""
    source_switcher

    # Call REAL function - should return default ETH_DEV
    result=$(get_eth_dev)

    assert_equals "en5" "$result" "Should return configured ETH_DEV when no priority set"
}

test_get_eth_dev_with_priority() {
    test_start "get_eth_dev_with_priority"
    setup
    export INTERFACE_PRIORITY="en6,en5,en0"

    # Mock ifconfig to show en6 as available ethernet
    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
case "$1" in
    en6)
        echo "en6: flags=8863<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST>"
        echo "        status: active"
        ;;
    en5)
        echo "en5: flags=8863<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST>"
        echo "        status: active"
        ;;
    en0)
        echo "en0: flags=8863<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST>"
        echo "        status: active"
        ;;
    *)
        exit 1
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    source_switcher
    result=$(get_eth_dev)

    assert_equals "en6" "$result" "Should return first available ethernet from priority list"
}

# ============================================================================
# Test: get_wifi_dev function
# ============================================================================

test_get_wifi_dev_default() {
    test_start "get_wifi_dev_default"
    setup
    export INTERFACE_PRIORITY=""
    source_switcher

    result=$(get_wifi_dev)

    assert_equals "en0" "$result" "Should return configured WIFI_DEV when no priority set"
}

test_get_wifi_dev_with_priority() {
    test_start "get_wifi_dev_with_priority"
    setup
    export INTERFACE_PRIORITY="en5,en0"
    export WIFI_DEV="en0"
    source_switcher

    result=$(get_wifi_dev)

    assert_equals "en0" "$result" "Should return wifi interface from priority list"
}

# ============================================================================
# Test: wifi_is_on function
# ============================================================================

test_wifi_is_on_true() {
    test_start "wifi_is_on_true"
    setup

    # Mock networksetup to return WiFi On
    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
if [ "$1" = "-getairportpower" ]; then
    echo "Wi-Fi Power (en0): On"
fi
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    source_switcher

    if wifi_is_on; then
        result="on"
    else
        result="off"
    fi

    assert_equals "on" "$result" "wifi_is_on should return true when WiFi is On"
}

test_wifi_is_on_false() {
    test_start "wifi_is_on_false"
    setup

    # Mock networksetup to return WiFi Off
    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
if [ "$1" = "-getairportpower" ]; then
    echo "Wi-Fi Power (en0): Off"
fi
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    source_switcher

    if wifi_is_on; then
        result="on"
    else
        result="off"
    fi

    assert_equals "off" "$result" "wifi_is_on should return false when WiFi is Off"
}

# ============================================================================
# Test: eth_has_link function
# ============================================================================

test_eth_has_link_active() {
    test_start "eth_has_link_active"
    setup

    # Mock ifconfig to show active status
    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
echo "en5: flags=8863<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST>"
echo "        ether 00:11:22:33:44:55"
echo "        inet 192.168.1.100 netmask 0xffffff00 broadcast 192.168.1.255"
echo "        status: active"
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    source_switcher

    if eth_has_link; then
        result="active"
    else
        result="inactive"
    fi

    assert_equals "active" "$result" "eth_has_link should return true when status is active"
}

test_eth_has_link_inactive() {
    test_start "eth_has_link_inactive"
    setup

    # Mock ifconfig to show inactive status
    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
echo "en5: flags=8863<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST>"
echo "        ether 00:11:22:33:44:55"
echo "        status: inactive"
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    source_switcher

    if eth_has_link; then
        result="active"
    else
        result="inactive"
    fi

    assert_equals "inactive" "$result" "eth_has_link should return false when status is inactive"
}

# ============================================================================
# Test: eth_is_up function
# ============================================================================

test_eth_is_up_with_ip() {
    test_start "eth_is_up_with_ip"
    setup

    # Mock ipconfig to return IP address
    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
if [ "$1" = "getifaddr" ]; then
    echo "192.168.1.100"
fi
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    source_switcher

    if eth_is_up; then
        result="up"
    else
        result="down"
    fi

    assert_equals "up" "$result" "eth_is_up should return true when interface has IP"
}

test_eth_is_up_no_ip() {
    test_start "eth_is_up_no_ip"
    setup

    # Mock ipconfig to return no IP address
    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
if [ "$1" = "getifaddr" ]; then
    # Return nothing (no IP assigned)
    exit 0
fi
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    source_switcher

    if eth_is_up; then
        result="up"
    else
        result="down"
    fi

    assert_equals "down" "$result" "eth_is_up should return false when interface has no IP"
}

# ============================================================================
# Test: check_internet function - gateway method
# ============================================================================

test_check_internet_gateway_success() {
    test_start "check_internet_gateway_success"
    setup
    export CHECK_METHOD="gateway"

    # Mock netstat to return a gateway
    cat > "$MOCK_DIR/bin/netstat" << 'EOF'
#!/bin/sh
echo "Routing tables"
echo "Internet:"
echo "Destination        Gateway            Flags        Refs      Use   Netif Expire"
echo "default            192.168.1.1        UGSc          123       45      en5"
EOF
    chmod +x "$MOCK_DIR/bin/netstat"

    # Mock ping to succeed
    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    # Add mocks to PATH
    export PATH="$MOCK_DIR/bin:$PATH"

    source_switcher

    if check_internet "en5" 1; then
        result="success"
    else
        result="failed"
    fi

    assert_equals "success" "$result" "check_internet with gateway method should succeed"
}

test_check_internet_gateway_no_gateway() {
    test_start "check_internet_gateway_no_gateway"
    setup
    export CHECK_METHOD="gateway"

    # Mock netstat to return no gateway
    cat > "$MOCK_DIR/bin/netstat" << 'EOF'
#!/bin/sh
echo "Routing tables"
echo "Internet:"
echo "Destination        Gateway            Flags        Refs      Use   Netif Expire"
EOF
    chmod +x "$MOCK_DIR/bin/netstat"

    export PATH="$MOCK_DIR/bin:$PATH"

    source_switcher

    if check_internet "en5" 1; then
        result="success"
    else
        result="failed"
    fi

    assert_equals "failed" "$result" "check_internet should fail when no gateway found"
}

# ============================================================================
# Test: check_internet function - curl method (for inactive interfaces)
# ============================================================================

test_check_internet_curl_inactive_interface() {
    test_start "check_internet_curl_inactive_interface"
    setup
    export CHECK_METHOD="gateway"  # Doesn't matter for inactive interfaces
    export CHECK_TARGET="http://captive.apple.com/hotspot-detect.html"

    # Mock curl to succeed
    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    export PATH="$MOCK_DIR/bin:$PATH"

    source_switcher

    # is_active_interface=0 means inactive, should use curl
    if check_internet "en6" 0; then
        result="success"
    else
        result="failed"
    fi

    assert_equals "success" "$result" "Inactive interface check should use curl and succeed"
}

test_check_internet_curl_inactive_fails() {
    test_start "check_internet_curl_inactive_fails"
    setup
    export CHECK_METHOD="gateway"
    export CHECK_TARGET="http://captive.apple.com/hotspot-detect.html"

    # Mock curl to fail
    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 1
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    export PATH="$MOCK_DIR/bin:$PATH"

    source_switcher

    if check_internet "en6" 0; then
        result="success"
    else
        result="failed"
    fi

    assert_equals "failed" "$result" "Inactive interface check should fail when curl fails"
}

# ============================================================================
# Test: check_internet function - ping method
# ============================================================================

test_check_internet_ping_success() {
    test_start "check_internet_ping_success"
    setup
    export CHECK_METHOD="ping"
    export CHECK_TARGET="8.8.8.8"

    # Mock ping to succeed
    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    export PATH="$MOCK_DIR/bin:$PATH"

    source_switcher

    if check_internet "en5" 1; then
        result="success"
    else
        result="failed"
    fi

    assert_equals "success" "$result" "check_internet with ping method should succeed"
}

test_check_internet_ping_no_target() {
    test_start "check_internet_ping_no_target"
    setup
    export CHECK_METHOD="ping"
    export CHECK_TARGET=""  # No target set

    source_switcher

    if check_internet "en5" 1; then
        result="success"
    else
        result="failed"
    fi

    assert_equals "failed" "$result" "check_internet with ping should fail without target"
}

# ============================================================================
# Run all tests
# ============================================================================

echo "============================================"
echo "macOS Switcher Real Unit Tests"
echo "============================================"
echo "Testing ACTUAL functions from src/macos/switcher.sh"
echo ""

# State management tests
test_read_last_state_file_exists
test_read_last_state_file_missing
test_read_last_state_disconnected
test_write_state_connected
test_write_state_disconnected

# Interface detection tests
test_get_eth_dev_default
test_get_eth_dev_with_priority
test_get_wifi_dev_default
test_get_wifi_dev_with_priority

# WiFi state tests
test_wifi_is_on_true
test_wifi_is_on_false

# Ethernet link tests
test_eth_has_link_active
test_eth_has_link_inactive
test_eth_is_up_with_ip
test_eth_is_up_no_ip

# Internet check tests
test_check_internet_gateway_success
test_check_internet_gateway_no_gateway
test_check_internet_curl_inactive_interface
test_check_internet_curl_inactive_fails
test_check_internet_ping_success
test_check_internet_ping_no_target

# Cleanup
teardown_mocks

# Print summary
test_summary
