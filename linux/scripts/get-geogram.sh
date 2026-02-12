#!/bin/bash
# Geogram — One-line installer for Linux
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/geograms/geogram/main/linux/scripts/get-geogram.sh | bash
#
# Installs the latest release to ~/.local/share/geogram and sets up
# desktop integration (icons, .desktop file, ~/.local/bin/geogram).
# No root required.

set -euo pipefail

APP_ID="geogram.radio"
REPO="geograms/geogram"
ASSET="geogram-linux-x64.tar.gz"
INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/geogram"

echo "Geogram Installer"
echo "=================="

# ---- Detect latest version ------------------------------------------------
echo "Fetching latest release..."
RELEASE_URL="https://github.com/$REPO/releases/latest/download/$ASSET"

# ---- Download --------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading $ASSET..."
curl -fSL --progress-bar -o "$TMP/$ASSET" "$RELEASE_URL"

# ---- Extract (overwrites bundle files, preserves user data) ---------------
echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
tar -xzf "$TMP/$ASSET" -C "$INSTALL_DIR" --strip-components=1 --overwrite

# ---- Desktop integration ---------------------------------------------------
if [ -x "$INSTALL_DIR/install-desktop.sh" ]; then
    "$INSTALL_DIR/install-desktop.sh"
else
    echo "Warning: install-desktop.sh not found in bundle — skipping desktop integration."
    echo "You can run geogram directly: $INSTALL_DIR/geogram"
fi

echo ""
echo "Done! Launching Geogram..."
nohup "$INSTALL_DIR/geogram" >/dev/null 2>&1 &
