#!/bin/sh
set -e

cd "$(dirname "$0")"

echo "========================================"
echo "Running All Tests"
echo "========================================"
echo ""

FAILED=0

# Run unit tests
echo "→ Running unit tests..."
echo ""

for test_file in unit/test_*.sh; do
    if [ -f "$test_file" ]; then
        echo "Running $(basename "$test_file")..."
        if sh "$test_file"; then
            echo ""
        else
            FAILED=$((FAILED + 1))
            echo "FAILED: $test_file"
            echo ""
        fi
    fi
done

# Run integration tests if Docker is available and running
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo "→ Running integration tests..."
    echo ""

    if [ -f "integration/test_linux_integration.sh" ]; then
        echo "Running Linux integration tests..."
        if bash integration/test_linux_integration.sh; then
            echo ""
        else
            FAILED=$((FAILED + 1))
            echo "FAILED: Linux integration tests"
            echo ""
        fi
    fi
else
    echo "→ Skipping Linux integration tests (Docker not available or not running)"
    echo ""
fi

# Run macOS integration tests if on macOS
if [ "$(uname -s)" = "Darwin" ] && [ -f "integration/test_macos_integration.sh" ]; then
    echo "→ Running macOS integration tests..."
    echo ""

    if bash integration/test_macos_integration.sh; then
        echo ""
    else
        FAILED=$((FAILED + 1))
        echo "FAILED: macOS integration tests"
        echo ""
    fi
fi

# Summary
echo "========================================"
if [ $FAILED -eq 0 ]; then
    echo "✓ All tests passed!"
    echo "========================================"
    exit 0
else
    echo "✗ $FAILED test(s) failed"
    echo "========================================"
    exit 1
fi
