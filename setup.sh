#!/bin/bash

# Geogram Desktop - Complete Setup Script
# This script sets up everything needed to run geogram-desktop on a new machine

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=============================="
echo "🚀 Geogram Desktop Setup"
echo "=============================="
echo ""
echo "This script will:"
echo "  1. Install Linux system dependencies (requires sudo)"
echo "  2. Install Flutter SDK 3.38.3+ with Dart 3.10+"
echo "  3. Configure the environment"
echo ""

# Check if install-linux-deps.sh exists
if [ ! -f "$SCRIPT_DIR/install-linux-deps.sh" ]; then
    echo "❌ install-linux-deps.sh not found!"
    exit 1
fi

# Check if install-flutter.sh exists
if [ ! -f "$SCRIPT_DIR/install-flutter.sh" ]; then
    echo "❌ install-flutter.sh not found!"
    exit 1
fi

# Step 1: Install Linux dependencies
echo "=============================="
echo "Step 1: Installing Linux Dependencies"
echo "=============================="
echo ""
bash "$SCRIPT_DIR/install-linux-deps.sh"

echo ""
echo "=============================="
echo "Step 2: Installing Flutter SDK"
echo "=============================="
echo ""
bash "$SCRIPT_DIR/install-flutter.sh"

echo ""
echo "=============================="
echo "✨ Setup Complete!"
echo "=============================="
echo ""
echo "You can now run the desktop app with:"
echo "  cd $SCRIPT_DIR"
echo "  ./launch-desktop.sh"
echo ""
