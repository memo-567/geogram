#!/bin/bash
# Shared App Data Test - Bash Smoke Test
#
# This script tests remote device browsing functionality by:
# 1. Launching two Geogram instances with localhost scanning
# 2. Creating a blog post on Instance A
# 3. Verifying Instance B can discover Instance A
# 4. Verifying Instance B can access Instance A's blog data
#
# Exit codes:
#   0 - All tests passed
#   1 - Test failed or error occurred

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Test configuration
PORT_A=17000
PORT_B=17100
TEMP_DIR_A="/tmp/geogram-shared-test-a"
TEMP_DIR_B="/tmp/geogram-shared-test-b"
NICKNAME_A="TestInstance-A"
NICKNAME_B="TestInstance-B"
SCAN_RANGE="$PORT_A-$PORT_B"

# Timing configuration
STARTUP_WAIT=15
DISCOVERY_TIMEOUT=30
API_TIMEOUT=5

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test tracking
TESTS_PASSED=0
TESTS_FAILED=0
TEST_FAILURES=()

# Process IDs
PID_A=""
PID_B=""

# Test data
CALLSIGN_A=""
BLOG_ID=""

# Helper functions
log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}======================================${NC}"
}

pass_test() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log_success "$1"
}

fail_test() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TEST_FAILURES+=("$1: $2")
    log_error "$1 - $2"
}

# Cleanup function
cleanup() {
    log_section "Cleanup"

    if [ -n "$PID_B" ]; then
        log_info "Stopping Instance B (PID: $PID_B)..."
        kill -TERM $PID_B 2>/dev/null || true
    fi

    if [ -n "$PID_A" ]; then
        log_info "Stopping Instance A (PID: $PID_A)..."
        kill -TERM $PID_A 2>/dev/null || true
    fi

    sleep 2

    # Force kill if still running
    if [ -n "$PID_B" ]; then
        kill -KILL $PID_B 2>/dev/null || true
    fi
    if [ -n "$PID_A" ]; then
        kill -KILL $PID_A 2>/dev/null || true
    fi

    log_info "Temp directories kept for inspection:"
    log_info "  Instance A: $TEMP_DIR_A"
    log_info "  Instance B: $TEMP_DIR_B"
}

# Set trap for cleanup
trap cleanup EXIT

# Main test execution
log_section "Geogram Shared App Data Test Suite"

# Check binary exists
BINARY_PATH="$PROJECT_DIR/build/linux/x64/release/bundle/geogram_desktop"
if [ ! -f "$BINARY_PATH" ]; then
    log_error "Binary not found: $BINARY_PATH"
    log_info "Please build first: flutter build linux --release"
    exit 1
fi
log_success "Binary found: $BINARY_PATH"

# Setup: Clean and create temp directories
log_section "Setup"

if [ -d "$TEMP_DIR_A" ]; then
    log_info "Removing existing: $TEMP_DIR_A"
    rm -rf "$TEMP_DIR_A"
fi
mkdir -p "$TEMP_DIR_A"
log_success "Created: $TEMP_DIR_A"

if [ -d "$TEMP_DIR_B" ]; then
    log_info "Removing existing: $TEMP_DIR_B"
    rm -rf "$TEMP_DIR_B"
fi
mkdir -p "$TEMP_DIR_B"
log_success "Created: $TEMP_DIR_B"

# Launch Instance A
log_section "Launch Instance A"

log_info "Starting Instance A on port $PORT_A..."
"$BINARY_PATH" \
    --port=$PORT_A \
    --data-dir="$TEMP_DIR_A" \
    --new-identity \
    --nickname="$NICKNAME_A" \
    --skip-intro \
    --http-api \
    --debug-api \
    --scan-localhost=$SCAN_RANGE \
    > "$TEMP_DIR_A/stdout.log" 2>&1 &
PID_A=$!

if [ -z "$PID_A" ]; then
    fail_test "Launch Instance A" "Failed to start process"
    exit 1
fi
log_success "Instance A started (PID: $PID_A)"

# Launch Instance B
log_section "Launch Instance B"

log_info "Starting Instance B on port $PORT_B..."
"$BINARY_PATH" \
    --port=$PORT_B \
    --data-dir="$TEMP_DIR_B" \
    --new-identity \
    --nickname="$NICKNAME_B" \
    --skip-intro \
    --http-api \
    --debug-api \
    --scan-localhost=$SCAN_RANGE \
    > "$TEMP_DIR_B/stdout.log" 2>&1 &
PID_B=$!

if [ -z "$PID_B" ]; then
    fail_test "Launch Instance B" "Failed to start process"
    exit 1
fi
log_success "Instance B started (PID: $PID_B)"

# Wait for startup
log_info "Waiting ${STARTUP_WAIT}s for instances to initialize..."
sleep $STARTUP_WAIT

# Wait for Instance A to be ready
log_section "Wait for Instance A Ready"

READY=false
for i in {1..12}; do
    if curl -s -f "http://localhost:$PORT_A/api/status" > /dev/null 2>&1; then
        READY=true
        break
    fi
    log_info "Attempt $i/12..."
    sleep $API_TIMEOUT
done

if [ "$READY" = false ]; then
    fail_test "Instance A ready" "Timeout waiting for API"
    exit 1
fi

# Get callsign
RESPONSE=$(curl -s "http://localhost:$PORT_A/api/status")
CALLSIGN_A=$(echo "$RESPONSE" | grep -oP '"callsign"\s*:\s*"\K[^"]+' || echo "")

if [ -z "$CALLSIGN_A" ]; then
    fail_test "Get Instance A callsign" "Failed to extract callsign"
    exit 1
fi

