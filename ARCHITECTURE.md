# TypeScript Core Architecture

## Overview

The ethernet-wifi-switcher now uses a hybrid architecture with a **TypeScript core engine** for decision-making and **thin shell wrappers** for platform-specific operations.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ Platform Layer (Shell/PowerShell)                           │
│  • Collect network facts (link status, IP, WiFi state)      │
│  • Execute OS-specific commands (networksetup, nmcli, etc)  │
└──────────────────┬──────────────────────────────────────────┘
                   │ Facts (env vars)
                   ▼
┌─────────────────────────────────────────────────────────────┐
│ TypeScript Core (Node.js)                                   │
│  • Pure decision engine: evaluate(facts, state, config)     │
│  • Zero side effects, fully deterministic                   │
│  • Returns: actions, reason codes, new state                │
└──────────────────┬──────────────────────────────────────────┘
                   │ Actions (stdout)
                   ▼
┌─────────────────────────────────────────────────────────────┐
│ Platform Layer (Shell/PowerShell)                           │
│  • Parse and apply actions                                  │
│  • Update system state (enable/disable WiFi)                │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. TypeScript Core (`src/ts/`)

#### Core Engine (`src/ts/core/engine.ts`)
- **Pure decision function**: `evaluate(facts: Facts, state: State, config: Config) -> DecisionResult`
- No side effects - only transforms inputs to outputs
- Handles all decision logic:
  - Ethernet connect/disconnect
  - DHCP timeout and retry
  - Internet connectivity monitoring
  - Interface failover
  - State transitions

#### Types (`src/ts/core/types.ts`)
- **Facts**: Current network state (readonly data from platform)
  - `ethHasLink`, `ethHasIp`, `wifiIsOn`
  - Optional: `ethHasInternet`, `wifiHasInternet`
  
- **State**: Persistent state across invocations
  - `lastEthState`, `lastEthStateChange`
  - `lastInternetCheckState`, `lastInternetCheckSuccess`

- **Config**: User configuration
  - `timeout`, `checkInternet`, `checkMethod`
  - `checkInterval`, `logAllChecks`, `interfacePriority`

- **Actions**: Commands to execute
  - `ENABLE_WIFI`, `DISABLE_WIFI`
  - `WAIT_FOR_IP`, `CHECK_INTERNET`
  - `LOG`, `NO_ACTION`

#### CLI (`src/ts/cli/cli.ts`)
- Command-line interface to the core engine
- **Input**: Environment variables or JSON files
- **Output**: Deterministic action lines (parseable by shell)
- **Features**:
  - DRY_RUN mode (prefix with `[DRY_RUN]`)
  - State file management
  - Help and documentation

### 2. Platform Wrappers

#### macOS Wrapper (`src/macos/switcher-ts-wrapper.sh`)
```bash
collect_facts() {
  # Use networksetup, ipconfig, ifconfig
  # Set: ETH_HAS_LINK, ETH_HAS_IP, WIFI_IS_ON
}

apply_action() {
  case "$action_type" in
    ENABLE_WIFI) networksetup -setairportpower on ;;
    DISABLE_WIFI) networksetup -setairportpower off ;;
    # ...
  esac
}

main() {
  collect_facts
  export facts...
  node $TS_CLI | while read line; do
    apply_action "$line"
  done
}
```

#### Linux Wrapper (`src/linux/switcher-ts-wrapper.sh`)
- Similar structure to macOS
- Uses backend libraries (`network-nmcli.sh`, `network-ip.sh`)
- Handles multiple WiFi control methods (NetworkManager, rfkill)

#### Windows Wrapper (`src/windows/switcher-ps1-wrapper.ps1`)
- **TODO**: To be implemented
- Will use PowerShell cmdlets for fact collection
- Apply actions via `Get-NetAdapter`, `Set-NetAdapterBinding`

### 3. Swift Watcher (macOS Only)

`src/macos/EthWifiWatch.swift` remains unchanged:
- Monitors `SCDynamicStore` for network events
- Triggers wrapper when changes detected
- No decision logic - just event detection

## Data Flow

### Example: Ethernet Connects

1. **Event**: User plugs in ethernet cable
2. **Watcher** (Swift): Detects link change, calls wrapper
3. **Wrapper** (Shell):
   - Collects facts: `ETH_HAS_LINK=1`, `ETH_HAS_IP=0`, `WIFI_IS_ON=1`
   - Exports to environment
4. **CLI** (Node.js):
   - Loads facts from env vars
   - Loads previous state from file
   - Calls `evaluate(facts, state, config)`
5. **Engine** (TypeScript):
   - Detects: Link but no IP
   - Decision: Wait for DHCP (up to timeout)
   - Returns: `WAIT_FOR_IP` action
6. **CLI** (Node.js):
   - Formats action: `ACTION: WAIT_FOR_IP duration=1`
   - Outputs to stdout
   - Saves new state
7. **Wrapper** (Shell):
   - Parses action line
   - Executes: `sleep 1`
   - Re-runs wrapper to check again

### Example: Ethernet Has No Internet

1. **Wrapper**: Collects facts including `ETH_HAS_INTERNET=0`
2. **Engine**: 
   - Detects: Ethernet connected but no internet
   - Decision: Enable WiFi for failover
   - Returns: `ENABLE_WIFI` + `LOG` actions
