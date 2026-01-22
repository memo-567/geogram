#!/bin/bash

# Geogram Android Launch Script
# This script sets up the Flutter environment and launches the Android app

set -e

# Define Flutter path
FLUTTER_HOME="$HOME/flutter"
FLUTTER_BIN="$FLUTTER_HOME/bin/flutter"

# Define Android SDK paths
ANDROID_SDK="$HOME/Android/Sdk"
ADB="$ANDROID_SDK/platform-tools/adb"

# Check if Flutter is installed
if [ ! -f "$FLUTTER_BIN" ]; then
    echo "Flutter not found at $FLUTTER_HOME"
    echo "Please install Flutter or update FLUTTER_HOME in this script"
    exit 1
fi

# Check if ADB is available
if [ ! -f "$ADB" ]; then
    echo "ADB not found at $ADB"
    echo "Please install Android SDK or update ANDROID_SDK in this script"
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Change to the geogram directory
cd "$SCRIPT_DIR"

echo "Launching Geogram on Android..."
echo "Working directory: $SCRIPT_DIR"

# Restart ADB server to ensure clean state (prevents memory/hang issues)
echo ""
echo "Restarting ADB server..."
"$ADB" kill-server 2>/dev/null || true
sleep 1
"$ADB" start-server

# Check device status
echo ""
echo "Checking connected devices..."
DEVICE_LINES=$("$ADB" devices | tail -n +2 | grep -v "^$")

if [ -z "$DEVICE_LINES" ]; then
    echo "No Android device connected!"
    echo "Please connect your device and enable USB debugging"
    exit 1
fi

# Collect all valid device IDs
DEVICE_IDS=()
while IFS= read -r line; do
    if [ -z "$line" ]; then
        continue
    fi

    DEVICE_ID=$(echo "$line" | awk '{print $1}')
    DEVICE_STATE=$(echo "$line" | awk '{print $2}')

    if [ "$DEVICE_STATE" = "unauthorized" ]; then
        echo "Device $DEVICE_ID is unauthorized - skipping"
        echo "  Please accept the USB debugging prompt on this device"
        continue
    fi

    if [ "$DEVICE_STATE" = "offline" ]; then
        echo "Device $DEVICE_ID is offline. Attempting to reconnect..."
        "$ADB" -s "$DEVICE_ID" reconnect
        sleep 2
        # Re-check status
        DEVICE_STATE=$("$ADB" devices | grep "^$DEVICE_ID" | awk '{print $2}')
        if [ "$DEVICE_STATE" != "device" ]; then
            echo "Device $DEVICE_ID still offline - skipping"
            continue
        fi
    fi

    if [ "$DEVICE_STATE" = "device" ]; then
        DEVICE_IDS+=("$DEVICE_ID")
        echo "Device found: $DEVICE_ID"
    fi
done <<< "$DEVICE_LINES"

if [ ${#DEVICE_IDS[@]} -eq 0 ]; then
    echo "No valid Android devices available!"
    exit 1
fi

echo ""
echo "Found ${#DEVICE_IDS[@]} device(s) ready for installation"

echo ""
echo "Flutter version:"
"$FLUTTER_BIN" --version

# Get dependencies - try offline first, fall back to online
echo ""
echo "Checking dependencies..."
if ! "$FLUTTER_BIN" pub get --offline 2>/dev/null; then
    echo "Fetching dependencies online..."
    "$FLUTTER_BIN" pub get
fi

# Build the APK once (debug build to enable run-as for android-sync.sh)
echo ""
echo "Building APK..."
"$FLUTTER_BIN" build apk --debug --no-pub

APK_PATH="$SCRIPT_DIR/build/app/outputs/flutter-apk/app-debug.apk"

if [ ! -f "$APK_PATH" ]; then
    echo "APK not found at $APK_PATH"
    exit 1
fi

echo ""
echo "Installing on all devices..."

# Install on each device
FAILED_DEVICES=()
for DEVICE_ID in "${DEVICE_IDS[@]}"; do
    echo ""
    echo "Installing on $DEVICE_ID..."
    if "$ADB" -s "$DEVICE_ID" install -r "$APK_PATH"; then
        echo "Successfully installed on $DEVICE_ID"
    else
        echo "Failed to install on $DEVICE_ID"
        FAILED_DEVICES+=("$DEVICE_ID")
    fi
done

echo ""
echo "Launching app on all devices..."

# Launch app on each device
for DEVICE_ID in "${DEVICE_IDS[@]}"; do
    echo "Launching on $DEVICE_ID..."
    "$ADB" -s "$DEVICE_ID" shell am start -n dev.geogram/.MainActivity
done

echo ""
echo "========================================"
echo "Installation complete!"
echo "Installed on ${#DEVICE_IDS[@]} device(s)"
if [ ${#FAILED_DEVICES[@]} -gt 0 ]; then
    echo "Failed on ${#FAILED_DEVICES[@]} device(s): ${FAILED_DEVICES[*]}"
fi
echo "========================================"
