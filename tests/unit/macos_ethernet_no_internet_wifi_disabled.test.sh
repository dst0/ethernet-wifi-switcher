#!/bin/sh
# Test critical bug: Ethernet loses internet while WiFi is disabled
# Expected: System should enable WiFi, check it, and switch if it has internet
# Bug: System checks WiFi while it's still off/disabled, reports no internet, doesn't switch

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load test frameworks
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../lib/mock.sh"

# Setup test environment
MOCK_DIR="/tmp/eth-wifi-macos-bug-$$"
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
    export INTERFACE_PRIORITY="en5,en0"

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
# BUG TEST: Ethernet connected (WiFi off) -> Ethernet loses internet -> Should switch to WiFi
# ============================================================================

test_ethernet_loses_internet_wifi_disabled_should_failover() {
    test_start "ethernet_loses_internet_wifi_disabled_should_failover"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="ping"
    export CHECK_TARGET="8.8.8.8"
    export LOG_ALL_CHECKS="1"

    # Mock ipconfig: Both interfaces have IP addresses
    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
case "$1" in
    getifaddr)
        case "$2" in
            en5) echo "192.168.1.100" ;;  # Ethernet has IP
            en0) echo "192.168.1.101" ;;  # WiFi has IP
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

    # Mock ping: Ethernet fails, WiFi succeeds
    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
# Check which interface is being tested by looking at routing
# For simplicity in this test, we'll check the -I flag if passed
# But macOS ping doesn't support -I, so we rely on context
# The switcher will call ping when checking ethernet (active) - it will fail
# The switcher will use curl when checking wifi (inactive) - we'll make curl succeed

# For this test, we'll make ping always fail (simulating ethernet has no internet)
exit 1
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    # Mock curl: WiFi works (used for inactive interface checks)
    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
# Check if --interface en0 is in the args
for arg in "$@"; do
    case "$arg" in
        en0)
            # WiFi has internet
            exit 0
            ;;
        en5)
            # Ethernet has no internet
            exit 1
            ;;
    esac
done
# Default: success
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    # Mock networksetup: Track WiFi power state
    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
WIFI_STATE_FILE="${WIFI_STATE_FILE:-/tmp/wifi_state_test}"
case "$1" in
    -getairportpower)
        if [ -f "$WIFI_STATE_FILE" ]; then
            echo "Wi-Fi Power (en0): On"
        else
            echo "Wi-Fi Power (en0): Off"
        fi
        ;;
    -setairportpower)
        # $2 is interface, $3 is on/off
        if [ "$3" = "on" ]; then
            touch "$WIFI_STATE_FILE"
            # Simulate WiFi connecting and getting IP (happens in real scenario)
            sleep 0.1
        else
            rm -f "$WIFI_STATE_FILE"
        fi
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    source_switcher

    # Initial state: Ethernet connected with internet, WiFi OFF
    rm -f "$WIFI_STATE_FILE"  # WiFi is OFF
    write_state "connected"    # Ethernet is active

    echo "=== Initial State: Ethernet active with internet, WiFi OFF ==="
    echo "State file: connected"
    echo "WiFi: OFF"
    echo ""

    # Now simulate: Ethernet loses internet
    # Run switcher_tick - it should detect ethernet has no internet
    # and switch to WiFi
    echo "=== Running switcher_tick: Ethernet loses internet ==="
    switcher_tick

    # Check results
    result=$(cat "$STATE_FILE")
    wifi_on=$(test -f "$WIFI_STATE_FILE" && echo "yes" || echo "no")

    echo ""
    echo "=== Results ==="
    echo "State file: $result"
    echo "WiFi: $wifi_on"
    echo ""

    # EXPECTED BEHAVIOR:
    # 1. Detect ethernet has no internet
    # 2. Enable WiFi to check it
    # 3. Check WiFi for internet (should succeed)
    # 4. Switch to WiFi (state = disconnected, wifi = on)

    assert_equals "disconnected" "$result" "Should switch to WiFi when ethernet loses internet"
    assert_equals "yes" "$wifi_on" "WiFi should be enabled after failover"

    cleanup
}

