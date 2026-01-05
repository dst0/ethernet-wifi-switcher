# Testing

This repo treats networking code as *high risk* and assumes it can fail in surprising ways. The goal of this document is to describe what tests exist **today**, what they *really* validate, and what’s still missing.

## TL;DR (Current reality)

- The test runner is `./tests/run_all_tests.sh`.
- On **macOS**, it currently runs:
  - **Real unit tests** (mocked system commands, real production functions):
    - `tests/unit/macos_switcher.test.sh` (21 tests)
  - **Integration tests** (real installer + real system changes):
    - `tests/integration/test_macos_integration.sh` (1 scenario)
- The runner also executes Linux unit tests and the Linux Docker integration test **if Docker is available**, even when invoked from macOS.
- Many other `tests/unit/*.test.*` files exist but are **not executed by `run_all_tests.sh`** (because it only runs `unit/test_*.sh` plus the three “real unit tests” listed above). Treat those as legacy/untrusted until they’re either deleted or wired into CI.

## How to run

Primary entry point:

```bash
./tests/run_all_tests.sh
```

macOS integration (requires sudo):

```bash
bash tests/integration/test_macos_integration.sh
```

## What “real” means here

For this project, a test is “real” only if it meets both:

1. **Executes production code** (sources `src/.../*.sh` or runs a produced installer/script).
2. **Only mocks external dependencies** (system commands, filesystem, network), not the core decision logic.

A test is *not* considered trustworthy if it re-implements the logic inside the test and then asserts that its own variables match.

## Current test inventory (as executed by `tests/run_all_tests.sh`)

### 1) macOS real unit tests (mocked commands, real functions)

**File:** `tests/unit/macos_switcher.test.sh`

**What it does**
- Sources **real** functions from `src/macos/switcher.sh` (filters out the `main "$@"` call so the script doesn’t start running).
- Creates a temporary mock `PATH` so calls to `networksetup`, `ipconfig`, `ifconfig`, `netstat`, `ping`, `curl` are intercepted by mocks.

**What it actually validates**
- Your parsing/decision logic when given specific command outputs.
- State file read/write behavior.
- Interface selection logic (including `INTERFACE_PRIORITY`).
- Connectivity check logic and error handling *given the mocked network/system responses*.

**What it does NOT validate**
- That real macOS tools behave like the mocks in all versions/locales.
- That routing actually changes on the machine.
- That events from `SCDynamicStore` are handled correctly (that’s driven by the Swift watcher).

**Tests (21) mapped to behaviors**
- State file:
  - `read_last_state` (file exists / missing / content variants)
  - `write_state` (connected/disconnected)
- Interface selection:
  - `get_eth_dev` (default + priority-driven)
  - `get_wifi_dev` (default + priority-driven)
- Wi‑Fi status & Ethernet status:
  - `wifi_is_on` (on/off)
  - `eth_has_link` (link up/down)
  - `eth_is_up` (has IP / no IP)
- Internet checks:
  - `check_internet` (gateway success + no gateway)
  - `check_internet` (curl inactive interface success + fail)
  - `check_internet` (ping success + missing target)

### 2) macOS integration test (real installer + real system locations)

**File:** `tests/integration/test_macos_integration.sh`

**This is the most “real” macOS test currently in the repo.**

**What it does**
- Builds `dist/install-macos.sh` via `./build.sh macos`.
- Runs the generated installer with `sudo`.
- Verifies that installation artifacts exist:
  - Installs helper to `/usr/local/sbin/eth-wifi-auto.sh`
  - Installs LaunchDaemon plist to `/Library/LaunchDaemons/com.ethwifiauto.watch.plist`
  - Installs a watcher binary into the chosen install directory.
- Runs `dist/install-macos.sh --uninstall` and verifies cleanup.

**What it validates**
- The build pipeline produces a runnable installer.
- Installer writes to the real macOS filesystem locations.
- Uninstall path works and removes system files.

