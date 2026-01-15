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
CYAN='\033[0;36m'
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
echo -e "${YELLOW}[1/6] Building CLI binary...${NC}"
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
echo -e "${YELLOW}[2/6] Stopping existing instances...${NC}"

# Check if systemd service exists and stop it gracefully
SYSTEMD_SERVICE_EXISTS=$(ssh "$REMOTE_HOST" "systemctl list-unit-files geogram-station.service 2>/dev/null | grep -q geogram-station && echo 'yes' || echo 'no'")

if [ "$SYSTEMD_SERVICE_EXISTS" = "yes" ]; then
    echo "Stopping systemd service..."
    ssh "$REMOTE_HOST" "systemctl stop geogram-station 2>/dev/null" || true
    sleep 2
else
    # Fallback: kill screen and any running processes
    ssh "$REMOTE_HOST" "screen -S $SCREEN_NAME -X quit >/dev/null 2>&1" || true
fi

# Make sure process is really dead
ssh "$REMOTE_HOST" "pkill -f geogram-cli >/dev/null 2>&1; sleep 1" || true
echo -e "${GREEN}Existing instances stopped.${NC}"
echo ""

# Step 3: Upload binary
echo -e "${YELLOW}[3/6] Uploading binary to $REMOTE_HOST...${NC}"
ssh "$REMOTE_HOST" "mkdir -p $REMOTE_DIR"
if ! scp "$LOCAL_BINARY" "$REMOTE_HOST:$REMOTE_BINARY"; then
    echo -e "${RED}Error: Failed to upload binary${NC}"
    exit 1
fi
ssh "$REMOTE_HOST" "chmod +x $REMOTE_BINARY"
echo -e "${GREEN}Upload complete.${NC}"
echo ""

# Step 4: Check if setup is needed (empty deployment folder)
echo -e "${YELLOW}[4/6] Checking deployment status...${NC}"

NEEDS_SETUP=$(ssh "$REMOTE_HOST" "test -f $REMOTE_DIR/config.json && echo 'no' || echo 'yes'")

