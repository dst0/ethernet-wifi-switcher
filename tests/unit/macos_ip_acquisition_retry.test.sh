#!/bin/sh
# Real unit tests for macOS IP acquisition retry functionality
# Tests actual eth_is_up_with_retry logic from src/macos/switcher.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../lib/mock.sh"

# Setup test environment
setup() {
    MOCK_DIR="/tmp/macos-ip-retry-test-$$"
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
    export CHECK_METHOD="gateway"
    export CHECK_TARGET=""

    # IP acquisition retry settings
    export ETH_CONNECT_TIMEOUT="5"
    export ETH_CONNECT_RETRIES="3"
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
# Test: eth_is_up basic behavior
# ============================================================================

test_eth_is_up_with_ip() {
    test_start "eth_is_up_with_ip"
    setup

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
echo "192.168.1.100"
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    source_switcher

    if eth_is_up; then
        result="up"
    else
        result="down"
    fi

    assert_equals "up" "$result" "eth_is_up should return true with valid IP"
    cleanup
}

test_eth_is_up_without_ip() {
    test_start "eth_is_up_without_ip"
    setup

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
echo ""
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    source_switcher

    if eth_is_up; then
        result="up"
    else
        result="down"
    fi

    assert_equals "down" "$result" "eth_is_up should return false without IP"
    cleanup
}

test_eth_is_up_with_link_local() {
    test_start "eth_is_up_with_link_local"
    setup

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
echo "169.254.100.50"
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    source_switcher

    if eth_is_up; then
        result="up"
    else
        result="down"
    fi

    # Link-local IPs should be considered "up" for the purpose of this check
    # but they indicate no DHCP - the real check is in internet connectivity
    assert_equals "up" "$result" "eth_is_up should return true with link-local IP (DHCP may fail later)"
    cleanup
}

# ============================================================================
# Test: eth_is_up_with_retry behavior
# ============================================================================

test_eth_is_up_with_retry_immediate_success() {
    test_start "eth_is_up_with_retry_immediate_success"
    setup
    export ETH_CONNECT_RETRIES="3"
    export ETH_RETRY_INTERVAL="0"

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
echo "192.168.1.100"
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    source_switcher

    if eth_is_up_with_retry; then
        result="up"
    else
        result="down"
    fi

    assert_equals "up" "$result" "eth_is_up_with_retry should succeed immediately if IP available"
    cleanup
}

test_eth_is_up_with_retry_eventual_success() {
    test_start "eth_is_up_with_retry_eventual_success"
    setup
    export TIMEOUT="5"

    # Create counter file for mock
    echo "0" > "$MOCK_DIR/counter"

    # Use EOF without quotes to allow variable expansion
    cat > "$MOCK_DIR/bin/ipconfig" << EOF
#!/bin/sh
COUNTER_FILE="$MOCK_DIR/counter"
count=\$(cat "\$COUNTER_FILE")
count=\$((count + 1))
echo "\$count" > "\$COUNTER_FILE"
# Fail first 2 calls, succeed on 3rd
if [ "\$count" -lt 3 ]; then
    echo ""
else
    echo "192.168.1.100"
fi
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    source_switcher

    if eth_is_up_with_retry; then
        result="up"
    else
        result="down"
    fi

    assert_equals "up" "$result" "eth_is_up_with_retry should succeed after retries"
    cleanup
}

test_eth_is_up_with_retry_all_fail() {
    test_start "eth_is_up_with_retry_all_fail"
    setup
    export ETH_CONNECT_RETRIES="2"
    export ETH_RETRY_INTERVAL="0"

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
echo ""
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    source_switcher

    if eth_is_up_with_retry; then
        result="up"
    else
        result="down"
    fi

    assert_equals "down" "$result" "eth_is_up_with_retry should fail if all retries fail"
    cleanup
}

# ============================================================================
# Test: Retry configuration
# ============================================================================

test_retry_uses_configured_retries() {
    test_start "retry_uses_configured_retries"
    setup
    export TIMEOUT="6"

    echo "0" > "$MOCK_DIR/counter"

    cat > "$MOCK_DIR/bin/ipconfig" << EOF
#!/bin/sh
COUNTER_FILE="$MOCK_DIR/counter"
count=\$(cat "\$COUNTER_FILE")
count=\$((count + 1))
echo "\$count" > "\$COUNTER_FILE"
# Fail first 4 calls, succeed on 5th
if [ "\$count" -lt 5 ]; then
    echo ""
else
    echo "192.168.1.100"
fi
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    source_switcher

    if eth_is_up_with_retry; then
        result="up"
    else
        result="down"
    fi

    assert_equals "up" "$result" "Should succeed on 5th retry with TIMEOUT=6"
    cleanup
}

test_zero_retries_single_check() {
    test_start "zero_retries_single_check"
    setup
    export TIMEOUT="0"

    echo "0" > "$MOCK_DIR/counter"

    cat > "$MOCK_DIR/bin/ipconfig" << EOF
#!/bin/sh
COUNTER_FILE="$MOCK_DIR/counter"
count=\$(cat "\$COUNTER_FILE")
count=\$((count + 1))
echo "\$count" > "\$COUNTER_FILE"
echo ""
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    source_switcher

    eth_is_up_with_retry 2>/dev/null || true

    # Read final count
    final_count=$(cat "$MOCK_DIR/counter")

    # With TIMEOUT=0, should only check once
    assert_equals "1" "$final_count" "With TIMEOUT=0, should only check once"
    cleanup
}

# ============================================================================
# Test: eth_has_link (prerequisite for retry logic)
# ============================================================================

test_eth_has_link_active() {
    test_start "eth_has_link_active"
    setup

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
echo "en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST>"
echo "	status: active"
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    source_switcher

    if eth_has_link; then
        result="active"
    else
        result="inactive"
    fi

    assert_equals "active" "$result" "eth_has_link should return true when active"
    cleanup
}

test_eth_has_link_inactive() {
    test_start "eth_has_link_inactive"
    setup

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
echo "en5: flags=8822<BROADCAST,SMART,SIMPLEX,MULTICAST>"
echo "	status: inactive"
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    source_switcher

    if eth_has_link; then
        result="active"
    else
        result="inactive"
    fi

    assert_equals "inactive" "$result" "eth_has_link should return false when inactive"
    cleanup
}

# ============================================================================
# Run all tests
# ============================================================================

echo "============================================"
echo "macOS IP Acquisition Retry Real Unit Tests"
echo "============================================"
echo "Testing ACTUAL retry logic from src/macos/switcher.sh"
echo ""

test_eth_is_up_with_ip
test_eth_is_up_without_ip
test_eth_is_up_with_link_local
test_eth_is_up_with_retry_immediate_success
test_eth_is_up_with_retry_eventual_success
test_eth_is_up_with_retry_all_fail
test_retry_uses_configured_retries
test_zero_retries_single_check
test_eth_has_link_active
test_eth_has_link_inactive

test_summary
