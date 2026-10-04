#!/bin/sh
# Source helper for unit tests
# Allows sourcing production scripts without executing their main logic

# Set a flag to prevent main execution when sourcing
export SOURCED_FOR_TESTING=1

# Source a script, preventing main execution by providing safe defaults
# Usage: source_script_functions <path_to_script> [platform]
source_script_functions() {
    script_path="$1"
    platform="${2:-generic}"

    if [ ! -f "$script_path" ]; then
        echo "ERROR: Script not found: $script_path" >&2
        return 1
    fi

    # Create temp file with modified script that stops before main execution
    temp_script=$(mktemp)

    case "$platform" in
        macos)
            # For macOS switcher, extract only functions (stop at 'main' call)
            # The script calls 'main "$@"' at the end
            sed -n '/^[a-zA-Z_][a-zA-Z_0-9]*()[ ]*{/,/^main "\$@"$/p' "$script_path" | \
                sed '/^main "\$@"$/d' > "$temp_script"
            ;;
        linux)
            # For Linux switcher, stop before the execution section
            # Look for "# Initial check" comment
            sed -n '1,/^# Initial check$/p' "$script_path" | \
                sed '/^# Initial check$/d' > "$temp_script"
            ;;
        backend)
            # Backend files are pure function definitions - safe to source directly
            cp "$script_path" "$temp_script"
            ;;
        *)
            # Generic: copy entire file (user responsibility to handle execution)
            cp "$script_path" "$temp_script"
            ;;
    esac

    # Source the temp file
    . "$temp_script"
    rm -f "$temp_script"
}

# Source macOS switcher functions only (no main execution)
source_macos_switcher() {
    script_path="${1:-$(dirname "$0")/../../src/macos/switcher.sh}"

    # For macOS, we need to handle the script structure carefully
    # The script has functions defined first, then main() function, then main "$@" call

    # We'll source up to but not including the final main call
    # by creating a modified temp version

    temp_script=$(mktemp)

    # Copy everything except the final "main "$@"" line
    grep -v '^main "\$@"$' "$script_path" > "$temp_script"

    # Add a guard so main() doesn't auto-execute
    echo '# Sourced for testing - main not called' >> "$temp_script"

    . "$temp_script"
    rm -f "$temp_script"
}

# Source Linux switcher functions only
source_linux_switcher() {
    script_path="${1:-$(dirname "$0")/../../src/linux/switcher.sh}"

    temp_script=$(mktemp)

    # Copy up to the execution section (before "# Initial check")
    sed -n '1,/^# Initial check$/p' "$script_path" | \
        sed '/^# Initial check$/d' > "$temp_script"

    . "$temp_script"
    rm -f "$temp_script"
}

# Source Linux backend (safe to source directly)
source_linux_backend() {
    backend="${1:-nmcli}"
    script_dir="${2:-$(dirname "$0")/../../src/linux/lib}"

    case "$backend" in
        nmcli)
            . "$script_dir/network-nmcli.sh"
            ;;
        ip)
            . "$script_dir/network-ip.sh"
            ;;
        *)
            echo "ERROR: Unknown backend: $backend" >&2
            return 1
            ;;
    esac
}

# Mock external commands for testing
# This creates shell functions that override the actual commands
mock_external_command() {
    cmd_name="$1"
    output="$2"
    exit_code="${3:-0}"

    # Create a shell function that overrides the command
    eval "$cmd_name() {
        echo '$output'
        return $exit_code
    }"
}

# Mock external command with dynamic output based on arguments
# Usage: mock_external_command_dynamic <cmd_name> <case_statement_body>
mock_external_command_dynamic() {
    cmd_name="$1"
    shift
    cases="$*"

    eval "$cmd_name() {
        case \"\$*\" in
            $cases
        esac
    }"
}

