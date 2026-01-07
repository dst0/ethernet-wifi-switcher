#!/bin/bash
set -e

echo "==================================="
echo "Linux Integration Test"
echo "==================================="

# Build and run in Docker
cd "$(dirname "$0")/../.."

# Build the installer first
./build.sh linux

# Build test container
docker build -t eth-wifi-test-linux -f tests/integration/Dockerfile.linux .

# Run tests in container
docker run --rm \
    eth-wifi-test-linux \
    bash -c "
        set -e
        echo '1. Testing installation with environment overrides...'
        # Use environment variables to avoid interactive prompts and nmcli issues
        export CHECK_INTERNET=1
        export CHECK_METHOD=gateway
        export INTERFACE_PRIORITY='eth0,wlan0'
        export CHECK_TARGET=''
        export CHECK_INTERVAL=10
        export LOG_ALL_CHECKS=0
        export TEST_MODE=1  # Skip systemd operations

        sudo -E bash /test/install-linux.sh <<EOF
y
EOF

        echo '2. Verifying installation...'
        [ -f /tmp/eth-wifi-auto-test/eth-wifi-auto.sh ] || { echo 'Switcher not installed'; exit 1; }
        [ -f /tmp/eth-wifi-auto-test/uninstall.sh ] || { echo 'Uninstaller not installed'; exit 1; }
        [ -f /tmp/eth-wifi-auto-test.service ] || { echo 'Service file not created'; exit 1; }

        echo '3. Verifying service configuration...'
        grep -q 'INTERFACE_PRIORITY=eth0,wlan0' /tmp/eth-wifi-auto-test.service || { echo 'Priority not configured'; exit 1; }
        grep -q 'CHECK_INTERNET=1' /tmp/eth-wifi-auto-test.service || { echo 'Internet check not enabled'; exit 1; }
        grep -q 'CHECK_METHOD=gateway' /tmp/eth-wifi-auto-test.service || { echo 'Check method not configured'; exit 1; }

        echo '4. Testing uninstallation...'
        export TEST_MODE=1
        sudo -E bash /tmp/eth-wifi-auto-test/uninstall.sh

        echo '5. Verifying cleanup...'
        [ ! -f /tmp/eth-wifi-auto-test/eth-wifi-auto.sh ] || { echo 'Switcher not removed'; exit 1; }
        [ ! -f /tmp/eth-wifi-auto-test.service ] || { echo 'Service file not removed'; exit 1; }

        echo 'All tests passed!'
    "

echo "==================================="
echo "✓ Integration tests passed"
echo "==================================="
