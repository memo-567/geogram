#!/bin/bash
# Alert Photo Synchronization Test Script
# Tests the Alert photo upload and download through a station
#
# Usage: ./tests/run_alert_photo_test.sh
#
# This script:
# 1. Launches a temporary station instance
# 2. Launches two client instances connected to the station
# 3. Client A creates an alert with a photo and shares it
# 4. Client B verifies it can retrieve the alert and download the photo
#
# Prerequisites:
# - Build the app: flutter build linux --release
# - jq installed for JSON parsing
# - curl installed

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GEOGRAM="$PROJECT_DIR/build/linux/x64/release/bundle/geogram_desktop"

# Configuration
PORT_STATION=6300
PORT_CLIENT_A=6301
PORT_CLIENT_B=6302
DATA_STATION=/tmp/geogram-station-test
DATA_CLIENT_A=/tmp/geogram-client-a-test
DATA_CLIENT_B=/tmp/geogram-client-b-test
STARTUP_WAIT=12
API_WAIT=2

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# PIDs for cleanup
PID_STATION=""
PID_CLIENT_A=""
PID_CLIENT_B=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
}

cleanup() {
    log_info "Cleaning up..."
    [ -n "$PID_STATION" ] && kill $PID_STATION 2>/dev/null || true
    [ -n "$PID_CLIENT_A" ] && kill $PID_CLIENT_A 2>/dev/null || true
    [ -n "$PID_CLIENT_B" ] && kill $PID_CLIENT_B 2>/dev/null || true
    sleep 2
    rm -rf "$DATA_STATION" "$DATA_CLIENT_A" "$DATA_CLIENT_B"
}

check_dependencies() {
    if [ ! -f "$GEOGRAM" ]; then
        log_error "Geogram binary not found at $GEOGRAM"
        log_error "Please build with: flutter build linux --release"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed"
        exit 1
    fi

    if ! command -v curl &> /dev/null; then
        log_error "curl is required but not installed"
        exit 1
    fi
}

wait_for_api() {
    local port=$1
    local name=$2
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if curl -s "http://localhost:$port/api/status" > /dev/null 2>&1; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done

    log_error "$name API not available on port $port after $max_attempts seconds"
    return 1
}

debug_action() {
    local port=$1
    local action=$2
    shift 2
    local params="$@"

    local json="{\"action\": \"$action\""
    if [ -n "$params" ]; then
        json="$json, $params"
    fi
    json="$json}"

    curl -s -X POST "http://localhost:$port/api/debug" \
        -H "Content-Type: application/json" \
        -d "$json"
}

api_get() {
    local port=$1
    local path=$2
    curl -s "http://localhost:$port$path"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [ "$expected" = "$actual" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC}: $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}: $message"
        echo -e "    Expected: $expected"
        echo -e "    Actual: $actual"
        return 1
    fi
}

assert_not_empty() {
    local value="$1"
    local message="$2"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [ -n "$value" ] && [ "$value" != "null" ] && [ "$value" != "" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC}: $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}: $message (got empty or null)"
        return 1
    fi
}

assert_json_field() {
    local json="$1"
    local field="$2"
    local expected="$3"
    local message="$4"

    local actual=$(echo "$json" | jq -r "$field")
    assert_equals "$expected" "$actual" "$message"
}

assert_json_field_not_empty() {
    local json="$1"
    local field="$2"
    local message="$3"

    local actual=$(echo "$json" | jq -r "$field")
    assert_not_empty "$actual" "$message"
}

assert_file_exists() {
    local path="$1"
    local message="$2"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [ -f "$path" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC}: $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}: $message (file not found: $path)"
        return 1
    fi
}

assert_http_status() {
    local expected_status="$1"
    local url="$2"
    local message="$3"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    local actual_status=$(curl -s -o /dev/null -w "%{http_code}" "$url")

    if [ "$expected_status" = "$actual_status" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC}: $message (HTTP $actual_status)"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}: $message"
        echo -e "    Expected HTTP: $expected_status"
        echo -e "    Actual HTTP: $actual_status"
        return 1
    fi
}

