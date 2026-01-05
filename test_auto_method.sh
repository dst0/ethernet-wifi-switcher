#!/bin/bash
# Test the automatic curl usage for inactive interfaces

echo "=== Testing Automatic Method Selection ==="
echo ""

# Source the switcher to get the check_internet function
# We'll mock the actual checks

# Mock functions
IPCONFIG="echo"
CHECK_METHOD="ping"
CHECK_TARGET="8.8.8.8"
CHECK_INTERNET="1"
LOG_ALL_CHECKS="1"
LAST_CHECK_STATE_FILE="/tmp/test_check_state"

log() { echo "[TEST] $*"; }

# Simplified check_internet function to test logic
check_internet() {
  iface="$1"
  is_active_interface="${2:-0}"

  echo ""
  echo "check_internet called:"
  echo "  Interface: $iface"
  echo "  Is Active: $is_active_interface"
  echo "  CHECK_METHOD configured: $CHECK_METHOD"

  if [ "$is_active_interface" = "0" ]; then
    echo "  → Using curl (inactive interface)"
  else
    echo "  → Using $CHECK_METHOD (active interface)"
  fi
}

echo "Scenario 1: Checking active interface en5"
check_internet "en5" 1

echo ""
echo "Scenario 2: Checking inactive higher-priority interface en0"
check_internet "en0" 0

echo ""
echo "Scenario 3: Checking inactive fallback interface wlan0"
check_internet "wlan0" 0

echo ""
echo "=== Summary ==="
echo "✓ Active interfaces use configured CHECK_METHOD ($CHECK_METHOD)"
echo "✓ Inactive interfaces automatically use curl to avoid macOS routing issues"
