# Test Suite

This directory contains the test harness and tests for Ethernet Wi‑Fi Switcher.

If you only read one thing about test status/quality, read `../TESTING.md`.

## Quick start

Run what CI (and most developers) should run:

```bash
./tests/run_all_tests.sh
```

## What `run_all_tests.sh` actually runs

### Real unit tests (high value)
These tests source production code and call real functions while mocking external commands.

- `tests/unit/macos_switcher.test.sh` (macOS)
- `tests/unit/linux_switcher.test.sh` (Linux logic; runnable on macOS because it uses mocks)
- `tests/unit/linux_backends.test.sh` (Linux backends; runnable on macOS because it uses mocks)

### Integration tests (high value)
- `tests/integration/test_linux_integration.sh`
  - Runs **only if Docker is available and running**.
- `tests/integration/test_macos_integration.sh`
  - Runs **only on macOS**.
  - Requires `sudo` and performs real install/uninstall of the generated macOS installer.

### Not currently executed by the runner
Many other files exist in `tests/unit/` (including PowerShell and legacy shell tests). Most of those are *not* executed by `run_all_tests.sh` because:

- It only runs `unit/test_*.sh` (note the `test_` prefix) for legacy tests.
- Many files in this repo use the `*.test.sh` naming pattern and are **not** matched by `unit/test_*.sh`.

Until they’re wired into the runner (and made to call real production code), treat them as legacy/untrusted.

## Writing tests

### What counts as a “real” test for this repo

A test should:
1. Source production code (`src/...`) *or* run a produced installer/script.
2. Mock only external dependencies (system commands, filesystem, network).
3. Fail if the production logic breaks.

See `../TESTING.md` for the macOS-focused “how real are these tests?” report.

## Structure

```
tests/
├── lib/                      # assertion + mocking helpers
├── unit/                     # unit tests
├── integration/              # integration tests
├── run_all_tests.sh          # main test runner
└── README.md                 # this file
```
