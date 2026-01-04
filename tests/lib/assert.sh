#!/bin/sh
# Assertion framework for tests

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TEST_COUNT=0
TEST_PASS_COUNT=0
TEST_FAIL_COUNT=0

# Assertion counters (per current test)
CURRENT_TEST=""
CURRENT_TEST_ASSERTIONS=0
CURRENT_TEST_PASSED=0
CURRENT_TEST_FAILED=0

# Total assertion counters (across all tests)
TOTAL_ASSERTIONS=0
TOTAL_ASSERTIONS_PASSED=0
TOTAL_ASSERTIONS_FAILED=0

# Start a test
test_start() {
    # Finalize previous test if any
    if [ -n "$CURRENT_TEST" ]; then
        test_end
    fi

    CURRENT_TEST="$1"
    TEST_COUNT=$((TEST_COUNT + 1))
    CURRENT_TEST_ASSERTIONS=0
    CURRENT_TEST_PASSED=0
    CURRENT_TEST_FAILED=0
}

# End current test (internal)
test_end() {
    if [ $CURRENT_TEST_FAILED -gt 0 ]; then
        TEST_FAIL_COUNT=$((TEST_FAIL_COUNT + 1))
        echo "${RED}✗${NC} $CURRENT_TEST ($CURRENT_TEST_PASSED/$CURRENT_TEST_ASSERTIONS assertions passed)"
    else
        TEST_PASS_COUNT=$((TEST_PASS_COUNT + 1))
        echo "${GREEN}✓${NC} $CURRENT_TEST ($CURRENT_TEST_ASSERTIONS/$CURRENT_TEST_ASSERTIONS assertions)"
    fi
}

# Assert equal
assert_equals() {
    expected="$1"
    actual="$2"
    message="${3:-Values should be equal}"

    CURRENT_TEST_ASSERTIONS=$((CURRENT_TEST_ASSERTIONS + 1))
    TOTAL_ASSERTIONS=$((TOTAL_ASSERTIONS + 1))

    if [ "$expected" = "$actual" ]; then
        CURRENT_TEST_PASSED=$((CURRENT_TEST_PASSED + 1))
        TOTAL_ASSERTIONS_PASSED=$((TOTAL_ASSERTIONS_PASSED + 1))
        return 0
    else
        echo "  ${RED}✗${NC} $message (expected: '$expected', got: '$actual')"
        CURRENT_TEST_FAILED=$((CURRENT_TEST_FAILED + 1))
        TOTAL_ASSERTIONS_FAILED=$((TOTAL_ASSERTIONS_FAILED + 1))
        return 1
    fi
}

# Assert not equal
assert_not_equals() {
    unexpected="$1"
    actual="$2"
    message="${3:-Values should not be equal}"

    CURRENT_TEST_ASSERTIONS=$((CURRENT_TEST_ASSERTIONS + 1))
    TOTAL_ASSERTIONS=$((TOTAL_ASSERTIONS + 1))

    if [ "$unexpected" != "$actual" ]; then
        CURRENT_TEST_PASSED=$((CURRENT_TEST_PASSED + 1))
        TOTAL_ASSERTIONS_PASSED=$((TOTAL_ASSERTIONS_PASSED + 1))
        return 0
    else
        echo "  ${RED}✗${NC} $message (unexpected: '$unexpected', got: '$actual')"
        CURRENT_TEST_FAILED=$((CURRENT_TEST_FAILED + 1))
        TOTAL_ASSERTIONS_FAILED=$((TOTAL_ASSERTIONS_FAILED + 1))
        return 1
    fi
}

# Assert file exists
assert_file_exists() {
    file="$1"
    message="${2:-File should exist: $file}"

    CURRENT_TEST_ASSERTIONS=$((CURRENT_TEST_ASSERTIONS + 1))
    TOTAL_ASSERTIONS=$((TOTAL_ASSERTIONS + 1))

    if [ -f "$file" ]; then
        CURRENT_TEST_PASSED=$((CURRENT_TEST_PASSED + 1))
        TOTAL_ASSERTIONS_PASSED=$((TOTAL_ASSERTIONS_PASSED + 1))
        return 0
    else
        echo "  ${RED}✗${NC} $message"
        CURRENT_TEST_FAILED=$((CURRENT_TEST_FAILED + 1))
        TOTAL_ASSERTIONS_FAILED=$((TOTAL_ASSERTIONS_FAILED + 1))
        return 1
    fi
}

