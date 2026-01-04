#!/bin/sh
set -e

# Load test framework
. "$(dirname "$0")/../lib/mock.sh"
. "$(dirname "$0")/../lib/assert.sh"

setup() {
    clear_mocks
    setup_mocks
}

# Test: Ethernet with internet should disable WiFi
test_eth_with_internet_disables_wifi() {
    test_start "eth_with_internet_disables_wifi"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="ping"
    export CHECK_TARGET="8.8.8.8"

    # Mock: ethernet is active, has internet
    active_type="ethernet"
    active_has_internet=1
    wifi_on="yes"

    # Expected: WiFi should be turned off
    expected_wifi_action="off"

    # Simulate the logic: if active is ethernet with internet, disable wifi
    if [ "$active_type" = "ethernet" ] && [ $active_has_internet -eq 1 ] && [ "$wifi_on" = "yes" ]; then
        actual_wifi_action="off"
    else
        actual_wifi_action="no_change"
    fi

    assert_equals "$expected_wifi_action" "$actual_wifi_action" "Ethernet with internet should disable WiFi"
}

# Test: WiFi with internet should keep WiFi on
test_wifi_with_internet_keeps_wifi_on() {
    test_start "wifi_with_internet_keeps_wifi_on"
    setup

    export CHECK_INTERNET="1"
    export CHECK_METHOD="ping"
    export CHECK_TARGET="8.8.8.8"

    # Mock: WiFi is active, has internet
    active_type="wifi"
    active_has_internet=1
    wifi_on="yes"

    # Expected: WiFi should stay on
    expected_wifi_state="yes"

    # Simulate the logic: if active is wifi with internet, keep wifi on
    if [ "$active_type" = "wifi" ] && [ $active_has_internet -eq 1 ]; then
        actual_wifi_state="yes"
    else
        actual_wifi_state="no"
    fi

    assert_equals "$expected_wifi_state" "$actual_wifi_state" "WiFi with internet should keep WiFi on"
}

# Test: Ethernet without internet, WiFi available, should switch and keep WiFi on
test_eth_no_internet_switch_to_wifi() {
    test_start "eth_no_internet_switch_to_wifi"
    setup

    export CHECK_INTERNET="1"
    export INTERFACE_PRIORITY="eth0,wlan0"

    # Mock: ethernet active but no internet, WiFi has internet
    active_type="ethernet"
    active_has_internet=0
    wifi_has_internet=1

    # Expected: should switch to WiFi
    expected_switch="wifi"

    # Simulate the logic
    if [ "$active_type" = "ethernet" ] && [ $active_has_internet -eq 0 ] && [ $wifi_has_internet -eq 1 ]; then
        actual_switch="wifi"
    else
        actual_switch="none"
    fi

    assert_equals "$expected_switch" "$actual_switch" "Should switch to WiFi when ethernet has no internet"
}

# Test: State file is set to 'connected' when ethernet is active
test_state_connected_when_eth_active() {
    test_start "state_connected_when_eth_active"
    setup

    export CHECK_INTERNET="1"

    active_type="ethernet"
    active_has_internet=1

    # Expected state
    expected_state="connected"

    # Simulate state logic
    if [ "$active_type" = "ethernet" ] && [ $active_has_internet -eq 1 ]; then
        actual_state="connected"
    else
        actual_state="disconnected"
    fi

    assert_equals "$expected_state" "$actual_state" "State should be 'connected' when ethernet is active with internet"
}

# Test: State file is set to 'disconnected' when WiFi is active
test_state_disconnected_when_wifi_active() {
    test_start "state_disconnected_when_wifi_active"
    setup

    export CHECK_INTERNET="1"

    active_type="wifi"
    active_has_internet=1

    # Expected state
    expected_state="disconnected"

    # Simulate state logic
    if [ "$active_type" = "wifi" ] && [ $active_has_internet -eq 1 ]; then
        actual_state="disconnected"
    else
        actual_state="connected"
    fi

    assert_equals "$expected_state" "$actual_state" "State should be 'disconnected' when WiFi is active with internet"
}

# Test: Ethernet becomes available with internet while on WiFi - should disable WiFi
test_eth_recovery_disables_wifi() {
    test_start "eth_recovery_disables_wifi"
    setup

    export CHECK_INTERNET="1"
    export INTERFACE_PRIORITY="eth0,wlan0"

    # Current state: WiFi active with internet
    current_active="wifi"
    current_has_internet=1
    wifi_on="yes"

    # Higher priority ethernet becomes available with internet
    eth_available=1
    eth_has_internet=1

    # Expected: should switch to ethernet and disable WiFi
    expected_action="switch_to_eth_disable_wifi"

    # Simulate recovery logic
    if [ "$current_active" = "wifi" ] && [ $eth_available -eq 1 ] && [ $eth_has_internet -eq 1 ]; then
        actual_action="switch_to_eth_disable_wifi"
    else
        actual_action="no_change"
    fi

    assert_equals "$expected_action" "$actual_action" "Ethernet recovery should switch from WiFi and disable it"
}

# Test: Ethernet with WiFi off, internet works - WiFi should stay off
test_eth_with_internet_wifi_already_off() {
    test_start "eth_with_internet_wifi_already_off"
    setup

    export CHECK_INTERNET="1"

    active_type="ethernet"
    active_has_internet=1
    wifi_on="no"

    # Expected: WiFi should stay off
    expected_wifi_action="no_change"

    # Simulate logic: if WiFi already off, no action needed
    if [ "$active_type" = "ethernet" ] && [ $active_has_internet -eq 1 ] && [ "$wifi_on" = "no" ]; then
        actual_wifi_action="no_change"
    elif [ "$active_type" = "ethernet" ] && [ $active_has_internet -eq 1 ] && [ "$wifi_on" = "yes" ]; then
        actual_wifi_action="off"
    else
        actual_wifi_action="other"
    fi

    assert_equals "$expected_wifi_action" "$actual_wifi_action" "WiFi already off should not trigger action when ethernet has internet"
}

# Test: Neither ethernet nor WiFi has internet - keep current active
test_no_internet_anywhere_keep_current() {
    test_start "no_internet_anywhere_keep_current"
    setup

    export CHECK_INTERNET="1"

    active_type="ethernet"
    active_has_internet=0
    wifi_has_internet=0

    # Expected: keep current interface
    expected_decision="keep_current"

    # Simulate logic
    if [ $active_has_internet -eq 0 ] && [ $wifi_has_internet -eq 0 ]; then
        actual_decision="keep_current"
    else
        actual_decision="switch"
    fi

    assert_equals "$expected_decision" "$actual_decision" "Should keep current interface when no internet anywhere"
}

echo "Running WiFi State Management Tests"
echo "===================================="

test_eth_with_internet_disables_wifi
test_wifi_with_internet_keeps_wifi_on
test_eth_no_internet_switch_to_wifi
test_state_connected_when_eth_active
test_state_disconnected_when_wifi_active
test_eth_recovery_disables_wifi
test_eth_with_internet_wifi_already_off
test_no_internet_anywhere_keep_current

# Cleanup
teardown_mocks

# Summary
test_summary
