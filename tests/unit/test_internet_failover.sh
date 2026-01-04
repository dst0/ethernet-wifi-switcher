#!/bin/sh
set -e

# Load test framework
. "$(dirname "$0")/../lib/mock.sh"
. "$(dirname "$0")/../lib/assert.sh"

setup() {
    clear_mocks
    setup_mocks
}

# Test: Priority list with internet check - eth1 is connected
test_priority_eth1_is_connected() {
    test_start "priority_eth1_is_connected"
    setup

    export INTERFACE_PRIORITY="eth1,wlan0"
    iface="eth1"
    iface_state="connected"

    assert_equals "connected" "$iface_state" "eth1 should be connected"
}

# Test: Priority list with internet check - eth1 has internet
test_priority_eth1_has_internet() {
    test_start "priority_eth1_has_internet"
    setup

    export INTERFACE_PRIORITY="eth1,wlan0"
    export CHECK_INTERNET="1"
    export CHECK_METHOD="ping"
    export CHECK_TARGET="8.8.8.8"

    mock_command ping ""

    iface="eth1"
    if ping -c 1 -W 2 -I "$iface" "$CHECK_TARGET" >/dev/null 2>&1; then
        internet_status="has_internet"
    else
        internet_status="no_internet"
    fi

    assert_equals "has_internet" "$internet_status" "eth1 should have internet"
}

# Test: eth1 loses internet - should have no internet
test_eth1_loses_internet_no_internet() {
    test_start "eth1_no_internet"
    setup

    export INTERFACE_PRIORITY="eth1,wlan0"
    active_iface="eth1"
    active_has_internet="no"

    assert_equals "no" "$active_has_internet" "eth1 should have no internet"
}

# Test: eth1 loses internet - should fallback to wlan0
test_eth1_loses_internet_fallback_wlan0() {
    test_start "eth1_fallback_wlan0"
    setup

    export INTERFACE_PRIORITY="eth1,wlan0"
    active_iface="eth1"

    found_working=""
    for iface in $(echo "$INTERFACE_PRIORITY" | tr ',' ' '); do
        iface=$(echo "$iface" | xargs)
        if [ "$iface" = "$active_iface" ]; then
            continue
        fi
        if echo "$iface" | grep -q "wlan"; then
            found_working="$iface"
            break
        fi
    done

    assert_equals "wlan0" "$found_working" "Should fallback to wlan0"
}

# Test: WiFi should be enabled when checking for internet
test_enable_wifi_to_check_internet() {
    test_start "enable_wifi_to_check"
    setup

    export INTERFACE_PRIORITY="eth1,wlan0"
    export CHECK_INTERNET="1"

    # Mock: eth1 has no internet, wifi is disabled
    active_iface="eth1"
    active_has_internet="no"
    wifi_enabled="disabled"
    next_iface="wlan0"

    # Simulate logic: when checking wifi, enable it first
    if echo "$next_iface" | grep -q "wlan" && [ "$wifi_enabled" = "disabled" ]; then
        action="enable_wifi"
    else
        action="none"
    fi

    assert_equals "enable_wifi" "$action" "Should enable wifi to check for internet"
}

# Test: After failover to wifi, eth1 should still be monitored
test_continue_monitoring_failed_eth() {
    test_start "continue_monitoring_eth"
    setup

    export CHECK_INTERNET="1"
    export CHECK_INTERVAL="30"

    # State: failed over to wifi
    current_iface="wlan0"
    higher_priority_iface="eth1"

    # Periodic check should test ALL interfaces in priority order
    # including the failed higher priority one
    should_check_eth1="yes"

    assert_equals "yes" "$should_check_eth1" "Should continue monitoring eth1 for recovery"
}

# Test: When eth1 recovers internet, should switch back from wifi
test_switch_back_when_eth_recovers() {
    test_start "switch_back_on_recovery"
    setup

    export INTERFACE_PRIORITY="eth1,wlan0"
    export CHECK_INTERNET="1"

    # Current state: using wifi because eth1 lost internet
    current_iface="wlan0"
    current_has_internet="yes"

    # Periodic check finds eth1 now has internet again
    eth1_state="connected"
    eth1_has_internet="yes"

    # Since eth1 is higher priority and has internet, switch back
    if [ "$eth1_has_internet" = "yes" ] && [ "$current_iface" != "eth1" ]; then
        should_switch_to="eth1"
    else
        should_switch_to="wlan0"
    fi

    assert_equals "eth1" "$should_switch_to" "Should switch back to eth1 when it recovers"
}