# Test variant: Using gateway ping method
test_ethernet_loses_internet_wifi_disabled_gateway_method() {
    test_start "ethernet_loses_internet_wifi_disabled_gateway_method"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="gateway"
    export LOG_ALL_CHECKS="1"

    # Mock ipconfig: Both interfaces have IP
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

    # Mock netstat: Ethernet has gateway, WiFi has gateway
    cat > "$MOCK_DIR/bin/netstat" << 'EOF'
#!/bin/sh
echo "Routing tables"
echo "Internet:"
echo "default            192.168.1.1        UGSc           en5"
echo "default            192.168.1.1        UGSc           en0"
EOF
    chmod +x "$MOCK_DIR/bin/netstat"

    # Mock ping: Ethernet gateway fails, WiFi gateway succeeds
    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
# First call is to test ethernet gateway (will fail)
# Subsequent calls are to test wifi gateway (will succeed)
if [ ! -f /tmp/ping_count_$$ ]; then
    echo "0" > /tmp/ping_count_$$
fi
count=$(cat /tmp/ping_count_$$)
count=$((count + 1))
echo "$count" > /tmp/ping_count_$$

if [ $count -eq 1 ]; then
    # First ping (ethernet) fails
    exit 1
else
    # Subsequent pings (wifi) succeed
    exit 0
fi
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    # Mock curl: WiFi works
    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
for arg in "$@"; do
    case "$arg" in
        en0) exit 0 ;;  # WiFi works
        en5) exit 1 ;;  # Ethernet fails
    esac
done
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    # Mock networksetup
    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
WIFI_STATE_FILE="${WIFI_STATE_FILE:-/tmp/wifi_state_test}"
case "$1" in
    -getairportpower)
        if [ -f "$WIFI_STATE_FILE" ]; then
            echo "Wi-Fi Power (en0): On"
        else
            echo "Wi-Fi Power (en0): Off"
        fi
        ;;
    -setairportpower)
        if [ "$3" = "on" ]; then
            touch "$WIFI_STATE_FILE"
            sleep 0.1
        else
            rm -f "$WIFI_STATE_FILE"
        fi
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    source_switcher

    # Initial state: Ethernet connected, WiFi OFF
    rm -f "$WIFI_STATE_FILE" /tmp/ping_count_$$
    write_state "connected"

    switcher_tick

    result=$(cat "$STATE_FILE")
    wifi_on=$(test -f "$WIFI_STATE_FILE" && echo "yes" || echo "no")

    rm -f /tmp/ping_count_$$ 2>/dev/null || true

    assert_equals "disconnected" "$result" "Should switch to WiFi (gateway method)"
    assert_equals "yes" "$wifi_on" "WiFi should be enabled"

    cleanup
}

# Test: Ethernet loses internet, WiFi is already ON but not connected to network
test_ethernet_loses_internet_wifi_on_but_no_connection() {
    test_start "ethernet_loses_internet_wifi_on_but_no_connection"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="ping"
    export CHECK_TARGET="8.8.8.8"
    export LOG_ALL_CHECKS="1"

    # Mock ipconfig: Ethernet has IP, WiFi has NO IP (not connected to any network)
    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
case "$1" in
    getifaddr)
        case "$2" in
            en5) echo "192.168.1.100" ;;  # Ethernet has IP
            en0) exit 1 ;;                 # WiFi has NO IP
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

    # Mock ping: Always fail (ethernet has no internet)
    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
exit 1
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    # Mock networksetup
    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
WIFI_STATE_FILE="${WIFI_STATE_FILE:-/tmp/wifi_state_test}"
case "$1" in
    -getairportpower)
        if [ -f "$WIFI_STATE_FILE" ]; then
            echo "Wi-Fi Power (en0): On"
        else
            echo "Wi-Fi Power (en0): Off"
        fi
        ;;
    -setairportpower)
        if [ "$3" = "on" ]; then
            touch "$WIFI_STATE_FILE"
        else
            rm -f "$WIFI_STATE_FILE"
        fi
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    source_switcher

    # Initial state: Ethernet connected, WiFi ON but not connected to network
    touch "$WIFI_STATE_FILE"  # WiFi is ON
    write_state "connected"

    switcher_tick

    result=$(cat "$STATE_FILE")
    wifi_on=$(test -f "$WIFI_STATE_FILE" && echo "yes" || echo "no")

    # EXPECTED: Should stay on ethernet (no working alternative)
    # WiFi is on but has no IP, so can't be used
    assert_equals "connected" "$result" "Should stay on ethernet (no working alternative)"
    assert_equals "yes" "$wifi_on" "WiFi should stay on"

    cleanup
}

# Run all tests
echo "===================================="
echo "Testing Ethernet Failover with WiFi Disabled"
echo "===================================="
echo ""

test_ethernet_loses_internet_wifi_disabled_should_failover
test_ethernet_loses_internet_wifi_disabled_gateway_method
test_ethernet_loses_internet_wifi_on_but_no_connection

test_summary
