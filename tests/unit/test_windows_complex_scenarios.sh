#!/bin/sh
set -e

# Load test framework
. "$(dirname "$0")/../lib/assert.sh"

WINDOWS_SWITCHER="$(dirname "$0")/../../src/windows/switcher.ps1"

# Test: Verify Ensure-WifiOnAndWait function exists
test_ensure_wifi_function_exists() {
    test_start "ensure_wifi_function_exists"

    content=$(cat "$WINDOWS_SWITCHER")
    assert_contains "$content" "Ensure-WifiOnAndWait" "Should have Ensure-WifiOnAndWait function"
}

# Test: Verify retry logic in Ensure-WifiOnAndWait
test_ensure_wifi_has_retry_logic() {
    test_start "ensure_wifi_has_retry_logic"

    content=$(cat "$WINDOWS_SWITCHER")
    assert_contains "$content" "\$maxRetries = 15" "Should wait up to 15 retries"
    assert_contains "$content" "\$retries = 0" "Should initialize retry counter"
}

# Test: Verify CHECK_INTERVAL is defined
test_check_interval_defined() {
    test_start "check_interval_defined"

    content=$(cat "$WINDOWS_SWITCHER")
    assert_contains "$content" "CheckInterval" "Should have CheckInterval variable"
}

# Test: Verify internet check logging
test_internet_check_logging() {
    test_start "internet_check_logging"

    content=$(cat "$WINDOWS_SWITCHER")
    assert_contains "$content" "LogCheckAttempts" "Should have LogCheckAttempts variable"
    assert_contains "$content" "Internet check:" "Should log internet check attempts"
}

# Test: Verify priority-based interface checking
test_priority_interface_checking() {
    test_start "priority_interface_checking"

    content=$(cat "$WINDOWS_SWITCHER")
    assert_contains "$content" "InterfacePriority" "Should support InterfacePriority"
    assert_contains "$content" "higher priority interfaces" "Should check higher priority interfaces"
}

# Test: Verify state file handling
test_state_file_handling() {
    test_start "state_file_handling"

    content=$(cat "$WINDOWS_SWITCHER")
    assert_contains "$content" "Write-State" "Should have Write-State function"
    assert_contains "$content" "Read-LastState" "Should have Read-LastState function"
}

# Test: Verify failover logic
test_failover_logic_present() {
    test_start "failover_logic_present"

    content=$(cat "$WINDOWS_SWITCHER")
    assert_contains "$content" "NO internet" "Should detect no internet"
    assert_contains "$content" "alternatives" "Should search for alternatives"
}

# Test: Verify Test-InternetConnectivity function
test_internet_connectivity_function() {
    test_start "internet_connectivity_function"

    content=$(cat "$WINDOWS_SWITCHER")
    assert_contains "$content" "Test-InternetConnectivity" "Should have Test-InternetConnectivity function"
    assert_contains "$content" "CheckMethod" "Should support different check methods"
}

# Test: Verify WiFi power management
test_wifi_power_management() {
    test_start "wifi_power_management"

    content=$(cat "$WINDOWS_SWITCHER")
    assert_contains "$content" "Set-WifiSoftState" "Should have Set-WifiSoftState function"
    assert_contains "$content" "Test-WifiNeedsEnable" "Should have Test-WifiNeedsEnable function"
}

# Run tests
test_ensure_wifi_function_exists
test_ensure_wifi_has_retry_logic
test_check_interval_defined
test_internet_check_logging
test_priority_interface_checking
test_state_file_handling
test_failover_logic_present
test_internet_connectivity_function
test_wifi_power_management

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
