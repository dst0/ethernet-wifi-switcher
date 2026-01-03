#!/bin/sh
set -eu

# =========================================================
# Universal Ethernet/Wi-Fi Auto Switcher - Build Coordinator
# =========================================================

DIST_DIR="dist"
mkdir -p "$DIST_DIR"

PLATFORM=${1:-all}

echo "🚀 Starting build (Platform: $PLATFORM)..."

# 1. macOS
if [ "$PLATFORM" = "all" ] || [ "$PLATFORM" = "macos" ]; then
    if [ -f "src/macos/build-macos.sh" ]; then
        sh src/macos/build-macos.sh
    else
        echo "⚠️ macOS build script not found."
    fi
fi

# 2. Linux
if [ "$PLATFORM" = "all" ] || [ "$PLATFORM" = "linux" ]; then
    if [ -f "src/linux/build-linux.sh" ]; then
        sh src/linux/build-linux.sh
    else
        echo "⚠️ Linux build script not found."
    fi
fi

# 3. Windows
if [ "$PLATFORM" = "all" ] || [ "$PLATFORM" = "windows" ]; then
    if [ -f "src/windows/build-windows.sh" ]; then
        sh src/windows/build-windows.sh
    else
        echo "⚠️ Windows build script not found."
    fi
fi

echo ""
echo "🎉 All builds complete! Artifacts are in ./$DIST_DIR"
ls -l "$DIST_DIR"
