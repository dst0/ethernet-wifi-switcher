# Test Suite

Comprehensive testing framework for the Ethernet Wi-Fi Switcher project.

## Structure

```
tests/
├── lib/                    # Test framework libraries
│   ├── mock.sh            # Mock command framework
│   └── assert.sh          # Assertion functions
├── unit/                  # Unit tests with mocked commands
│   ├── auto_defaults_flag.test.sh           # Command-line flag tests
│   ├── linux_backends.test.sh               # Backend function tests
│   ├── linux_interface_detection.test.sh    # Interface detection tests
│   ├── linux_complex_scenarios.test.sh      # Complex edge cases
│   ├── internet_check.test.sh               # Connectivity check methods (Linux)
│   ├── internet_failover.test.sh            # Internet-based failover logic (Linux)
│   ├── ip_acquisition_retry.test.sh         # IP retry mechanisms (Linux)
│   ├── multi_interface.test.sh              # Priority selection (Linux)
│   ├── wifi_state_management.test.sh        # WiFi state transitions (Linux)
│   ├── wifi_complex_scenarios.test.sh       # WiFi edge cases (Linux)
│   ├── macos_internet_state_logging.test.sh # Internet state logging (macOS)
│   ├── macos_internet_check.test.sh         # Connectivity checks (macOS)
│   ├── macos_internet_failover.test.sh      # Failover scenarios (macOS)
│   ├── macos_ip_acquisition_retry.test.sh   # IP retry mechanisms (macOS)
│   ├── macos_multi_interface.test.sh        # Priority selection (macOS)
│   ├── macos_wifi_state_management.test.sh  # WiFi state transitions (macOS)
│   ├── macos_complex_scenarios.test.sh      # Complex edge cases (macOS)
│   ├── macos_interface_and_internet.test.sh # macOS-specific tests
│   ├── windows_basic.test.sh                # Windows basic tests (static)
│   ├── windows_complex_scenarios.test.sh    # Windows edge cases (static)
│   ├── internet_state_logging.test.ps1      # Internet state logging (Windows)
│   ├── internet_check.test.ps1              # Connectivity checks (Windows)
│   ├── internet_failover.test.ps1           # Failover scenarios (Windows)
│   ├── ip_acquisition_retry.test.ps1        # IP retry mechanisms (Windows)
│   ├── multi_interface.test.ps1             # Priority selection (Windows)
│   └── wifi_state_management.test.ps1       # WiFi state transitions (Windows)
├── integration/           # Integration tests in containers
│   ├── Dockerfile.linux
│   ├── test_linux_integration.sh
│   └── test_macos_integration.sh
├── run_all_tests.sh      # Run all tests
└── README.md             # This file
```

## Running Tests

### All Tests
```bash
./tests/run_all_tests.sh
```

### Unit Tests Only
```bash
# Run specific shell test
bash tests/unit/linux_interface_detection.test.sh

# Run specific PowerShell test (requires pwsh)
pwsh -File tests/unit/internet_state_logging.test.ps1

# Run all shell unit tests
for test in tests/unit/*.test.sh; do bash "$test"; done

# Run all PowerShell unit tests (requires pwsh)
for test in tests/unit/*.test.ps1; do pwsh -File "$test"; done

# Run all unit tests (both shell and PowerShell)
for test in tests/unit/*.test.sh; do bash "$test"; done
for test in tests/unit/*.test.ps1; do pwsh -File "$test"; done
```

### Integration Tests
Requires Docker:
```bash
./tests/integration/test_linux_integration.sh
```

## Test Framework

### Mock Framework (`lib/mock.sh`)

Mock system commands for isolated testing:

```bash
# Load framework
. tests/lib/mock.sh

# Setup mocks
setup_mocks

# Mock command output
mock_command nmcli "eth0 ethernet connected"

# Mock with exit code
mock_command_exit ping 0 "PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data."

# Clear mocks
clear_mocks

# Cleanup
teardown_mocks
```

