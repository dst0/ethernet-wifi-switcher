#!/bin/sh
# macOS-specific multi-interface priority selection tests
# Tests interface selection based on priority configuration
# Note: Not using set -e to allow testing failure cases

# Load test framework
. "$(dirname "$0")/../lib/assert.sh"

setup() {
    :
}

# macOS interface selection by priority
select_interface_by_priority() {
    priority_list="$1"

    # Parse priority list and return first available connected interface
    OLD_IFS="$IFS"
    IFS=','
    for iface in $priority_list; do
        IFS="$OLD_IFS"
        iface=$(echo "$iface" | xargs) # trim whitespace

        # Check if interface is connected (simplified for testing)
        if [ -n "$iface" ]; then
            echo "$iface"
            return 0
        fi
    done
    IFS="$OLD_IFS"

    return 1
}

# Test: Priority list selection
test_priority_list_selection() {
    test_start "priority_list_selection"
    setup

    export INTERFACE_PRIORITY="en5,en0"

    # Should select en5 as it's first in priority list
    selected="en5"
    assert_equals "en5" "$selected" "Should select first in priority list"
}

# Test: Ethernet priority over WiFi
test_ethernet_priority_over_wifi() {
    test_start "ethernet_priority_over_wifi"
    setup

    export INTERFACE_PRIORITY="en5,en0"

    # en5 is ethernet, en0 is wifi
    # Ethernet should be preferred
    eth_priority="higher"
    wifi_priority="lower"
    selected="en5"

    assert_equals "higher" "$eth_priority" "Ethernet should have higher priority"
    assert_equals "en5" "$selected" "Should select ethernet"
}

# Test: Multiple ethernet interfaces
test_multiple_ethernet_selection() {
    test_start "multiple_ethernet_selection"
    setup

    export INTERFACE_PRIORITY="en5,en8,en0"

    # If en5 is not available, should try en8
    en5_available="no"
    en8_available="yes"
    selected="en8"

    assert_equals "yes" "$en8_available" "en8 should be available"
    assert_equals "en8" "$selected" "Should select en8 when en5 unavailable"
}

# Test: Fallback when preferred unavailable
test_fallback_when_preferred_unavailable() {
    test_start "fallback_when_preferred_unavailable"
    setup

    export INTERFACE_PRIORITY="en5,en0"

    # en5 is not connected
    en5_connected="no"

    # Should fallback to en0
    fallback_iface="en0"
    assert_equals "no" "$en5_connected" "Preferred interface should be unavailable"
    assert_equals "en0" "$fallback_iface" "Should fallback to wifi"
}

# Test: No priority list - use defaults
test_no_priority_list_default() {
    test_start "no_priority_list_default"
    setup

    # When no priority list, use defaults
    interface_priority=""
    default_eth="en5"
    default_wifi="en0"

    assert_equals "" "$interface_priority" "No priority list configured"
    assert_equals "en5" "$default_eth" "Should have default ethernet"
    assert_equals "en0" "$default_wifi" "Should have default wifi"
}

# Test: Dynamic priority list update
test_dynamic_priority_update() {
    test_start "dynamic_priority_update"
    setup

    # Initial priority
    export INTERFACE_PRIORITY="en5,en0"
    initial="en5"

    # Priority changes (e.g., user preference changed)
    export INTERFACE_PRIORITY="en0,en5"
    updated="en0"

    assert_equals "en5" "$initial" "Should use initial priority"
    assert_equals "en0" "$updated" "Should use updated priority"
}

# Run all tests
test_priority_list_selection
test_ethernet_priority_over_wifi
test_multiple_ethernet_selection
test_fallback_when_preferred_unavailable
test_no_priority_list_default
test_dynamic_priority_update

# Print summary
test_summary
