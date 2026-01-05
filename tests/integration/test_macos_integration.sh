#!/bin/bash
set -e

echo "==================================="
echo "macOS Integration Test"
echo "==================================="

# Check if running on macOS
if [ "$(uname -s)" != "Darwin" ]; then
    echo "Skipping macOS tests (not running on macOS)"
    exit 0
fi

# Build and test locally
cd "$(dirname "$0")/../.."

# Build the installer first
./build.sh macos

TEST_WORKDIR="/tmp/eth-wifi-auto-test-$$"

echo "1. Testing installation to test directory..."
export CHECK_INTERNET=1
export CHECK_METHOD=gateway
export INTERFACE_PRIORITY="en5,en0"

# Install to test directory
sudo bash dist/install-macos.sh "$TEST_WORKDIR" <<EOF
EOF

echo "2. Verifying installation..."
[ -f "$TEST_WORKDIR/eth-wifi-auto.sh" ] || { echo 'Switcher not installed'; exit 1; }
[ -f "$TEST_WORKDIR/uninstall.sh" ] || { echo 'Uninstaller not installed'; exit 1; }
[ -f "$TEST_WORKDIR/bin/ethwifiauto-watch" ] || { echo 'Watcher binary not installed'; exit 1; }
[ -f /usr/local/sbin/eth-wifi-auto.sh ] || { echo 'System helper not installed'; exit 1; }
[ -f /Library/LaunchDaemons/com.ethwifiauto.watch.plist ] || { echo 'LaunchDaemon plist not installed'; exit 1; }

echo "3. Testing that uninstall with --uninstall flag doesn't produce errors..."
# This should run without "illegal option" errors
if sudo bash dist/install-macos.sh --uninstall 2>&1 | grep -q "illegal option"; then
    echo "ERROR: Uninstall failed with 'illegal option' error"
    exit 1
fi

echo "4. Verifying cleanup after --uninstall..."
[ ! -f /usr/local/sbin/eth-wifi-auto.sh ] || { echo 'System helper not removed'; exit 1; }
[ ! -f /Library/LaunchDaemons/com.ethwifiauto.watch.plist ] || { echo 'LaunchDaemon plist not removed'; exit 1; }

echo "5. Cleanup test workspace..."
sudo rm -rf "$TEST_WORKDIR"

echo "All tests passed!"

echo "==================================="
echo "✓ macOS integration tests passed"
echo "==================================="
