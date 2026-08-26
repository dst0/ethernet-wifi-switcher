# TypeScript Testing Addendum

## Overview

With the TypeScript core migration, we now have **two test suites**:

1. **TypeScript tests** (Jest) - Test the core decision engine and CLI
2. **Shell tests** (Bash) - Test the old shell-based switcher (legacy)

## TypeScript Tests (New)

### Location
- `src/ts/core/__tests__/` - Core engine tests
- `src/ts/cli/__tests__/` - CLI tests

### Running
```bash
# Run all TypeScript tests
npm test

# Run with coverage
npm test -- --coverage

# Run specific test file
npm test -- src/ts/core/__tests__/engine.test.ts

# Watch mode
npm run test:watch
```

### Test Coverage

#### Core Engine Tests (15 tests)
- **Basic connect/disconnect** (4 tests)
  - Enable WiFi when ethernet connects
  - Disable WiFi when ethernet disconnects
  - No-op when already in correct state
  
- **DHCP timeout handling** (3 tests)
  - Wait when ethernet has link but no IP
  - Enable WiFi after timeout
  - Respect custom timeout values

- **Internet connectivity monitoring** (3 tests)
  - Enable WiFi when ethernet has no internet
  - Disable WiFi when ethernet has internet
  - Log state transitions correctly

- **State management** (2 tests)
  - Track ethernet state changes
  - Preserve state when unchanged

- **Factory functions** (2 tests)
  - createInitialState
  - createDefaultConfig

#### CLI Tests (13 tests)
- **loadFacts** (4 tests)
  - Load from environment variables
  - Use defaults when vars not set
  - Load from JSON file
  - Handle optional fields

- **loadConfig** (3 tests)
  - Load from environment variables
  - Use defaults when vars not set
  - Load from JSON file

- **formatAction** (6 tests)
  - Format all action types
  - DRY_RUN prefix
  - Consistent output format

### Test Philosophy

**TypeScript tests focus on:**
- Pure decision logic (no side effects)
- State transitions
- Edge cases (timeouts, failures)
- Deterministic outputs

**NOT tested in TypeScript:**
- Actual network commands (networksetup, nmcli)
- File system operations (tested via mocks)
- OS-specific behavior (handled by wrappers)

## Shell Tests (Legacy)

### Status
The shell tests in `tests/unit/*.test.sh` were written for the **old shell-based switcher**. They:
- Source `src/macos/switcher.sh` (old implementation)
- Mock system commands
- Test decision functions directly

### Migration Plan
These tests need to be:
1. **Adapted** to test the new TS wrappers, OR
2. **Replaced** with integration tests that verify end-to-end behavior

### Current State
- ✅ Preserved for reference
- ⚠️ Test old implementation (not TS core)
- 🚧 Need wrapper-based tests

## Running All Tests

```bash
# TypeScript tests
npm test

# Shell tests (old)
./tests/run_all_tests.sh

# Both (planned)
npm run test:all
```

## Test Matrix

| Test Type | What It Tests | Framework | Status |
|-----------|---------------|-----------|--------|
| TS Core Unit | Decision engine | Jest | ✅ 15 passing |
| TS CLI Unit | CLI I/O | Jest | ✅ 13 passing |
| Wrapper Integration | Fact collection + action application | Bash | 🚧 Planned |
| Old Shell Unit | Legacy switcher | Bash | ⚠️ Legacy |
| macOS Integration | Real installer | Bash | ✅ 1 passing |
| Linux Integration | Docker-based | Bash | ✅ Available |

## CI Integration

### Current
```yaml
- npm install
- npm test            # TypeScript tests
- ./tests/run_all_tests.sh  # Shell tests (old)
```

### Planned
```yaml
- npm install
- npm run build       # Compile TypeScript
- npm test           # TypeScript tests
- npm run lint       # ESLint
- ./tests/run_wrapper_tests.sh  # New wrapper tests
```

## Writing New Tests

### TypeScript Tests

**Location**: `src/ts/**/__tests__/*.test.ts`

**Example**:
```typescript
import { evaluate } from '../engine';
import { Facts, State, Config } from '../types';

describe('Engine', () => {
  test('should disable WiFi when ethernet connects', () => {
    const facts: Facts = {
      ethDev: 'eth0',
      wifiDev: 'wlan0',
      ethHasLink: true,
      ethHasIp: true,
      wifiIsOn: true,
      timestamp: Date.now()
    };
    const state = { lastEthState: 'disconnected' };
    const config = { timeout: 7, checkInternet: false, ... };

    const result = evaluate(facts, state, config);

    expect(result.actions).toContainEqual(
      expect.objectContaining({ type: 'DISABLE_WIFI' })
    );
  });
});
```

### Shell Wrapper Tests (Planned)

**Location**: `tests/unit/wrapper_*.test.sh`

**Example**:
```bash
test_wrapper_collects_facts() {
  # Mock system commands
  mock_networksetup "Wi-Fi Power: On"
  mock_ipconfig "192.168.1.100"
  
  # Run wrapper
  output=$(DRY_RUN=1 ./src/macos/switcher-ts-wrapper.sh)
  
  # Verify actions
  assert_contains "$output" "ACTION: DISABLE_WIFI"
}
```

## Debugging Tests

### TypeScript
```bash
# Run single test with output
npm test -- --verbose src/ts/core/__tests__/engine.test.ts

# Debug with Node inspector
node --inspect-brk ./node_modules/.bin/jest --runInBand
```

### Shell
```bash
# Run single test with trace
sh -x tests/unit/macos_switcher.test.sh

# Enable debug output
DEBUG=1 sh tests/unit/macos_switcher.test.sh
```

## Test Quality Checklist

- [ ] Pure functions tested with multiple scenarios
- [ ] Edge cases covered (timeouts, failures, empty values)
- [ ] State transitions verified
- [ ] Output format validated (for CLI tests)
- [ ] Mock setup/teardown working correctly
- [ ] Tests run in isolation (no shared state)
- [ ] Deterministic (no flaky tests)
- [ ] Fast (< 3 seconds for full suite)

## Coverage Goals

**Current**:
- TypeScript core: ~90% coverage
- CLI: ~85% coverage

**Target**:
- TypeScript core: > 95%
- CLI: > 90%
- Wrappers: > 80% (fact collection + action application)
