#!/bin/bash
set -euo pipefail

# =========================================================
# Eth/Wi-Fi Auto Switcher (macOS Installer Template)
# =========================================================

DAEMON_LABEL="com.ethwifiauto.watch"

# System install paths
SYS_HELPER_PATH="/usr/local/sbin/eth-wifi-auto.sh"
SYS_WATCHER_BIN="/usr/local/sbin/ethwifiauto-watch"
SYS_PLIST_PATH="/Library/LaunchDaemons/${DAEMON_LABEL}.plist"

DEFAULT_WORKDIR="${HOME}/.ethernet-wifi-auto-switcher"
WORKDIR="${1:-}"

# If no workdir provided and interactive, ask user
if [[ -z "$WORKDIR" && -t 0 ]]; then
  read -p "Enter installation directory [$DEFAULT_WORKDIR]: " input_dir
  WORKDIR=${input_dir:-$DEFAULT_WORKDIR}
fi

WORKDIR="${WORKDIR:-$DEFAULT_WORKDIR}"

# PLACEHOLDERS (Filled by build-macos.sh)
WATCHER_BASE64="__WATCHER_BINARY_B64__"
HELPER_CONTENT_B64="__HELPER_SCRIPT_B64__"
UNINSTALL_CONTENT_B64="__UNINSTALL_SCRIPT_B64__"
PLIST_CONTENT_B64="__PLIST_TEMPLATE_B64__"

die(){ echo "ERROR: $*" >&2; exit 1; }
need_macos(){ [[ "$(uname -s)" == "Darwin" ]] || die "macOS only."; }

ensure_root(){
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Re-running with sudo..."
    exec sudo -E bash "$0" "$WORKDIR"
  fi
}

real_user_home(){
  if [[ -n "${SUDO_USER:-}" ]]; then
    dscl . -read "/Users/${SUDO_USER}" NFSHomeDirectory 2>/dev/null | awk '{print $2}'
  else
    echo "$HOME"
  fi
}

detect_interfaces() {
    echo "Detecting network interfaces..."

    # Detect defaults
    AUTO_WIFI=$(networksetup -listallhardwareports | awk '/Hardware Port: (Wi-Fi|AirPort)/ {getline; print $2}' | head -n 1) || AUTO_WIFI=""
    AUTO_ETH=$(networksetup -listallhardwareports | awk '/Hardware Port: (Ethernet|LAN|USB 10\/100\/1000 LAN)/ {getline; print $2}' | head -n 1) || AUTO_ETH=""

    if [[ -z "$AUTO_ETH" ]]; then
        AUTO_ETH=$(networksetup -listallhardwareports | awk '/Device: en/ {print $2}' | grep -v "^${AUTO_WIFI}$" | head -n 1) || AUTO_ETH=""
    fi

    if [[ -t 0 ]]; then
        echo ""
        echo "Available network interfaces:"
        networksetup -listallhardwareports
        echo ""

        WIFI_PROMPT=${AUTO_WIFI:-"Not set"}
        read -p "Enter Wi-Fi interface [$WIFI_PROMPT]: " input_wifi
        WIFI_DEV=${input_wifi:-$AUTO_WIFI}

        ETH_PROMPT=${AUTO_ETH:-"Not set"}
        read -p "Enter Ethernet interface [$ETH_PROMPT]: " input_eth
        ETH_DEV=${input_eth:-$AUTO_ETH}
    else
        WIFI_DEV="$AUTO_WIFI"
        ETH_DEV="$AUTO_ETH"
    fi

    echo ""
    echo "Using interfaces:"
    echo "  Wi-Fi:    ${WIFI_DEV:-not found}"
    echo "  Ethernet: ${ETH_DEV:-not found}"

    if [[ -z "$WIFI_DEV" || -z "$ETH_DEV" ]]; then
        die "Both Wi-Fi and Ethernet interfaces must be specified to continue."
    fi
}

stop_processes_by_pattern() {
    local pattern="$1"
    local label="$2"
    local pids
    pids=$(pgrep -f "$pattern" || true)

    if [[ -n "$pids" ]]; then
        echo "Stopping $label processes..."
        for pid in $pids; do
            pname=$(ps -p "$pid" -o comm= 2>/dev/null || echo "$pattern")
            kill "$pid" 2>/dev/null || true
            sleep 0.1
            if ! ps -p "$pid" >/dev/null 2>&1; then
                echo "    process $pid $pname stopped"
            else
                echo "    process $pid $pname failed to stop"
            fi
        done
    fi
}