if [ "$NEEDS_SETUP" = "yes" ]; then
    echo -e "${CYAN}"
    echo "=============================================="
    echo "  First-time Setup Required"
    echo "=============================================="
    echo -e "${NC}"
    echo "No existing configuration found. Running setup wizard..."
    echo ""

    # Ask for station name/description
    echo -e "${YELLOW}--- RELAY IDENTITY ---${NC}"
    printf "Relay name [${CYAN}p2p.radio${NC}]: "
    read RELAY_NAME
    RELAY_NAME=${RELAY_NAME:-"p2p.radio"}

    printf "Description [${CYAN}Geogram Station${NC}]: "
    read RELAY_DESC
    RELAY_DESC=${RELAY_DESC:-"Geogram Station"}
    echo ""

    # Ask for location
    echo -e "${YELLOW}--- LOCATION (optional, press ENTER to skip) ---${NC}"
    printf "Location name (e.g., Lisbon, Portugal): "
    read RELAY_LOCATION

    RELAY_LAT=""
    RELAY_LON=""
    if [ -n "$RELAY_LOCATION" ]; then
        printf "Latitude (e.g., 38.7223): "
        read RELAY_LAT
        printf "Longitude (e.g., -9.1393): "
        read RELAY_LON
    fi
    echo ""

    # Ask for SSL configuration
    echo -e "${YELLOW}--- SSL/HTTPS CONFIGURATION ---${NC}"
    printf "Domain for SSL [${CYAN}p2p.radio${NC}]: "
    read SSL_DOMAIN
    SSL_DOMAIN=${SSL_DOMAIN:-"p2p.radio"}

    # Auto-generate email from domain
    SSL_EMAIL="admin@${SSL_DOMAIN}"
    ENABLE_SSL="true"
    echo -e "SSL Email: ${CYAN}${SSL_EMAIL}${NC} (auto-generated)"
    echo ""

    # Ask for network role
    echo -e "${YELLOW}--- NETWORK ROLE ---${NC}"
    echo "Select station role:"
    echo "  1) Root Station - Primary station (accepts node connections)"
    echo "  2) Node Station - Connects to an existing root station"
    printf "Enter choice (1 or 2) [${CYAN}1${NC}]: "
    read ROLE_CHOICE
    ROLE_CHOICE=${ROLE_CHOICE:-1}

    RELAY_ROLE="root"
    PARENT_URL=""
    if [ "$ROLE_CHOICE" = "2" ]; then
        RELAY_ROLE="node"
        printf "Parent station URL (e.g., wss://station.example.com): "
        read PARENT_URL
    fi
    echo ""

    # Generate NOSTR keys using openssl
    echo -e "${YELLOW}Generating cryptographic keys...${NC}"

    # Generate a random 32-byte private key
    PRIVKEY_HEX=$(openssl rand -hex 32)

    # For simplicity, we'll use a placeholder npub/nsec format
    # The actual bech32 encoding would be done by the CLI
    NPUB="npub1$(echo $PRIVKEY_HEX | cut -c1-58)"
    NSEC="nsec1$(echo $PRIVKEY_HEX)"

    # Generate X3 callsign from npub (simplified - take chars and convert)
    CALLSIGN="X3$(echo $PRIVKEY_HEX | tr 'a-f' 'A-F' | cut -c1-4)"

    echo -e "${GREEN}Generated callsign: $CALLSIGN${NC}"
    echo ""

    # Show summary
    echo -e "${CYAN}"
    echo "=============================================="
    echo "  Setup Summary"
    echo "=============================================="
    echo -e "${NC}"
    echo -e "Relay Name:    ${CYAN}$RELAY_NAME${NC}"
    echo -e "Description:   ${CYAN}$RELAY_DESC${NC}"
    echo -e "Callsign:      ${CYAN}$CALLSIGN${NC}"
    echo -e "Role:          ${CYAN}$RELAY_ROLE${NC}"
    if [ -n "$RELAY_LOCATION" ]; then
        echo -e "Location:      ${CYAN}$RELAY_LOCATION${NC}"
    fi
    if [ "$ENABLE_SSL" = "true" ]; then
        echo -e "SSL Domain:    ${CYAN}$SSL_DOMAIN${NC}"
        echo -e "SSL Email:     ${CYAN}$SSL_EMAIL${NC}"
    fi
    echo ""

    read -p "Proceed with this configuration? (y/n) [y]: " CONFIRM
    CONFIRM=${CONFIRM:-y}

    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo -e "${YELLOW}Setup cancelled.${NC}"
        exit 0
    fi

    echo ""
    echo -e "${YELLOW}Creating configuration files...${NC}"

    # Build JSON for optional fields
    LAT_JSON="${RELAY_LAT:-null}"
    LON_JSON="${RELAY_LON:-null}"
    LOCATION_JSON="null"
    [ -n "$RELAY_LOCATION" ] && LOCATION_JSON="\"$RELAY_LOCATION\""
    PARENT_JSON="null"
    [ -n "$PARENT_URL" ] && PARENT_JSON="\"$PARENT_URL\""
    SSL_DOMAIN_JSON="null"
    [ -n "$SSL_DOMAIN" ] && SSL_DOMAIN_JSON="\"$SSL_DOMAIN\""
    SSL_EMAIL_JSON="null"
    [ -n "$SSL_EMAIL" ] && SSL_EMAIL_JSON="\"$SSL_EMAIL\""
    CREATED_DATE=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)

    # Create station_config.json
    ssh "$REMOTE_HOST" "cat > $REMOTE_DIR/station_config.json" << RELAY_EOF
{
  "httpPort": $PORT,
  "enabled": true,
  "tileServerEnabled": true,
  "osmFallbackEnabled": true,
  "maxZoomLevel": 15,
  "maxCacheSizeMB": 500,
  "name": "$RELAY_NAME",
  "description": "$RELAY_DESC",
  "location": $LOCATION_JSON,
  "latitude": $LAT_JSON,
  "longitude": $LON_JSON,
  "npub": "$NPUB",
  "nsec": "$NSEC",
  "enableAprs": false,
  "enableCors": true,
  "httpRequestTimeout": 30000,
  "maxConnectedDevices": 100,
  "stationRole": "$RELAY_ROLE",
  "parentRelayUrl": $PARENT_JSON,
  "setupComplete": true,
  "enableSsl": $ENABLE_SSL,
  "sslDomain": $SSL_DOMAIN_JSON,
  "sslEmail": $SSL_EMAIL_JSON,
  "sslAutoRenew": true,
  "httpsPort": 443
}
RELAY_EOF

    # Create config.json with station profile
    ssh "$REMOTE_HOST" "cat > $REMOTE_DIR/config.json" << CONFIG_EOF
{
  "activeProfileId": "station-profile",
  "profiles": [
    {
      "id": "station-profile",
      "name": "$RELAY_NAME",
      "callsign": "$CALLSIGN",
      "description": "$RELAY_DESC",
      "type": "station",
      "npub": "$NPUB",
      "nsec": "$NSEC",
      "locationName": $LOCATION_JSON,
      "latitude": $LAT_JSON,
      "longitude": $LON_JSON,
      "port": $PORT,
      "stationRole": "$RELAY_ROLE",
      "parentRelayUrl": $PARENT_JSON,
      "tileServerEnabled": true,
      "osmFallbackEnabled": true,
      "enableAprs": false,
      "created": "$CREATED_DATE"
    }
  ]
}
CONFIG_EOF

    # Create required directories
    ssh "$REMOTE_HOST" "mkdir -p $REMOTE_DIR/devices $REMOTE_DIR/tiles $REMOTE_DIR/ssl $REMOTE_DIR/logs"

    echo -e "${GREEN}Configuration files created.${NC}"

    # If SSL is enabled, set up certificates
    if [ "$ENABLE_SSL" = "true" ]; then
        echo ""
        echo -e "${YELLOW}Setting up SSL certificates...${NC}"
        echo "The station will automatically request SSL certificates from Let's Encrypt"
        echo "when it starts. Make sure port 80 is open for the ACME challenge."
        echo ""
    fi
