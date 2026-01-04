# Test Suite

Comprehensive testing framework for the Ethernet Wi-Fi Switcher project.

## Structure

```
tests/
├── lib/                    # Test framework libraries
│   ├── mock.sh            # Mock command framework
│   └── assert.sh          # Assertion functions
├── unit/                  # Unit tests with mocked commands
│   ├── test_linux_interface_detection.sh
│   ├── test_internet_check.sh
│   └── test_multi_interface.sh
├── integration/           # Integration tests in containers
│   ├── Dockerfile.linux
│   └── test_linux_integration.sh
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
# Run specific test
./tests/unit/test_linux_interface_detection.sh

# Run all unit tests
for test in tests/unit/test_*.sh; do sh "$test"; done
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

- **test_linux_interface_detection.sh**: Tests interface detection logic with various tools (nmcli, ip, /sys/class/net)
- **test_internet_check.sh**: Tests all three connectivity check methods (gateway, ping, curl)
- **test_multi_interface.sh**: Tests interface priority selection logic

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

- [ ] Add macOS-specific unit tests
- [ ] Add Windows PowerShell unit tests
- [ ] Add macOS integration tests (requires macOS runner)
- [ ] Add Windows integration tests
- [ ] Add code coverage reporting
- [ ] Add performance benchmarks
- [ ] Add stress testing for event handling
