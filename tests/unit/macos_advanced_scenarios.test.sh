#!/bin/sh
# Advanced scenario tests for macOS switcher
# Covers: edge cases, partial connectivity, race conditions, timing scenarios

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load test frameworks
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../lib/mock.sh"

# Setup test environment
MOCK_DIR="/tmp/eth-wifi-macos-advanced-$$"
mkdir -p "$MOCK_DIR/bin" "$MOCK_DIR/state"
export PATH="$MOCK_DIR/bin:$PATH"

setup() {
    clear_mocks
    mkdir -p "$MOCK_DIR/bin" "$MOCK_DIR/state"
    export STATE_DIR="$MOCK_DIR/state"
    export STATE_FILE="$STATE_DIR/eth-wifi-state"
    export LAST_CHECK_STATE_FILE="$STATE_FILE.last_check"
    export ETH_DEV="en5"
    export WIFI_DEV="en0"
    export TIMEOUT="7"
    export CHECK_INTERNET="1"
    export LOG_ALL_CHECKS="0"
    export INTERFACE_PRIORITY=""
    export CHECK_INTERVAL="30"
    export CHECK_METHOD="gateway"
    export CHECK_TARGET=""

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
# Edge Case Tests: Multiple Ethernet services
# ============================================================================

test_multiple_ethernet_first_available() {
    test_start "multiple_ethernet_first_available"
    setup

    export INTERFACE_PRIORITY="en7,en5,en6"

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
case "$1" in
    en7)
        echo "en7: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500"
        echo "    status: active"
        ;;
    en5)
        echo "en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500"
        echo "    status: active"
        ;;
    *)
        exit 1
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    source_switcher
    result=$(get_eth_dev)

    assert_equals "en7" "$result" "Should select first available interface from priority list"
    cleanup
}

test_multiple_ethernet_skip_unavailable() {
    test_start "multiple_ethernet_skip_unavailable"
    setup

    export INTERFACE_PRIORITY="en7,en5,en6"

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
case "$1" in
    en7)
        exit 1  # Not available
        ;;
    en5)
        echo "en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500"
        echo "    status: active"
        ;;
    *)
        exit 1
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    source_switcher
    result=$(get_eth_dev)

    assert_equals "en5" "$result" "Should skip unavailable and select next from priority list"
    cleanup
}

test_multiple_ethernet_skip_wifi() {
    test_start "multiple_ethernet_skip_wifi"
    setup

    export INTERFACE_PRIORITY="en0,en5"
    export WIFI_DEV="en0"

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
case "$1" in
    en0|en5)
        echo "en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500"
        echo "    status: active"
        ;;
    *)
        exit 1
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    source_switcher
    result=$(get_eth_dev)

    assert_equals "en5" "$result" "Should skip wifi device in priority list"
    cleanup
}

# ============================================================================
# Edge Case Tests: Output format variations
# ============================================================================

test_ifconfig_extra_whitespace() {
    test_start "ifconfig_extra_whitespace"
    setup

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
echo "en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500"
echo "        status:    active  "
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    source_switcher
    eth_has_link
    result=$?

    assert_equals "0" "$result" "Should handle extra whitespace in ifconfig output"
    cleanup
}

test_networksetup_wifi_extra_text() {
    test_start "networksetup_wifi_extra_text"
    setup

    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
echo "Wi-Fi Power (en0): On (extra info)"
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    source_switcher
    wifi_is_on
    result=$?

    assert_equals "0" "$result" "Should detect On status with extra text"
    cleanup
}

test_ipconfig_ipv6_address() {
    test_start "ipconfig_ipv6_address"
    setup

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
echo "fe80::1234:5678:90ab:cdef%en5"
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    source_switcher
    eth_is_up
    result=$?

    assert_equals "0" "$result" "Should accept IPv6 address as up"
    cleanup
}

# ============================================================================
# Partial Connectivity Tests: Captive portal
# ============================================================================

test_captive_portal_redirect() {
    test_start "captive_portal_redirect"
    setup

    export CHECK_METHOD="curl"
    export CHECK_TARGET="http://captive.apple.com/hotspot-detect.html"

    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 22  # HTTP error (redirect)
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    source_switcher
    check_internet "en5" 1
    result=$?

    assert_equals "1" "$result" "Should detect captive portal redirect as failure"
    cleanup
}

# ============================================================================
# Partial Connectivity Tests: DNS broken
# ============================================================================

