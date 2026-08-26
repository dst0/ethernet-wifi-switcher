#!/bin/sh
# Real integration-style tests for macOS complex scenarios
# Tests actual state machine behavior from src/macos/switcher.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../lib/mock.sh"

# Setup test environment
setup() {
    MOCK_DIR="/tmp/macos-complex-test-$$"
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
    export ETH_RETRY_INTERVAL="0"

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
# Test: Full ethernet connection sequence
# ============================================================================

test_full_eth_connect_sequence() {
    test_start "full_eth_connect_sequence"
    setup

    # Initial state: WiFi on, ethernet active with IP
    echo "on" > "$MOCK_DIR/wifi_state"

    cat > "$MOCK_DIR/bin/networksetup" << EOF
#!/bin/sh
MOCK_DIR="$MOCK_DIR"
if [ "\$1" = "-getairportpower" ]; then
    state=\$(cat "\$MOCK_DIR/wifi_state")
    if [ "\$state" = "on" ]; then
        echo "Wi-Fi Power (en0): On"
    else
        echo "Wi-Fi Power (en0): Off"
    fi
elif [ "\$1" = "-setairportpower" ]; then
    echo "\$3" > "\$MOCK_DIR/wifi_state"
fi
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
if [ "$1" = "en5" ]; then
    echo "en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST>"
    echo "\tstatus: active"
    echo "\tinet 192.168.1.100 netmask 0xffffff00"
fi
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
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

    source_switcher

    # Real orchestration
    switcher_tick

    final_state=$(read_last_state)
    final_wifi=$(cat "$MOCK_DIR/wifi_state")

    assert_equals "connected" "$final_state" "State should be connected"
    assert_equals "off" "$final_wifi" "WiFi should be off"
    cleanup
}

# ============================================================================
# Test: Ethernet disconnect and failover
# ============================================================================

test_eth_disconnect_failover() {
    test_start "eth_disconnect_failover"
    setup

    # Initial state: Ethernet previously connected, WiFi off
    echo "connected" > "$STATE_FILE"
    echo "off" > "$MOCK_DIR/wifi_state"

    cat > "$MOCK_DIR/bin/networksetup" << EOF
#!/bin/sh
MOCK_DIR="$MOCK_DIR"
if [ "\$1" = "-getairportpower" ]; then
    state=\$(cat "\$MOCK_DIR/wifi_state")
    if [ "\$state" = "on" ]; then
        echo "Wi-Fi Power (en0): On"
    else
        echo "Wi-Fi Power (en0): Off"
    fi
elif [ "\$1" = "-setairportpower" ]; then
    echo "\$3" > "\$MOCK_DIR/wifi_state"
fi
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    # Ethernet disconnected - no link
    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
if [ "$1" = "en5" ]; then
  echo "en5: flags=8822<BROADCAST,SMART,SIMPLEX,MULTICAST>"
  echo "\tstatus: inactive"
fi
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    # No IP on ethernet, no IP on wifi yet
    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    source_switcher

    export CHECK_INTERNET="0"
    switcher_tick

    final_state=$(read_last_state)
    final_wifi=$(cat "$MOCK_DIR/wifi_state")

    assert_equals "disconnected" "$final_state" "State should be disconnected"
    assert_equals "on" "$final_wifi" "WiFi should be on"
    cleanup
}

# ============================================================================
# Test: Internet loss triggers failover
# ============================================================================

test_internet_loss_triggers_failover() {
    test_start "internet_loss_triggers_failover"
    setup

    # Previous state: connected
    echo "connected" > "$STATE_FILE"
    echo "off" > "$MOCK_DIR/wifi_state"

    cat > "$MOCK_DIR/bin/networksetup" << EOF
#!/bin/sh
MOCK_DIR="$MOCK_DIR"
if [ "\$1" = "-getairportpower" ]; then
    state=\$(cat "\$MOCK_DIR/wifi_state")
    if [ "\$state" = "on" ]; then
        echo "Wi-Fi Power (en0): On"
    else
        echo "Wi-Fi Power (en0): Off"
    fi
elif [ "\$1" = "-setairportpower" ]; then
    echo "\$3" > "\$MOCK_DIR/wifi_state"
fi
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
if [ "$1" = "en5" ]; then
  echo "en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST>"
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

    # gateway ping fails -> no internet on active eth
    cat > "$MOCK_DIR/bin/ping" << 'EOF'
#!/bin/sh
exit 1
EOF
    chmod +x "$MOCK_DIR/bin/ping"

    # inactive interface checks use curl -> make wifi succeed
    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    export INTERFACE_PRIORITY="en5,en0"

    source_switcher

    switcher_tick

    final_state=$(read_last_state)
    final_wifi=$(cat "$MOCK_DIR/wifi_state")

    assert_equals "disconnected" "$final_state" "Should switch state to disconnected (WiFi active)"
    assert_equals "on" "$final_wifi" "WiFi should be on for failover"
    cleanup
}

# ============================================================================
# Test: Recovery from failover
# ============================================================================

test_recovery_from_failover() {
    test_start "recovery_from_failover"
    setup

    # Previous state: disconnected (WiFi active)
    echo "disconnected" > "$STATE_FILE"
    echo "on" > "$MOCK_DIR/wifi_state"

    cat > "$MOCK_DIR/bin/networksetup" << EOF
#!/bin/sh
MOCK_DIR="$MOCK_DIR"
if [ "\$1" = "-getairportpower" ]; then
    state=\$(cat "\$MOCK_DIR/wifi_state")
    if [ "\$state" = "on" ]; then
        echo "Wi-Fi Power (en0): On"
    else
        echo "Wi-Fi Power (en0): Off"
    fi
elif [ "\$1" = "-setairportpower" ]; then
    echo "\$3" > "\$MOCK_DIR/wifi_state"
fi
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
if [ "$1" = "en5" ]; then
  echo "en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST>"
  echo "\tstatus: active"
  echo "\tinet 192.168.1.100 netmask 0xffffff00"
fi
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
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

    source_switcher

    switcher_tick

    final_state=$(read_last_state)
    final_wifi=$(cat "$MOCK_DIR/wifi_state")

    assert_equals "connected" "$final_state" "Should recover to ethernet (connected)"
    assert_equals "off" "$final_wifi" "WiFi should be off after recovery"
    cleanup
}

# ============================================================================
# Test: No action when already in correct state
# ============================================================================

test_no_action_when_correct_state() {
    test_start "no_action_when_correct_state"
    setup

    # Ethernet connected, WiFi already off
    echo "connected" > "$STATE_FILE"
    echo "off" > "$MOCK_DIR/wifi_state"

    cat > "$MOCK_DIR/bin/networksetup" << EOF
#!/bin/sh
MOCK_DIR="$MOCK_DIR"
if [ "\$1" = "-getairportpower" ]; then
    echo "Wi-Fi Power (en0): Off"
elif [ "\$1" = "-setairportpower" ]; then
    echo "UNEXPECTED_WIFI_CHANGE" > "\$MOCK_DIR/unexpected_action"
fi
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    cat > "$MOCK_DIR/bin/ifconfig" << 'EOF'
#!/bin/sh
if [ "$1" = "en5" ]; then
  echo "en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST>"
  echo "\tstatus: active"
  echo "\tinet 192.168.1.100 netmask 0xffffff00"
fi
EOF
    chmod +x "$MOCK_DIR/bin/ifconfig"

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
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

    source_switcher

    switcher_tick

    had_action=$( [ -f "$MOCK_DIR/unexpected_action" ] && echo "yes" || echo "no" )

    assert_equals "no" "$had_action" "No WiFi action when already in correct state"
    cleanup
}

# ============================================================================
# Run all tests
# ============================================================================

echo "============================================"
echo "macOS Complex Scenarios Real Unit Tests"
echo "============================================"
echo "Testing ACTUAL state machine behavior from src/macos/switcher.sh"
echo ""

test_full_eth_connect_sequence
test_eth_disconnect_failover
test_internet_loss_triggers_failover
test_recovery_from_failover
test_no_action_when_correct_state

test_summary