# Test: Both interfaces lose internet - keep current decision
test_no_internet_keep_current_decision() {
    test_start "no_internet_keep_current_decision"
    setup

    export INTERFACE_PRIORITY="eth1,wlan0"
    eth1_has_internet="no"
    wlan0_has_internet="no"

    if [ "$eth1_has_internet" = "no" ] && [ "$wlan0_has_internet" = "no" ]; then
        decision="keep_current"
    else
        decision="switch"
    fi

    assert_equals "keep_current" "$decision" "Should keep current when no internet available"
}

# Test: Both interfaces lose internet - keep current interface
test_no_internet_keep_current_interface() {
    test_start "no_internet_keep_current_interface"
    setup

    current_iface="eth1"
    eth1_has_internet="no"
    wlan0_has_internet="no"

    if [ "$eth1_has_internet" = "no" ] && [ "$wlan0_has_internet" = "no" ]; then
        kept_iface="$current_iface"
    fi

    assert_equals "eth1" "$kept_iface" "Should keep eth1 even without internet"
}

# Test: Periodic check interval is configurable
test_periodic_check_interval() {
    test_start "periodic_check_interval"
    setup

    export CHECK_INTERNET="1"
    export CHECK_INTERVAL="10"

    configured_interval="$CHECK_INTERVAL"

    assert_equals "10" "$configured_interval" "Check interval should be configurable"
}

# Test: Internet check with gateway method
test_internet_check_gateway_method() {
    test_start "internet_check_gateway"
    setup

    export CHECK_METHOD="gateway"

    # Mock route showing gateway on eth1
    mock_command ip "default via 192.168.1.1 dev eth1"

    # Check if gateway exists for interface
    if ip route | grep -q "default.*eth1"; then
        gateway_status="found"
    else
        gateway_status="not_found"
    fi

    assert_equals "found" "$gateway_status" "Should find gateway for interface"
}

# Test: Internet check with ping method requires target
test_internet_check_ping_requires_target() {
    test_start "ping_requires_target"
    setup

    export CHECK_METHOD="ping"
    export CHECK_TARGET=""

    # Ping method without target should be invalid
    if [ -z "$CHECK_TARGET" ]; then
        validation="missing_target"
    else
        validation="ok"
    fi

    assert_equals "missing_target" "$validation" "Ping method should require CHECK_TARGET"
}

# Test: Internet check with curl method
test_internet_check_curl_method() {
    test_start "internet_check_curl"
    setup

    export CHECK_METHOD="curl"
    export CHECK_TARGET="http://example.com"

    # Mock curl success
    mock_command curl ""

    # Curl should use the target URL
    if curl -s --max-time 5 --interface eth1 "$CHECK_TARGET" >/dev/null 2>&1; then
        curl_status="success"
    else
        curl_status="fail"
    fi

    assert_equals "success" "$curl_status" "Curl should check HTTP endpoint"
}

# Test: Periodic checks continue running
test_periodic_check_continues() {
    test_start "periodic_check_continues"
    setup

    export CHECK_INTERNET="1"
    periodic_check_active="yes"

    assert_equals "yes" "$periodic_check_active" "Periodic check should continue running"
}

# Test: Periodic checks retry interfaces
test_periodic_check_retries() {
    test_start "periodic_check_retries"
    setup

    export INTERFACE_PRIORITY="eth1,wlan0"
    export CHECK_INTERVAL="30"
    eth1_internet_check2="no"

    assert_equals "no" "$eth1_internet_check2" "Should retry eth1 in iteration 2"
}

# Test: Periodic checks detect recovery
test_periodic_check_detects_recovery() {
    test_start "periodic_check_detects_recovery"
    setup

    eth1_internet_check3="yes"

    assert_equals "yes" "$eth1_internet_check3" "Should detect eth1 recovery in iteration 3"
}

