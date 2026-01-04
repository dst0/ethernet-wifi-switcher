#!/bin/sh
# macOS-specific internet state logging tests
# Note: Not using set -e to allow testing failure cases

# Load test framework
. "$(dirname "$0")/../lib/assert.sh"

# Mock check_internet function with state tracking (macOS-specific)
check_internet_with_state_tracking() {
    iface="$1"
    result="$2"  # 0 for success, 1 for failure

    STATE_FILE="${STATE_FILE:-/tmp/test-eth-wifi-state}"
    LAST_CHECK_STATE_FILE="${STATE_FILE}.last_check"

    # Log state changes (always logged regardless of LOG_CHECK_ATTEMPTS)
    last_check_state=$(cat "$LAST_CHECK_STATE_FILE" 2>/dev/null || echo "")
    current_check_state="success"
    if [ $result -ne 0 ]; then
        current_check_state="failed"
    fi

    if [ -z "$last_check_state" ]; then
        # First run - initialize state with specific message based on result
        if [ "$current_check_state" = "success" ]; then
            echo "Internet check: $iface is active and has internet"
        else
            echo "Internet check: $iface connection is not active"
        fi
        echo "$current_check_state" > "$LAST_CHECK_STATE_FILE"
    elif [ "$last_check_state" != "$current_check_state" ]; then
        # State changed - log the transition
        if [ "$current_check_state" = "success" ]; then
            echo "Internet check: $iface is now reachable (recovered from failure)"
        else
            echo "Internet check: $iface is now unreachable (was working before)"
        fi
        echo "$current_check_state" > "$LAST_CHECK_STATE_FILE"
    fi

    return $result
}

setup() {
    STATE_FILE="/tmp/test-eth-wifi-state-$$"
    LAST_CHECK_STATE_FILE="${STATE_FILE}.last_check"
    rm -f "$STATE_FILE" "$LAST_CHECK_STATE_FILE"
}

teardown() {
    rm -f "$STATE_FILE" "$LAST_CHECK_STATE_FILE"
}

# Test: First initialization with successful internet check
test_initialization_with_internet() {
    test_start "initialization_with_internet"
    setup

    output=$(check_internet_with_state_tracking "en5" 0)

    assert_contains "$output" "is active and has internet" "Should show active with internet on first success"

    # Verify state file was created
    state=$(cat "$LAST_CHECK_STATE_FILE" 2>/dev/null || echo "missing")
    assert_equals "success" "$state" "State file should contain 'success'"

    teardown
}

# Test: First initialization with failed internet check
test_initialization_without_internet() {
    test_start "initialization_without_internet"
    setup

    output=$(check_internet_with_state_tracking "en5" 1)

    assert_contains "$output" "connection is not active" "Should show not active on first failure"

    # Verify state file was created
    state=$(cat "$LAST_CHECK_STATE_FILE" 2>/dev/null || echo "missing")
    assert_equals "failed" "$state" "State file should contain 'failed'"

    teardown
}

# Test: Recovery from failure (failed -> success)
test_recovery_from_failure() {
    test_start "recovery_from_failure"
    setup

    # First call - initialize with failure
    check_internet_with_state_tracking "en5" 1 >/dev/null

    # Second call - recover
    output=$(check_internet_with_state_tracking "en5" 0)

    assert_contains "$output" "recovered from failure" "Should show recovery message"

    # Verify state changed to success
    state=$(cat "$LAST_CHECK_STATE_FILE")
    assert_equals "success" "$state" "State should be 'success' after recovery"

    teardown
}

# Test: Loss of internet (success -> failed)
test_loss_of_internet() {
    test_start "loss_of_internet"
    setup

    # First call - initialize with success
    check_internet_with_state_tracking "en5" 0 >/dev/null

    # Second call - lose internet
    output=$(check_internet_with_state_tracking "en5" 1)

    assert_contains "$output" "was working before" "Should show loss message"

    # Verify state changed to failed
    state=$(cat "$LAST_CHECK_STATE_FILE")
    assert_equals "failed" "$state" "State should be 'failed' after loss"

    teardown
}

# Test: No logging when same state (success -> success)
test_no_logging_same_state_success() {
    test_start "no_logging_same_state_success"
    setup

    # First call - initialize with success
    check_internet_with_state_tracking "en5" 0 >/dev/null

    # Second call - same state
    output=$(check_internet_with_state_tracking "en5" 0)

    assert_equals "" "$output" "Should produce no output when state unchanged"

    teardown
}

# Test: No logging when same state (failed -> failed)
test_no_logging_same_state_failed() {
    test_start "no_logging_same_state_failed"
    setup

    # First call - initialize with failure
    check_internet_with_state_tracking "en5" 1 >/dev/null

    # Second call - same state
    output=$(check_internet_with_state_tracking "en5" 1)

    assert_equals "" "$output" "Should produce no output when state unchanged"

    teardown
}

# Test: Multiple state changes
test_multiple_state_changes() {
    test_start "multiple_state_changes"
    setup

    # Change 1: Initialize with success
    out1=$(check_internet_with_state_tracking "en5" 0)
    assert_contains "$out1" "is active and has internet"

    # Change 2: Lose internet
    out2=$(check_internet_with_state_tracking "en5" 1)
    assert_contains "$out2" "was working before"

    # Change 3: Recover
    out3=$(check_internet_with_state_tracking "en5" 0)
    assert_contains "$out3" "recovered from failure"

    # Change 4: Same state
    out4=$(check_internet_with_state_tracking "en5" 0)
    assert_equals "" "$out4" "No output on same state"

    teardown
}

# Run all tests
test_initialization_with_internet
test_initialization_without_internet
test_recovery_from_failure
test_loss_of_internet
test_no_logging_same_state_success
test_no_logging_same_state_failed
test_multiple_state_changes

# Print summary
test_summary
