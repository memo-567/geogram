#!/bin/bash
#
# Deploy Console VM files to p2p.radio
# Downloads JSLinux/TinyEMU files and uploads to station
#
# NOTE: JSLinux uses vfsync.org for remote filesystem access.
# The VM requires internet connectivity to work properly.
#

# Configuration
REMOTE_HOST="root@p2p.radio"
REMOTE_DIR="/root/geogram/console/vm"
JSLINUX_BASE="https://bellard.org/jslinux"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR=$(mktemp -d)

echo "=============================================="
echo "  Console VM Deployment"
echo "=============================================="
echo ""
echo "Target: $REMOTE_HOST:$REMOTE_DIR"
echo "Temp dir: $TEMP_DIR"
echo ""

# Create remote directory
echo -e "${YELLOW}[1/4] Creating remote directory...${NC}"
ssh "$REMOTE_HOST" "mkdir -p $REMOTE_DIR"
echo -e "${GREEN}Done.${NC}"
echo ""

# Download JSLinux files
echo -e "${YELLOW}[2/4] Downloading JSLinux files...${NC}"
cd "$TEMP_DIR"

# Core files for the emulator
declare -A FILES
FILES["jslinux.js"]="$JSLINUX_BASE/jslinux.js"
FILES["term.js"]="$JSLINUX_BASE/term.js"
FILES["x86emu-wasm.js"]="$JSLINUX_BASE/x86emu-wasm.js"
FILES["x86emu-wasm.wasm"]="$JSLINUX_BASE/x86emu-wasm.wasm"
FILES["kernel-x86.bin"]="$JSLINUX_BASE/kernel-x86.bin"
FILES["alpine-x86.cfg"]="$JSLINUX_BASE/alpine-x86.cfg"
FILES["alpine-x86-rootfs.tar.gz"]="https://dl-cdn.alpinelinux.org/alpine/v3.12/releases/x86/alpine-minirootfs-3.12.0-x86.tar.gz"
FILES["alpine-x86-rootfs.cpio.gz"]="$JSLINUX_BASE/alpine-x86-rootfs.cpio.gz"

# Optional: Android QEMU archive (placeholder if not present locally)
LOCAL_QEMU_ARCHIVE="$SCRIPT_DIR/console_vm_assets/qemu-android-aarch64.tar.gz"
if [ -f "$LOCAL_QEMU_ARCHIVE" ]; then
    FILES["qemu-android-aarch64.tar.gz"]="file://$LOCAL_QEMU_ARCHIVE"
fi

# Optional: local initrd override (preferred)
LOCAL_INITRD="$SCRIPT_DIR/console_vm_assets/alpine-x86-rootfs.cpio.gz"
if [ -f "$LOCAL_INITRD" ]; then
    FILES["alpine-x86-rootfs.cpio.gz"]="file://$LOCAL_INITRD"
fi

# Download each file
for file in "${!FILES[@]}"; do
    url="${FILES[$file]}"
    echo "  Downloading $file from $url..."
    # Handle file:// URLs for locally provided assets
    if [[ "$url" == file://* ]]; then
        src="${url#file://}"
        if cp "$src" "$file"; then
            size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "?")
            echo -e "    ${GREEN}OK (local)${NC} ($size bytes)"
        else
            echo -e "    ${RED}FAILED to copy local asset${NC}"
        fi
        continue
    fi

    if curl -sL -o "$file" "$url"; then
        size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "?")
        if [ "$size" -gt 100 ]; then
            echo -e "    ${GREEN}OK${NC} ($size bytes)"
        else
            echo -e "    ${RED}FAILED (too small: $size bytes)${NC}"
            rm -f "$file"
        fi
    else
        echo -e "    ${RED}FAILED${NC}"
    fi
done

echo -e "${GREEN}Downloads complete.${NC}"
echo ""

# Generate manifest
echo -e "${YELLOW}[3/4] Generating manifest.json...${NC}"

UPDATED=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)

# Start manifest
cat > manifest.json << EOF
{
  "version": "1.0.0",
  "updated": "$UPDATED",
  "note": "Alpine Linux x86 with local rootfs - works offline",
  "files": [
EOF

first=true
for file in jslinux.js term.js x86emu-wasm.js x86emu-wasm.wasm kernel-x86.bin alpine-x86.cfg alpine-x86-rootfs.tar.gz alpine-x86-rootfs.cpio.gz qemu-android-aarch64.tar.gz; do
    if [ -f "$file" ]; then
        size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0")
        sha=$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$file" 2>/dev/null | cut -d' ' -f1 || echo "")

        if [ "$first" = true ]; then
            first=false
        else
            printf ",\n" >> manifest.json
        fi

        printf '    {"name": "%s", "size": %s, "sha256": "%s"}' "$file" "$size" "$sha" >> manifest.json
    fi
done

# Close JSON
echo "" >> manifest.json
echo "  ]" >> manifest.json
echo "}" >> manifest.json

echo "Manifest:"
cat manifest.json
echo ""
echo -e "${GREEN}Manifest generated.${NC}"
echo ""

# Upload files to server
echo -e "${YELLOW}[4/4] Uploading files to server...${NC}"
for file in manifest.json jslinux.js term.js x86emu-wasm.js x86emu-wasm.wasm kernel-x86.bin alpine-x86.cfg alpine-x86-rootfs.tar.gz alpine-x86-rootfs.cpio.gz qemu-android-aarch64.tar.gz; do
    if [ -f "$file" ]; then
        size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "?")
        echo "  Uploading $file ($size bytes)..."
        if scp -q "$file" "$REMOTE_HOST:$REMOTE_DIR/"; then
            echo -e "    ${GREEN}OK${NC}"
        else
            echo -e "    ${RED}FAILED${NC}"
        fi
    fi
done

echo -e "${GREEN}Upload complete.${NC}"
echo ""

# Cleanup
rm -rf "$TEMP_DIR"

# Test the endpoint
echo -e "${YELLOW}Testing deployment...${NC}"
MANIFEST_TEST=$(curl -s "https://p2p.radio/console/vm/manifest.json" 2>/dev/null || curl -s "http://p2p.radio/console/vm/manifest.json" 2>/dev/null)

if echo "$MANIFEST_TEST" | grep -q '"version"'; then
    echo -e "${GREEN}SUCCESS: Console VM files are available!${NC}"
    echo ""
    echo "Manifest response:"
    echo "$MANIFEST_TEST" | head -20
else
    echo -e "${YELLOW}WARNING: Could not verify deployment${NC}"
    echo "Response: $MANIFEST_TEST"
    echo ""
    echo "You may need to restart the station server."
fi

echo ""
echo "=============================================="
echo "  Deployment complete"
echo "=============================================="
