#!/bin/bash
# Geogram — Install desktop integration (no root required)
#
# Installs icons, .desktop file, autostart entry, and terminal symlink
# into the user's XDG directories so the desktop environment can find
# Geogram's icon in the taskbar, alt-tab, and app launcher.
#
# If you move this folder, re-run this script.

set -euo pipefail

APP_ID="geogram.radio"
APP_NAME="Geogram"

# ---------------------------------------------------------------------------
# Resolve the bundle directory (works regardless of CWD or symlinks)
# The script lives at the bundle root, next to the geogram binary.
# ---------------------------------------------------------------------------
BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -x "$BUNDLE_DIR/geogram" ]; then
    echo "Error: Cannot find geogram binary at $BUNDLE_DIR/geogram"
    echo "Make sure this script is inside the bundle directory."
    exit 1
fi

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
# Install icons
# ---------------------------------------------------------------------------
ICON_SRC="$BUNDLE_DIR/icons"

for SIZE in 48 64 128 256 512; do
    SRC="$ICON_SRC/${SIZE}x${SIZE}/${APP_ID}.png"
    DEST="$ICON_BASE/${SIZE}x${SIZE}/apps"
    if [ -f "$SRC" ]; then
        mkdir -p "$DEST"
        cp "$SRC" "$DEST/${APP_ID}.png"
    fi
done

SRC_SVG="$ICON_SRC/scalable/${APP_ID}.svg"
if [ -f "$SRC_SVG" ]; then
    mkdir -p "$ICON_BASE/scalable/apps"
    cp "$SRC_SVG" "$ICON_BASE/scalable/apps/${APP_ID}.svg"
fi

echo "Icons installed."

# ---------------------------------------------------------------------------
# Install .desktop file with absolute Exec path
# ---------------------------------------------------------------------------
mkdir -p "$APP_DIR"
cat > "$APP_DIR/${APP_ID}.desktop" << EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=Resilient, Decentralized Communication
Exec=$BUNDLE_DIR/geogram
Icon=$APP_ID
Categories=Network;InstantMessaging;
Keywords=geo;geogram;chat;mesh;radio;offline;
Terminal=false
StartupWMClass=$APP_ID
EOF
chmod +x "$APP_DIR/${APP_ID}.desktop"

echo "Desktop entry installed."

# ---------------------------------------------------------------------------
# Enable autostart on login
# ---------------------------------------------------------------------------
mkdir -p "$AUTOSTART_DIR"
cat > "$AUTOSTART_DIR/${APP_ID}.desktop" << EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Exec=$BUNDLE_DIR/geogram --minimized
Icon=$APP_ID
X-GNOME-Autostart-enabled=true
StartupWMClass=$APP_ID
EOF
chmod +x "$AUTOSTART_DIR/${APP_ID}.desktop"

echo "Autostart enabled."

# ---------------------------------------------------------------------------
# Create symlink in ~/.local/bin for terminal access
# ---------------------------------------------------------------------------
mkdir -p "$BIN_DIR"
ln -sf "$BUNDLE_DIR/geogram" "$BIN_DIR/geogram"
echo "Terminal command: geogram"

# ---------------------------------------------------------------------------
# Update caches
# gtk-update-icon-cache requires an index.theme file to exist.
# If the user's local hicolor theme lacks one, copy it from the system.
# ---------------------------------------------------------------------------
if [ ! -f "$ICON_BASE/index.theme" ]; then
    if [ -f /usr/share/icons/hicolor/index.theme ]; then
        cp /usr/share/icons/hicolor/index.theme "$ICON_BASE/index.theme"
    fi
fi
if command -v gtk-update-icon-cache &>/dev/null; then
    gtk-update-icon-cache --force "$ICON_BASE" 2>/dev/null || true
fi
if command -v update-desktop-database &>/dev/null; then
    update-desktop-database "$APP_DIR" 2>/dev/null || true
fi

echo ""
echo "Geogram desktop integration installed successfully."
echo "If you move this folder, re-run this script."
