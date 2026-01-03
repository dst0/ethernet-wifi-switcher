#!/bin/sh
set -eu

# macOS Build Script
# Compiles Swift watcher and bundles everything into a self-contained installer.

SRC_DIR="src/macos"
DIST_DIR="dist"
OUTPUT="$DIST_DIR/install-macos.sh"
TEMP_BIN="ethwifiauto-watch-universal"

mkdir -p "$DIST_DIR"

if ! command -v swiftc > /dev/null 2>&1; then
    echo "⚠️ swiftc not found. Skipping macOS build."
    exit 0
fi

echo "🍎 Building macOS Universal Binary..."
swiftc -O -target arm64-apple-macosx11.0 "$SRC_DIR/EthWifiWatch.swift" -o "${TEMP_BIN}-arm64"
swiftc -O -target x86_64-apple-macosx11.0 "$SRC_DIR/EthWifiWatch.swift" -o "${TEMP_BIN}-x86_64"
lipo -create "${TEMP_BIN}-arm64" "${TEMP_BIN}-x86_64" -output "$TEMP_BIN"
rm "${TEMP_BIN}-arm64" "${TEMP_BIN}-x86_64"

echo "📦 Encoding components..."
WATCHER_B64=$(base64 < "$TEMP_BIN")
HELPER_B64=$(base64 < "$SRC_DIR/switcher.sh")
UNINSTALL_B64=$(base64 < "$SRC_DIR/uninstall.sh")
PLIST_B64=$(base64 < "$SRC_DIR/watch.plist")
rm "$TEMP_BIN"

echo "🏗️ Generating $OUTPUT..."
sed -e "s|__WATCHER_BINARY_B64__|$WATCHER_B64|" \
    -e "s|__HELPER_SCRIPT_B64__|$HELPER_B64|" \
    -e "s|__UNINSTALL_SCRIPT_B64__|$UNINSTALL_B64|" \
    -e "s|__PLIST_TEMPLATE_B64__|$PLIST_B64|" \
    "$SRC_DIR/install-template.sh" > "$OUTPUT"

chmod +x "$OUTPUT"
echo "✅ macOS build complete: $OUTPUT"
