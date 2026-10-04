#!/bin/sh
# Critical failover test: Ethernet has IP but no internet connectivity
# Tests that switcher properly fails over to WiFi when ethernet internet fails

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load test frameworks
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../lib/mock.sh"

# Setup test environment
MOCK_DIR="/tmp/eth-wifi-macos-failover-$$"
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
    export TIMEOUT="2"
    export CHECK_INTERVAL="30"
    export INTERFACE_PRIORITY=""

    export NETWORKSETUP="$MOCK_DIR/bin/networksetup"
    export DATE="date"
    export IPCONFIG="$MOCK_DIR/bin/ipconfig"
    export IFCONFIG="$MOCK_DIR/bin/ifconfig"

    # Use a test-specific WiFi state file
    export WIFI_STATE_FILE="$MOCK_DIR/wifi_state"

    rm -f "$STATE_FILE" "$LAST_CHECK_STATE_FILE" "$WIFI_STATE_FILE" 2>/dev/null || true
}

source_switcher() {
    . "$PROJECT_ROOT/src/macos/switcher.sh"
}

cleanup() {
    rm -rf "$MOCK_DIR"
}

# ============================================================================
# CHECK_INTERNET=0 Tests: No internet validation (default behavior)
# ============================================================================

test_check_internet_0_ethernet_has_ip_keeps_wifi_off() {
    test_start "check_internet_0_ethernet_has_ip_keeps_wifi_off"
    setup

    export CHECK_INTERNET="0"

    # Ethernet has IP (but internet might be broken - we don't check)
    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
case "$1" in
    getifaddr)
        case "$2" in
            en5) echo "192.168.1.100" ;;
            en0) echo "192.168.1.101" ;;
            *) exit 1 ;;
        esac
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
echo "en5: flags=8863<UP> mtu 1500"
echo "    status: active"
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
WIFI_STATE_FILE="${WIFI_STATE_FILE:-/tmp/wifi_state_test}"
case "$*" in
    *getairportpower*)
        if [ -f "$WIFI_STATE_FILE" ]; then
            echo "Wi-Fi Power (en0): On"
        else
            echo "Wi-Fi Power (en0): Off"
        fi
        ;;
    *setairportpower*on*)
        touch "$WIFI_STATE_FILE"
        ;;
    *setairportpower*off*)
        rm -f "$WIFI_STATE_FILE"
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    # Use a test-specific WiFi state file
    WIFI_STATE_FILE="$MOCK_DIR/wifi_state"
    export WIFI_STATE_FILE

    source_switcher

    # Start with WiFi on (simulating previous state)
    touch "$WIFI_STATE_FILE"
    write_state "disconnected"

    switcher_tick

    result=$(cat "$STATE_FILE")
    wifi_on=$(test -f "$WIFI_STATE_FILE" && echo "yes" || echo "no")

    rm -f "$WIFI_STATE_FILE" 2>/dev/null || true

    # With CHECK_INTERNET=0, ethernet with IP is considered "good"
    assert_equals "connected" "$result" "Should mark as connected"
    assert_equals "no" "$wifi_on" "WiFi should be turned OFF (no internet validation)"
    cleanup
}

test_check_internet_0_ethernet_no_ip_enables_wifi() {
    test_start "check_internet_0_ethernet_no_ip_enables_wifi"
    setup

    export CHECK_INTERNET="0"

    # Ethernet has NO IP
    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
exit 1  # No IP on ethernet
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
echo "en5: flags=8863<UP> mtu 1500"
echo "    status: active"
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
case "$*" in
    *getairportpower*)
        if [ -f $WIFI_STATE_FILE ]; then
            echo "Wi-Fi Power (en0): On"
        else
            echo "Wi-Fi Power (en0): Off"
        fi
        ;;
    *setairportpower*on*)
        touch $WIFI_STATE_FILE
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    source_switcher

    rm -f $WIFI_STATE_FILE 2>/dev/null || true
    write_state "connected"

    switcher_tick

    result=$(cat "$STATE_FILE")
    wifi_on=$(test -f $WIFI_STATE_FILE && echo "yes" || echo "no")

    rm -f $WIFI_STATE_FILE 2>/dev/null || true

    assert_equals "disconnected" "$result" "Should mark as disconnected"
    assert_equals "yes" "$wifi_on" "WiFi should be enabled when ethernet has no IP"
    cleanup
}

# ============================================================================
# CHECK_INTERNET=1, CHECK_METHOD=gateway Tests
# ============================================================================