else
    echo -e "${GREEN}Existing configuration found. Skipping setup.${NC}"
fi
echo ""

# Step 5: Start the server
echo -e "${YELLOW}[5/6] Starting geogram-cli on port $PORT...${NC}"

# Check if systemd is available on remote
SYSTEMD_AVAILABLE=$(ssh "$REMOTE_HOST" "command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1 && echo 'yes' || echo 'no'")

if [ "$SYSTEMD_AVAILABLE" = "yes" ]; then
    echo "Systemd detected, installing service..."

    # Create systemd service file
    ssh "$REMOTE_HOST" "cat > /etc/systemd/system/geogram-station.service" << 'SERVICE_EOF'
[Unit]
Description=Geogram Station Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/geogram
ExecStart=/root/geogram/geogram-cli --data-dir=/root/geogram station
Restart=on-failure
RestartSec=5
StartLimitBurst=5
StartLimitIntervalSec=60

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/root/geogram

# Logging
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    # Reload systemd, enable and start/restart the service
    ssh "$REMOTE_HOST" "systemctl daemon-reload && systemctl enable geogram-station"

    # Use restart to handle both fresh start and updates
    if [ "$SYSTEMD_SERVICE_EXISTS" = "yes" ]; then
        ssh "$REMOTE_HOST" "systemctl restart geogram-station"
    else
        ssh "$REMOTE_HOST" "systemctl start geogram-station"
    fi

    echo -e "${GREEN}Started as systemd service 'geogram-station'.${NC}"
    echo ""
    echo "Management commands:"
    echo "  Status:  ssh $REMOTE_HOST 'systemctl status geogram-station'"
    echo "  Logs:    ssh $REMOTE_HOST 'journalctl -u geogram-station -f'"
    echo "  Stop:    ssh $REMOTE_HOST 'systemctl stop geogram-station'"
    echo "  Restart: ssh $REMOTE_HOST 'systemctl restart geogram-station'"
