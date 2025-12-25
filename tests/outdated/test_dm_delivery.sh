#!/bin/bash
# Automated DM Delivery Test
# Tests that DMs are delivered between two temporary Geogram instances

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PORT_A=5577
PORT_B=5588
TEMP_DIR_A="/tmp/geogram-A-${PORT_A}"
TEMP_DIR_B="/tmp/geogram-B-${PORT_B}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== DM Delivery Test ===${NC}"

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    pkill -f "geogram_desktop.*--port=$PORT_A" 2>/dev/null || true
    pkill -f "geogram_desktop.*--port=$PORT_B" 2>/dev/null || true
    sleep 1
}
trap cleanup EXIT

# Kill any existing instances
cleanup

# Build if needed
BINARY_PATH="$PROJECT_DIR/build/linux/x64/release/bundle/geogram_desktop"
if [ ! -f "$BINARY_PATH" ]; then
    echo -e "${YELLOW}Building Geogram...${NC}"
    cd "$PROJECT_DIR"
    ~/flutter/bin/flutter build linux --release
fi

# Clean temp directories
rm -rf "$TEMP_DIR_A" "$TEMP_DIR_B"
mkdir -p "$TEMP_DIR_A" "$TEMP_DIR_B"

# Start instances
echo -e "${CYAN}Starting Instance A on port $PORT_A...${NC}"
"$BINARY_PATH" \
    --port=$PORT_A \
    --data-dir="$TEMP_DIR_A" \
    --new-identity \
    --nickname="Test-A" \
    --skip-intro \
    --http-api \
    --debug-api \
    --scan-localhost=$PORT_A-$PORT_B \
    &>/dev/null &
PID_A=$!

echo -e "${CYAN}Starting Instance B on port $PORT_B...${NC}"
"$BINARY_PATH" \
    --port=$PORT_B \
    --data-dir="$TEMP_DIR_B" \
    --new-identity \
    --nickname="Test-B" \
    --skip-intro \
    --http-api \
    --debug-api \
    --scan-localhost=$PORT_A-$PORT_B \
    &>/dev/null &
PID_B=$!

# Wait for instances to start
echo -e "${YELLOW}Waiting for instances to start...${NC}"
for i in {1..30}; do
    STATUS_A=$(curl -s http://localhost:$PORT_A/api/status 2>/dev/null | grep -o '"callsign":"[^"]*"' | head -1 || true)
    STATUS_B=$(curl -s http://localhost:$PORT_B/api/status 2>/dev/null | grep -o '"callsign":"[^"]*"' | head -1 || true)
    if [ -n "$STATUS_A" ] && [ -n "$STATUS_B" ]; then
        break
    fi
    sleep 1
    echo -n "."
done
echo ""

# Get callsigns
CALLSIGN_A=$(curl -s http://localhost:$PORT_A/api/status | grep -o '"callsign":"[^"]*"' | cut -d'"' -f4)
CALLSIGN_B=$(curl -s http://localhost:$PORT_B/api/status | grep -o '"callsign":"[^"]*"' | cut -d'"' -f4)

if [ -z "$CALLSIGN_A" ] || [ -z "$CALLSIGN_B" ]; then
    echo -e "${RED}FAILED: Could not get callsigns${NC}"
    echo "Status A: $(curl -s http://localhost:$PORT_A/api/status 2>/dev/null || echo 'not responding')"
    echo "Status B: $(curl -s http://localhost:$PORT_B/api/status 2>/dev/null || echo 'not responding')"
    exit 1
fi

echo -e "${GREEN}Instance A: $CALLSIGN_A${NC}"
echo -e "${GREEN}Instance B: $CALLSIGN_B${NC}"

# Wait for device discovery
echo -e "${YELLOW}Waiting for device discovery...${NC}"
for i in {1..15}; do
    DEVICES_A=$(curl -s http://localhost:$PORT_A/api/devices 2>/dev/null || echo "{}")
    if echo "$DEVICES_A" | grep -q "$CALLSIGN_B"; then
        echo -e "${GREEN}A discovered B${NC}"
        break
    fi
    sleep 1
    echo -n "."
done
echo ""

# Send DM from A to B
echo -e "${CYAN}Sending DM from A to B via debug API...${NC}"
SEND_RESULT=$(curl -s -X POST http://localhost:$PORT_A/api/debug \
    -H "Content-Type: application/json" \
    -d "{\"action\":\"send_dm\",\"callsign\":\"$CALLSIGN_B\",\"content\":\"Test message from A at $(date +%H:%M:%S)\"}" 2>/dev/null)
echo "Send result: $SEND_RESULT"

# Wait for processing
sleep 3

# Check A's logs
echo -e "\n${CYAN}=== Instance A Logs (DM) ===${NC}"
curl -s "http://localhost:$PORT_A/api/log?filter=DM&limit=10" 2>/dev/null | grep -o '"logs":\[.*\]' | sed 's/\\n/\n/g' | head -20

# Check A's outgoing message file
echo -e "\n${CYAN}=== A's Chat Folder ===${NC}"
ls -la "$TEMP_DIR_A/chat/" 2>/dev/null || echo "No chat folder"
if [ -d "$TEMP_DIR_A/chat/$CALLSIGN_B" ]; then
    echo -e "\n${GREEN}A's messages to $CALLSIGN_B:${NC}"
    cat "$TEMP_DIR_A/chat/$CALLSIGN_B/messages.txt" 2>/dev/null || echo "No messages file"
fi

# Check B's received message
echo -e "\n${CYAN}=== B's Chat Folder ===${NC}"
ls -la "$TEMP_DIR_B/chat/" 2>/dev/null || echo "No chat folder"
if [ -d "$TEMP_DIR_B/chat/$CALLSIGN_A" ]; then
    echo -e "\n${GREEN}B received messages from $CALLSIGN_A:${NC}"
    cat "$TEMP_DIR_B/chat/$CALLSIGN_A/messages.txt" 2>/dev/null || echo "No messages file"
else
    echo -e "${RED}B did NOT receive any messages from A!${NC}"
fi

# Check B's logs for any errors
echo -e "\n${CYAN}=== Instance B Logs (DM/Error) ===${NC}"
curl -s "http://localhost:$PORT_B/api/log?filter=DM&limit=10" 2>/dev/null | grep -o '"logs":\[.*\]' | head -10
curl -s "http://localhost:$PORT_B/api/log?filter=Error&limit=5" 2>/dev/null | grep -o '"logs":\[.*\]' | head -5

# Final status
echo -e "\n${CYAN}=== Test Summary ===${NC}"
if [ -f "$TEMP_DIR_B/chat/$CALLSIGN_A/messages.txt" ]; then
    if grep -q "Test message from A" "$TEMP_DIR_B/chat/$CALLSIGN_A/messages.txt" 2>/dev/null; then
        echo -e "${GREEN}SUCCESS: Message was delivered from A to B!${NC}"
    else
        echo -e "${YELLOW}PARTIAL: B has chat folder but message content not found${NC}"
    fi
else
    echo -e "${RED}FAILED: Message was NOT delivered to B${NC}"
fi

echo -e "\n${YELLOW}Test complete. Instances will be killed.${NC}"