test_check_internet_1_gateway_ping_fails_failover() {
    test_start "check_internet_1_gateway_ping_fails_failover"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="gateway"
    export LOG_ALL_CHECKS="0"

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
case "$1" in
    getifaddr)
        case "$2" in
            en5) echo "192.168.1.100" ;;
            en0) echo "192.168.1.101" ;;
            *) exit 1 ;;
        esac
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
echo "flags=8863<UP> mtu 1500"
echo "    status: active"
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    # Gateway exists for ethernet
    cat > "$MOCK_DIR/bin/netstat" << 'EOF'
#!/bin/sh
echo "Routing tables"
echo "Internet:"
echo "default            192.168.1.1        UGSc           en5"
EOF
    chmod +x "$MOCK_DIR/bin/netstat"

    # Ping to gateway FAILS
    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
exit 1  # Gateway unreachable
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    # WiFi works (checked via curl)
    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
case "$*" in
    *getairportpower*)
        if [ -f $WIFI_STATE_FILE ]; then
            echo "Wi-Fi Power (en0): On"
        else
            echo "Wi-Fi Power (en0): Off"
        fi
        ;;
    *setairportpower*on*)
        touch $WIFI_STATE_FILE
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    source_switcher

    rm -f $WIFI_STATE_FILE 2>/dev/null || true
    write_state "connected"

    switcher_tick

    result=$(cat "$STATE_FILE")
    wifi_on=$(test -f $WIFI_STATE_FILE && echo "yes" || echo "no")

    rm -f $WIFI_STATE_FILE 2>/dev/null || true

    assert_equals "disconnected" "$result" "Should failover when gateway ping fails"
    assert_equals "yes" "$wifi_on" "WiFi should be enabled for failover"
    cleanup
}

test_check_internet_1_gateway_no_gateway_failover() {
    test_start "check_internet_1_gateway_no_gateway_failover"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="gateway"
    export LOG_ALL_CHECKS="0"

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
case "$1" in
    getifaddr)
        case "$2" in
            en5) echo "192.168.1.100" ;;
            en0) echo "192.168.1.101" ;;
            *) exit 1 ;;
        esac
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
echo "flags=8863<UP> mtu 1500"
echo "    status: active"
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    # NO gateway in routing table for ethernet
    cat > "$MOCK_DIR/bin/netstat" << 'EOF'
#!/bin/sh
echo "Routing tables"
echo "Internet:"
# No default route for en5
EOF
    chmod +x "$MOCK_DIR/bin/netstat"

    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 0  # WiFi works
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
case "$*" in
    *getairportpower*)
        if [ -f $WIFI_STATE_FILE ]; then
            echo "Wi-Fi Power (en0): On"
        else
            echo "Wi-Fi Power (en0): Off"
        fi
        ;;
    *setairportpower*on*)
        touch $WIFI_STATE_FILE
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    source_switcher

    rm -f $WIFI_STATE_FILE 2>/dev/null || true
    write_state "connected"

    switcher_tick

    result=$(cat "$STATE_FILE")
    wifi_on=$(test -f $WIFI_STATE_FILE && echo "yes" || echo "no")

    rm -f $WIFI_STATE_FILE 2>/dev/null || true

    assert_equals "disconnected" "$result" "Should failover when no gateway found"
    assert_equals "yes" "$wifi_on" "WiFi should be enabled"
    cleanup
}

test_check_internet_1_gateway_works_stays_ethernet() {
    test_start "check_internet_1_gateway_works_stays_ethernet"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="gateway"

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
case "$1" in
    getifaddr)
        case "$2" in
            en5) echo "192.168.1.100" ;;
            *) exit 1 ;;
        esac
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
echo "flags=8863<UP> mtu 1500"
echo "    status: active"
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    cat > "$MOCK_DIR/bin/netstat" << 'EOF'
#!/bin/sh
echo "default            192.168.1.1        UGSc           en5"
EOF
    chmod +x "$MOCK_DIR/bin/netstat"

    # Gateway ping succeeds
    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
case "$*" in
    *getairportpower*)
        if [ -f $WIFI_STATE_FILE ]; then
            echo "Wi-Fi Power (en0): On"
        else
            echo "Wi-Fi Power (en0): Off"
        fi
        ;;
    *setairportpower*off*)
        rm -f $WIFI_STATE_FILE
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    source_switcher

    touch $WIFI_STATE_FILE
    write_state "disconnected"

    switcher_tick

    result=$(cat "$STATE_FILE")
    wifi_on=$(test -f $WIFI_STATE_FILE && echo "yes" || echo "no")

    rm -f $WIFI_STATE_FILE 2>/dev/null || true

    assert_equals "connected" "$result" "Should stay on ethernet when gateway works"
    assert_equals "no" "$wifi_on" "WiFi should be turned off"
    cleanup
}