**What it does NOT validate**
- That the background LaunchDaemon runs correctly long-term.
- That the watcher correctly responds to real link transitions.
- That actual switching happens (Wi‑Fi really toggles off/on as intended).

## macOS test status (as of 2026-01-05)

The test runner was executed on macOS and all executed tests passed:

- `tests/unit/macos_switcher.test.sh`: **21 passed**
- `tests/integration/test_macos_integration.sh`: **passed** (single scenario)

## How “real” are the macOS tests?

### Confidence levels (macOS)

- **Installer correctness (files/permissions/uninstall): medium-high**
  - We validate real file placement and uninstall cleanup.
  - We do *not* validate launchctl runtime behavior beyond install/uninstall.

- **Switcher logic correctness (decision-making): medium**
  - The unit test invokes real functions.
  - But it uses mocks for all macOS commands and for the network.

- **True end-to-end network behavior: low**
  - There is no test that forces real interface up/down and confirms:
    - Wi‑Fi power toggled
    - active route changed
    - connectivity restored
    - logs show the transition

If we assume the code is not reliable and needs exhaustive testing, the current macOS suite is a solid start but not sufficient.

## Coverage & edge cases (macOS)

### Covered reasonably well (unit-level)
- State persistence across runs (missing/empty/explicit values)
- Interface selection with priority lists
- Parsing / command output handling for:
  - default route lookup via `netstat`
  - Wi‑Fi power status via `networksetup`
  - IP presence via `ipconfig`
- Internet check mode errors:
  - missing gateway
  - missing `CHECK_TARGET` for ping
  - curl failure

### Not covered (or only indirectly covered)

#### “Real world” macOS behaviors
- Different `networksetup` output formats/locales.
- Different interface names (USB dongles can be `en7`, `en8`, etc.).
- Multiple Ethernet services simultaneously (Thunderbolt + USB + dock).
- Sleep/wake cycles (a major source of flakiness for network daemons).
- Captive portal behavior (HTTP 200 with portal content, redirects, TLS interception).

#### Failure modes we should assume exist
- Partial connectivity: DNS broken but ping works; ping blocked but HTTP works.
- Gateway reachable but internet down (gateway ping is a local-only proxy).
- Route table changes without link events.
- Race conditions:
  - state file written while another instance reads
  - watcher triggers multiple events rapidly
- Timing sensitivity:
  - DHCP takes longer than TIMEOUT
  - Wi‑Fi comes up but doesn’t associate immediately

## What to do next (macOS-focused, exhaustive mindset)

### 1) Add a macOS “runtime” E2E smoke test (high ROI)
Goal: verify the installed service *actually runs* and produces logs.

- Install to a temp dir.
- Use `launchctl print system/com.ethwifiauto.watch` to confirm it’s loaded.
- Tail logs for a short window and assert at least one “started” line.

### 2) Add a safe “no network changes” contract test
Goal: validate actual system command output parsing against the real machine without toggling interfaces.

- Run `networksetup -listallhardwareports` for real.
- Feed exact output into parsing functions (or record fixture outputs).

### 3) Add a controlled “real switching” test (careful)
This is inherently invasive. If you do it, gate it behind an explicit env flag (e.g., `RUN_DESTRUCTIVE_TESTS=1`).

Scenarios:
- Disable Wi‑Fi power, ensure script enables it when Ethernet disconnects.
- Plug/unplug Ethernet (or disable the interface) and verify:
  - Wi‑Fi power toggles
  - default route moves
  - connectivity checks reflect the change

### 4) Expand unit tests around parsing variability
Add fixtures for:
- multiple `netstat -rn` formats
- `ipconfig getifaddr` errors
- `ifconfig` output differences

## Document consolidation

The repo used to contain multiple overlapping Markdown reports about testing.
Those have been intentionally consolidated so that:
- `TESTING.md` is the single source of truth for test status/quality.
- `tests/README.md` tells you how to run and write tests.
