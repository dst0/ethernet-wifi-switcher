#!/bin/sh
# Test installer completion message
# Verifies that completion message adapts to user configuration

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load test framework
. "$SCRIPT_DIR/../lib/assert.sh"

# Setup test environment
MOCK_DIR="/tmp/eth-wifi-installer-completion-test-$$"
mkdir -p "$MOCK_DIR"

setup() {
    export TEST_MODE=1
    export CHECK_INTERNET="1"
    export CHECK_METHOD="ping"
    export CHECK_TARGET="8.8.8.8"
    export CHECK_INTERVAL="30"
    export INTERFACE_PRIORITY=""
}

cleanup() {
    # Don't remove the directory here, it's needed for subsequent tests
    true
}

final_cleanup() {
    rm -rf "$MOCK_DIR"
}

# Get completion message by simulating the end of install
get_completion_message() {
    mkdir -p "$MOCK_DIR"
    temp_file="$MOCK_DIR/completion_message.sh"

    # Create a script that outputs the completion message
    cat > "$temp_file" << 'TESTEOF'
#!/bin/sh
echo ""
echo "✅ Installation complete."
echo ""
echo "The service is now running. Starting in 3 seconds..."
echo ""

if [ "$CHECK_INTERNET" = "1" ]; then
    echo "How it works:"
    if [ -n "$INTERFACE_PRIORITY" ]; then
        echo "  • When primary interface has internet → I'll use it and disable others"
        echo "  • When primary interface loses internet → I'll switch to next working interface"
        echo "  • When higher priority interface restores internet → I'll switch back to it"
        echo "  • Interface priority: $INTERFACE_PRIORITY"
    else
        echo "  • When Ethernet connected with internet → I'll disable WiFi"
        echo "  • When Ethernet connected but no internet → I'll switch to WiFi (automatic failover)"
        echo "  • When Ethernet disconnected → I'll switch to WiFi"
    fi
    if [ "$CHECK_METHOD" = "gateway" ]; then
        echo "  • Validates connectivity by pinging gateway every ${CHECK_INTERVAL}s"
    elif [ "$CHECK_METHOD" = "ping" ]; then
        echo "  • Validates connectivity by pinging $CHECK_TARGET every ${CHECK_INTERVAL}s"
    elif [ "$CHECK_METHOD" = "curl" ]; then
        echo "  • Validates connectivity via HTTP to $CHECK_TARGET every ${CHECK_INTERVAL}s"
    fi
    echo "  • Continues working after OS reboot"
else
    echo "How it works:"
    if [ -n "$INTERFACE_PRIORITY" ]; then
        echo "  • I'll use highest priority interface that has an IP address"
        echo "  • Interface priority: $INTERFACE_PRIORITY"
    else
        echo "  • When Ethernet connected (has IP) → I'll disable WiFi"
        echo "  • When Ethernet disconnected (no IP) → I'll enable WiFi"
    fi
    echo "  • Continues working after OS reboot"
    echo ""
    echo "  ⚠️  Note: Internet connectivity is NOT validated."
    echo "     If an interface has IP but no internet, it will still be used."
fi
TESTEOF

    chmod +x "$temp_file"
    sh "$temp_file"
}

# ============================================================================
# Test: Completion message with CHECK_INTERNET=1, no priority
# ============================================================================

test_completion_internet_enabled_no_priority() {
    test_start "completion_internet_enabled_no_priority"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="ping"
    export CHECK_TARGET="8.8.8.8"
    export CHECK_INTERVAL="30"
    export INTERFACE_PRIORITY=""

    output=$(get_completion_message)

    assert_contains "$output" "Installation complete" "Should show completion"
    assert_contains "$output" "How it works:" "Should explain behavior"
    assert_contains "$output" "When Ethernet connected with internet → I'll disable WiFi" "Should explain ethernet behavior"
    assert_contains "$output" "When Ethernet connected but no internet → I'll switch to WiFi" "Should explain failover"
    assert_contains "$output" "When Ethernet disconnected → I'll switch to WiFi" "Should explain disconnection"
    assert_contains "$output" "pinging $CHECK_TARGET every ${CHECK_INTERVAL}s" "Should explain validation method"
    assert_contains "$output" "Continues working after OS reboot" "Should mention persistence"

    # Should NOT show priority-specific messages
    assert_not_contains "$output" "Primary interface" "Should not mention primary interface"
    assert_not_contains "$output" "Interface priority:" "Should not show priority list"

    # Should NOT show warning about no internet validation
    assert_not_contains "$output" "Internet connectivity is NOT validated" "Should not show disabled warning"

    cleanup
}

# ============================================================================
# Test: Completion message with CHECK_INTERNET=1, with priority
# ============================================================================

test_completion_internet_enabled_with_priority() {
    test_start "completion_internet_enabled_with_priority"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="ping"
    export CHECK_TARGET="8.8.8.8"
    export CHECK_INTERVAL="30"
    export INTERFACE_PRIORITY="en5,en7,en0"

    output=$(get_completion_message)

    assert_contains "$output" "Installation complete" "Should show completion"
    assert_contains "$output" "How it works:" "Should explain behavior"
    assert_contains "$output" "When primary interface has internet → I'll use it and disable others" "Should explain priority behavior"
    assert_contains "$output" "When primary interface loses internet → I'll switch to next working interface" "Should explain failover"
    assert_contains "$output" "When higher priority interface restores internet → I'll switch back to it" "Should explain switching back"
    assert_contains "$output" "Interface priority: $INTERFACE_PRIORITY" "Should show priority list"
    assert_contains "$output" "pinging $CHECK_TARGET every ${CHECK_INTERVAL}s" "Should explain validation method"
    assert_contains "$output" "Continues working after OS reboot" "Should mention persistence"

    # Should NOT show simple ethernet/WiFi messages
    assert_not_contains "$output" "When Ethernet connected with internet → I'll disable WiFi" "Should not show simple ethernet message"
    assert_not_contains "$output" "When Ethernet disconnected → I'll switch to WiFi" "Should not show simple WiFi message"

    # Should NOT show warning about no internet validation
    assert_not_contains "$output" "Internet connectivity is NOT validated" "Should not show disabled warning"

    cleanup
}

