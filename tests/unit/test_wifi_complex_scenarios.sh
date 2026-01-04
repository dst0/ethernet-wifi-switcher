#!/bin/sh
set -e

# Load test framework
. "$(dirname "$0")/../lib/mock.sh"
. "$(dirname "$0")/../lib/assert.sh"

SWITCHER_SCRIPT="$(dirname "$0")/../../src/macos/switcher.sh"

setup() {
    clear_mocks
    setup_mocks
    mock_state_dir

    # Default environment
    export WIFI_DEV="en0"
    export ETH_DEV="en5"
    export CHECK_INTERNET="1"
    export CHECK_METHOD="curl"
    export LOG_CHECK_ATTEMPTS="1"
    export INTERFACE_PRIORITY="en5,en0"
    export CHECK_INTERVAL="30"

    # Override command paths
    export NETWORKSETUP="$MOCK_DIR/bin/networksetup"
    export IPCONFIG="$MOCK_DIR/bin/ipconfig"
    export IFCONFIG="$MOCK_DIR/bin/ifconfig"
    export DATE="$MOCK_DIR/bin/date"

    # Create date mock
    cat > "$MOCK_DIR/bin/date" << 'EOF'
#!/bin/sh
echo "2026-01-04 12:00:00"
EOF
    chmod +x "$MOCK_DIR/bin/date"

    # Create sleep mock (instant)
    cat > "$MOCK_DIR/bin/sleep" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/sleep"
}

# Test: WiFi already ON when script tries to enable it
test_wifi_already_on_no_redundant_enable() {
    test_start "wifi_already_on_no_redundant_enable"
    setup

    # Ethernet fails internet check, WiFi is ALREADY ON and has IP
    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
iface="$2"
if [ "$iface" = "en5" ]; then
    echo "192.168.1.10"
    exit 0
elif [ "$iface" = "en0" ]; then
    echo "192.168.1.50"
    exit 0
fi
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    # WiFi is already ON
    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
if [ "$1" = "-getairportpower" ]; then
    echo "Wi-Fi Power (en0): On"
elif [ "$1" = "-setairportpower" ]; then
    echo "UNEXPECTED: Should not try to enable WiFi that's already on!" >&2
    exit 1
fi
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    # Ethernet fails, WiFi succeeds
    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do
    if [ "$1" = "--interface" ]; then
        iface="$2"
        shift 2
    else
        shift
    fi
done
if [ "$iface" = "en5" ]; then
    exit 1
elif [ "$iface" = "en0" ]; then
    exit 0
fi
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    output=$("$SWITCHER_SCRIPT" 2>&1)

    # Should NOT contain "Enabling WiFi" since it's already on
    if echo "$output" | grep -q "Enabling WiFi"; then
        assert_equals "should_not_enable" "did_enable" "Should not try to enable WiFi that's already on"
    else
        assert_equals "skip_enable" "skip_enable" "Correctly skips enabling WiFi when already on"
    fi

    assert_contains "$output" "Switching to WiFi" "Should switch to WiFi"
}

# Test: WiFi enabled but not connected (no IP yet)
test_wifi_on_but_no_ip_yet() {
    test_start "wifi_on_but_no_ip_yet"
    setup

    # Ethernet has IP but no internet
    # WiFi is ON but has NO IP
    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
iface="$2"
if [ "$iface" = "en5" ]; then
    echo "192.168.1.10"
    exit 0
elif [ "$iface" = "en0" ]; then
    # WiFi has no IP
    exit 1
fi
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    # WiFi is ON
    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
if [ "$1" = "-getairportpower" ]; then
    echo "Wi-Fi Power (en0): On"
fi
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    # No internet anywhere
    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 1
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    output=$("$SWITCHER_SCRIPT" 2>&1)

    assert_contains "$output" "Interface en0 has no IP address" "Should detect WiFi has no IP"
    assert_contains "$output" "keeping current: en5" "Should keep current interface"
}

# Test: Ethernet recovers during WiFi failover
test_eth_recovers_during_wifi_failover() {
    test_start "eth_recovers_during_wifi_failover"
    setup

    # Initially: Ethernet has IP but no internet
    # WiFi will eventually work
    # Simulates Ethernet recovering while checking WiFi
    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
iface="$2"
if [ "$iface" = "en5" ]; then
    echo "192.168.1.10"
    exit 0
elif [ "$iface" = "en0" ]; then
    echo "192.168.1.50"
    exit 0
fi
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
if [ "$1" = "-getairportpower" ]; then
    if [ -f "/tmp/wifi_on_$$" ]; then
        echo "Wi-Fi Power (en0): On"
    else
        echo "Wi-Fi Power (en0): Off"
    fi
elif [ "$1" = "-setairportpower" ]; then
    if [ "$3" = "on" ]; then
        touch "/tmp/wifi_on_$$"
    else
        rm -f "/tmp/wifi_on_$$"
    fi
fi
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    # Both have internet (Ethernet recovered)
    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    output=$("$SWITCHER_SCRIPT" 2>&1)

    # Should keep Ethernet (higher priority)
    assert_contains "$output" "Active interface en5 has internet" "Ethernet should have internet"
}

