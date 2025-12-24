#!/bin/bash

# Flutter Installation Script with Resume Support
# This script downloads and installs Flutter SDK with the ability to resume interrupted downloads

set -e

# Configuration
# Flutter 3.38.3 includes Dart 3.10 which is required by geogram (pubspec.yaml requires SDK ^3.10.0)
FLUTTER_VERSION="3.38.3"
FLUTTER_HOME="$HOME/flutter"
DOWNLOAD_DIR="$HOME"
FLUTTER_ARCHIVE="flutter.tar.xz"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

echo "🔧 Flutter Installation Script"
echo "=============================="
echo "Target directory: $FLUTTER_HOME"
echo "Flutter version: $FLUTTER_VERSION"
echo ""

# Check if Flutter is already installed
if [ -d "$FLUTTER_HOME" ] && [ -f "$FLUTTER_HOME/bin/flutter" ]; then
    echo "✅ Flutter is already installed at $FLUTTER_HOME"
    echo ""
    "$FLUTTER_HOME/bin/flutter" --version
    echo ""
    read -p "Do you want to reinstall? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
    echo "Removing existing installation..."
    rm -rf "$FLUTTER_HOME"
fi

# Download Flutter with resume support
echo "📥 Downloading Flutter SDK..."
echo "   URL: $FLUTTER_URL"
echo "   (Download can be resumed if interrupted)"
echo ""

cd "$DOWNLOAD_DIR"

# Use curl with -C - to resume downloads
curl -C - -L "$FLUTTER_URL" -o "$FLUTTER_ARCHIVE"

# Check if download was successful
if [ ! -f "$FLUTTER_ARCHIVE" ]; then
    echo "❌ Download failed!"
    exit 1
fi

echo ""
echo "✅ Download complete!"
echo ""

# Extract Flutter
echo "📦 Extracting Flutter SDK..."
tar xf "$FLUTTER_ARCHIVE"

if [ ! -d "$FLUTTER_HOME" ]; then
    echo "❌ Extraction failed!"
    exit 1
fi

echo "✅ Extraction complete!"
echo ""

# Clean up archive
echo "🧹 Cleaning up..."
rm "$FLUTTER_ARCHIVE"

echo ""
echo "✅ Flutter installed successfully at $FLUTTER_HOME"
echo ""
echo "🔍 Running flutter doctor to check dependencies..."
echo ""

"$FLUTTER_HOME/bin/flutter" doctor

echo ""
echo "=============================="
echo "✨ Installation Complete!"
echo ""
echo "Flutter is ready to use. You can now run:"
echo "  ./launch-desktop.sh"
echo ""
echo "Note: If flutter doctor shows missing dependencies,"
echo "you may need to install them manually."
echo ""
