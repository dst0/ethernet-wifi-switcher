#!/bin/sh
set -e

# Load test framework
. "$(dirname "$0")/../lib/mock.sh"
. "$(dirname "$0")/../lib/assert.sh"

# Setup
setup() {
    clear_mocks
    setup_mocks
}

# Simplified get_eth_dev function for testing
get_eth_dev_mock() {
    if [ -n "$INTERFACE_PRIORITY" ]; then
        OLD_IFS="$IFS"
        IFS=','
        for iface in $INTERFACE_PRIORITY; do
            IFS="$OLD_IFS"
            iface=$(echo "$iface" | xargs)
            if [ -n "$iface" ]; then
                # Check if ethernet (not wifi)
                if echo "$iface" | grep -qE '^(eth|enp|eno|ens)'; then
                    echo "$iface"
                    return 0
                fi
            fi
        done
        IFS="$OLD_IFS"
    fi
    echo "$ETH_DEV"
}

# Test: Priority selects first ethernet
test_priority_first_ethernet() {
    test_start "priority_first_ethernet"
    setup

    export INTERFACE_PRIORITY="eth0,eth1,wlan0"
    export ETH_DEV="eth2"

    result=$(get_eth_dev_mock)
    assert_equals "eth0" "$result" "Should select first ethernet from priority"
}

# Test: Priority skips wifi for ethernet
test_priority_skip_wifi() {
    test_start "priority_skip_wifi"
    setup

    export INTERFACE_PRIORITY="wlan0,eth0,eth1"
    export ETH_DEV="eth2"

    result=$(get_eth_dev_mock)
    assert_equals "eth0" "$result" "Should skip wifi and select first ethernet"
}

# Test: No priority uses default
test_no_priority_default() {
    test_start "no_priority_default"
    setup

    export INTERFACE_PRIORITY=""
    export ETH_DEV="enp0s3"

    result=$(get_eth_dev_mock)
    assert_equals "enp0s3" "$result" "Should use default without priority"
}

# Test: Priority with modern interface names
test_priority_modern_names() {
    test_start "priority_modern_names"
    setup

    export INTERFACE_PRIORITY="enp0s3,enp0s8,wlp1s0"
    export ETH_DEV="eth0"

    result=$(get_eth_dev_mock)
    assert_equals "enp0s3" "$result" "Should handle modern interface names"
}

# Test: Priority with whitespace
test_priority_whitespace() {
    test_start "priority_whitespace"
    setup

    export INTERFACE_PRIORITY=" eth0 , eth1 , wlan0 "
    export ETH_DEV="eth2"

    result=$(get_eth_dev_mock)
    assert_equals "eth0" "$result" "Should handle whitespace in priority list"
}

# Run all tests
echo "Running Multi-Interface Tests"
echo "=============================="
test_priority_first_ethernet
test_priority_skip_wifi
test_no_priority_default
test_priority_modern_names
test_priority_whitespace

# Cleanup
teardown_mocks

# Summary
test_summary
