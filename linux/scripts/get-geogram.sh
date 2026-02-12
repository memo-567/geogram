#!/bin/bash
# Geogram — One-line installer for Linux
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/geograms/geogram/main/linux/scripts/get-geogram.sh | bash
#
# Downloads the latest release, installs desktop integration (icons,
# app menu entry, autostart, terminal symlink), and launches Geogram.
# No root required. Safe to re-run (upgrades in place without losing data).

set -euo pipefail

REPO="geograms/geogram"
ASSET="geogram-linux-x64.tar.gz"
INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/geogram"

echo "Geogram Installer"
echo "=================="

# ---- Download ---------------------------------------------------------------
RELEASE_URL="https://github.com/$REPO/releases/latest/download/$ASSET"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading latest release..."
curl -fSL --progress-bar -o "$TMP/$ASSET" "$RELEASE_URL"

# ---- Extract (overwrites bundle files, preserves user data) -----------------
echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
tar -xzf "$TMP/$ASSET" -C "$INSTALL_DIR" --strip-components=1 --overwrite

# ---- Verify binary landed ---------------------------------------------------
if [ ! -f "$INSTALL_DIR/geogram" ]; then
    echo "Error: extraction failed — geogram binary not found."
    exit 1
fi
chmod +x "$INSTALL_DIR/geogram"

# ---- Desktop integration ----------------------------------------------------
if [ -x "$INSTALL_DIR/install-desktop.sh" ]; then
    "$INSTALL_DIR/install-desktop.sh"
else
    echo "Warning: install-desktop.sh not found in bundle — skipping desktop integration."
    echo "You can run geogram directly: $INSTALL_DIR/geogram"
fi

echo ""
echo "Done! Launching Geogram..."
nohup "$INSTALL_DIR/geogram" >/dev/null 2>&1 &