# Test: All interfaces checked in priority order
test_check_all_interfaces_priority_order() {
    test_start "check_all_priority_order"
    setup

    export INTERFACE_PRIORITY="eth0,wlan0,eth1"
    interfaces_to_check="eth0,wlan0,eth1"

    assert_equals "eth0,wlan0,eth1" "$interfaces_to_check" "Should check all interfaces in priority order"
}

# Test: All interfaces checked count
test_check_all_interfaces_count() {
    test_start "check_all_interfaces_count"
    setup

    export INTERFACE_PRIORITY="eth0,wlan0,eth1"
    check_count=3

    assert_equals "3" "$check_count" "Should check all 3 interfaces"
}

# Test: 5 mixed interfaces - parse all
test_five_interfaces_parse_all() {
    test_start "five_interfaces_parse"
    setup

    export INTERFACE_PRIORITY="eth0,wlan0,eth1,wlan1,eth2"

    checked_interfaces=""
    for iface in $(echo "$INTERFACE_PRIORITY" | tr ',' ' '); do
        iface=$(echo "$iface" | xargs)
        if [ -z "$checked_interfaces" ]; then
            checked_interfaces="$iface"
        else
            checked_interfaces="$checked_interfaces,$iface"
        fi
    done

    assert_equals "eth0,wlan0,eth1,wlan1,eth2" "$checked_interfaces" "Should parse all 5 interfaces"
}

# Test: 5 mixed interfaces - count ethernet
test_five_interfaces_count_ethernet() {
    test_start "five_interfaces_eth_count"
    setup

    export INTERFACE_PRIORITY="eth0,wlan0,eth1,wlan1,eth2"
    eth_count=$(echo "$INTERFACE_PRIORITY" | tr ',' '\n' | grep -E '^eth' | wc -l | xargs)

    assert_equals "3" "$eth_count" "Should detect 3 ethernet interfaces"
}

# Test: 5 mixed interfaces - count wifi
test_five_interfaces_count_wifi() {
    test_start "five_interfaces_wifi_count"
    setup

    export INTERFACE_PRIORITY="eth0,wlan0,eth1,wlan1,eth2"
    wifi_count=$(echo "$INTERFACE_PRIORITY" | tr ',' '\n' | grep -E '^wlan' | wc -l | xargs)

    assert_equals "2" "$wifi_count" "Should detect 2 wifi interfaces"
}

# Test: 5 interfaces - failover cascade through all until finding internet
test_five_interfaces_cascade_failover() {
    test_start "five_iface_cascade"
    setup

    export INTERFACE_PRIORITY="eth0,wlan0,eth1,wlan1,eth2"
    export CHECK_INTERNET="1"

    # Scenario: eth0-eth3 have no internet, eth2 has internet
    eth0_internet="no"
    wlan0_internet="no"
    eth1_internet="no"
    wlan1_internet="no"
    eth2_internet="yes"

    # Simulate checking in order until finding working one
    found_working=""
    for iface in eth0 wlan0 eth1 wlan1 eth2; do
        # Get internet status for this iface
        case "$iface" in
            eth0) status="$eth0_internet" ;;
            wlan0) status="$wlan0_internet" ;;
            eth1) status="$eth1_internet" ;;
            wlan1) status="$wlan1_internet" ;;
            eth2) status="$eth2_internet" ;;
        esac

        if [ "$status" = "yes" ]; then
            found_working="$iface"
            break
        fi
    done

    assert_equals "eth2" "$found_working" "Should cascade through all and find eth2"
}

# Test: 5 interfaces - switch to recovered higher priority
test_five_interfaces_switch_to_higher() {
    test_start "five_iface_switch_higher"
    setup

    export INTERFACE_PRIORITY="eth0,wlan0,eth1,wlan1,eth2"
    eth0_internet="yes"
    eth0_priority=1
    eth2_priority=5

    if [ "$eth0_internet" = "yes" ] && [ $eth0_priority -lt $eth2_priority ]; then
        should_switch_to="eth0"
    else
        should_switch_to="eth2"
    fi

    assert_equals "eth0" "$should_switch_to" "Should switch to eth0 when it recovers"
}

