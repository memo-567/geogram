#!/bin/bash

# Geogram Desktop Launch Script
# This script sets up the Flutter environment and launches the desktop app

set -e

# Define Flutter path
FLUTTER_HOME="$HOME/flutter"
FLUTTER_BIN="$FLUTTER_HOME/bin/flutter"

# Check if Flutter is installed
if [ ! -f "$FLUTTER_BIN" ]; then
    echo "❌ Flutter not found at $FLUTTER_HOME"
    echo "Please run ./install-flutter.sh to install Flutter"
    exit 1
fi

# Check Dart SDK version (must be >= 3.10.0 as required by pubspec.yaml)
DART_VERSION=$("$FLUTTER_BIN" --version 2>&1 | grep -oP 'Dart \K[0-9]+\.[0-9]+' | head -1)
DART_MAJOR=$(echo "$DART_VERSION" | cut -d. -f1)
DART_MINOR=$(echo "$DART_VERSION" | cut -d. -f2)

if [ "$DART_MAJOR" -lt 3 ] || ([ "$DART_MAJOR" -eq 3 ] && [ "$DART_MINOR" -lt 10 ]); then
    echo "❌ Dart version $DART_VERSION is too old"
    echo "This project requires Dart SDK ^3.10.0"
    echo "Please run ./install-flutter.sh to install the correct Flutter version (3.38.3+)"
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Change to the geogram directory
cd "$SCRIPT_DIR"

# FVP cache directory
FVP_CACHE="linux/fvp-cache"

# Function to restore fvp cache if needed
restore_fvp_if_needed() {
    local build_type=$1
    local cache_src="$FVP_CACHE/$build_type/fvp"
    local build_dst="build/linux/x64/$build_type/plugins"

    if [ -d "$cache_src" ] && [ ! -d "$build_dst/fvp" ]; then
        echo "📦 Restoring fvp $build_type build from cache..."
        mkdir -p "$build_dst"
        cp -r "$cache_src" "$build_dst/"
    fi
}

# Function to cache fvp build
cache_fvp() {
    local build_type=$1
    local build_src="build/linux/x64/$build_type/plugins/fvp"
    local cache_dst="$FVP_CACHE/$build_type"

    if [ -d "$build_src" ]; then
        mkdir -p "$cache_dst"
        rm -rf "$cache_dst/fvp"
        cp -r "$build_src" "$cache_dst/"
    fi
}

echo "🚀 Launching Geogram Desktop..."
echo "📍 Working directory: $SCRIPT_DIR"

# Kill any existing geogram processes to free up ports
if pgrep -f "geogram" > /dev/null 2>&1; then
    echo "🔄 Killing existing geogram processes..."
    pkill -f "geogram" 2>/dev/null || true
    sleep 1
fi

# Get dependencies - try offline first, fall back to online
echo "📦 Checking dependencies..."
if ! "$FLUTTER_BIN" pub get --offline 2>/dev/null; then
    echo "📡 Fetching dependencies online..."
    "$FLUTTER_BIN" pub get
fi

# Clean build to ensure fresh compilation
echo "🧹 Cleaning previous build..."
"$FLUTTER_BIN" clean

# Re-fetch dependencies after clean
echo "📦 Re-fetching dependencies..."
"$FLUTTER_BIN" pub get --offline 2>/dev/null || "$FLUTTER_BIN" pub get

# Restore fvp cache if available
restore_fvp_if_needed "debug"
restore_fvp_if_needed "release"

echo ""
echo "▶️  Starting app..."

# Run the app on Linux desktop
"$FLUTTER_BIN" run -d linux --no-pub "$@"

# Cache fvp builds after successful run
cache_fvp "debug"
cache_fvp "release"