else
    echo "Systemd not available, using screen in daemon mode..."

    # Start in screen with station command (daemon mode - no interactive prompt)
    ssh "$REMOTE_HOST" "cd $REMOTE_DIR && screen -dmS $SCREEN_NAME ./geogram-cli --data-dir=$REMOTE_DIR station"

    echo -e "${GREEN}Started in screen session '$SCREEN_NAME'.${NC}"
    echo ""
    echo "Management commands:"
    echo "  Monitor: ssh $REMOTE_HOST 'screen -r $SCREEN_NAME'"
    echo "  Stop:    ssh $REMOTE_HOST 'screen -S $SCREEN_NAME -X quit'"
fi

# Create/update launch script on remote server
echo "Creating launch script on remote server..."
ssh "$REMOTE_HOST" "cat > $REMOTE_DIR/start-geogram.sh" << 'LAUNCH_EOF'
#!/bin/bash
#
# Geogram Station Launch Script
# This script manages the Geogram station server.
#
# Usage:
#   ./start-geogram.sh              - Start using systemd (if available) or screen
#   ./start-geogram.sh start        - Same as above
#   ./start-geogram.sh stop         - Stop the server
#   ./start-geogram.sh restart      - Restart the server
#   ./start-geogram.sh status       - Show server status
#   ./start-geogram.sh logs         - Show server logs (follow mode)
#   ./start-geogram.sh screen       - Force screen mode
#   ./start-geogram.sh systemd      - Force systemd mode
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

MODE="${1:-start}"

# Check if systemd is available
has_systemd() {
    command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1
}

# Check if systemd service is installed
has_service() {
    systemctl list-unit-files geogram-station.service 2>/dev/null | grep -q geogram-station
}

# Check if running
is_running() {
    pgrep -f geogram-cli >/dev/null 2>&1
}

start_systemd() {
    echo "Starting with systemd..."
    if ! has_service; then
        echo "Error: systemd service not installed. Run server-deploy.sh first."
        exit 1
    fi
    systemctl start geogram-station
    echo "Service started. Check status with: systemctl status geogram-station"
    echo "View logs with: journalctl -u geogram-station -f"
}

start_screen() {
    echo "Starting with screen..."
    # Kill any existing screen session
    screen -S geogram -X quit 2>/dev/null || true
    pkill -f geogram-cli 2>/dev/null || true
    sleep 1

    # Start in screen with daemon mode (station command)
    screen -dmS geogram ./geogram-cli --data-dir="$SCRIPT_DIR" station

    echo "Started in screen session 'geogram'."
    echo "Attach with: screen -r geogram"
    echo "Detach with: Ctrl+A, D"
}

do_start() {
    if is_running; then
        echo "Geogram is already running."
        exit 0
    fi
    if has_systemd && has_service; then
        start_systemd
    else
        start_screen
    fi
}

do_stop() {
    echo "Stopping Geogram..."
    if has_systemd && has_service; then
        systemctl stop geogram-station 2>/dev/null || true
    fi
    screen -S geogram -X quit 2>/dev/null || true
    pkill -f geogram-cli 2>/dev/null || true
    sleep 1
    if is_running; then
        echo "Warning: Process still running, force killing..."
        pkill -9 -f geogram-cli 2>/dev/null || true
    fi
    echo "Stopped."
}

do_restart() {
    do_stop
    sleep 1
    do_start
}

do_status() {
    if has_systemd && has_service; then
        systemctl status geogram-station --no-pager
    else
        if is_running; then
            echo "Geogram is running (screen mode)"
            screen -ls | grep geogram || true
            echo ""
            echo "PID: $(pgrep -f geogram-cli)"
        else
            echo "Geogram is not running"
        fi
    fi
}

do_logs() {
    if has_systemd && has_service; then
        journalctl -u geogram-station -f
    else
        echo "Logs are in: $SCRIPT_DIR/logs/"
        echo ""
        if [ -f "$SCRIPT_DIR/logs/crash.txt" ]; then
            echo "=== Recent crash log ==="
            tail -20 "$SCRIPT_DIR/logs/crash.txt"
        fi
        # Find today's log
        TODAY=$(date +%Y-%m-%d)
        YEAR=$(date +%Y)
        LOG_FILE="$SCRIPT_DIR/logs/$YEAR/log-$TODAY.txt"
        if [ -f "$LOG_FILE" ]; then
            echo ""
            echo "=== Today's log (last 50 lines) ==="
            tail -50 "$LOG_FILE"
        fi
    fi
}