cleanup_existing() {
    local found_old_install=0

    # 1. Look for the standard plist
    if [[ -f "$SYS_PLIST_PATH" ]]; then
        found_old_install=1
        echo "Old installation detected at: $SYS_PLIST_PATH"

        # Use plutil to safely extract values (handles binary plists)
        OLD_WORKDIR=$(plutil -extract WorkingDirectory raw -o - "$SYS_PLIST_PATH" 2>/dev/null || true)

        if [[ -z "$OLD_WORKDIR" ]]; then
            OLD_LOGPATH=$(plutil -extract StandardOutPath raw -o - "$SYS_PLIST_PATH" 2>/dev/null || true)
            if [[ -n "$OLD_LOGPATH" ]]; then
                OLD_WORKDIR=$(dirname "$OLD_LOGPATH")
            fi
        fi

        if [[ -n "$OLD_WORKDIR" ]]; then
            echo "  Workspace directory: $OLD_WORKDIR"
        fi

        if [[ -n "$OLD_WORKDIR" ]] && [[ -f "$OLD_WORKDIR/uninstall.sh" ]]; then
            echo "  Running existing uninstaller..."
            bash "$OLD_WORKDIR/uninstall.sh" || true
        else
            if [[ -z "$OLD_WORKDIR" ]]; then
                echo "  Workspace directory not found. Performing manual cleanup..."
            else
                echo "  No uninstaller found. Performing manual cleanup..."
            fi
            stop_processes_by_pattern "ethwifiauto-watch" "watcher"
            stop_processes_by_pattern "eth-wifi-auto.sh" "helper"
            launchctl bootout system "$SYS_PLIST_PATH" 2>/dev/null || true
            launchctl unload "$SYS_PLIST_PATH" 2>/dev/null || true
            rm -f "$SYS_PLIST_PATH" "$SYS_HELPER_PATH" "$SYS_WATCHER_BIN"
        fi
    fi

    # 2. Extra safety: check for any other plists that might be ours
    for extra_plist in /Library/LaunchDaemons/com.eth-wifi-auto*.plist /Library/LaunchDaemons/com.ethwifiauto*.plist; do
        if [[ -f "$extra_plist" ]]; then
            # Skip the one we are about to install if it's already there (handled above)
            [[ "$extra_plist" == "$SYS_PLIST_PATH" ]] && continue

            found_old_install=1
            echo "Old installation detected at: $extra_plist"
            echo "  Removing legacy configuration..."
            stop_processes_by_pattern "ethwifiauto-watch" "watcher"
            stop_processes_by_pattern "eth-wifi-auto.sh" "helper"
            launchctl bootout system "$extra_plist" 2>/dev/null || true
            launchctl unload "$extra_plist" 2>/dev/null || true
            rm -f "$extra_plist"
        fi
    done

    # 3. Report status
    if [[ "$found_old_install" -eq 0 ]]; then
        echo "No old installation detected."
    fi
}