### Assertion Framework (`lib/assert.sh`)

Write tests with assertions:

```bash
# Load framework
. tests/lib/assert.sh

# Start test
test_start "my_test_name"

# Assertions
assert_equals "expected" "actual" "Description"
assert_not_equals "unexpected" "actual" "Description"
assert_file_exists "/path/to/file" "Description"
assert_contains "haystack" "needle" "Description"

# Command result assertions
some_command
assert_success "Command should succeed"

# Print summary
test_summary
```

## Unit Tests

Unit tests mock all system commands to test logic in isolation:

### Platform Coverage Summary

| Platform | Language | Test Files | Test Count | Status |
|----------|----------|-----------|-----------|--------|
| Linux | Bash/Shell | 11 files | 60+ tests | ✅ Active |
| macOS | Bash/Shell | 8 files | 52 tests | ✅ Active |
| Windows | PowerShell | 6 files | 34 tests | ✅ Active |
| **Total** | **Multiple** | **25 files** | **146+ tests** | **✅ Executable** |

### Linux Tests
- **linux_backends.test.sh**: Tests both nmcli and ip backends, verifies all backend functions work correctly
- **linux_interface_detection.test.sh**: Tests interface detection logic with various tools (nmcli, ip, /sys/class/net)
- **linux_complex_scenarios.test.sh**: Tests complex edge cases specific to Linux (simultaneous changes, race conditions)
- **internet_check.test.sh**: Tests all three connectivity check methods (gateway, ping, curl)
- **internet_failover.test.sh**: Tests internet-based failover scenarios
- **internet_state_logging.test.sh**: Tests internet state logging messages (initialization, recovery, loss)
- **ip_acquisition_retry.test.sh**: Tests DHCP retry logic and timeout handling
- **multi_interface.test.sh**: Tests interface priority selection logic with multiple interfaces
- **wifi_state_management.test.sh**: Tests WiFi state transitions and radio control
- **wifi_complex_scenarios.test.sh**: Tests complex WiFi scenarios (delayed connections, failover)
- **auto_defaults_flag.test.sh**: Tests --auto and --defaults command-line flags and their behavior

### macOS Tests

All macOS tests use shell/bash and mock macOS-specific tools (networksetup, ipconfig, ifconfig, etc.):

- **macos_internet_state_logging.test.sh**: Tests internet state logging messages (initialization, recovery, loss)
- **macos_internet_check.test.sh**: Tests all three connectivity check methods (gateway ping, ICMP ping, HTTP curl)
- **macos_internet_failover.test.sh**: Tests internet-based failover scenarios (priority switching, recovery, multi-interface)
- **macos_ip_acquisition_retry.test.sh**: Tests DHCP retry logic using ipconfig and timeout handling
- **macos_multi_interface.test.sh**: Tests interface priority selection logic with multiple network adapters
- **macos_wifi_state_management.test.sh**: Tests WiFi state transitions using networksetup
- **macos_complex_scenarios.test.sh**: Tests complex edge cases specific to macOS (rapid toggling, simultaneous changes)
- **macos_interface_and_internet.test.sh**: Tests macOS-specific interface handling and internet checks (10 tests)

### Windows Tests (PowerShell Unit Tests)

All Windows tests are executable PowerShell unit tests (`.ps1`) that mock Windows-specific cmdlets (Get-NetAdapter, Get-NetRoute, etc.):

- **internet_state_logging.test.ps1**: Tests internet state logging messages (initialization, recovery, loss)
- **internet_check.test.ps1**: Tests all three connectivity check methods (gateway ping, ICMP ping, HTTP curl)
- **internet_failover.test.ps1**: Tests internet-based failover scenarios (priority switching, recovery, multi-interface)
- **ip_acquisition_retry.test.ps1**: Tests DHCP retry logic and timeout handling
- **multi_interface.test.ps1**: Tests interface priority selection logic with multiple network adapters
- **wifi_state_management.test.ps1**: Tests WiFi state transitions and radio control

