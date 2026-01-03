#!/bin/sh
set -eu

# These will be set by the installer
SYS_PLIST_PATH="SYS_PLIST_PATH_PLACEHOLDER"
SYS_HELPER_PATH="SYS_HELPER_PATH_PLACEHOLDER"
SYS_WATCHER_BIN="SYS_WATCHER_BIN_PLACEHOLDER"
WORKDIR="WORKDIR_PLACEHOLDER"

echo "Stopping LaunchDaemon..."
sudo launchctl bootout system "$SYS_PLIST_PATH" 2>/dev/null || true
sudo launchctl unload "$SYS_PLIST_PATH" 2>/dev/null || true

echo "Stopping any running processes..."
sudo pkill -f "ethwifiauto-watch" || true
sudo pkill -f "eth-wifi-auto.sh" || true

echo "Removing system files..."
sudo rm -f "$SYS_PLIST_PATH" "$SYS_HELPER_PATH" "$SYS_WATCHER_BIN"

echo "Removing workspace..."
sudo rm -rf "$WORKDIR"

echo "✅ Uninstalled completely."
echo ""