pass_test "Instance A ready (callsign: $CALLSIGN_A)"

# Wait for Instance B to be ready
log_section "Wait for Instance B Ready"

READY=false
for i in {1..12}; do
    if curl -s -f "http://localhost:$PORT_B/api/status" > /dev/null 2>&1; then
        READY=true
        break
    fi
    log_info "Attempt $i/12..."
    sleep $API_TIMEOUT
done

if [ "$READY" = false ]; then
    fail_test "Instance B ready" "Timeout waiting for API"
    exit 1
fi

pass_test "Instance B ready"

# Create blog post on Instance A
log_section "Create Blog Post on Instance A"

BLOG_RESPONSE=$(curl -s -X POST "http://localhost:$PORT_A/api/debug" \
    -H "Content-Type: application/json" \
    -d '{
        "action": "blog_create",
        "title": "Shared App Data Test Post",
        "content": "This is a test blog post created to verify remote device browsing functionality works correctly.",
        "status": "published"
    }')

SUCCESS=$(echo "$BLOG_RESPONSE" | grep -oP '"success"\s*:\s*\K(true|false)' || echo "false")

if [ "$SUCCESS" != "true" ]; then
    ERROR=$(echo "$BLOG_RESPONSE" | grep -oP '"error"\s*:\s*"\K[^"]+' || echo "Unknown error")
    fail_test "Create blog post" "$ERROR"
    exit 1
fi

BLOG_ID=$(echo "$BLOG_RESPONSE" | grep -oP '"blog_id"\s*:\s*"\K[^"]+' || echo "")

if [ -z "$BLOG_ID" ]; then
    fail_test "Create blog post" "No blog_id in response"
    exit 1
fi

pass_test "Blog post created (ID: $BLOG_ID)"

# Wait for device discovery
log_section "Device Discovery"

log_info "Waiting for Instance B to discover Instance A (timeout: ${DISCOVERY_TIMEOUT}s)..."

DISCOVERED=false
for i in $(seq 1 $DISCOVERY_TIMEOUT); do
    DEVICES_RESPONSE=$(curl -s "http://localhost:$PORT_B/api/devices" 2>/dev/null || echo "")

    if echo "$DEVICES_RESPONSE" | grep -q "\"callsign\".*:.*\"$CALLSIGN_A\""; then
        DISCOVERED=true
        log_success "Instance B discovered Instance A in ${i}s"
        break
    fi

    if [ $((i % 5)) -eq 0 ]; then
        log_info "Still waiting... (${i}s elapsed)"
    fi

    sleep 1
done

if [ "$DISCOVERED" = false ]; then
    fail_test "Device discovery" "Timeout after ${DISCOVERY_TIMEOUT}s"
    exit 1
fi

pass_test "Device discovery completed"

# Browse Instance A's apps from Instance B
log_section "Browse Remote Device Apps (Instance B browsing Instance A)"

BROWSE_RESPONSE=$(curl -s -X POST "http://localhost:$PORT_B/api/debug" \
    -H "Content-Type: application/json" \
    -d "{
        \"action\": \"device_browse_apps\",
        \"callsign\": \"$CALLSIGN_A\"
    }")

SUCCESS=$(echo "$BROWSE_RESPONSE" | grep -oP '"success"\s*:\s*\K(true|false)' || echo "false")

if [ "$SUCCESS" != "true" ]; then
    ERROR=$(echo "$BROWSE_RESPONSE" | grep -oP '"error"\s*:\s*"\K[^"]+' || echo "Unknown error")
    fail_test "Browse remote apps" "$ERROR"
    log_info "Response: $BROWSE_RESPONSE"
    exit 1
fi

# Check if blog app is listed
if echo "$BROWSE_RESPONSE" | grep -q "\"type\".*:.*\"blog\""; then
    pass_test "Blog app discovered in Instance A's public data"

    # Extract blog item count
    ITEM_COUNT=$(echo "$BROWSE_RESPONSE" | grep -oP '"type"\s*:\s*"blog"[^}]*"itemCount"\s*:\s*\K[0-9]+' || echo "0")

    if [ "$ITEM_COUNT" -gt 0 ]; then
        pass_test "Blog has $ITEM_COUNT post(s) visible from Instance B"
    else
        fail_test "Blog item count" "Blog app found but shows 0 items (expected at least 1)"
        exit 1
    fi
else
    fail_test "Browse remote apps" "Blog app not found in Instance A's public apps"
    log_info "Response: $BROWSE_RESPONSE"
    exit 1
fi

# Verify file system structure
log_section "Verify File System"

YEAR=$(date +%Y)
BLOG_DIR="$TEMP_DIR_A/devices/$CALLSIGN_A/blog/$YEAR"

if [ -d "$BLOG_DIR" ]; then
    pass_test "Blog directory exists: $BLOG_DIR"

    # Find blog post directory
    BLOG_POST_DIR=$(find "$BLOG_DIR" -type d -name "*" | grep "$BLOG_ID" | head -1)

    if [ -n "$BLOG_POST_DIR" ] && [ -f "$BLOG_POST_DIR/post.md" ]; then
        pass_test "Blog post file found: $BLOG_POST_DIR/post.md"
    else
        fail_test "Blog post file" "Not found in expected location"
    fi
else
    fail_test "Blog directory" "Not found: $BLOG_DIR"
fi

# Test Results
log_section "Test Results"

echo ""
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"

if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo ""
    echo "Failures:"
    for failure in "${TEST_FAILURES[@]}"; do
        echo -e "${RED}  - $failure${NC}"
    done
    echo ""
    exit 1
fi

echo ""
log_success "All tests passed!"
echo ""

exit 0
