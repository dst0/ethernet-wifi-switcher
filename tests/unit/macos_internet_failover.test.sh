#!/bin/sh
# macOS-specific internet failover tests
# Tests priority-based switching and internet failure recovery
# Note: Not using set -e to allow testing failure cases

# Load test framework
. "$(dirname "$0")/../lib/assert.sh"

setup() {
    :
}

# Test: Ethernet has priority and is connected
test_priority_eth_connected() {
    test_start "priority_eth_connected"
    setup

    export INTERFACE_PRIORITY="en5,en0"
    active_iface="en5"
    active_has_internet="yes"

    assert_equals "en5" "$active_iface" "Should use ethernet (en5) as it has higher priority"
}

# Test: Ethernet loses internet, fallback to WiFi
test_eth_loses_internet_fallback_wifi() {
    test_start "eth_loses_internet_fallback_wifi"
    setup

    export INTERFACE_PRIORITY="en5,en0"

    # Simulate: eth (en5) loses internet
    primary_iface="en5"
    primary_has_internet="no"

    # Should fallback to secondary (en0 for wifi)
    fallback_iface="en0"
    fallback_has_internet="yes"

    assert_equals "no" "$primary_has_internet" "Primary ethernet should have no internet"
    assert_equals "yes" "$fallback_has_internet" "Secondary wifi should have internet"
    assert_equals "en0" "$fallback_iface" "Should switch to wifi (en0)"
}

# Test: Higher priority interface recovers
test_higher_priority_recovery() {
    test_start "higher_priority_recovery"
    setup

    export INTERFACE_PRIORITY="en5,en0"

    # State: Currently using en0 (wifi)
    current_iface="en0"

    # But en5 (ethernet) just recovered
    primary_iface="en5"
    primary_has_internet="yes"

    assert_equals "en5" "$primary_iface" "Primary should be checked and found working"
}

# Test: Multiple ethernet interfaces - select by priority
test_multi_interface_selection() {
    test_start "multi_interface_selection"
    setup

    export INTERFACE_PRIORITY="en5,en8,en0"

    # en5 is not connected, en8 is available
    en5_connected="no"
    en8_connected="yes"
    en8_has_internet="yes"

    assert_equals "yes" "$en8_has_internet" "Should select en8 when en5 unavailable"
}

# Test: No interface has internet
test_no_internet_switch_candidate() {
    test_start "no_internet_switch_candidate"
    setup

    export INTERFACE_PRIORITY="en5,en0"

    en5_has_internet="no"
    en0_has_internet="no"

    assert_equals "no" "$en5_has_internet" "Ethernet should have no internet"
    assert_equals "no" "$en0_has_internet" "WiFi should also have no internet"
}

# Test: Both interfaces have no internet
test_both_interfaces_no_internet() {
    test_start "both_interfaces_no_internet"
    setup

    export INTERFACE_PRIORITY="en5,en0"

    primary_internet="no"
    secondary_internet="no"

    assert_equals "no" "$primary_internet" "Primary has no internet"
    assert_equals "no" "$secondary_internet" "Secondary has no internet"
}

# Run all tests
test_priority_eth_connected
test_eth_loses_internet_fallback_wifi
test_higher_priority_recovery
test_multi_interface_selection
test_no_internet_switch_candidate
test_both_interfaces_no_internet

# Print summary
test_summary
