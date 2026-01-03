#!/bin/sh
set -eu

# Build script for Windows installer
# Bundles switcher and uninstaller into a single PowerShell script.

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$(cd "$SRC_DIR/../../dist" && pwd)"

echo "🪟 Building Windows installer..."

# macOS base64 doesn't have -w 0, so we use tr to remove newlines
SWITCHER_B64=$(base64 < "$SRC_DIR/switcher.ps1" | tr -d '\n')
UNINSTALLER_B64=$(base64 < "$SRC_DIR/uninstall.ps1" | tr -d '\n')

sed -e "s|__SWITCHER_B64__|$SWITCHER_B64|" \
    -e "s|__UNINSTALLER_B64__|$UNINSTALLER_B64|" \
    "$SRC_DIR/install-template.ps1" > "$DIST_DIR/install-windows.ps1"

echo "✅ Windows build complete: dist/install-windows.ps1"