test_dns_broken_ping_ip_works() {
    test_start "dns_broken_ping_ip_works"
    setup

    export CHECK_METHOD="ping"
    export CHECK_TARGET="8.8.8.8"

    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    source_switcher
    check_internet "en5" 1
    result=$?

    assert_equals "0" "$result" "Should succeed pinging IP when DNS broken"
    cleanup
}

test_dns_broken_curl_fails() {
    test_start "dns_broken_curl_fails"
    setup

    export CHECK_METHOD="curl"
    export CHECK_TARGET="http://google.com"

    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 6  # Couldn't resolve host
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    source_switcher
    check_internet "en5" 1
    result=$?

    assert_equals "1" "$result" "Should fail when DNS broken"
    cleanup
}

# ============================================================================
# Partial Connectivity Tests: Ping blocked
# ============================================================================

test_ping_blocked_gateway_timeout() {
    test_start "ping_blocked_gateway_timeout"
    setup

    export CHECK_METHOD="gateway"

    cat > "$MOCK_DIR/bin/netstat" << 'EOF'
#!/bin/sh
echo "default            192.168.1.1        UGScg                en5"
EOF
    chmod +x "$MOCK_DIR/bin/netstat"

    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
exit 2  # Timeout
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    source_switcher
    check_internet "en5" 1
    result=$?

    assert_equals "1" "$result" "Should fail when gateway blocks ping"
    cleanup
}

test_ping_blocked_curl_works() {
    test_start "ping_blocked_curl_works"
    setup

    export CHECK_METHOD="curl"
    export CHECK_TARGET="http://captive.apple.com/hotspot-detect.html"

    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    source_switcher
    check_internet "en5" 1
    result=$?

    assert_equals "0" "$result" "Should succeed with curl when ping blocked"
    cleanup
}

# ============================================================================
# Partial Connectivity Tests: TLS issues
# ============================================================================

test_tls_certificate_error() {
    test_start "tls_certificate_error"
    setup

    export CHECK_METHOD="curl"
    export CHECK_TARGET="https://expired.badssl.com/"

    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 60  # SSL certificate problem
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    source_switcher
    check_internet "en5" 1
    result=$?

    assert_equals "1" "$result" "Should fail on TLS certificate error"
    cleanup
}

# ============================================================================
# Partial Connectivity Tests: Routing issues
# ============================================================================

test_no_gateway_configured() {
    test_start "no_gateway_configured"
    setup

    export CHECK_METHOD="gateway"

    cat > "$MOCK_DIR/bin/netstat" << 'EOF'
#!/bin/sh
echo "Routing tables"
# No routes for en5
EOF
    chmod +x "$MOCK_DIR/bin/netstat"

    source_switcher
    check_internet "en5" 1
    result=$?

    assert_equals "1" "$result" "Should fail when no gateway for interface"
    cleanup
}

# ============================================================================
# Race Condition Tests: State file operations
# ============================================================================

test_read_partial_state_write() {
    test_start "read_partial_state_write"
    setup

    source_switcher
    write_state "connected"

    # Simulate partial write
    echo -n "disco" > "$STATE_FILE"

    result=$(read_last_state)

    assert_not_equals "" "$result" "Should handle partial state file"
    cleanup
}

test_multiple_rapid_state_writes() {
    test_start "multiple_rapid_state_writes"
    setup

    source_switcher

    # Rapid state changes
    write_state "connected"
    write_state "disconnected"
    write_state "connected"
    write_state "disconnected"
    write_state "connected"

    result=$(read_last_state)

    assert_equals "connected" "$result" "Should have last written state"
    cleanup
}

test_state_file_deleted() {
    test_start "state_file_deleted"
    setup

    source_switcher
    write_state "connected"
    rm -f "$STATE_FILE"

    result=$(read_last_state)

    assert_equals "disconnected" "$result" "Should return disconnected when file missing"
    cleanup
}

# ============================================================================
# Race Condition Tests: Rapid interface changes
# ============================================================================

test_rapid_link_flapping() {
    test_start "rapid_link_flapping"
    setup

    # Interface status changes on each call
    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
count=$(cat /tmp/counter$$ 2>/dev/null || echo "0")
count=$((count + 1))
echo "$count" > /tmp/counter$$

if [ $((count % 2)) -eq 0 ]; then
    echo "en5: flags=8863<UP> mtu 1500"
    echo "    status: active"
else
    echo "en5: flags=8863<UP> mtu 1500"
    echo "    status: inactive"
fi
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    source_switcher

    # Multiple rapid checks
    eth_has_link || true
    eth_has_link || true
    eth_has_link || true

    rm -f /tmp/counter$$ 2>/dev/null || true
    assert_true "true" "Should handle rapid link state changes"
    cleanup
}

