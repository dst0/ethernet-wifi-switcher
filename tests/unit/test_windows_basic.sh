#!/bin/sh
set -e

. "$(dirname "$0")/../lib/assert.sh"

SWITCHER_POWERSHELL="$(dirname "$0")/../../src/windows/switcher.ps1"

# Test: File exists
test_file_exists() {
    test_start "windows_file_exists"
    assert_file_exists "$SWITCHER_POWERSHELL" "Windows switcher.ps1 should exist"
}

# Test: Get-EthernetAdapter function
test_get_ethernet_adapter() {
    test_start "windows_get_ethernet_adapter"
    content="$(cat "$SWITCHER_POWERSHELL")"
    assert_contains "$content" "function Get-EthernetAdapter" "Get-EthernetAdapter should be defined"
}

# Test: Get-WifiAdapter function
test_get_wifi_adapter() {
    test_start "windows_get_wifi_adapter"
    content="$(cat "$SWITCHER_POWERSHELL")"
    assert_contains "$content" "function Get-WifiAdapter" "Get-WifiAdapter should be defined"
}

# Test: Test-InternetConnectivity function
test_internet_connectivity() {
    test_start "windows_test_internet_connectivity"
    content="$(cat "$SWITCHER_POWERSHELL")"
    assert_contains "$content" "function Test-InternetConnectivity" "Test-InternetConnectivity should be defined"
}

# Test: Log-Message function
test_log_message() {
    test_start "windows_log_message"
    content="$(cat "$SWITCHER_POWERSHELL")"
    assert_contains "$content" "function Log-Message" "Log-Message should be defined"
}

# Test: CheckInternet variable
test_check_internet_var() {
    test_start "windows_check_internet_var"
    content="$(cat "$SWITCHER_POWERSHELL")"
    assert_contains "$content" "\$CheckInternet =" "CheckInternet variable should be defined"
}

# Test: CheckMethod variable
test_check_method_var() {
    test_start "windows_check_method_var"
    content="$(cat "$SWITCHER_POWERSHELL")"
    assert_contains "$content" "\$CheckMethod =" "CheckMethod variable should be defined"
}

# Test: CheckMethod switch statement
test_check_method_switch() {
    test_start "windows_check_method_switch"
    content="$(cat "$SWITCHER_POWERSHELL")"
    assert_contains "$content" "switch (\$CheckMethod)" "CheckMethod switch statement should exist"
}

# Test: Test-Connection for gateway
test_test_connection() {
    test_start "windows_test_connection"
    content="$(cat "$SWITCHER_POWERSHELL")"
    assert_contains "$content" "Test-Connection" "Test-Connection should be used for gateway check"
}

# Test: Invoke-WebRequest for HTTP check
test_invoke_webrequest() {
    test_start "windows_invoke_webrequest"
    content="$(cat "$SWITCHER_POWERSHELL")"
    assert_contains "$content" "Invoke-WebRequest" "Invoke-WebRequest should be used for HTTP check"
}

# Test: InterfacePriority variable
test_interface_priority_var() {
    test_start "windows_interface_priority_var"
    content="$(cat "$SWITCHER_POWERSHELL")"
    assert_contains "$content" "\$InterfacePriority =" "InterfacePriority variable should be defined"
}

# Test: InterfacePriority split logic
test_interface_priority_split() {
    test_start "windows_interface_priority_split"
    content="$(cat "$SWITCHER_POWERSHELL")"
    assert_contains "$content" "\$InterfacePriority -split ','" "InterfacePriority should be split by comma"
}

echo "Running Windows Basic Tests"
echo "============================"

# Run all tests
test_file_exists
test_get_ethernet_adapter
test_get_wifi_adapter
test_internet_connectivity
test_log_message
test_check_internet_var
test_check_method_var
test_check_method_switch
test_test_connection
test_invoke_webrequest
test_interface_priority_var
test_interface_priority_split

# Summary
test_summary
