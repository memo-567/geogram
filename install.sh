#!/bin/bash
# Geogram — Build and install desktop integration (dev shortcut)
set -e
flutter build linux --release
./build/linux/x64/release/bundle/install-desktop.sh