case "$MODE" in
    start|"")
        do_start
        ;;
    stop)
        do_stop
        ;;
    restart)
        do_restart
        ;;
    status)
        do_status
        ;;
    logs|log)
        do_logs
        ;;
    systemd)
        start_systemd
        ;;
    screen)
        start_screen
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs|screen|systemd}"
        exit 1
        ;;
esac
LAUNCH_EOF
ssh "$REMOTE_HOST" "chmod +x $REMOTE_DIR/start-geogram.sh"
echo -e "${GREEN}Launch script created: $REMOTE_DIR/start-geogram.sh${NC}"
echo ""

# Step 6: Test that it's online
echo -e "${YELLOW}[6/6] Testing deployment...${NC}"
sleep 3

# Test HTTP endpoint
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "http://p2p.radio/api/status" 2>/dev/null || echo "000")

if [ "$HTTP_STATUS" = "200" ]; then
    echo -e "${GREEN}SUCCESS: Server is online and responding (HTTP $HTTP_STATUS)${NC}"
    echo ""

    # Check if SSL is enabled and wait for certificate
    STATUS_JSON=$(curl -s "http://p2p.radio/api/status" 2>/dev/null)
    HTTPS_ENABLED=$(echo "$STATUS_JSON" | grep -o '"https_enabled":true' || echo "")

    if [ -n "$HTTPS_ENABLED" ]; then
        echo -e "${YELLOW}SSL enabled, waiting for certificate request to complete...${NC}"
        for i in 1 2 3 4 5 6 7 8 9 10; do
            sleep 2
            STATUS_JSON=$(curl -s "http://p2p.radio/api/status" 2>/dev/null)
            HTTPS_RUNNING=$(echo "$STATUS_JSON" | grep -o '"https_running":true' || echo "")
            if [ -n "$HTTPS_RUNNING" ]; then
                echo -e "${GREEN}HTTPS is now running on port 443${NC}"
                break
            fi
            printf "."
        done
        echo ""
        if [ -z "$HTTPS_RUNNING" ]; then
            echo -e "${YELLOW}Note: HTTPS may still be starting (certificate request in progress)${NC}"
        fi
    fi

    # Show status details
    echo ""
    echo "Server status:"
    curl -s "http://p2p.radio/api/status" 2>/dev/null | head -c 600
    echo ""
    echo ""
    echo "Endpoints:"
    echo "  HTTP:      http://p2p.radio/api/status"
    if [ -n "$HTTPS_RUNNING" ]; then
        echo "  HTTPS:     https://p2p.radio/api/status"
    fi
    echo "  WebSocket: ws://p2p.radio/"
    echo ""
    echo "Management (via start-geogram.sh on server):"
    echo "  Status:  ssh $REMOTE_HOST 'cd $REMOTE_DIR && ./start-geogram.sh status'"
    echo "  Logs:    ssh $REMOTE_HOST 'cd $REMOTE_DIR && ./start-geogram.sh logs'"
    echo "  Stop:    ssh $REMOTE_HOST 'cd $REMOTE_DIR && ./start-geogram.sh stop'"
    echo "  Restart: ssh $REMOTE_HOST 'cd $REMOTE_DIR && ./start-geogram.sh restart'"
else
    echo -e "${YELLOW}WARNING: Server may still be starting (HTTP $HTTP_STATUS)${NC}"
    echo ""
    echo "Checking server status..."
    ssh "$REMOTE_HOST" "cd $REMOTE_DIR && ./start-geogram.sh status" || true
    echo ""
    echo "Try again in a few seconds:"
    echo "  curl http://p2p.radio/api/status"
    echo ""
    echo "To debug:"
    echo "  ssh $REMOTE_HOST 'cd $REMOTE_DIR && ./start-geogram.sh logs'"
fi

echo ""
echo "=============================================="
echo "  Deployment complete"
echo "=============================================="
