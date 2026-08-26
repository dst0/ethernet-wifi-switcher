#!/bin/sh
set -e

# Load test framework
. "$(dirname "$0")/../lib/assert.sh"

LINUX_SWITCHER="$(dirname "$0")/../../src/linux/switcher.sh"

# Test: Verify ensure_wifi_on_and_wait function exists
test_ensure_wifi_function_exists() {
    test_start "ensure_wifi_function_exists"

    content=$(cat "$LINUX_SWITCHER")
    assert_contains "$content" "ensure_wifi_on_and_wait" "Should have ensure_wifi_on_and_wait function"
}

# Test: Verify retry logic in ensure_wifi_on_and_wait
test_ensure_wifi_has_retry_logic() {
    test_start "ensure_wifi_has_retry_logic"

    content=$(cat "$LINUX_SWITCHER")
    assert_contains "$content" "max_wait_retries=15" "Should wait up to 15 retries"
    assert_contains "$content" "wait_retries=0" "Should initialize retry counter"
}

# Test: Verify CHECK_INTERVAL is defined
test_check_interval_defined() {
    test_start "check_interval_defined"

    content=$(cat "$LINUX_SWITCHER")
    assert_contains "$content" "CHECK_INTERVAL" "Should have CHECK_INTERVAL variable"
}

# Test: Verify internet check logging
test_internet_check_logging() {
    test_start "internet_check_logging"

    content=$(cat "$LINUX_SWITCHER")
    assert_contains "$content" "LOG_ALL_CHECKS" "Should have LOG_ALL_CHECKS variable"
    assert_contains "$content" "Internet check:" "Should log internet check attempts"
}

# Test: Verify priority-based interface checking
test_priority_interface_checking() {
    test_start "priority_interface_checking"

    content=$(cat "$LINUX_SWITCHER")
    assert_contains "$content" "INTERFACE_PRIORITY" "Should support INTERFACE_PRIORITY"
    assert_contains "$content" "higher priority interfaces" "Should check higher priority interfaces"
}

# Test: Verify state file persistence
test_state_file_handling() {
    test_start "state_file_handling"

    content=$(cat "$LINUX_SWITCHER")
    assert_contains "$content" "write_state" "Should have write_state function"
    assert_contains "$content" "read_last_state" "Should have read_last_state function"
}

# Test: Verify failover logic
test_failover_logic_present() {
    test_start "failover_logic_present"

    content=$(cat "$LINUX_SWITCHER")
    assert_contains "$content" "NO internet, searching for alternatives" "Should search for alternatives"
    assert_contains "$content" "keeping current:" "Should keep current if no alternative"
}

# Run tests
test_ensure_wifi_function_exists
test_ensure_wifi_has_retry_logic
test_check_interval_defined
test_internet_check_logging
test_priority_interface_checking
test_state_file_handling
test_failover_logic_present

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
