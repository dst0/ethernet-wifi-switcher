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

    # Override command paths to use mocks
    export NETWORKSETUP="$MOCK_DIR/bin/networksetup"
    export IPCONFIG="$MOCK_DIR/bin/ipconfig"
    export IFCONFIG="$MOCK_DIR/bin/ifconfig"
    export DATE="$MOCK_DIR/bin/date"
    export CHECK_INTERVAL="30"

    # Create date mock
    cat > "$MOCK_DIR/bin/date" << 'EOF'
#!/bin/sh
echo "2026-01-04 12:00:00"
EOF
    chmod +x "$MOCK_DIR/bin/date"
}

test_wait_for_ip_retry_success() {
    test_start "wait_for_ip_retry_success"
    setup

    # Mock: Ethernet is down (no IP)
    # We need to make sure eth_is_up returns false
    # eth_is_up calls: ipconfig getifaddr "$ETH_DEV"

    # Mock: WiFi is initially OFF
    # wifi_is_on calls: networksetup -getairportpower "$WIFI_DEV"
    mock_command "networksetup" "Wi-Fi Power (en0): Off"

    # Custom mock for ipconfig to simulate delay
    # It needs to handle:
    # 1. getifaddr en5 -> empty (eth down)
    # 2. getifaddr en0 -> empty (wifi connecting...)
    # 3. getifaddr en0 -> empty (wifi connecting...)
    # 4. getifaddr en0 -> 192.168.1.50 (wifi connected!)

    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
cmd="$1"
iface="$2"

if [ "$iface" = "en5" ]; then
    # Ethernet UP
    echo "192.168.1.10"
    exit 0
fi

if [ "$iface" = "en0" ]; then
    # WiFi behavior controlled by counter (use fixed file path)
    count_file="/tmp/ipconfig_count_test"
    if [ ! -f "$count_file" ]; then
        echo "0" > "$count_file"
    fi

    count=$(cat "$count_file")
    count=$((count + 1))
    echo "$count" > "$count_file"

    if [ "$count" -lt 4 ]; then
        # First 3 calls return nothing (simulating delay)
        exit 1
    else
        # Afterwards return IP
        echo "192.168.1.50"
        exit 0
    fi
fi
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    # Mock curl to fail for en5, succeed for en0
    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
# Args: --interface enX ...
while [ $# -gt 0 ]; do
    if [ "$1" = "--interface" ]; then
        iface="$2"
        shift 2
    else
        shift
    fi
done

if [ "$iface" = "en5" ]; then
    exit 1 # Fail
elif [ "$iface" = "en0" ]; then
    exit 0 # Success
else
    exit 1
fi
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    # Smart networksetup that tracks state
    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
arg1="$1"
arg2="$2"
arg3="$3"

if [ "$arg1" = "-getairportpower" ]; then
    if [ -f "/tmp/wifi_on_$$" ]; then
        echo "Wi-Fi Power (en0): On"
    else
        echo "Wi-Fi Power (en0): Off"
    fi
elif [ "$arg1" = "-setairportpower" ]; then
    if [ "$arg3" = "on" ]; then
        touch "/tmp/wifi_on_$$"
    else
        rm -f "/tmp/wifi_on_$$"
    fi
fi
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    # Mock sleep to run faster (each sleep counts as 1 second for counter)
    cat > "$MOCK_DIR/bin/sleep" << 'EOF'
#!/bin/sh
# Instant sleep but increment counter for ipconfig simulation
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/sleep"

    # Run script and capture output
    output=$("$SWITCHER_SCRIPT" 2>&1)

    # Assertions
    assert_contains "$output" "Enabling WiFi (en0) to check for internet" "Should log enabling wifi"
    assert_contains "$output" "Waiting for IP address on en0" "Should log waiting for IP"
    assert_contains "$output" "Found working internet on en0" "Should eventually find internet"
    assert_contains "$output" "Switching to WiFi (en0)" "Should switch to wifi"

    # Cleanup
    rm -f "/tmp/ipconfig_count_test" "/tmp/wifi_on_$$"
}

test_wait_for_ip_timeout() {
    test_start "wait_for_ip_timeout"
    setup

    # Reset counter from previous test
    rm -f "/tmp/ipconfig_count_test"

    # Mock: Ethernet is down
    # Mock: WiFi is initially OFF

    # Custom mock for ipconfig that NEVER returns IP for WiFi
    cat > "$MOCK_DIR/bin/ipconfig" << 'EOF'
#!/bin/sh
cmd="$1"
iface="$2"

if [ "$iface" = "en5" ]; then
    # Ethernet UP but will have no internet
    echo "192.168.1.10"
    exit 0
fi

if [ "$iface" = "en0" ]; then
    # WiFi NEVER gets IP
    exit 1
fi
EOF
    chmod +x "$MOCK_DIR/bin/ipconfig"

    # Mock curl to always fail (no internet anywhere)
    cat > "$MOCK_DIR/bin/curl" << 'EOF'
#!/bin/sh
exit 1
EOF
    chmod +x "$MOCK_DIR/bin/curl"

    # Smart networksetup (same as above)
    cat > "$MOCK_DIR/bin/networksetup" << 'EOF'
#!/bin/sh
arg1="$1"
arg2="$2"
arg3="$3"

if [ "$arg1" = "-getairportpower" ]; then
    if [ -f "/tmp/wifi_on_$$" ]; then
        echo "Wi-Fi Power (en0): On"
    else
        echo "Wi-Fi Power (en0): Off"
    fi
elif [ "$arg1" = "-setairportpower" ]; then
    if [ "$arg3" = "on" ]; then
        touch "/tmp/wifi_on_$$"
    else
        rm -f "/tmp/wifi_on_$$"
    fi
fi
EOF
    chmod +x "$MOCK_DIR/bin/networksetup"

    # Run script
    # It should try to enable wifi, wait 15s (mocked fast?), then fail.
    # Since we can't mock `sleep` easily without making the test slow,
    # we might want to override `sleep` in the mock bin to be instant.

    cat > "$MOCK_DIR/bin/sleep" << 'EOF'
#!/bin/sh
# Instant sleep
exit 0
EOF
    chmod +x "$MOCK_DIR/bin/sleep"

    output=$("$SWITCHER_SCRIPT" 2>&1)

    assert_contains "$output" "Waiting for IP address on en0" "Should log waiting for IP"
    assert_contains "$output" "Interface en0 has no IP address" "Should report no IP after timeout"

    # Cleanup
    rm -f "/tmp/wifi_on_$$" "/tmp/ipconfig_count_test"
}

# Run tests
test_wait_for_ip_retry_success
test_wait_for_ip_timeout

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