# ============================================================================
# CHECK_INTERNET=1, CHECK_METHOD=ping Tests (domain ping)
# ============================================================================

test_check_internet_1_ping_domain_fails_failover() {
    test_start "check_internet_1_ping_domain_fails_failover"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="ping"
    export CHECK_TARGET="8.8.8.8"
    export LOG_ALL_CHECKS="0"

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
case "$1" in
    getifaddr)
        case "$2" in
            en5) echo "192.168.1.100" ;;
            en0) echo "192.168.1.101" ;;
            *) exit 1 ;;
        esac
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
echo "flags=8863<UP> mtu 1500"
echo "    status: active"
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    # Ping to 8.8.8.8 FAILS (active interface)
    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
exit 1  # Ping fails
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    # WiFi works (checked via curl)
    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
case "$*" in
    *getairportpower*)
        if [ -f $WIFI_STATE_FILE ]; then
            echo "Wi-Fi Power (en0): On"
        else
            echo "Wi-Fi Power (en0): Off"
        fi
        ;;
    *setairportpower*on*)
        touch $WIFI_STATE_FILE
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    source_switcher

    rm -f $WIFI_STATE_FILE 2>/dev/null || true
    write_state "connected"

    switcher_tick

    result=$(cat "$STATE_FILE")
    wifi_on=$(test -f $WIFI_STATE_FILE && echo "yes" || echo "no")

    rm -f $WIFI_STATE_FILE 2>/dev/null || true

    assert_equals "disconnected" "$result" "Should failover when ping fails"
    assert_equals "yes" "$wifi_on" "WiFi should be enabled"
    cleanup
}

test_check_internet_1_ping_domain_works_stays_ethernet() {
    test_start "check_internet_1_ping_domain_works_stays_ethernet"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="ping"
    export CHECK_TARGET="8.8.8.8"

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
case "$1" in
    getifaddr)
        case "$2" in
            en5) echo "192.168.1.100" ;;
            *) exit 1 ;;
        esac
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
echo "flags=8863<UP> mtu 1500"
echo "    status: active"
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    # Ping succeeds
    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
case "$*" in
    *getairportpower*)
        if [ -f $WIFI_STATE_FILE ]; then
            echo "Wi-Fi Power (en0): On"
        else
            echo "Wi-Fi Power (en0): Off"
        fi
        ;;
    *setairportpower*off*)
        rm -f $WIFI_STATE_FILE
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    source_switcher

    touch $WIFI_STATE_FILE
    write_state "disconnected"

    switcher_tick

    result=$(cat "$STATE_FILE")
    wifi_on=$(test -f $WIFI_STATE_FILE && echo "yes" || echo "no")

    rm -f $WIFI_STATE_FILE 2>/dev/null || true

    assert_equals "connected" "$result" "Should stay on ethernet when ping works"
    assert_equals "no" "$wifi_on" "WiFi should be turned off"
    cleanup
}

test_check_internet_1_ping_no_target_fails() {
    test_start "check_internet_1_ping_no_target_fails"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="ping"
    export CHECK_TARGET=""  # No target specified

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
case "$1" in
    getifaddr)
        case "$2" in
            en5) echo "192.168.1.100" ;;
            en0) echo "192.168.1.101" ;;
            *) exit 1 ;;
        esac
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
echo "flags=8863<UP> mtu 1500"
echo "    status: active"
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 0  # WiFi works
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
case "$*" in
    *getairportpower*)
        if [ -f /tmp/wifi_notarget$$ ]; then
            echo "Wi-Fi Power (en0): On"
        else
            echo "Wi-Fi Power (en0): Off"
        fi
        ;;
    *setairportpower*on*)
        touch /tmp/wifi_notarget$$
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    source_switcher

    rm -f /tmp/wifi_notarget$$ 2>/dev/null || true
    write_state "connected"

    switcher_tick

    result=$(cat "$STATE_FILE")
    wifi_on=$(test -f /tmp/wifi_notarget$$ && echo "yes" || echo "no")

    rm -f /tmp/wifi_notarget$$ 2>/dev/null || true

    assert_equals "disconnected" "$result" "Should failover when CHECK_TARGET not set"
    assert_equals "yes" "$wifi_on" "WiFi should be enabled"
    cleanup
}

