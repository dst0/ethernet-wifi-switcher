#!/bin/sh
# Real unit tests for macOS internet failover functionality
# Tests actual failover logic from src/macos/switcher.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../lib/mock.sh"

# Setup test environment
setup() {
    MOCK_DIR="/tmp/macos-failover-test-$$"
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
# Test: Ethernet has internet - should disable WiFi
# ============================================================================

test_eth_has_internet_disables_wifi() {
    test_start "eth_has_internet_disables_wifi"
    setup

    # Mock eth with link, IP, and internet
    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
if [ "$1" = "en5" ]; then
    echo "en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500"
    echo "\tstatus: active"
    echo "\tinet 192.168.1.100 netmask 0xffffff00 broadcast 192.168.1.255"
fi
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
# Active eth has IP, wifi has none
if [ "$1" = "getifaddr" ] && [ "$2" = "en5" ]; then
  echo "192.168.1.100"
fi
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

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

    # Track WiFi power changes
    cat > "$MOCK_DIR/bin/networksetup" << EOF
#!/bin/sh
if [ "\$1" = "-getairportpower" ]; then
    echo "Wi-Fi Power (en0): On"
elif [ "\$1" = "-setairportpower" ]; then
    echo "\$3" > "$MOCK_DIR/wifi_action"
fi
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    source_switcher

    # Run the REAL orchestration
    switcher_tick

    action=$(cat "$MOCK_DIR/wifi_action" 2>/dev/null || echo "none")

    # In internet-check mode, eth having internet should result in WiFi being turned off
    assert_equals "off" "$action" "WiFi should be turned off when eth has internet"
    cleanup
}

# ============================================================================
# Test: Ethernet loses internet - should enable WiFi
# ============================================================================

test_eth_loses_internet_enables_wifi() {
    test_start "eth_loses_internet_enables_wifi"
    setup

    # Ensure previous state is ethernet connected (state file uses connected/disconnected)
    mkdir -p "$STATE_DIR"
    echo "connected" > "$STATE_FILE"
    echo "success" > "$LAST_CHECK_STATE_FILE"

    # eth has link + IP
    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
if [ "$1" = "en5" ]; then
    echo "en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500"
    echo "\tstatus: active"
    echo "\tinet 192.168.1.100 netmask 0xffffff00"
fi
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
if [ "$1" = "getifaddr" ] && [ "$2" = "en5" ]; then
  echo "192.168.1.100"
elif [ "$1" = "getifaddr" ] && [ "$2" = "en0" ]; then
  echo "192.168.2.100"
fi
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    cat > "$MOCK_DIR/bin/netstat" << 'EOF'
#!/bin/sh
echo "default            192.168.1.1        UGSc           en5"
EOF
    chmod +x "$MOCK_DIR/bin/netstat"

    # Active gateway ping fails
    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
exit 1
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    # For inactive interface checks, script uses curl. Make WiFi succeed.
    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    # Track WiFi power changes
    cat > "$MOCK_DIR/bin/networksetup" << EOF
#!/bin/sh
if [ "\$1" = "-getairportpower" ]; then
    echo "Wi-Fi Power (en0): Off"
elif [ "\$1" = "-setairportpower" ]; then
    echo "\$3" > "$MOCK_DIR/wifi_action"
fi
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    # Prefer eth then wifi
    export INTERFACE_PRIORITY="en5,en0"

    source_switcher

    # Run REAL orchestration
    switcher_tick

    action=$(cat "$MOCK_DIR/wifi_action" 2>/dev/null || echo "none")

    # Eth has no internet; should fall back to WiFi and turn it on
    assert_equals "on" "$action" "WiFi should be turned on when eth loses internet"
    cleanup
}

# ============================================================================
# Test: Ethernet disconnected - should enable WiFi
# ============================================================================

test_eth_disconnected_enables_wifi() {
    test_start "eth_disconnected_enables_wifi"
    setup

    # eth no link + no IP
    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
if [ "$1" = "en5" ]; then
    echo "en5: flags=8822<BROADCAST,SMART,SIMPLEX,MULTICAST> mtu 1500"
    echo "\tstatus: inactive"
fi
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
# WiFi has IP so it can become active
if [ "$1" = "getifaddr" ] && [ "$2" = "en0" ]; then
  echo "192.168.2.100"
fi
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    # Track WiFi power changes
    cat > "$MOCK_DIR/bin/networksetup" << EOF
#!/bin/sh
if [ "\$1" = "-getairportpower" ]; then
    echo "Wi-Fi Power (en0): Off"
elif [ "\$1" = "-setairportpower" ]; then
    echo "\$3" > "$MOCK_DIR/wifi_action"
fi
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    source_switcher

    # Run REAL orchestration (in non-internet mode, disconnect should enable wifi)
    export CHECK_INTERNET="0"
    echo "connected" > "$STATE_FILE"
    switcher_tick

    action=$(cat "$MOCK_DIR/wifi_action" 2>/dev/null || echo "none")
    assert_equals "on" "$action" "WiFi should be turned on when eth disconnected"
    cleanup
}

# ============================================================================
# Test: WiFi failover has internet - no action
# ============================================================================

test_wifi_failover_has_internet_no_action() {
    test_start "wifi_failover_has_internet_no_action"
    setup

    # Setup: WiFi is on with IP and internet; eth has no link.
    echo "disconnected" > "$STATE_FILE"

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
if [ "$1" = "en5" ]; then
  echo "en5: flags=8822<BROADCAST,SMART,SIMPLEX,MULTICAST> mtu 1500"
  echo "\tstatus: inactive"
fi
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
if [ "$1" = "getifaddr" ] && [ "$2" = "en0" ]; then
  echo "192.168.2.100"
fi
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    # Any wifi power change should be considered unexpected
    cat > "$MOCK_DIR/bin/networksetup" << EOF
#!/bin/sh
if [ "\$1" = "-getairportpower" ]; then
    echo "Wi-Fi Power (en0): On"
elif [ "\$1" = "-setairportpower" ]; then
    echo "UNEXPECTED" > "$MOCK_DIR/wifi_action"
fi
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    source_switcher

    export CHECK_INTERNET="0"
    switcher_tick

    action=$(cat "$MOCK_DIR/wifi_action" 2>/dev/null || echo "none")
    assert_equals "none" "$action" "WiFi should not be toggled when it is already the active working interface"
    cleanup
}

# ============================================================================
# Test: read_last_state and write_state for failover tracking
# ============================================================================

test_failover_state_tracking() {
    test_start "failover_state_tracking"
    setup

    source_switcher

    # Write ETH_ACTIVE state
    write_state "ETH_ACTIVE"
    eth_state=$(read_last_state)
    assert_equals "ETH_ACTIVE" "$eth_state" "Should read ETH_ACTIVE"

    # Write WIFI_FAILOVER state
    write_state "WIFI_FAILOVER"
    wifi_state=$(read_last_state)
    assert_equals "WIFI_FAILOVER" "$wifi_state" "Should read WIFI_FAILOVER"

    cleanup
}

# ============================================================================
# Run all tests
# ============================================================================

echo "============================================"
echo "macOS Internet Failover Real Unit Tests"
echo "============================================"
echo "Testing ACTUAL failover logic from src/macos/switcher.sh"
echo ""

test_eth_has_internet_disables_wifi
test_eth_loses_internet_enables_wifi
test_eth_disconnected_enables_wifi
test_wifi_failover_has_internet_no_action
test_failover_state_tracking

test_summary
