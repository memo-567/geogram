#!/bin/bash
# Geogram — Remove desktop integration
#
# Removes icons, .desktop file, autostart entry, and terminal symlink
# installed by install-desktop.sh. Does not touch the application bundle.

set -euo pipefail

APP_ID="geogram.radio"

# ---------------------------------------------------------------------------
# XDG base directories
# ---------------------------------------------------------------------------
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
ICON_BASE="$DATA_HOME/icons/hicolor"
APP_DIR="$DATA_HOME/applications"
AUTOSTART_DIR="$CONFIG_HOME/autostart"
BIN_DIR="$HOME/.local/bin"

# ---------------------------------------------------------------------------
# Remove icons
# ---------------------------------------------------------------------------
for SIZE in 48 64 128 256 512; do
    rm -f "$ICON_BASE/${SIZE}x${SIZE}/apps/${APP_ID}.png"
done
rm -f "$ICON_BASE/scalable/apps/${APP_ID}.svg"
echo "Icons removed."

# ---------------------------------------------------------------------------
# Remove .desktop file
# ---------------------------------------------------------------------------
rm -f "$APP_DIR/${APP_ID}.desktop"
echo "Desktop entry removed."

# ---------------------------------------------------------------------------
# Remove autostart entry
# ---------------------------------------------------------------------------
rm -f "$AUTOSTART_DIR/${APP_ID}.desktop"
echo "Autostart entry removed."

# ---------------------------------------------------------------------------
# Remove terminal symlink
# ---------------------------------------------------------------------------
if [ -L "$BIN_DIR/geogram" ]; then
    rm -f "$BIN_DIR/geogram"
    echo "Terminal symlink removed."
fi

# ---------------------------------------------------------------------------
# Update caches
# ---------------------------------------------------------------------------
if command -v gtk-update-icon-cache &>/dev/null; then
    gtk-update-icon-cache --force "$ICON_BASE" 2>/dev/null || true
fi
if command -v update-desktop-database &>/dev/null; then
    update-desktop-database "$APP_DIR" 2>/dev/null || true
fi

echo ""
echo "Geogram desktop integration removed."