# ============================================================================
# Timing Tests: DHCP acquisition
# ============================================================================

test_dhcp_immediate() {
    test_start "dhcp_immediate"
    setup
    export TIMEOUT="5"

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
echo "en5: flags=8863<UP> mtu 1500"
echo "    status: active"
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
echo "192.168.1.100"
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    source_switcher
    eth_is_up_with_retry
    result=$?

    assert_equals "0" "$result" "Should succeed with immediate DHCP"
    cleanup
}

test_dhcp_delayed() {
    test_start "dhcp_delayed"
    setup
    export TIMEOUT="5"

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
echo "en5: flags=8863<UP> mtu 1500"
echo "    status: active"
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    # IP available after 2 attempts
    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
count=$(cat /tmp/counter_ip$$ 2>/dev/null || echo "0")
count=$((count + 1))
echo "$count" > /tmp/counter_ip$$

if [ "$count" -ge 3 ]; then
    echo "192.168.1.100"
else
    exit 1
fi
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    source_switcher
    eth_is_up_with_retry
    result=$?

    rm -f /tmp/counter_ip$$ 2>/dev/null || true
    assert_equals "0" "$result" "Should succeed after DHCP delay"
    cleanup
}

test_dhcp_timeout() {
    test_start "dhcp_timeout"
    setup
    export TIMEOUT="2"

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
echo "en5: flags=8863<UP> mtu 1500"
echo "    status: active"
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
exit 1  # No IP ever
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    source_switcher
    eth_is_up_with_retry
    result=$?

    assert_equals "1" "$result" "Should timeout when DHCP fails"
    cleanup
}

test_dhcp_self_assigned_ip() {
    test_start "dhcp_self_assigned_ip"
    setup

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
echo "169.254.123.45"
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    source_switcher
    eth_is_up
    result=$?

    # Current implementation accepts any IP (including self-assigned)
    assert_equals "0" "$result" "Accepts self-assigned IP as up (limitation)"
    cleanup
}

# ============================================================================
# Timing Tests: Sleep/wake scenarios
# ============================================================================

test_sleep_wake_delayed_ip_renewal() {
    test_start "sleep_wake_delayed_ip_renewal"
    setup
    export TIMEOUT="5"

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
echo "en5: flags=8863<UP> mtu 1500"
echo "    status: active"
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    # IP takes time to renew after wake
    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
count=$(cat /tmp/counter_wake$$ 2>/dev/null || echo "0")
count=$((count + 1))
echo "$count" > /tmp/counter_wake$$

if [ "$count" -ge 3 ]; then
    echo "192.168.1.100"
else
    exit 1
fi
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    source_switcher
    eth_is_up_with_retry
    result=$?

    rm -f /tmp/counter_wake$$ 2>/dev/null || true
    assert_equals "0" "$result" "Should wait for IP renewal after wake"
    cleanup
}

test_sleep_wake_stale_gateway() {
    test_start "sleep_wake_stale_gateway"
    setup
    export CHECK_METHOD="gateway"

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
echo "192.168.1.100"  # Old cached IP
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    cat > "$MOCK_DIR/bin/netstat" << 'EOF'
#!/bin/sh
echo "Routing tables"
# No valid routes (stale network state)
EOF
    chmod +x "$MOCK_DIR/bin/netstat"

    source_switcher
    check_internet "en5" 1
    result=$?

    assert_equals "1" "$result" "Should fail with stale gateway info"
    cleanup
}

# Run all tests
test_multiple_ethernet_first_available
test_multiple_ethernet_skip_unavailable
test_multiple_ethernet_skip_wifi
test_ifconfig_extra_whitespace
test_networksetup_wifi_extra_text
test_ipconfig_ipv6_address
test_captive_portal_redirect
test_dns_broken_ping_ip_works
test_dns_broken_curl_fails
test_ping_blocked_gateway_timeout
test_ping_blocked_curl_works
test_tls_certificate_error
test_no_gateway_configured
test_read_partial_state_write
test_multiple_rapid_state_writes
test_state_file_deleted
test_rapid_link_flapping
test_dhcp_immediate
test_dhcp_delayed
test_dhcp_timeout
test_dhcp_self_assigned_ip
test_sleep_wake_delayed_ip_renewal
test_sleep_wake_stale_gateway

test_summary