# Test: WiFi loses internet after being active
test_wifi_active_loses_internet() {
    test_start "wifi_active_loses_internet"
    setup

    # WiFi is active but has no internet
    # Ethernet is down
    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
iface="$2"
if [ "$iface" = "en5" ]; then
    # Ethernet down
    exit 1
elif [ "$iface" = "en0" ]; then
    # WiFi has IP
    echo "192.168.1.50"
    exit 0
fi
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
if [ "$1" = "-getairportpower" ]; then
    echo "Wi-Fi Power (en0): On"
fi
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    # No internet anywhere
    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 1
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    output=$("$SWITCHER_SCRIPT" 2>&1)

    assert_contains "$output" "Active interface en0" "WiFi should be detected as active"
    assert_contains "$output" "NO internet" "Should detect no internet"
    assert_contains "$output" "keeping current: en0" "Should keep WiFi active (no alternative)"
}

# Test: Multiple interfaces in priority order
test_three_interfaces_priority() {
    test_start "three_interfaces_priority"
    setup

    export INTERFACE_PRIORITY="en5,en4,en0"

    # en5 has IP but no internet
    # en4 has IP and internet (should be chosen)
    # en0 also has internet but lower priority
    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
iface="$2"
case "$iface" in
    en5) echo "192.168.1.10"; exit 0 ;;
    en4) echo "192.168.2.10"; exit 0 ;;
    en0) echo "192.168.3.10"; exit 0 ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
if [ "$1" = "-getairportpower" ]; then
    echo "Wi-Fi Power (en0): On"
fi
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    # en5 fails, en4 succeeds, en0 succeeds
    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do
    if [ "$1" = "--interface" ]; then
        iface="$2"
        shift 2
    else
        shift
    fi
done
case "$iface" in
    en5) exit 1 ;;
    en4) exit 0 ;;
    en0) exit 0 ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    output=$("$SWITCHER_SCRIPT" 2>&1)

    assert_contains "$output" "Found working internet on en4" "Should find en4 has internet"
    # Should NOT switch to en0 even though it has internet (en4 is higher priority)
}

# Test: WiFi takes long to get IP but eventually succeeds
test_wifi_delayed_ip_success() {
    test_start "wifi_delayed_ip_success"
    setup

    rm -f "/tmp/ipconfig_count_complex"

    # Ethernet fails
    # WiFi gets IP after 5 attempts
    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
iface="$2"
if [ "$iface" = "en5" ]; then
    echo "192.168.1.10"
    exit 0
elif [ "$iface" = "en0" ]; then
    count_file="/tmp/ipconfig_count_complex"
    if [ ! -f "$count_file" ]; then
        echo "0" > "$count_file"
    fi
    count=$(cat "$count_file")
    count=$((count + 1))
    echo "$count" > "$count_file"

    if [ "$count" -lt 5 ]; then
        exit 1
    else
        echo "192.168.1.50"
        exit 0
    fi
fi
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
if [ "$1" = "-getairportpower" ]; then
    if [ -f "/tmp/wifi_on_$$" ]; then
        echo "Wi-Fi Power (en0): On"
    else
        echo "Wi-Fi Power (en0): Off"
    fi
elif [ "$1" = "-setairportpower" ]; then
    if [ "$3" = "on" ]; then
        touch "/tmp/wifi_on_$$"
    fi
fi
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    # Ethernet fails, WiFi succeeds
    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do
    if [ "$1" = "--interface" ]; then
        iface="$2"
        shift 2
    else
        shift
    fi
done
if [ "$iface" = "en5" ]; then
    exit 1
elif [ "$iface" = "en0" ]; then
    exit 0
fi
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    output=$("$SWITCHER_SCRIPT" 2>&1)

    assert_contains "$output" "Waiting for IP address on en0" "Should wait for IP"
    assert_contains "$output" "Found working internet on en0" "Should eventually find WiFi"
    assert_contains "$output" "Switching to WiFi" "Should switch to WiFi"

    rm -f "/tmp/ipconfig_count_complex" "/tmp/wifi_on_$$"
}

# Test: State file persistence
test_state_file_persistence() {
    test_start "state_file_persistence"
    setup

    # Ethernet is active with internet
    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
iface="$2"
if [ "$iface" = "en5" ]; then
    echo "192.168.1.10"
    exit 0
fi
exit 1
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
if [ "$1" = "-getairportpower" ]; then
    echo "Wi-Fi Power (en0): On"
elif [ "$1" = "-setairportpower" ] && [ "$3" = "off" ]; then
    # Just log, don't actually track state for this test
    exit 0
fi
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    output=$("$SWITCHER_SCRIPT" 2>&1)

    # Check state file was written
    if [ -f "$STATE_FILE" ]; then
        state=$(cat "$STATE_FILE")
        assert_equals "connected" "$state" "State file should contain 'connected'"
    else
        assert_equals "exists" "missing" "State file should exist"
    fi
}

# Run tests
test_wifi_already_on_no_redundant_enable
test_wifi_on_but_no_ip_yet
test_eth_recovers_during_wifi_failover
test_wifi_active_loses_internet
test_three_interfaces_priority
test_wifi_delayed_ip_success
test_state_file_persistence

# Finalize last test
if [ -n "$CURRENT_TEST" ]; then
    test_end
fi

# Print summary
echo ""
echo "=================================="
echo "Test Summary"
echo "=================================="
echo "Tests: $TEST_PASS_COUNT passed ($TEST_COUNT total)"
echo "=================================="

if [ $TEST_FAIL_COUNT -gt 0 ]; then
    exit 1
fi
