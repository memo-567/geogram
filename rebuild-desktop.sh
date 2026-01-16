#!/bin/bash

# Geogram Desktop Rebuild Script
# Builds release version of the desktop app

set -e

FLUTTER_HOME="$HOME/flutter"
FLUTTER_BIN="$FLUTTER_HOME/bin/flutter"

if [ ! -f "$FLUTTER_BIN" ]; then
    echo "❌ Flutter not found at $FLUTTER_HOME"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

FVP_CACHE="linux/fvp-cache"

# Restore fvp cache if needed
for build_type in debug release; do
    cache_src="$FVP_CACHE/$build_type/fvp"
    build_dst="build/linux/x64/$build_type/plugins"
    if [ -d "$cache_src" ] && [ ! -d "$build_dst/fvp" ]; then
        echo "📦 Restoring fvp $build_type from cache..."
        mkdir -p "$build_dst"
        cp -r "$cache_src" "$build_dst/"
    fi
done

echo "🔨 Building Linux desktop app..."
"$FLUTTER_BIN" build linux

# Cache fvp after build
if [ -d "build/linux/x64/release/plugins/fvp" ]; then
    mkdir -p "$FVP_CACHE/release"
    rm -rf "$FVP_CACHE/release/fvp"
    cp -r "build/linux/x64/release/plugins/fvp" "$FVP_CACHE/release/"
fi

echo ""
echo "✅ Build complete!"
echo "Run with: ./launch-desktop.sh"
