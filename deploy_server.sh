#!/bin/bash
#
# Geogram CLI Deployment Script
# Compiles, uploads, and deploys geogram-cli to p2p.radio
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

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Local binary path
LOCAL_BINARY="$SCRIPT_DIR/build/geogram-cli"

echo "=============================================="
echo "  Geogram CLI Deployment"
echo "=============================================="
echo ""
echo "Target: $REMOTE_HOST:$REMOTE_DIR"
echo "Port: $PORT"
echo ""

# Step 1: Build the CLI binary
echo -e "${YELLOW}[1/5] Building CLI binary...${NC}"
if ! ./launch-cli.sh --build-only; then
    echo -e "${RED}Error: Build failed${NC}"
    exit 1
fi

if [ ! -f "$LOCAL_BINARY" ]; then
    echo -e "${RED}Error: Binary not found at $LOCAL_BINARY${NC}"
    exit 1
fi

echo -e "${GREEN}Build complete.${NC}"
echo ""

# Step 2: Kill existing instances on remote
echo -e "${YELLOW}[2/5] Stopping existing instances...${NC}"
ssh "$REMOTE_HOST" "screen -S $SCREEN_NAME -X quit >/dev/null 2>&1; pkill -f geogram-cli >/dev/null 2>&1; sleep 1" || true
echo -e "${GREEN}Existing instances stopped.${NC}"
echo ""

# Step 3: Upload binary
echo -e "${YELLOW}[3/5] Uploading binary to $REMOTE_HOST...${NC}"
if ! scp "$LOCAL_BINARY" "$REMOTE_HOST:$REMOTE_BINARY"; then
    echo -e "${RED}Error: Failed to upload binary${NC}"
    exit 1
fi
ssh "$REMOTE_HOST" "chmod +x $REMOTE_BINARY"
echo -e "${GREEN}Upload complete.${NC}"
echo ""

# Step 4: Create configs and start with screen
echo -e "${YELLOW}[4/5] Starting geogram-cli on port $PORT...${NC}"

# Create relay config if it doesn't exist
ssh "$REMOTE_HOST" "test -f $REMOTE_DIR/relay_config.json || cat > $REMOTE_DIR/relay_config.json << 'EOF'
{
  \"port\": 80,
  \"enabled\": true,
  \"tileServerEnabled\": true,
  \"osmFallbackEnabled\": true,
  \"maxZoomLevel\": 15,
  \"maxCacheSize\": 500,
  \"callsign\": \"P2P-RADIO\",
  \"enableAprs\": false,
  \"enableCors\": true,
  \"httpRequestTimeout\": 30000,
  \"maxConnectedDevices\": 100,
  \"relayRole\": \"root\",
  \"setupComplete\": true,
  \"enableSsl\": false,
  \"sslPort\": 443,
  \"sslAutoRenew\": true
}
EOF"

# Create config.json with a relay profile if it doesn't exist
ssh "$REMOTE_HOST" "test -f $REMOTE_DIR/config.json || cat > $REMOTE_DIR/config.json << 'EOF'
{
  \"activeProfileId\": \"relay-profile\",
  \"profiles\": [
    {
      \"id\": \"relay-profile\",
      \"name\": \"p2p.radio\",
      \"callsign\": \"P2P-RADIO\",
      \"type\": \"relay\",
      \"created\": \"2024-01-01T00:00:00.000Z\"
    }
  ]
}
EOF"

# Start in screen
ssh "$REMOTE_HOST" "cd $REMOTE_DIR && screen -dmS $SCREEN_NAME ./geogram-cli --data-dir=$REMOTE_DIR"

# Wait for startup and send relay start command
sleep 2
ssh "$REMOTE_HOST" "screen -S $SCREEN_NAME -p 0 -X stuff 'relay start\n'" || true

echo -e "${GREEN}Started in screen session '$SCREEN_NAME'.${NC}"
echo ""

# Step 5: Test that it's online
echo -e "${YELLOW}[5/5] Testing deployment...${NC}"
sleep 3

# Test HTTP endpoint
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "http://p2p.radio/api/status" 2>/dev/null || echo "000")

if [ "$HTTP_STATUS" = "200" ]; then
    echo -e "${GREEN}SUCCESS: Server is online and responding (HTTP $HTTP_STATUS)${NC}"
    echo ""
    # Show status details
    echo "Server status:"
    curl -s "http://p2p.radio/api/status" 2>/dev/null | head -c 500
    echo ""
    echo ""
    echo "Endpoints:"
    echo "  Status:    http://p2p.radio/api/status"
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
echo "  Deployment complete"
echo "=============================================="