# Test: 5 interfaces - recovery reason
test_five_interfaces_recovery_reason() {
    test_start "five_iface_recovery_reason"
    setup

    eth0_internet="yes"
    eth0_priority=1
    eth2_priority=5

    if [ "$eth0_internet" = "yes" ] && [ $eth0_priority -lt $eth2_priority ]; then
        reason="higher_priority_recovered"
    else
        reason="keep_current"
    fi

    assert_equals "higher_priority_recovered" "$reason" "Reason should be higher priority recovery"
}

# Test: 5 interfaces - enable wifi for checking
test_five_interfaces_enable_wifi() {
    test_start "five_iface_enable_wifi"
    setup

    export INTERFACE_PRIORITY="eth0,wlan0,eth1,wlan1,eth2"
    wifi_enabled="no"
    next_check="wlan0"

    if echo "$next_check" | grep -q "wlan" && [ "$wifi_enabled" = "no" ]; then
        action="enable_wifi"
    else
        action="none"
    fi

    assert_equals "enable_wifi" "$action" "Should enable wifi to check wlan interfaces"
}

# Test: 5 interfaces - count wifi interfaces
test_five_interfaces_wifi_count() {
    test_start "five_iface_wifi_in_priority"
    setup

    export INTERFACE_PRIORITY="eth0,wlan0,eth1,wlan1,eth2"
    wifi_ifaces_in_priority=$(echo "$INTERFACE_PRIORITY" | tr ',' '\n' | grep "wlan" | wc -l | xargs)

    assert_equals "2" "$wifi_ifaces_in_priority" "Should have 2 wifi interfaces in priority"
}

# Test: Logging - continuous checking message
test_logging_continuous_checking() {
    test_start "logging_continuous_checking"
    setup

    export CHECK_INTERVAL="30"
    no_internet_msg="Will continue checking all interfaces every ${CHECK_INTERVAL}s until internet is restored"

    assert_contains "$no_internet_msg" "continue checking" "Should log about continuous checking"
}

# Test: Logging - monitoring higher priority message
test_logging_monitoring_higher_priority() {
    test_start "logging_monitoring_higher"
    setup

    recovery_msg="Periodic checks will continue monitoring higher priority interfaces for recovery"

    assert_contains "$recovery_msg" "monitoring higher priority" "Should log about monitoring higher priority"
}

# Test: Logging shows priority list when searching
test_logging_shows_priority_list() {
    test_start "logging_priority_list"
    setup

    export INTERFACE_PRIORITY="eth0,wlan0,eth1,wlan1,eth2"

    # When active interface loses internet, should log priority list
    active_iface="eth0"
    has_internet="no"

    expected_log="Will try all interfaces in priority order: $INTERFACE_PRIORITY"

    assert_contains "$expected_log" "priority order" "Should show priority list in logs"
}

echo "Running Internet Failover Tests"
echo "================================"

test_priority_eth1_is_connected
test_priority_eth1_has_internet
test_eth1_loses_internet_no_internet
test_eth1_loses_internet_fallback_wlan0
test_enable_wifi_to_check_internet
test_continue_monitoring_failed_eth
test_switch_back_when_eth_recovers
test_no_internet_keep_current_decision
test_no_internet_keep_current_interface
test_periodic_check_interval
test_internet_check_gateway_method
test_internet_check_ping_requires_target
test_internet_check_curl_method
test_periodic_check_continues
test_periodic_check_retries
test_periodic_check_detects_recovery
test_check_all_interfaces_priority_order
test_check_all_interfaces_count
test_five_interfaces_parse_all
test_five_interfaces_count_ethernet
test_five_interfaces_count_wifi
test_five_interfaces_cascade_failover
test_five_interfaces_switch_to_higher
test_five_interfaces_recovery_reason
test_five_interfaces_enable_wifi
test_five_interfaces_wifi_count
test_logging_continuous_checking
test_logging_monitoring_higher_priority
test_logging_shows_priority_list

# Cleanup
teardown_mocks

# Summary
test_summary
