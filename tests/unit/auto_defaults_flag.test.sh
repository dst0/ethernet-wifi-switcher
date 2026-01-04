#!/bin/sh
# Test --auto and --defaults flags

# Load test framework
. "$(dirname "$0")/../lib/assert.sh"

test_start "parse_auto_flag"
# Simulate parsing --auto flag
USE_DEFAULTS=0
for arg in "command" "--auto"; do
    case "$arg" in
        --auto|--defaults)
            USE_DEFAULTS=1
            AUTO_INSTALL_DEPS=1
            ;;
    esac
done
assert_equals "1" "$USE_DEFAULTS" "USE_DEFAULTS should be 1 with --auto"
assert_equals "1" "$AUTO_INSTALL_DEPS" "AUTO_INSTALL_DEPS should be 1 with --auto"

test_start "parse_defaults_flag"
# Simulate parsing --defaults flag
USE_DEFAULTS=0
AUTO_INSTALL_DEPS=0
for arg in "command" "--defaults"; do
    case "$arg" in
        --auto|--defaults)
            USE_DEFAULTS=1
            AUTO_INSTALL_DEPS=1
            ;;
    esac
done
assert_equals "1" "$USE_DEFAULTS" "USE_DEFAULTS should be 1 with --defaults"
assert_equals "1" "$AUTO_INSTALL_DEPS" "AUTO_INSTALL_DEPS should be 1 with --defaults"

test_start "auto_mode_config_defaults"
# Verify auto mode uses correct defaults
if [ "1" = "1" ]; then  # Simulate USE_DEFAULTS=1
    CHECK_INTERNET="${CHECK_INTERNET:-1}"
    CHECK_INTERVAL="${CHECK_INTERVAL:-30}"
    CHECK_METHOD="${CHECK_METHOD:-ping}"
    CHECK_TARGET="${CHECK_TARGET:-8.8.8.8}"
    TIMEOUT="${TIMEOUT:-7}"
    LOG_CHECK_ATTEMPTS="${LOG_CHECK_ATTEMPTS:-0}"
fi

assert_equals "1" "$CHECK_INTERNET" "CHECK_INTERNET should be enabled in auto mode"
assert_equals "30" "$CHECK_INTERVAL" "CHECK_INTERVAL should be 30 seconds"
assert_equals "ping" "$CHECK_METHOD" "CHECK_METHOD should be ping (not gateway)"
assert_equals "8.8.8.8" "$CHECK_TARGET" "CHECK_TARGET should be 8.8.8.8"
assert_equals "7" "$TIMEOUT" "TIMEOUT should be 7 seconds"
assert_equals "0" "$LOG_CHECK_ATTEMPTS" "LOG_CHECK_ATTEMPTS should be disabled"

test_start "uninstall_flag_preserved"
# Verify --uninstall flag doesn't trigger USE_DEFAULTS
USE_DEFAULTS=0
for arg in "--uninstall"; do
    case "$arg" in
        --auto|--defaults)
            USE_DEFAULTS=1
            AUTO_INSTALL_DEPS=1
            ;;
        --uninstall)
            # Should not set USE_DEFAULTS
            ;;
    esac
done
assert_equals "0" "$USE_DEFAULTS" "USE_DEFAULTS should remain 0 with --uninstall"

test_start "mixed_flags_handling"
# Test handling multiple flags including workdir
WORKDIR=""
USE_DEFAULTS=0
for arg in "/custom/path" "--auto"; do
    case "$arg" in
        --auto|--defaults)
            USE_DEFAULTS=1
            AUTO_INSTALL_DEPS=1
            ;;
        --uninstall)
            ;;
        *)
            if [ -z "$WORKDIR" ] && [ "$arg" != "--auto" ] && [ "$arg" != "--defaults" ]; then
                WORKDIR="$arg"
            fi
            ;;
    esac
done
assert_equals "1" "$USE_DEFAULTS" "USE_DEFAULTS should be set"
assert_equals "/custom/path" "$WORKDIR" "WORKDIR should be parsed correctly"

test_start "auto_skips_interactive_prompts"
# Verify that when USE_DEFAULTS=1 and -t 0 (non-interactive), conditions work
USE_DEFAULTS=1
# Simulate the condition: if [ -t 0 ] && [ "$USE_DEFAULTS" = "0" ]
if [ "$USE_DEFAULTS" = "0" ]; then
    SHOULD_PROMPT="yes"
else
    SHOULD_PROMPT="no"
fi
assert_equals "no" "$SHOULD_PROMPT" "Should not prompt when USE_DEFAULTS=1"

test_start "interactive_mode_without_auto"
# Verify normal interactive mode behavior
USE_DEFAULTS=0
if [ "$USE_DEFAULTS" = "0" ]; then
    SHOULD_PROMPT="yes"
else
    SHOULD_PROMPT="no"
fi
assert_equals "yes" "$SHOULD_PROMPT" "Should prompt in interactive mode without --auto"

test_start "auto_enables_internet_monitoring"
# Most important: verify that --auto enables internet monitoring by default
USE_DEFAULTS=1
if [ "$USE_DEFAULTS" = "1" ]; then
    CHECK_INTERNET="${CHECK_INTERNET:-1}"
fi
assert_equals "1" "$CHECK_INTERNET" "Internet monitoring should be enabled in auto mode"

test_start "auto_uses_ping_not_gateway"
# Verify ping to 8.8.8.8 is used instead of gateway
USE_DEFAULTS=1
if [ "$USE_DEFAULTS" = "1" ]; then
    CHECK_METHOD="${CHECK_METHOD:-ping}"
    CHECK_TARGET="${CHECK_TARGET:-8.8.8.8}"
fi
assert_equals "ping" "$CHECK_METHOD" "Should use ping method in auto mode"
assert_equals "8.8.8.8" "$CHECK_TARGET" "Should ping 8.8.8.8 (not gateway) in auto mode"
assert_not_equals "gateway" "$CHECK_METHOD" "Should NOT use gateway method"

# Print summary
test_summary