# ============================================================================
# CHECK_INTERNET=1, CHECK_METHOD=curl Tests
# ============================================================================

test_check_internet_1_curl_fails_failover() {
    test_start "check_internet_1_curl_fails_failover"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="curl"
    export CHECK_TARGET="http://captive.apple.com/hotspot-detect.html"

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
case "$1" in
    getifaddr)
        case "$2" in
            en5) echo "192.168.1.100" ;;
            en0) echo "192.168.1.101" ;;
            *) exit 1 ;;
        esac
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
echo "flags=8863<UP> mtu 1500"
echo "    status: active"
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    # Ethernet curl fails, WiFi curl succeeds
    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
for arg in "$@"; do
    if [ "$arg" = "en5" ]; then
        exit 1  # Ethernet fails
    elif [ "$arg" = "en0" ]; then
        exit 0  # WiFi works
    fi
done
exit 1
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
case "$*" in
    *getairportpower*)
        if [ -f /tmp/wifi_curl_fail$$ ]; then
            echo "Wi-Fi Power (en0): On"
        else
            echo "Wi-Fi Power (en0): Off"
        fi
        ;;
    *setairportpower*on*)
        touch /tmp/wifi_curl_fail$$
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    source_switcher

    rm -f /tmp/wifi_curl_fail$$ 2>/dev/null || true
    write_state "connected"

    switcher_tick

    result=$(cat "$STATE_FILE")
    wifi_on=$(test -f /tmp/wifi_curl_fail$$ && echo "yes" || echo "no")

    rm -f /tmp/wifi_curl_fail$$ 2>/dev/null || true

    assert_equals "disconnected" "$result" "Should failover when curl fails"
    assert_equals "yes" "$wifi_on" "WiFi should be enabled"
    cleanup
}

test_check_internet_1_curl_works_stays_ethernet() {
    test_start "check_internet_1_curl_works_stays_ethernet"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="curl"
    export CHECK_TARGET="http://captive.apple.com/hotspot-detect.html"

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
case "$1" in
    getifaddr)
        case "$2" in
            en5) echo "192.168.1.100" ;;
            *) exit 1 ;;
        esac
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
echo "flags=8863<UP> mtu 1500"
echo "    status: active"
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    # Curl succeeds
    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
case "$*" in
    *getairportpower*)
        if [ -f $WIFI_STATE_FILE ]; then
            echo "Wi-Fi Power (en0): On"
        else
            echo "Wi-Fi Power (en0): Off"
        fi
        ;;
    *setairportpower*off*)
        rm -f $WIFI_STATE_FILE
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    source_switcher

    touch $WIFI_STATE_FILE
    write_state "disconnected"

    switcher_tick

    result=$(cat "$STATE_FILE")
    wifi_on=$(test -f $WIFI_STATE_FILE && echo "yes" || echo "no")

    rm -f $WIFI_STATE_FILE 2>/dev/null || true

    assert_equals "connected" "$result" "Should stay on ethernet when curl works"
    assert_equals "no" "$wifi_on" "WiFi should be turned off"
    cleanup
}

test_check_internet_1_curl_default_target() {
    test_start "check_internet_1_curl_default_target"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="curl"
    export CHECK_TARGET=""  # Empty - should use default

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
case "$1" in
    getifaddr)
        case "$2" in
            en5) echo "192.168.1.100" ;;
            *) exit 1 ;;
        esac
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
echo "flags=8863<UP> mtu 1500"
echo "    status: active"
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    # Curl succeeds with default target
    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
case "$*" in
    *getairportpower*)
        echo "Wi-Fi Power (en0): Off"
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    source_switcher

    write_state "connected"

    switcher_tick

    result=$(cat "$STATE_FILE")

    assert_equals "connected" "$result" "Should work with default curl target"
    cleanup
}

# Run all tests
test_check_internet_0_ethernet_has_ip_keeps_wifi_off
test_check_internet_0_ethernet_no_ip_enables_wifi
test_check_internet_1_gateway_ping_fails_failover
test_check_internet_1_gateway_no_gateway_failover
test_check_internet_1_gateway_works_stays_ethernet
test_check_internet_1_ping_domain_fails_failover
test_check_internet_1_ping_domain_works_stays_ethernet
test_check_internet_1_ping_no_target_fails
test_check_internet_1_curl_fails_failover
test_check_internet_1_curl_works_stays_ethernet
test_check_internet_1_curl_default_target

test_summary