# Main test flow
main() {
    log_section "Geogram Alert Photo Synchronization Test"

    check_dependencies
    cleanup

    # Create data directories
    mkdir -p "$DATA_STATION" "$DATA_CLIENT_A" "$DATA_CLIENT_B"

    # ==========================================
    # Start Station Instance
    # ==========================================
    log_section "Starting Station Instance"
    log_info "Starting station on port $PORT_STATION..."

    "$GEOGRAM" --port=$PORT_STATION --data-dir="$DATA_STATION" \
        --new-identity --identity-type=station --nickname="TestStation" --skip-intro \
        --http-api --debug-api --no-update &>/dev/null &
    PID_STATION=$!
    log_info "Station PID: $PID_STATION"

    sleep $STARTUP_WAIT

    if ! wait_for_api $PORT_STATION "Station"; then
        log_error "Station failed to start"
        cleanup
        exit 1
    fi

    # Get station info
    STATION_STATUS=$(api_get $PORT_STATION "/api/status")
    STATION_CALLSIGN=$(echo "$STATION_STATUS" | jq -r '.callsign')
    log_info "Station callsign: $STATION_CALLSIGN"

    # ==========================================
    # Start Client A Instance
    # ==========================================
    log_section "Starting Client A Instance"
    log_info "Starting Client A on port $PORT_CLIENT_A..."

    "$GEOGRAM" --port=$PORT_CLIENT_A --data-dir="$DATA_CLIENT_A" \
        --new-identity --nickname="ClientA" --skip-intro \
        --http-api --debug-api --no-update \
        --scan-localhost=6299-6310 &>/dev/null &
    PID_CLIENT_A=$!
    log_info "Client A PID: $PID_CLIENT_A"

    sleep $STARTUP_WAIT

    if ! wait_for_api $PORT_CLIENT_A "Client A"; then
        log_error "Client A failed to start"
        cleanup
        exit 1
    fi

    CLIENT_A_STATUS=$(api_get $PORT_CLIENT_A "/api/status")
    CLIENT_A_CALLSIGN=$(echo "$CLIENT_A_STATUS" | jq -r '.callsign')
    log_info "Client A callsign: $CLIENT_A_CALLSIGN"

    # ==========================================
    # Start Client B Instance
    # ==========================================
    log_section "Starting Client B Instance"
    log_info "Starting Client B on port $PORT_CLIENT_B..."

    "$GEOGRAM" --port=$PORT_CLIENT_B --data-dir="$DATA_CLIENT_B" \
        --new-identity --nickname="ClientB" --skip-intro \
        --http-api --debug-api --no-update \
        --scan-localhost=6299-6310 &>/dev/null &
    PID_CLIENT_B=$!
    log_info "Client B PID: $PID_CLIENT_B"

    sleep $STARTUP_WAIT

    if ! wait_for_api $PORT_CLIENT_B "Client B"; then
        log_error "Client B failed to start"
        cleanup
        exit 1
    fi

    CLIENT_B_STATUS=$(api_get $PORT_CLIENT_B "/api/status")
    CLIENT_B_CALLSIGN=$(echo "$CLIENT_B_STATUS" | jq -r '.callsign')
    log_info "Client B callsign: $CLIENT_B_CALLSIGN"

    echo ""
    log_info "All instances running:"
    log_info "  Station: $STATION_CALLSIGN (port $PORT_STATION)"
    log_info "  Client A: $CLIENT_A_CALLSIGN (port $PORT_CLIENT_A)"
    log_info "  Client B: $CLIENT_B_CALLSIGN (port $PORT_CLIENT_B)"

    # ==========================================
    # Test 1: Create Alert with Photo on Client A
    # ==========================================
    log_section "Test 1: Create Alert with Photo"
    log_test "Creating alert with test photo on Client A..."

    CREATE_RESULT=$(debug_action $PORT_CLIENT_A "alert_create" \
        '"title": "Photo Test Alert"' \
        ', "description": "Alert with photo for sync testing"' \
        ', "latitude": 38.7223' \
        ', "longitude": -9.1393' \
        ', "severity": "urgent"' \
        ', "type": "infrastructure-broken"' \
        ', "photo": true')

    echo "Create result: $CREATE_RESULT"

    assert_json_field "$CREATE_RESULT" ".success" "true" "Alert creation with photo succeeds"
    assert_json_field "$CREATE_RESULT" ".photo_created" "true" "Photo was created"

    ALERT_ID=$(echo "$CREATE_RESULT" | jq -r '.alert.id')
    ALERT_PATH=$(echo "$CREATE_RESULT" | jq -r '.alert_path')
    PHOTO_PATH=$(echo "$CREATE_RESULT" | jq -r '.photo_path')

    assert_not_empty "$ALERT_ID" "Alert ID returned"
    assert_not_empty "$ALERT_PATH" "Alert path returned"
    assert_not_empty "$PHOTO_PATH" "Photo path returned"

    log_info "Created alert: $ALERT_ID"
    log_info "Alert path: $ALERT_PATH"
    log_info "Photo path: $PHOTO_PATH"

    # Verify photo file exists locally on Client A
    assert_file_exists "$PHOTO_PATH" "Photo file exists on Client A"

    echo ""
    sleep $API_WAIT

    # ==========================================
    # Test 2: Share Alert to Station
    # ==========================================
    log_section "Test 2: Share Alert to Station"
    log_test "Sharing alert from Client A to station..."

    SHARE_RESULT=$(debug_action $PORT_CLIENT_A "alert_share" \
        "\"alert_id\": \"$ALERT_ID\"")

    echo "Share result: $SHARE_RESULT"

    assert_json_field "$SHARE_RESULT" ".success" "true" "Alert sharing succeeds"
    assert_json_field_not_empty "$SHARE_RESULT" ".event_id" "NOSTR event ID returned"

    CONFIRMED=$(echo "$SHARE_RESULT" | jq -r '.confirmed')
    log_info "Stations confirmed: $CONFIRMED"

    echo ""
    sleep $API_WAIT

    # ==========================================
    # Test 3: Verify Alert on Station
    # ==========================================
    log_section "Test 3: Verify Alert on Station"
    log_test "Checking if alert arrived at station..."

    # List alerts on station
    STATION_ALERTS=$(api_get $PORT_STATION "/api/alerts")
    STATION_ALERT_COUNT=$(echo "$STATION_ALERTS" | jq '.total')

    log_info "Station has $STATION_ALERT_COUNT alerts"
    echo "Station alerts: $STATION_ALERTS"

    # Try to get the specific alert
    STATION_ALERT=$(api_get $PORT_STATION "/api/alerts/$ALERT_ID")
    echo "Station alert details: $STATION_ALERT"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if echo "$STATION_ALERT" | jq -e '.id' > /dev/null 2>&1; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC}: Alert found on station"
    else
        # Alert might be in a different format due to NOSTR transmission
        log_warn "Alert may not be directly visible yet (NOSTR propagation)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}: Alert not found on station"
    fi

    echo ""
    sleep $API_WAIT

    # ==========================================
    # Test 4: Check Photo Upload to Station
    # ==========================================
    log_section "Test 4: Verify Photo Upload to Station"
    log_test "Checking if photo was uploaded to station..."

    # Check station's data directory for the photo
    STATION_PHOTO_PATH="$DATA_STATION/devices/$CLIENT_A_CALLSIGN/alerts/active"

    log_info "Looking for photos in: $STATION_PHOTO_PATH"

    if [ -d "$STATION_PHOTO_PATH" ]; then
        FOUND_PHOTOS=$(find "$STATION_PHOTO_PATH" -name "*.png" -o -name "*.jpg" 2>/dev/null | head -5)
        if [ -n "$FOUND_PHOTOS" ]; then
            log_info "Found photos on station:"
            echo "$FOUND_PHOTOS" | while read photo; do
                log_info "  $photo"
            done
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "  ${GREEN}PASS${NC}: Photos found on station storage"
        else
            log_warn "No photos found in station storage"
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "  ${RED}FAIL${NC}: No photos in station storage"
        fi
    else
        log_warn "Station alerts directory not found: $STATION_PHOTO_PATH"
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}: Station alerts directory not found"
    fi

    echo ""

    # ==========================================
    # Test 5: Photo Download via HTTP (from Station)
    # ==========================================
    log_section "Test 5: Photo Download via HTTP API"
    log_test "Attempting to download photo from station API..."

    # Try to download the photo via the alert files API
    PHOTO_URL="http://localhost:$PORT_STATION/$CLIENT_A_CALLSIGN/api/alerts/$ALERT_ID/files/test_photo.png"
    log_info "Photo URL: $PHOTO_URL"

    DOWNLOAD_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$PHOTO_URL")
    log_info "Download HTTP status: $DOWNLOAD_STATUS"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if [ "$DOWNLOAD_STATUS" = "200" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC}: Photo downloadable from station (HTTP 200)"

        # Actually download and verify it's a valid file
        TEMP_DOWNLOAD="/tmp/geogram-test-download.png"
        curl -s -o "$TEMP_DOWNLOAD" "$PHOTO_URL"
        DOWNLOADED_SIZE=$(stat -f%z "$TEMP_DOWNLOAD" 2>/dev/null || stat -c%s "$TEMP_DOWNLOAD" 2>/dev/null)
        log_info "Downloaded file size: $DOWNLOADED_SIZE bytes"

        if [ "$DOWNLOADED_SIZE" -gt 0 ]; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "  ${GREEN}PASS${NC}: Downloaded file has content"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "  ${RED}FAIL${NC}: Downloaded file is empty"
        fi
        rm -f "$TEMP_DOWNLOAD"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}: Photo not downloadable (HTTP $DOWNLOAD_STATUS)"
        log_warn "Photo may not have been uploaded to station yet"
    fi

    echo ""

    # ==========================================
    # Test 6: Client B retrieves alert from station
    # ==========================================
    log_section "Test 6: Client B Alert Retrieval"
    log_test "Checking if Client B can see the alert..."

    # Note: This would require Client B to actually sync with the station
    # For now we just verify the API is accessible
    CLIENT_B_ALERTS=$(api_get $PORT_CLIENT_B "/api/alerts")
    log_info "Client B alerts response: $CLIENT_B_ALERTS"

    echo ""

    # ==========================================
    # Summary
    # ==========================================
    log_section "Test Summary"
    echo ""
    echo "Instances:"
    echo "  Station: $STATION_CALLSIGN (port $PORT_STATION)"
    echo "  Client A: $CLIENT_A_CALLSIGN (port $PORT_CLIENT_A)"
    echo "  Client B: $CLIENT_B_CALLSIGN (port $PORT_CLIENT_B)"
    echo ""
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo -e "Total tests:  $TESTS_TOTAL"
    echo ""

    # Show data directories for debugging
    log_info "Data directories (preserved for inspection):"
    log_info "  Station: $DATA_STATION"
    log_info "  Client A: $DATA_CLIENT_A"
    log_info "  Client B: $DATA_CLIENT_B"

    # Cleanup processes but keep data for inspection
    log_info "Stopping instances..."
    [ -n "$PID_STATION" ] && kill $PID_STATION 2>/dev/null || true
    [ -n "$PID_CLIENT_A" ] && kill $PID_CLIENT_A 2>/dev/null || true
    [ -n "$PID_CLIENT_B" ] && kill $PID_CLIENT_B 2>/dev/null || true

    echo ""
    if [ $TESTS_FAILED -gt 0 ]; then
        log_error "Some tests failed!"
        log_info "Check the data directories above for debugging."
        exit 1
    else
        log_info "All tests passed!"
        # Cleanup data on success
        rm -rf "$DATA_STATION" "$DATA_CLIENT_A" "$DATA_CLIENT_B"
        exit 0
    fi
}

# Run main with cleanup on exit
trap cleanup EXIT
main "$@"
