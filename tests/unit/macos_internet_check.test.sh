#!/bin/sh
# Real unit tests for macOS internet check functionality
# Tests actual check_internet function from src/macos/switcher.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../lib/mock.sh"

# Setup test environment
setup() {
    MOCK_DIR="/tmp/macos-internet-check-test-$$"
    mkdir -p "$MOCK_DIR/bin" "$MOCK_DIR/state"
    export PATH="$MOCK_DIR/bin:$PATH"

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
# Test: Gateway check method - active interface
# ============================================================================

test_check_internet_gateway_active_success() {
    test_start "check_internet_gateway_active_success"
    setup
    export CHECK_METHOD="gateway"

    cat > "$MOCK_DIR/bin/netstat" << 'EOF'
#!/bin/sh
echo "Routing tables"
echo "Internet:"
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
        result="failed"
    fi

    assert_equals "success" "$result" "Gateway check on active interface should succeed"
    cleanup
}

test_check_internet_gateway_active_no_gateway() {
    test_start "check_internet_gateway_active_no_gateway"
    setup
    export CHECK_METHOD="gateway"

    cat > "$MOCK_DIR/bin/netstat" << 'EOF'
#!/bin/sh
echo "Routing tables"
echo "Internet:"
echo "default            192.168.2.1        UGSc           en0"
EOF
    chmod +x "$MOCK_DIR/bin/netstat"

    source_switcher

    if check_internet "en5" 1; then
        result="success"
    else
        result="failed"
    fi

    assert_equals "failed" "$result" "Gateway check should fail when no gateway for interface"
    cleanup
}

test_check_internet_gateway_active_ping_fails() {
    test_start "check_internet_gateway_active_ping_fails"
    setup
    export CHECK_METHOD="gateway"

    cat > "$MOCK_DIR/bin/netstat" << 'EOF'
#!/bin/sh
echo "default            192.168.1.1        UGSc           en5"
EOF
    chmod +x "$MOCK_DIR/bin/netstat"

    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
exit 1
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    source_switcher

    if check_internet "en5" 1; then
        result="success"
    else
        result="failed"
    fi

    assert_equals "failed" "$result" "Gateway check should fail when ping fails"
    cleanup
}

# ============================================================================
# Test: Ping check method
# ============================================================================

test_check_internet_ping_active_success() {
    test_start "check_internet_ping_active_success"
    setup
    export CHECK_METHOD="ping"
    export CHECK_TARGET="8.8.8.8"

    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    source_switcher

    if check_internet "en5" 1; then
        result="success"
    else
        result="failed"
    fi

    assert_equals "success" "$result" "Ping check should succeed"
    cleanup
}

test_check_internet_ping_no_target() {
    test_start "check_internet_ping_no_target"
    setup
    export CHECK_METHOD="ping"
    export CHECK_TARGET=""

    source_switcher

    if check_internet "en5" 1; then
        result="success"
    else
        result="failed"
    fi

    assert_equals "failed" "$result" "Ping check should fail without CHECK_TARGET"
    cleanup
}

# ============================================================================
# Test: Curl check method
# ============================================================================

test_check_internet_curl_active_success() {
    test_start "check_internet_curl_active_success"
    setup
    export CHECK_METHOD="curl"
    export CHECK_TARGET="http://captive.apple.com/hotspot-detect.html"

    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    source_switcher

    if check_internet "en5" 1; then
        result="success"
    else
        result="failed"
    fi

    assert_equals "success" "$result" "Curl check should succeed"
    cleanup
}

test_check_internet_curl_uses_default_target() {
    test_start "check_internet_curl_uses_default_target"
    setup
    export CHECK_METHOD="curl"
    export CHECK_TARGET=""

    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    source_switcher

    if check_internet "en5" 1; then
        result="success"
    else
        result="failed"
    fi

    assert_equals "success" "$result" "Curl check should use default target"
    cleanup
}

# ============================================================================
# Test: Inactive interface (always uses curl on macOS)
# ============================================================================

test_check_internet_inactive_uses_curl() {
    test_start "check_internet_inactive_uses_curl"
    setup
    export CHECK_METHOD="gateway"
    export CHECK_TARGET="http://captive.apple.com/hotspot-detect.html"

    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    source_switcher

    if check_internet "en6" 0; then
        result="success"
    else
        result="failed"
    fi

    assert_equals "success" "$result" "Inactive interface check should use curl"
    cleanup
}

test_check_internet_inactive_curl_fails() {
    test_start "check_internet_inactive_curl_fails"
    setup
    export CHECK_METHOD="gateway"
    export CHECK_TARGET="http://captive.apple.com/hotspot-detect.html"

    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 1
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    source_switcher

    if check_internet "en6" 0; then
        result="success"
    else
        result="failed"
    fi

    assert_equals "failed" "$result" "Inactive interface check should fail when curl fails"
    cleanup
}

# ============================================================================
# Run all tests
# ============================================================================

echo "============================================"
echo "macOS Internet Check Real Unit Tests"
echo "============================================"
echo "Testing ACTUAL check_internet from src/macos/switcher.sh"
echo ""

test_check_internet_gateway_active_success
test_check_internet_gateway_active_no_gateway
test_check_internet_gateway_active_ping_fails
test_check_internet_ping_active_success
test_check_internet_ping_no_target
test_check_internet_curl_active_success
test_check_internet_curl_uses_default_target
test_check_internet_inactive_uses_curl
test_check_internet_inactive_curl_fails

test_summary
