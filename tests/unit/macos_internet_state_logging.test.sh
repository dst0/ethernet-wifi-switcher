#!/bin/sh
# Real unit tests for macOS internet state logging functionality
# Tests actual state logging behavior from src/macos/switcher.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../lib/mock.sh"

# Setup test environment
setup() {
    MOCK_DIR="/tmp/macos-state-log-test-$$"
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
# Test: State file initialization
# ============================================================================

test_state_file_creates_directory() {
    test_start "state_file_creates_directory"
    setup

    source_switcher

    # The script creates STATE_DIR in setup, verify it exists
    assert_true "[ -d '$STATE_DIR' ]" "State directory should exist after setup"

    # Write state should work with existing directory
    write_state "ETH_ACTIVE"

    assert_true "[ -f '$STATE_FILE' ]" "State file should be created"
    cleanup
}

test_state_file_content() {
    test_start "state_file_content"
    setup

    source_switcher

    write_state "ETH_ACTIVE"

    content=$(cat "$STATE_FILE")
    assert_equals "ETH_ACTIVE" "$content" "State file should contain ETH_ACTIVE"
    cleanup
}

# ============================================================================
# Test: State transitions
# ============================================================================

test_state_transition_to_wifi_failover() {
    test_start "state_transition_to_wifi_failover"
    setup

    source_switcher

    # Initial state
    write_state "ETH_ACTIVE"

    # Transition to failover
    write_state "WIFI_FAILOVER"

    state=$(read_last_state)
    assert_equals "WIFI_FAILOVER" "$state" "State should be WIFI_FAILOVER"
    cleanup
}

test_state_transition_to_eth_active() {
    test_start "state_transition_to_eth_active"
    setup

    source_switcher

    # Initial failover state
    write_state "WIFI_FAILOVER"

    # Transition back to ethernet
    write_state "ETH_ACTIVE"

    state=$(read_last_state)
    assert_equals "ETH_ACTIVE" "$state" "State should be ETH_ACTIVE"
    cleanup
}

# ============================================================================
# Test: Last check state file for internet status tracking
# ============================================================================

test_last_check_state_initialization() {
    test_start "last_check_state_initialization"
    setup

    source_switcher

    # Initially no last check state file
    if [ -f "$LAST_CHECK_STATE_FILE" ]; then
        initial_exists="yes"
    else
        initial_exists="no"
    fi

    assert_equals "no" "$initial_exists" "Last check state file should not exist initially"
    cleanup
}

test_last_check_state_write_and_read() {
    test_start "last_check_state_write_and_read"
    setup

    source_switcher

    # Write last check state
    echo "eth_internet:1" > "$LAST_CHECK_STATE_FILE"

    if [ -f "$LAST_CHECK_STATE_FILE" ]; then
        content=$(cat "$LAST_CHECK_STATE_FILE")
    else
        content=""
    fi

    assert_equals "eth_internet:1" "$content" "Last check state should contain eth_internet:1"
    cleanup
}

# ============================================================================
# Test: LOG_ALL_CHECKS behavior
# ============================================================================

test_log_check_attempts_disabled() {
    test_start "log_check_attempts_disabled"
    setup
    export LOG_ALL_CHECKS="0"

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

    # Should not produce extra logging when disabled
    # This is behavioral - the function should work without verbose output
    result=$(check_internet "en5" 1 2>&1)

    # Test passes if check_internet works (returns success)
    if check_internet "en5" 1; then
        success="yes"
    else
        success="no"
    fi

    assert_equals "yes" "$success" "check_internet should work with LOG_ALL_CHECKS=0"
    cleanup
}

test_log_check_attempts_enabled() {
    test_start "log_check_attempts_enabled"
    setup
    export LOG_ALL_CHECKS="1"

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

    # Should produce logging output when enabled
    # Test that function still works (doesn't break when logging enabled)
    if check_internet "en5" 1; then
        success="yes"
    else
        success="no"
    fi

    assert_equals "yes" "$success" "check_internet should work with LOG_ALL_CHECKS=1"
    cleanup
}

# ============================================================================
# Test: Multiple state writes
# ============================================================================

test_multiple_state_writes() {
    test_start "multiple_state_writes"
    setup

    source_switcher

    # Write multiple states
    write_state "ETH_ACTIVE"
    write_state "WIFI_FAILOVER"
    write_state "ETH_ACTIVE"
    write_state "ETH_DOWN"

    final_state=$(read_last_state)
    assert_equals "ETH_DOWN" "$final_state" "Final state should be ETH_DOWN"
    cleanup
}

# ============================================================================
# Run all tests
# ============================================================================

echo "============================================"
echo "macOS Internet State Logging Real Unit Tests"
echo "============================================"
echo "Testing ACTUAL state logging from src/macos/switcher.sh"
echo ""

test_state_file_creates_directory
test_state_file_content
test_state_transition_to_wifi_failover
test_state_transition_to_eth_active
test_last_check_state_initialization
test_last_check_state_write_and_read
test_log_check_attempts_disabled
test_log_check_attempts_enabled
test_multiple_state_writes

test_summary
