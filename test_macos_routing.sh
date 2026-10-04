#!/bin/bash
# Test script to demonstrate macOS routing issue and solutions

echo "=== Testing macOS Internet Connectivity on Multiple Interfaces ==="
echo ""

# Get interface info
echo "Available interfaces:"
for iface in en0 en5 en1; do
    ip=$(/usr/sbin/ipconfig getifaddr "$iface" 2>/dev/null || echo "no IP")
    status=$(/sbin/ifconfig "$iface" 2>/dev/null | grep "status:" | awk '{print $2}' || echo "not found")
    echo "  $iface: IP=$ip, status=$status"
done
echo ""

# Show routing table
echo "Default route:"
netstat -nr | grep "^default"
echo ""

# Test different methods
TEST_TARGET="8.8.8.8"
TEST_URL="http://captive.apple.com/hotspot-detect.html"

for iface in en0 en5; do
    ip=$(/usr/sbin/ipconfig getifaddr "$iface" 2>/dev/null)

    if [ -z "$ip" ]; then
        echo "$iface: No IP address, skipping tests"
        echo ""
        continue
    fi

    echo "Testing $iface (IP: $ip):"

    # Test 1: Gateway ping (most reliable)
    gateway=$(netstat -nr | grep "^default" | grep "$iface" | awk '{print $2}' | head -n 1)
    if [ -n "$gateway" ]; then
        echo "  Gateway method:"
        if ping -c 1 -W 2000 "$gateway" >/dev/null 2>&1; then
            echo "    ✓ Ping to gateway $gateway succeeded"
        else
            echo "    ✗ Ping to gateway $gateway failed"
        fi
    else
        echo "  Gateway method: No gateway found"
    fi

    # Test 2: Ping without binding (current broken behavior)
    echo "  Ping method (unbound):"
    if ping -c 1 -W 3000 "$TEST_TARGET" >/dev/null 2>&1; then
        echo "    ✓ Ping to $TEST_TARGET succeeded (but which interface?)"
    else
        echo "    ✗ Ping to $TEST_TARGET failed"
    fi

    # Test 3: Ping with -b binding (new behavior)
    echo "  Ping method (bound with -b):"
    if ping -b "$ip" -c 1 -W 3000 "$TEST_TARGET" >/dev/null 2>&1; then
        echo "    ✓ Ping to $TEST_TARGET via $ip succeeded"
    else
        echo "    ✗ Ping to $TEST_TARGET via $ip failed"
    fi

    # Test 4: curl with --interface (best for non-active interfaces)
    echo "  Curl method (--interface):"
    if command -v curl >/dev/null 2>&1; then
        if curl --interface "$iface" --connect-timeout 5 --max-time 10 -s -f "$TEST_URL" >/dev/null 2>&1; then
            echo "    ✓ HTTP check to $TEST_URL via $iface succeeded"
        else
            echo "    ✗ HTTP check to $TEST_URL via $iface failed"
        fi
    else
        echo "    curl not available"
    fi

    echo ""
done

echo "=== Recommendation ==="
echo "✓ FIXED: macOS now automatically uses curl for testing inactive interfaces"
echo "  - Active interface: Uses your configured CHECK_METHOD"
echo "  - Inactive/higher-priority interfaces: Automatically uses curl"
echo "  - No configuration changes needed!"
echo ""
echo "You can now use any CHECK_METHOD (gateway, ping, or curl)"
echo "The system will automatically handle the macOS routing limitation."