main(){
  need_macos
  ensure_root
  cleanup_existing
  detect_interfaces

  if [[ "$WORKDIR" == "$DEFAULT_WORKDIR" && -n "${SUDO_USER:-}" ]]; then
    WORKDIR="$(real_user_home)/.ethernet-wifi-auto-switcher"
  fi

  WORKDIR="$(python3 -c 'import os,sys; print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "$WORKDIR")"

  mkdir -p "$WORKDIR"
  chmod 755 "$WORKDIR" || true

  SRC_DIR="${WORKDIR}/src"
  BIN_DIR="${WORKDIR}/bin"
  STATE_DIR="${WORKDIR}/state"
  mkdir -p "$SRC_DIR" "$BIN_DIR" "$STATE_DIR"
  chmod 755 "$SRC_DIR" "$BIN_DIR" "$STATE_DIR" || true

  WATCH_LOG="${WORKDIR}/watch.log"
  WATCH_ERR="${WORKDIR}/watch.err"
  HELPER_LOG="${WORKDIR}/helper.log"
  HELPER_ERR="${WORKDIR}/helper.err"

  WORK_HELPER="${WORKDIR}/eth-wifi-auto.sh"
  WORK_BIN="${BIN_DIR}/ethwifiauto-watch"
  WORK_PLIST="${WORKDIR}/${DAEMON_LABEL}.plist"
  WORK_UNINSTALL="${WORKDIR}/uninstall.sh"

  echo "Installation directory: $WORKDIR"
  echo ""

  echo "Extracting helper script..."
  echo "$HELPER_CONTENT_B64" | base64 -d > "$WORK_HELPER"
  sed -i '' "s|WIFI_DEV=\"\${WIFI_DEV:-en0}\"|WIFI_DEV=\"$WIFI_DEV\"|g" "$WORK_HELPER"
  sed -i '' "s|ETH_DEV=\"\${ETH_DEV:-en5}\"|ETH_DEV=\"$ETH_DEV\"|g" "$WORK_HELPER"
  sed -i '' "s|STATE_DIR=\"\${STATE_DIR:-/tmp}\"|STATE_DIR=\"$STATE_DIR\"|g" "$WORK_HELPER"
  chmod +x "$WORK_HELPER"

  echo "Extracting watcher binary..."
  echo "$WATCHER_BASE64" | base64 -d > "$WORK_BIN"
  chmod +x "$WORK_BIN"
  /usr/bin/codesign -s - "$WORK_BIN" >/dev/null 2>&1 || true

  echo "Installing system binaries..."
  mkdir -p /usr/local/sbin
  cp -f "$WORK_HELPER" "$SYS_HELPER_PATH"
  cp -f "$WORK_BIN" "$SYS_WATCHER_BIN"
  chmod +x "$SYS_HELPER_PATH" "$SYS_WATCHER_BIN"

  echo "Generating LaunchDaemon plist..."
  echo "$PLIST_CONTENT_B64" | base64 -d > "$WORK_PLIST"
  sed -i '' "s|\$DAEMON_LABEL|$DAEMON_LABEL|g" "$WORK_PLIST"
  sed -i '' "s|\$SYS_WATCHER_BIN|$SYS_WATCHER_BIN|g" "$WORK_PLIST"
  sed -i '' "s|\$SYS_HELPER_PATH|$SYS_HELPER_PATH|g" "$WORK_PLIST"
  sed -i '' "s|\$HELPER_LOG|$HELPER_LOG|g" "$WORK_PLIST"
  sed -i '' "s|\$HELPER_ERR|$HELPER_ERR|g" "$WORK_PLIST"
  sed -i '' "s|\$WATCH_LOG|$WATCH_LOG|g" "$WORK_PLIST"
  sed -i '' "s|\$WATCH_ERR|$WATCH_ERR|g" "$WORK_PLIST"
  sed -i '' "s|\$WIFI_DEV|$WIFI_DEV|g" "$WORK_PLIST"
  sed -i '' "s|\$ETH_DEV|$ETH_DEV|g" "$WORK_PLIST"
  sed -i '' "s|\$WORKDIR|$WORKDIR|g" "$WORK_PLIST"

  cp -f "$WORK_PLIST" "$SYS_PLIST_PATH"
  chown root:wheel "$SYS_PLIST_PATH"
  chmod 644 "$SYS_PLIST_PATH"

  echo "Extracting uninstall script..."
  echo "$UNINSTALL_CONTENT_B64" | base64 -d > "$WORK_UNINSTALL"
  sed -i '' "s|SYS_PLIST_PATH_PLACEHOLDER|$SYS_PLIST_PATH|g" "$WORK_UNINSTALL"
  sed -i '' "s|SYS_HELPER_PATH_PLACEHOLDER|$SYS_HELPER_PATH|g" "$WORK_UNINSTALL"
  sed -i '' "s|SYS_WATCHER_BIN_PLACEHOLDER|$SYS_WATCHER_BIN|g" "$WORK_UNINSTALL"
  sed -i '' "s|WORKDIR_PLACEHOLDER|$WORKDIR|g" "$WORK_UNINSTALL"
  chmod +x "$WORK_UNINSTALL"

  echo "Loading LaunchDaemon..."
  launchctl bootout system "$SYS_PLIST_PATH" >/dev/null 2>&1 || true
  launchctl bootstrap system "$SYS_PLIST_PATH" >/dev/null 2>&1 || true

  echo "✅ Installed successfully."
}

uninstall() {
  ensure_root
  echo "Uninstalling..."
  # We need to extract the uninstaller script to run it
  # or we can just embed the logic here.
  # Since we already have UNINSTALL_CONTENT_B64, let's use it.
  echo "$UNINSTALL_CONTENT_B64" | base64 -d | \
    sed "s|SYS_PLIST_PATH_PLACEHOLDER|$SYS_PLIST_PATH|g" | \
    sed "s|SYS_HELPER_PATH_PLACEHOLDER|$SYS_HELPER_PATH|g" | \
    sed "s|SYS_WATCHER_BIN_PLACEHOLDER|$SYS_WATCHER_BIN|g" | \
    sed "s|WORKDIR_PLACEHOLDER|$WORKDIR|g" | bash
}

if [[ "${1:-}" == "--uninstall" ]]; then
  uninstall
else
  main "$@"
fi