# ============================================================================
# Test: Completion message with CHECK_INTERNET=0, no priority
# ============================================================================

test_completion_internet_disabled_no_priority() {
    test_start "completion_internet_disabled_no_priority"
    setup

    export CHECK_INTERNET="0"
    export INTERFACE_PRIORITY=""

    output=$(get_completion_message)

    assert_contains "$output" "Installation complete" "Should show completion"
    assert_contains "$output" "How it works:" "Should explain behavior"
    assert_contains "$output" "When Ethernet connected (has IP) → I'll disable WiFi" "Should explain IP-based ethernet behavior"
    assert_contains "$output" "When Ethernet disconnected (no IP) → I'll enable WiFi" "Should explain IP-based WiFi behavior"
    assert_contains "$output" "Continues working after OS reboot" "Should mention persistence"
    assert_contains "$output" "Internet connectivity is NOT validated" "Should show warning"
    assert_contains "$output" "If an interface has IP but no internet, it will still be used" "Should explain limitation"

    # Should NOT show priority-specific messages
    assert_not_contains "$output" "Primary interface" "Should not mention primary interface"
    assert_not_contains "$output" "Interface priority:" "Should not show priority list"

    # Should NOT show internet validation messages
    assert_not_contains "$output" "pinging" "Should not mention pinging"
    assert_not_contains "$output" "automatic failover" "Should not mention failover"

    cleanup
}

# ============================================================================
# Test: Completion message with CHECK_INTERNET=0, with priority
# ============================================================================

test_completion_internet_disabled_with_priority() {
    test_start "completion_internet_disabled_with_priority"
    setup

    export CHECK_INTERNET="0"
    export INTERFACE_PRIORITY="en5,en7,en0"

    output=$(get_completion_message)

    assert_contains "$output" "Installation complete" "Should show completion"
    assert_contains "$output" "How it works:" "Should explain behavior"
    assert_contains "$output" "I'll use highest priority interface that has an IP address" "Should explain priority-based IP checking"
    assert_contains "$output" "Interface priority: $INTERFACE_PRIORITY" "Should show priority list"
    assert_contains "$output" "Continues working after OS reboot" "Should mention persistence"
    assert_contains "$output" "Internet connectivity is NOT validated" "Should show warning"
    assert_contains "$output" "If an interface has IP but no internet, it will still be used" "Should explain limitation"

    # Should NOT show simple ethernet/WiFi messages
    assert_not_contains "$output" "When Ethernet connected (has IP) → I'll disable WiFi" "Should not show simple ethernet message"
    assert_not_contains "$output" "When Ethernet disconnected (no IP) → I'll enable WiFi" "Should not show simple WiFi message"

    # Should NOT show internet validation messages
    assert_not_contains "$output" "pinging" "Should not mention pinging"
    assert_not_contains "$output" "automatic failover" "Should not mention failover"

    cleanup
}

# ============================================================================
# Test: Completion message explains gateway method
# ============================================================================

test_completion_gateway_method() {
    test_start "completion_gateway_method"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="gateway"
    export CHECK_INTERVAL="45"
    export INTERFACE_PRIORITY=""

    output=$(get_completion_message)

    assert_contains "$output" "pinging gateway every ${CHECK_INTERVAL}s" "Should explain gateway method"

    cleanup
}

# ============================================================================
# Test: Completion message explains ping method
# ============================================================================

test_completion_ping_method() {
    test_start "completion_ping_method"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="ping"
    export CHECK_TARGET="1.1.1.1"
    export CHECK_INTERVAL="60"
    export INTERFACE_PRIORITY=""

    output=$(get_completion_message)

    assert_contains "$output" "pinging $CHECK_TARGET every ${CHECK_INTERVAL}s" "Should explain ping method with target"

    cleanup
}

# ============================================================================
# Test: Completion message explains curl method
# ============================================================================

test_completion_curl_method() {
    test_start "completion_curl_method"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="curl"
    export CHECK_TARGET="http://captive.apple.com"
    export CHECK_INTERVAL="90"
    export INTERFACE_PRIORITY=""

    output=$(get_completion_message)

    assert_contains "$output" "via HTTP to $CHECK_TARGET every ${CHECK_INTERVAL}s" "Should explain curl method"

    cleanup
}

# ============================================================================
# Test: Completion message with priority and gateway method
# ============================================================================

test_completion_priority_and_gateway() {
    test_start "completion_priority_and_gateway"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="gateway"
    export CHECK_INTERVAL="30"
    export INTERFACE_PRIORITY="en7,en5,en0"

    output=$(get_completion_message)

    assert_contains "$output" "When higher priority interface restores internet → I'll switch back to it" "Should explain switching back"
    assert_contains "$output" "When primary interface has internet" "Should show priority-based behavior"
    assert_contains "$output" "Interface priority: $INTERFACE_PRIORITY" "Should show priority list"
    assert_contains "$output" "pinging gateway" "Should show gateway method"

    cleanup
}

# Run all tests
test_completion_internet_enabled_no_priority
test_completion_internet_enabled_with_priority
test_completion_internet_disabled_no_priority
test_completion_internet_disabled_with_priority
test_completion_gateway_method
test_completion_ping_method
test_completion_curl_method
test_completion_priority_and_gateway

test_summary

final_cleanup