# Assert file does not exist
assert_file_not_exists() {
    file="$1"
    message="${2:-File should not exist: $file}"

    CURRENT_TEST_ASSERTIONS=$((CURRENT_TEST_ASSERTIONS + 1))
    TOTAL_ASSERTIONS=$((TOTAL_ASSERTIONS + 1))

    if [ ! -f "$file" ]; then
        CURRENT_TEST_PASSED=$((CURRENT_TEST_PASSED + 1))
        TOTAL_ASSERTIONS_PASSED=$((TOTAL_ASSERTIONS_PASSED + 1))
        return 0
    else
        echo "  ${RED}✗${NC} $message"
        CURRENT_TEST_FAILED=$((CURRENT_TEST_FAILED + 1))
        TOTAL_ASSERTIONS_FAILED=$((TOTAL_ASSERTIONS_FAILED + 1))
        return 1
    fi
}

# Assert contains
assert_contains() {
    haystack="$1"
    needle="$2"
    message="${3:-String should contain substring}"

    CURRENT_TEST_ASSERTIONS=$((CURRENT_TEST_ASSERTIONS + 1))
    TOTAL_ASSERTIONS=$((TOTAL_ASSERTIONS + 1))

    if echo "$haystack" | grep -q "$needle"; then
        CURRENT_TEST_PASSED=$((CURRENT_TEST_PASSED + 1))
        TOTAL_ASSERTIONS_PASSED=$((TOTAL_ASSERTIONS_PASSED + 1))
        return 0
    else
        echo "  ${RED}✗${NC} $message"
        CURRENT_TEST_FAILED=$((CURRENT_TEST_FAILED + 1))
        TOTAL_ASSERTIONS_FAILED=$((TOTAL_ASSERTIONS_FAILED + 1))
        return 1
    fi
}

# Assert command succeeds
assert_success() {
    message="${1:-Command should succeed}"

    CURRENT_TEST_ASSERTIONS=$((CURRENT_TEST_ASSERTIONS + 1))
    TOTAL_ASSERTIONS=$((TOTAL_ASSERTIONS + 1))

    if [ $? -eq 0 ]; then
        CURRENT_TEST_PASSED=$((CURRENT_TEST_PASSED + 1))
        TOTAL_ASSERTIONS_PASSED=$((TOTAL_ASSERTIONS_PASSED + 1))
        return 0
    else
        echo "  ${RED}✗${NC} $message"
        CURRENT_TEST_FAILED=$((CURRENT_TEST_FAILED + 1))
        TOTAL_ASSERTIONS_FAILED=$((TOTAL_ASSERTIONS_FAILED + 1))
        return 1
    fi
}

# Assert command fails
assert_failure() {
    message="${1:-Command should fail}"

    CURRENT_TEST_ASSERTIONS=$((CURRENT_TEST_ASSERTIONS + 1))
    TOTAL_ASSERTIONS=$((TOTAL_ASSERTIONS + 1))

    if [ $? -ne 0 ]; then
        CURRENT_TEST_PASSED=$((CURRENT_TEST_PASSED + 1))
        TOTAL_ASSERTIONS_PASSED=$((TOTAL_ASSERTIONS_PASSED + 1))
        return 0
    else
        echo "  ${RED}✗${NC} $message"
        CURRENT_TEST_FAILED=$((CURRENT_TEST_FAILED + 1))
        TOTAL_ASSERTIONS_FAILED=$((TOTAL_ASSERTIONS_FAILED + 1))
        return 1
    fi
}

# Print test summary
test_summary() {
    # Finalize last test
    if [ -n "$CURRENT_TEST" ]; then
        test_end
    fi

    echo ""
    echo "=================================="
    echo "Test Summary"
    echo "=================================="
    if [ $TEST_FAIL_COUNT -eq 0 ]; then
        echo "Tests: ${GREEN}$TEST_PASS_COUNT passed${NC} ($TEST_COUNT total)"
    else
        echo "Tests: ${GREEN}$TEST_PASS_COUNT passed${NC}, ${RED}$TEST_FAIL_COUNT failed${NC} ($TEST_COUNT total)"
    fi
    echo "=================================="

    if [ $TEST_FAIL_COUNT -gt 0 ]; then
        return 1
    fi
    return 0
}