**Running Windows PowerShell Tests:**

On macOS/Linux (with pwsh installed):
```bash
pwsh -File tests/unit/internet_state_logging.test.ps1
pwsh -File tests/unit/internet_check.test.ps1
pwsh -File tests/unit/internet_failover.test.ps1
pwsh -File tests/unit/ip_acquisition_retry.test.ps1
pwsh -File tests/unit/multi_interface.test.ps1
pwsh -File tests/unit/wifi_state_management.test.ps1

# Or run all at once:
for test in tests/unit/*.test.ps1; do echo "=== $(basename $test) ===" && pwsh -File "$test" && echo ""; done
```

On Windows (native PowerShell):
```powershell
pwsh -File tests/unit/internet_state_logging.test.ps1
# ... or other tests

# Run all:
Get-ChildItem tests/unit/*.test.ps1 | ForEach-Object { Write-Host "=== $($_.Name) ===" && & pwsh -File $_.FullName; Write-Host "" }
```

**Test Coverage Summary:**
- **internet_state_logging.test.ps1**: 7 tests (initialization with/without internet, recovery, loss, no-logging cases, multiple state changes)
- **internet_check.test.ps1**: 3 tests (gateway check, ICMP ping, HTTP/curl methods)
- **internet_failover.test.ps1**: 6 tests (priority switching, fallback to WiFi, recovery, multi-interface, no-internet handling)
- **ip_acquisition_retry.test.ps1**: 6 tests (immediate/delayed IP acquisition, timeouts, interface state, configurable timeouts)
- **multi_interface.test.ps1**: 6 tests (priority selection, Ethernet priority, fallback, dynamic priority updates)
- **wifi_state_management.test.ps1**: 6 tests (WiFi detection, enable/disable, state transitions, radio control, connection waits)
- **Total: 34 Windows-specific tests** (all operating on mocked Get-NetAdapter, Set-NetIPInterface, Test-NetConnection cmdlets)

### Adding New Unit Tests

1. Create `tests/unit/test_yourfeature.sh`
2. Load test frameworks:
   ```bash
   . "$(dirname "$0")/../lib/mock.sh"
   . "$(dirname "$0")/../lib/assert.sh"
   ```
3. Write test functions
4. Run tests and call `test_summary`

## Integration Tests

Integration tests run the full installer in Docker containers with real system tools:

- **test_linux_integration.sh**: Full install/uninstall cycle on Ubuntu
- Tests verify:
  - Installation completes successfully
  - All files are created in correct locations
  - Service is configured with proper environment variables
  - Uninstallation removes all files

### Adding New Integration Tests

1. Create `Dockerfile` for the platform
2. Create test script that runs in container
3. Verify installation, configuration, and cleanup

## CI/CD Integration

Tests run automatically in GitHub Actions:

```yaml
test:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - name: Run tests
      run: ./tests/run_all_tests.sh
```

## Best Practices

1. **Isolation**: Each test should be independent and not affect others
2. **Cleanup**: Always cleanup mocks and temporary files
3. **Descriptive Names**: Use clear test and assertion descriptions
4. **Fast**: Unit tests should run in milliseconds
5. **Coverage**: Test both success and failure paths

## Future Improvements

- [x] Add comprehensive Linux backend tests
- [x] Add WiFi state management tests
- [x] Add internet failover tests
- [x] Add complex scenario tests for all platforms
- [x] Add Windows PowerShell executable tests (34 tests across 6 files)
- [x] Add macOS comprehensive test suite (52 tests across 8 files)
- [ ] Add Windows complex scenario tests
- [ ] Add macOS integration tests (requires macOS runner)
- [ ] Add Windows integration tests (requires Windows runner)
- [ ] Add code coverage reporting
- [ ] Add performance benchmarks
- [ ] Add stress testing for event handling
