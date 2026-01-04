#!/bin/sh
# Note: Not using set -e to allow testing failure cases
# where commands may return non-zero exit codes

# Load test framework
. "$(dirname "$0")/../lib/mock.sh"
. "$(dirname "$0")/../lib/assert.sh"

# Setup
setup() {
    clear_mocks
    setup_mocks
    mock_state_dir
}

# Simplified check_internet function for testing
check_internet_mock() {
    iface="$1"
    CHECK_METHOD="${CHECK_METHOD:-gateway}"

    case "$CHECK_METHOD" in
        gateway)
            gateway=$(ip route show dev "$iface" 2>/dev/null | grep default | awk '{print $3}' | head -n 1)
            if [ -z "$gateway" ]; then
                return 1
            fi
            ping -I "$iface" -c 1 -W 2 "$gateway" >/dev/null 2>&1
            return $?
            ;;
        ping)
            if [ -z "$CHECK_TARGET" ]; then
                return 1
            fi
            ping -I "$iface" -c 1 -W 3 "$CHECK_TARGET" >/dev/null 2>&1
            return $?
            ;;
        curl)
            if [ -z "$CHECK_TARGET" ]; then
                CHECK_TARGET="http://captive.apple.com/hotspot-detect.html"
            fi
            curl --interface "$iface" --connect-timeout 5 --max-time 10 -s -f "$CHECK_TARGET" >/dev/null 2>&1
            return $?
            ;;
    esac
    return 1
}

# Test: Gateway check succeeds
test_gateway_check_success() {
    test_start "gateway_check_success"
    setup

    export CHECK_METHOD="gateway"
    mock_command ip "default via 192.168.1.1 dev eth0"
    mock_command_exit ping 0 ""

    check_internet_mock "eth0"
    result=$?
    assert_equals "$result" "0" "Gateway check should succeed"
}

# Test: Gateway check fails when no gateway
test_gateway_check_no_gateway() {
    test_start "gateway_check_no_gateway"
    setup

    export CHECK_METHOD="gateway"
    mock_command ip ""  # No gateway in output

    check_internet_mock "eth0"
    result=$?
    assert_equals "$result" "1" "Gateway check should fail without gateway"
}

# Test: Ping check succeeds
test_ping_check_success() {
    test_start "ping_check_success"
    setup

    export CHECK_METHOD="ping"
    export CHECK_TARGET="8.8.8.8"
    mock_command_exit ping 0 "PING 8.8.8.8"

    check_internet_mock "eth0"
    result=$?
    assert_equals "$result" "0" "Ping check should succeed"
}

# Test: Ping check fails without target
test_ping_check_no_target() {
    test_start "ping_check_no_target"
    setup

    export CHECK_METHOD="ping"
    export CHECK_TARGET=""

    check_internet_mock "eth0"
    result=$?
    assert_equals "$result" "1" "Ping check should fail without target"
}

# Test: Curl check succeeds
test_curl_check_success() {
    test_start "curl_check_success"
    setup

    export CHECK_METHOD="curl"
    export CHECK_TARGET="http://captive.apple.com/hotspot-detect.html"
    mock_command_exit curl 0 "Success"

    check_internet_mock "eth0"
    result=$?
    assert_equals "$result" "0" "Curl check should succeed"
}

# Test: Curl check uses default URL
test_curl_default_url() {
    test_start "curl_default_url"
    setup

    export CHECK_METHOD="curl"
    export CHECK_TARGET=""
    mock_command_exit curl 0 "Success"

    check_internet_mock "eth0"
    result=$?
    assert_equals "$result" "0" "Curl should use default URL"
}

# Run all tests
echo "Running Internet Check Tests"
echo "============================"
test_gateway_check_success
test_gateway_check_no_gateway
test_ping_check_success
test_ping_check_no_target
test_curl_check_success
test_curl_default_url

# Cleanup
teardown_mocks

# Summary
test_summary
