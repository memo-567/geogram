#!/bin/bash
#
# Geogram CLI Restart Script
# Restarts the geogram-cli server without recompiling
#

# Configuration
REMOTE_HOST="root@p2p.radio"
REMOTE_DIR="/root/geogram"
REMOTE_BINARY="$REMOTE_DIR/geogram-cli"
SCREEN_NAME="geogram"
PORT=80

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=============================================="
echo "  Geogram CLI Restart"
echo "=============================================="
echo ""
echo "Target: $REMOTE_HOST:$REMOTE_DIR"
echo ""

# Step 1: Kill existing instances on remote
echo -e "${YELLOW}[1/3] Stopping existing instances...${NC}"
ssh "$REMOTE_HOST" "screen -S $SCREEN_NAME -X quit >/dev/null 2>&1; pkill -f geogram-cli >/dev/null 2>&1; sleep 1" || true
echo -e "${GREEN}Existing instances stopped.${NC}"
echo ""

# Step 2: Start with screen
echo -e "${YELLOW}[2/3] Starting geogram-cli on port $PORT...${NC}"

# Start in screen
ssh "$REMOTE_HOST" "cd $REMOTE_DIR && screen -dmS $SCREEN_NAME ./geogram-cli --data-dir=$REMOTE_DIR"

# Wait for startup and send station start command
sleep 2
ssh "$REMOTE_HOST" "screen -S $SCREEN_NAME -p 0 -X stuff 'station start\n'" || true

echo -e "${GREEN}Started in screen session '$SCREEN_NAME'.${NC}"
echo ""

# Step 3: Test that it's online
echo -e "${YELLOW}[3/3] Testing deployment...${NC}"
sleep 3

# Test HTTP endpoint
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "http://p2p.radio/api/status" 2>/dev/null || echo "000")

if [ "$HTTP_STATUS" = "200" ]; then
    echo -e "${GREEN}SUCCESS: Server is online and responding (HTTP $HTTP_STATUS)${NC}"
    echo ""
    echo "Endpoints:"
    echo "  HTTP:      http://p2p.radio/api/status"
    echo "  WebSocket: ws://p2p.radio/"
    echo ""
    echo "Management:"
    echo "  Monitor: ssh $REMOTE_HOST 'screen -r $SCREEN_NAME'"
    echo "  Stop:    ssh $REMOTE_HOST 'screen -S $SCREEN_NAME -X quit'"
else
    echo -e "${YELLOW}WARNING: Server may still be starting (HTTP $HTTP_STATUS)${NC}"
    echo ""
    echo "Checking screen session..."
    ssh "$REMOTE_HOST" "screen -ls" || true
    echo ""
    echo "Try again in a few seconds:"
    echo "  curl http://p2p.radio/api/status"
    echo ""
    echo "To debug: ssh $REMOTE_HOST 'screen -r $SCREEN_NAME'"
fi

echo ""
echo "=============================================="
echo "  Restart complete"
echo "=============================================="
