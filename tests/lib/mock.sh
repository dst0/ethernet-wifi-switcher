#!/bin/sh
# Mock framework for testing without actual system commands

# Mock storage directory
MOCK_DIR="${MOCK_DIR:-/tmp/eth-wifi-test-$$}"
mkdir -p "$MOCK_DIR"

# Mock command outputs
mock_command() {
    cmd_name="$1"
    shift
    output="$*"
    echo "$output" > "$MOCK_DIR/${cmd_name}.mock"
}

# Mock command with exit code
mock_command_exit() {
    cmd_name="$1"
    exit_code="$2"
    shift 2
    output="$*"
    echo "$output" > "$MOCK_DIR/${cmd_name}.mock"
    echo "$exit_code" > "$MOCK_DIR/${cmd_name}.exit"
}

# Clear all mocks
clear_mocks() {
    rm -rf "$MOCK_DIR"
    mkdir -p "$MOCK_DIR"
}

# Create mock binaries
setup_mocks() {
    export PATH="$MOCK_DIR/bin:$PATH"
    export MOCK_DIR
    mkdir -p "$MOCK_DIR/bin"

    # Create generic mock command wrapper
    for cmd in nmcli ip ping curl wget networksetup ipconfig ifconfig netstat; do
        cat > "$MOCK_DIR/bin/$cmd" << 'MOCK_EOF'
#!/bin/sh
cmd_name=$(basename "$0")
mock_file="$MOCK_DIR/${cmd_name}.mock"
exit_file="$MOCK_DIR/${cmd_name}.exit"

if [ -f "$mock_file" ]; then
    cat "$mock_file"
    if [ -f "$exit_file" ]; then
        exit_code=$(cat "$exit_file")
        exit "$exit_code"
    fi
    exit 0
else
    # Return empty output if not configured (don't fail)
    exit 0
fi
MOCK_EOF
        chmod +x "$MOCK_DIR/bin/$cmd"
    done
}

# Teardown mocks
teardown_mocks() {
    rm -rf "$MOCK_DIR"
}

# Mock file system for testing
mock_fs() {
    mkdir -p "$MOCK_DIR/sys/class/net/eth0"
    mkdir -p "$MOCK_DIR/sys/class/net/wlan0/wireless"
    echo "1" > "$MOCK_DIR/sys/class/net/eth0/carrier"
}

# Mock state file directory
mock_state_dir() {
    mkdir -p "$MOCK_DIR/state"
    export STATE_DIR="$MOCK_DIR/state"
    export STATE_FILE="$MOCK_DIR/state/eth-wifi-state"
}
