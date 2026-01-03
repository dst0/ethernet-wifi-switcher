#!/bin/sh
set -eu

# Build script for Linux installer
# Bundles switcher and uninstaller into a single script.

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$(cd "$SRC_DIR/../../dist" && pwd)"

echo "🐧 Building Linux installer..."

# macOS base64 doesn't have -w 0, so we use tr to remove newlines
SWITCHER_B64=$(base64 < "$SRC_DIR/switcher.sh" | tr -d '\n')
UNINSTALLER_B64=$(base64 < "$SRC_DIR/uninstall.sh" | tr -d '\n')

sed -e "s|__SWITCHER_B64__|$SWITCHER_B64|" \
    -e "s|__UNINSTALLER_B64__|$UNINSTALLER_B64|" \
    "$SRC_DIR/install-template.sh" > "$DIST_DIR/install-linux.sh"

chmod +x "$DIST_DIR/install-linux.sh"

echo "✅ Linux build complete: dist/install-linux.sh"
