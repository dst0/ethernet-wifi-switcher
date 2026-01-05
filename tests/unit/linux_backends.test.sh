#!/bin/sh
set -e

# Load test framework
. "$(dirname "$0")/../lib/mock.sh"
. "$(dirname "$0")/../lib/assert.sh"

NMCLI_BACKEND="$(cd "$(dirname "$0")/../../src/linux/lib" && pwd)/network-nmcli.sh"
IP_BACKEND="$(cd "$(dirname "$0")/../../src/linux/lib" && pwd)/network-ip.sh"

setup() {
    clear_mocks
    setup_mocks
}

setup_nmcli_mock() {
    cat > "$MOCK_DIR/bin/nmcli" << 'EOF'
#!/bin/sh
case "$*" in
    "device")
        echo "eth0       ethernet  connected     Wired connection 1"
        echo "wlan0      wifi      disconnected  --"
        ;;
    "-t -f DEVICE,STATE device")
        echo "eth0:connected"
        echo "wlan0:disconnected"
        ;;
    "radio wifi")
        echo "enabled"
        ;;
    *)
        echo "eth0       ethernet  connected     Wired connection 1"
        echo "wlan0      wifi      disconnected  --"
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bin/nmcli"
}

# NMCLI Backend Tests
test_nmcli_get_first_ethernet() {
    test_start "nmcli_get_first_ethernet"
    setup
    setup_nmcli_mock
    . "$NMCLI_BACKEND"
    assert_equals "eth0" "$(get_first_ethernet_iface)" "Should detect eth0 as first ethernet"
}

test_nmcli_get_first_wifi() {
    test_start "nmcli_get_first_wifi"
    setup
    setup_nmcli_mock
    . "$NMCLI_BACKEND"
    assert_equals "wlan0" "$(get_first_wifi_iface)" "Should detect wlan0 as first wifi"
}

test_nmcli_is_ethernet_iface() {
    test_start "nmcli_is_ethernet_iface"
    setup
    setup_nmcli_mock
    . "$NMCLI_BACKEND"
    is_ethernet_iface "eth0"
    assert_success "eth0 should be ethernet"
}

test_nmcli_is_wifi_iface() {
    test_start "nmcli_is_wifi_iface"
    setup
    setup_nmcli_mock
    . "$NMCLI_BACKEND"
    is_wifi_iface "wlan0"
    assert_success "wlan0 should be wifi"
}

test_nmcli_get_iface_state_connected() {
    test_start "nmcli_get_iface_state_connected"
    setup
    setup_nmcli_mock
    . "$NMCLI_BACKEND"
    assert_equals "connected" "$(get_iface_state eth0)" "eth0 should be connected"
}

test_nmcli_get_iface_state_disconnected() {
    test_start "nmcli_get_iface_state_disconnected"
    setup
    setup_nmcli_mock
    . "$NMCLI_BACKEND"
    assert_equals "disconnected" "$(get_iface_state wlan0)" "wlan0 should be disconnected"
}

test_nmcli_is_wifi_enabled() {
    test_start "nmcli_is_wifi_enabled"
    setup
    setup_nmcli_mock
    . "$NMCLI_BACKEND"
    is_wifi_enabled
    assert_success "wifi should be enabled"
}

# IP Backend Tests
setup_ip_mock() {
    mock_command ip "1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP mode DEFAULT group default qlen 1000
    link/ether 08:00:27:8d:c4:9c brd ff:ff:ff:ff:ff:ff
3: wlan0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
    link/ether 08:00:27:8d:c4:9d brd ff:ff:ff:ff:ff:ff"

    mkdir -p "$MOCK_DIR/sys/class/net/wlan0/wireless"
    mkdir -p "$MOCK_DIR/sys/class/net/eth0"
    echo "up" > "$MOCK_DIR/sys/class/net/eth0/operstate"
    echo "1" > "$MOCK_DIR/sys/class/net/eth0/carrier"
    echo "up" > "$MOCK_DIR/sys/class/net/wlan0/operstate"
    echo "0" > "$MOCK_DIR/sys/class/net/wlan0/carrier"

    export SYS_CLASS_NET="$MOCK_DIR/sys/class/net"
}

test_ip_get_first_ethernet() {
    test_start "ip_get_first_ethernet"
    setup
    setup_ip_mock
    . "$IP_BACKEND"
    assert_equals "eth0" "$(get_first_ethernet_iface)" "Should detect eth0 as first ethernet"
}

test_ip_get_first_wifi() {
    test_start "ip_get_first_wifi"
    setup
    setup_ip_mock
    . "$IP_BACKEND"
    assert_equals "wlan0" "$(get_first_wifi_iface)" "Should detect wlan0 as first wifi"
}

test_ip_get_iface_state_connected() {
    test_start "ip_get_iface_state_connected"
    setup
    setup_ip_mock
    . "$IP_BACKEND"
    assert_equals "connected" "$(get_iface_state eth0)" "eth0 should be connected (UP)"
}

test_ip_get_iface_state_disconnected() {
    test_start "ip_get_iface_state_disconnected"
    setup
    setup_ip_mock
    . "$IP_BACKEND"
    assert_equals "disconnected" "$(get_iface_state wlan0)" "wlan0 should be disconnected (DOWN)"
}

test_ip_is_wifi_enabled() {
    test_start "ip_is_wifi_enabled"
    setup
    setup_ip_mock
    mock_command rfkill "0: phy0: Wireless LAN: Soft unblocked: yes: Hard unblocked: yes"
    . "$IP_BACKEND"
    is_wifi_enabled
    assert_success "wifi should be enabled (unblocked)"
}

# Run tests
echo "Running Linux Backend Tests"
echo "========================================"

# nmcli backend tests
test_nmcli_get_first_ethernet
test_nmcli_get_first_wifi
test_nmcli_is_ethernet_iface
test_nmcli_is_wifi_iface
test_nmcli_get_iface_state_connected
test_nmcli_get_iface_state_disconnected
test_nmcli_is_wifi_enabled

# ip backend tests
test_ip_get_first_ethernet
test_ip_get_first_wifi
test_ip_get_iface_state_connected
test_ip_get_iface_state_disconnected
test_ip_is_wifi_enabled

# Cleanup
teardown_mocks

# Summary
test_summary
