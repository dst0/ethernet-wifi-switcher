#!/bin/sh
# Real unit tests for Linux internet check functionality
# Tests actual check_internet function from src/linux/switcher.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../lib/mock.sh"

# Setup test environment
setup() {
    MOCK_DIR="/tmp/linux-internet-check-test-$$"
    mkdir -p "$MOCK_DIR/bin" "$MOCK_DIR/state"
    export PATH="$MOCK_DIR/bin:$PATH"

    export STATE_FILE="$MOCK_DIR/state/eth-wifi-state"
    export LAST_CHECK_STATE_FILE="$STATE_FILE.last_check"
    export TIMEOUT="2"
    export CHECK_INTERNET="1"
    export LOG_ALL_CHECKS="0"
    export INTERFACE_PRIORITY=""
    export CHECK_INTERVAL="30"

    # Create nmcli mock for backend loading
    cat > "$MOCK_DIR/bin/nmcli" << 'EOF'
#!/bin/sh
echo "eth0       ethernet  connected     Wired connection 1"
EOF
    chmod +x "$MOCK_DIR/bin/nmcli"

    rm -f "$STATE_FILE" "$LAST_CHECK_STATE_FILE" 2>/dev/null || true
}

source_switcher() {
    . "$PROJECT_ROOT/src/linux/lib/network-nmcli.sh"
    . "$PROJECT_ROOT/src/linux/switcher.sh"
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

    cat > "$MOCK_DIR/bin/ip" << 'EOF'
#!/bin/sh
if [ "$1" = "route" ] && [ "$2" = "show" ]; then
    echo "default via 192.168.1.1 dev eth0"
fi
EOF
    chmod +x "$MOCK_DIR/bin/ip"

    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    source_switcher

    if check_internet "eth0"; then
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

    cat > "$MOCK_DIR/bin/ip" << 'EOF'
#!/bin/sh
if [ "$1" = "route" ] && [ "$2" = "show" ]; then
    echo "default via 192.168.2.1 dev wlan0"
fi
EOF
    chmod +x "$MOCK_DIR/bin/ip"

    source_switcher

    if check_internet "eth0"; then
        result="success"
    else
        result="failed"
    fi

    assert_equals "failed" "$result" "Gateway check should fail when no gateway for interface"
    cleanup
}

test_check_internet_gateway_ping_fails() {
    test_start "check_internet_gateway_ping_fails"
    setup
    export CHECK_METHOD="gateway"

    cat > "$MOCK_DIR/bin/ip" << 'EOF'
#!/bin/sh
if [ "$1" = "route" ] && [ "$2" = "show" ]; then
    echo "default via 192.168.1.1 dev eth0"
fi
EOF
    chmod +x "$MOCK_DIR/bin/ip"

    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
exit 1
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    source_switcher

    if check_internet "eth0"; then
        result="success"
    else
        result="failed"
    fi

    assert_equals "failed" "$result" "Gateway check should fail when ping to gateway fails"
    cleanup
}

# ============================================================================
# Test: Ping check method
# ============================================================================

test_check_internet_ping_success() {
    test_start "check_internet_ping_success"
    setup
    export CHECK_METHOD="ping"
    export CHECK_TARGET="8.8.8.8"

    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    source_switcher

    if check_internet "eth0"; then
        result="success"
    else
        result="failed"
    fi

    assert_equals "success" "$result" "Ping check should succeed when target is reachable"
    cleanup
}

test_check_internet_ping_no_target() {
    test_start "check_internet_ping_no_target"
    setup
    export CHECK_METHOD="ping"
    export CHECK_TARGET=""

    source_switcher

    if check_internet "eth0"; then
        result="success"
    else
        result="failed"
    fi

    assert_equals "failed" "$result" "Ping check should fail without CHECK_TARGET"
    cleanup
}

test_check_internet_ping_target_unreachable() {
    test_start "check_internet_ping_target_unreachable"
    setup
    export CHECK_METHOD="ping"
    export CHECK_TARGET="8.8.8.8"

    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
exit 1
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    source_switcher

    if check_internet "eth0"; then
        result="success"
    else
        result="failed"
    fi

    assert_equals "failed" "$result" "Ping check should fail when target is unreachable"
    cleanup
}

# ============================================================================
# Test: Curl check method
# ============================================================================

test_check_internet_curl_success() {
    test_start "check_internet_curl_success"
    setup
    export CHECK_METHOD="curl"
    export CHECK_TARGET="http://captive.apple.com/hotspot-detect.html"

    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    source_switcher

    if check_internet "eth0"; then
        result="success"
    else
        result="failed"
    fi

    assert_equals "success" "$result" "Curl check should succeed when HTTP request succeeds"
    cleanup
}

test_check_internet_curl_default_target() {
    test_start "check_internet_curl_default_target"
    setup
    export CHECK_METHOD="curl"
    export CHECK_TARGET=""

    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
# Verify default captive portal URL is used
if echo "$*" | grep -q "captive.apple.com"; then
    exit 0
else
    exit 1
fi
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    source_switcher

    if check_internet "eth0"; then
        result="success"
    else
        result="failed"
    fi

    assert_equals "success" "$result" "Curl check should use default captive portal URL"
    cleanup
}

test_check_internet_curl_request_fails() {
    test_start "check_internet_curl_request_fails"
    setup
    export CHECK_METHOD="curl"
    export CHECK_TARGET="http://example.com"

    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 1
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    source_switcher

    if check_internet "eth0"; then
        result="success"
    else
        result="failed"
    fi

    assert_equals "failed" "$result" "Curl check should fail when HTTP request fails"
    cleanup
}

# ============================================================================
# Test: Log all checks option
# ============================================================================

test_check_internet_log_all_checks() {
    test_start "check_internet_log_all_checks"
    setup
    export CHECK_METHOD="gateway"
    export LOG_ALL_CHECKS="1"

    cat > "$MOCK_DIR/bin/ip" << 'EOF'
#!/bin/sh
echo "default via 192.168.1.1 dev eth0"
EOF
    chmod +x "$MOCK_DIR/bin/ip"

    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    source_switcher

    output=$(check_internet "eth0" 2>&1)
    result=$?

    assert_equals "0" "$result" "Check should succeed"
    # Verify log output contains check information
    if echo "$output" | grep -q "Internet check"; then
        log_result="found"
    else
        log_result="not_found"
    fi
    assert_equals "found" "$log_result" "Should log check details when LOG_ALL_CHECKS=1"
    cleanup
}

# Run all tests
echo "Linux Internet Check Real Unit Tests"
echo "======================================"

test_check_internet_gateway_active_success
test_check_internet_gateway_active_no_gateway
test_check_internet_gateway_ping_fails
test_check_internet_ping_success
test_check_internet_ping_no_target
test_check_internet_ping_target_unreachable
test_check_internet_curl_success
test_check_internet_curl_default_target
test_check_internet_curl_request_fails
test_check_internet_log_all_checks

test_summary