3. **Wrapper**: Executes `networksetup -setairportpower on`

## Testing Strategy

### TypeScript Tests
- **Unit tests** (`src/ts/**/__tests__/*.test.ts`)
- Test engine with mocked facts
- Test CLI with mocked filesystem
- Jest framework
- Run with: `npm test`

### Integration Tests
- **Wrapper tests** (planned)
- Test with mock system commands
- Verify fact collection
- Verify action application
- Shell-based tests using existing infrastructure

### Legacy Shell Tests
- Original tests in `tests/unit/*.test.sh`
- Test old shell-based switcher
- **Status**: Preserved for reference
- **Plan**: Adapt or replace with wrapper tests

## Environment Variables

### Facts (Input to CLI)
- `ETH_DEV`: Ethernet interface name
- `WIFI_DEV`: WiFi interface name
- `ETH_HAS_LINK`: `1` if ethernet has link
- `ETH_HAS_IP`: `1` if ethernet has IP
- `WIFI_IS_ON`: `1` if WiFi is powered on
- `ETH_HAS_INTERNET`: `1` if ethernet has internet (optional)
- `WIFI_HAS_INTERNET`: `1` if WiFi has internet (optional)

### Config (Input to CLI)
- `TIMEOUT`: DHCP timeout in seconds (default: 7)
- `CHECK_INTERNET`: `1` to enable internet monitoring
- `CHECK_METHOD`: `gateway`, `ping`, or `curl`
- `CHECK_TARGET`: Target for ping/curl checks
- `CHECK_INTERVAL`: Check interval in seconds (default: 30)
- `LOG_ALL_CHECKS`: `1` to log every check attempt
- `INTERFACE_PRIORITY`: Comma-separated interface order

### Runtime
- `STATE_FILE`: Path to state file (default: /tmp/eth-wifi-state)
- `DRY_RUN`: `1` for dry-run mode (no actual actions)
- `DEBUG`: `1` for verbose debug output
- `TS_CLI`: Path to TypeScript CLI (default: platform-specific)

## Output Format

### Action Lines
```
ACTION: ENABLE_WIFI
ACTION: DISABLE_WIFI
ACTION: WAIT_FOR_IP duration=5
ACTION: CHECK_INTERNET interface=eth0
ACTION: FORCE_ROUTE interface=eth0 gateway=192.168.1.1
ACTION: NO_ACTION
```

### Log Lines
```
LOG: Ethernet connected - WiFi disabled
LOG: Ethernet disconnected - WiFi enabled
LOG: Internet check: eth0 is now unreachable (was working before)
```

### Reason Codes
```
REASON: ETH_CONNECTED
REASON: ETH_DISCONNECTED
REASON: ETH_NO_INTERNET
REASON: ETH_WAITING_FOR_IP
REASON: ETH_IP_TIMEOUT
REASON: WIFI_ALREADY_ON
REASON: WIFI_ALREADY_OFF
```

## Development Guide

### Building
```bash
# Build TypeScript
npm run build

# Build all platforms
./build.sh

# Build specific platform
./build.sh macos
```

### Testing
```bash
# Run TypeScript tests
npm test

# Run shell tests
./tests/run_all_tests.sh

# Run specific test
npm test -- src/ts/core/__tests__/engine.test.ts
```

### Adding New Features

1. **Add to TypeScript core**:
   - Update types in `src/ts/core/types.ts`
   - Update engine logic in `src/ts/core/engine.ts`
   - Add tests in `src/ts/core/__tests__/`

2. **Update CLI** (if needed):
   - Add env var parsing in `src/ts/cli/cli.ts`
   - Update help text
   - Add CLI tests

3. **Update wrappers** (if needed):
   - Add fact collection logic
   - Add action application logic
   - Test with mock commands

### Debugging

#### Enable Debug Output
```bash
DEBUG=1 ETH_DEV=en5 WIFI_DEV=en0 ... node dist/ts/cli/cli.js
```

#### Dry-Run Mode
```bash
DRY_RUN=1 ./src/macos/switcher-ts-wrapper.sh
```

#### State Inspection
```bash
cat /tmp/eth-wifi-state
# Shows: {"lastEthState":"connected","lastEthStateChange":1234567890}
```

## Migration Notes

### From Old Shell Architecture

**Before** (shell-based):
- Decision logic embedded in `switcher.sh`
- Difficult to test without mocking many functions
- State management spread across functions
- Hard to reason about all possible states

**After** (TypeScript core):
- Decision logic in pure function
- Easy to test - just pass different facts
- State management explicit and typed
- All states visible in tests

### Backward Compatibility

- Original `src/macos/switcher.sh` preserved
- New wrapper: `src/macos/switcher-ts-wrapper.sh`
- Installers can choose which to use
- Migration path: Update one platform at a time

### Performance

- Negligible overhead: 50-100ms for Node.js startup
- Still event-driven (0% CPU when idle)
- State saved to file (no persistent Node.js process)
- Same external command latency (networksetup, etc)

## Future Enhancements

1. **Daemon Mode**: Keep Node.js process running to avoid startup overhead
2. **WebSocket API**: Expose engine as a service for GUI clients
3. **Config File**: Move from env vars to JSON config file
4. **Plugins**: Allow custom decision logic via plugins
5. **Analytics**: Track state transitions and export metrics
