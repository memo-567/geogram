#!/bin/bash
#
# Simple Mirror E2E Test
#
# Tests the simple mirror sync API between two Geogram instances:
# - Instance A (source) on port 5577
# - Instance B (destination) on port 5588
#
# Usage:
#   ./test-simple-mirror.sh              # Build and test
#   ./test-simple-mirror.sh --skip-build # Test only (assumes built)
#   ./test-simple-mirror.sh --dart-only  # Run only Dart tests (instances must be running)
#
# Tests include:
# 1. Basic sync functionality (file transfer, SHA1 verification)
# 2. Update sync (detecting and transferring modified files)
# 3. One-way mirror behavior (local changes overwritten)
# 4. Challenge-response authentication (via Dart test suite)
# 5. Replay attack prevention (via Dart test suite)
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
PORT_A=5577
PORT_B=5588
DATA_DIR_A="/tmp/geogram-mirror-test-a"
DATA_DIR_B="/tmp/geogram-mirror-test-b"
TEST_FOLDER="test-sync-folder"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Track cleanup
INSTANCE_A_PID=""
INSTANCE_B_PID=""

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"

    if [ -n "$INSTANCE_A_PID" ] && kill -0 "$INSTANCE_A_PID" 2>/dev/null; then
        echo "Stopping Instance A (PID $INSTANCE_A_PID)"
        kill "$INSTANCE_A_PID" 2>/dev/null || true
    fi

    if [ -n "$INSTANCE_B_PID" ] && kill -0 "$INSTANCE_B_PID" 2>/dev/null; then
        echo "Stopping Instance B (PID $INSTANCE_B_PID)"
        kill "$INSTANCE_B_PID" 2>/dev/null || true
    fi

    # Wait for processes to stop
    sleep 1

    # Remove test data directories
    echo "Removing test data directories..."
    rm -rf "$DATA_DIR_A" "$DATA_DIR_B"

    echo -e "${GREEN}Cleanup complete${NC}"
}

# Set trap for cleanup
trap cleanup EXIT

# Helper: Print step header with explanation
step_with_explanation() {
    local title="$1"
    local explanation="$2"
    echo ""
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────────────${NC}"
    echo -e "${BLUE}│ TEST: $title${NC}"
    echo -e "${BLUE}├─────────────────────────────────────────────────────────────────${NC}"
    echo -e "${CYAN}│ WHY: $explanation${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────────────${NC}"
}

# Helper: Print step
step() {
    echo -e "\n${BLUE}==> $1${NC}"
}

# Helper: Print success
success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Helper: Print error and exit
error() {
    echo -e "${RED}✗ $1${NC}"
    exit 1
}

# Helper: Wait for instance to be ready
wait_for_instance() {
    local port=$1
    local name=$2
    local max_attempts=30
    local attempt=0

    echo -n "Waiting for $name to be ready..."
    while [ $attempt -lt $max_attempts ]; do
        if curl -s "http://localhost:$port/api/status" > /dev/null 2>&1; then
            echo " ready!"
            return 0
        fi
        echo -n "."
        sleep 1
        attempt=$((attempt + 1))
    done

    echo " timeout!"
    error "$name failed to start within ${max_attempts}s"
}

# Helper: Make API request
api_request() {
    local port=$1
    local method=$2
    local endpoint=$3
    local data=$4

    if [ "$method" = "GET" ]; then
        curl -s "http://localhost:$port$endpoint"
    else
        curl -s -X "$method" "http://localhost:$port$endpoint" \
            -H "Content-Type: application/json" \
            -d "$data"
    fi
}

# Helper: Debug action
debug_action() {
    local port=$1
    local action=$2
    shift 2
    local params="$*"

    local json="{\"action\": \"$action\""
    for param in $params; do
        key="${param%%=*}"
        value="${param#*=}"
        json="$json, \"$key\": \"$value\""
    done
    json="$json}"

    curl -s -X POST "http://localhost:$port/api/debug" \
        -H "Content-Type: application/json" \
        -d "$json"
}

# Helper: Compute SHA1 of file
compute_sha1() {
    local file=$1
    sha1sum "$file" | cut -d' ' -f1
}

# Parse arguments
SKIP_BUILD=false
DART_ONLY=false
for arg in "$@"; do
    case $arg in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --dart-only)
            DART_ONLY=true
            shift
            ;;
    esac
done

# ============================================================
# Main Test Flow
# ============================================================

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Simple Mirror Sync E2E Test                                 ║${NC}"
echo -e "${BLUE}║         Tests: Basic Sync, Updates, Security (Challenge-Response)   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════╝${NC}"

# If --dart-only, skip to Dart tests
if [ "$DART_ONLY" = true ]; then
    step "Running Dart test suite only..."
    cd "$PROJECT_DIR"

    if ! command -v dart &> /dev/null; then
        # Try to find dart through flutter
        DART_CMD="$HOME/flutter/bin/dart"
        if [ ! -f "$DART_CMD" ]; then
            error "Dart not found. Install Flutter or add dart to PATH."
        fi
    else
        DART_CMD="dart"
    fi

    $DART_CMD run tests/mirror/mirror_sync_test.dart --port-a $PORT_A --port-b $PORT_B
    exit $?
fi

# Step 0: Build if needed
if [ "$SKIP_BUILD" = false ]; then
    step "Building Geogram..."
    cd "$PROJECT_DIR"
    $HOME/flutter/bin/flutter build linux --release 2>&1 | tail -5
    success "Build complete"
fi

# Step 1: Create test data directories
step "Setting up test directories..."
rm -rf "$DATA_DIR_A" "$DATA_DIR_B"
mkdir -p "$DATA_DIR_A/$TEST_FOLDER"
mkdir -p "$DATA_DIR_B/$TEST_FOLDER"
success "Test directories created"

# Step 2: Create test files on Instance A
step_with_explanation \
    "Create Test Files on Instance A" \
    "We create 3 test files with known content so we can verify
│ SHA1 hashes match after sync. This tests basic file integrity."

echo "Hello from file 1" > "$DATA_DIR_A/$TEST_FOLDER/file1.txt"
echo "Hello from file 2" > "$DATA_DIR_A/$TEST_FOLDER/file2.txt"
mkdir -p "$DATA_DIR_A/$TEST_FOLDER/subdir"
echo "Hello from subdir file" > "$DATA_DIR_A/$TEST_FOLDER/subdir/nested.txt"

# Compute expected SHA1s
SHA1_FILE1=$(compute_sha1 "$DATA_DIR_A/$TEST_FOLDER/file1.txt")
SHA1_FILE2=$(compute_sha1 "$DATA_DIR_A/$TEST_FOLDER/file2.txt")
SHA1_NESTED=$(compute_sha1 "$DATA_DIR_A/$TEST_FOLDER/subdir/nested.txt")

success "Created 3 test files"
echo "  - file1.txt (SHA1: ${SHA1_FILE1:0:8}...)"
echo "  - file2.txt (SHA1: ${SHA1_FILE2:0:8}...)"
echo "  - subdir/nested.txt (SHA1: ${SHA1_NESTED:0:8}...)"

# Step 3: Start Instance A
step_with_explanation \
    "Start Instance A (Source)" \
    "Instance A acts as the 'source' - it has the files that Instance B
│ will request. It runs with --debug-api to enable test automation."

cd "$PROJECT_DIR"
./build/linux/x64/release/bundle/geogram \
    --headless \
    --data-dir "$DATA_DIR_A" \
    --port $PORT_A \
    --debug-api \
    --skip-intro \
    --new-identity &
INSTANCE_A_PID=$!
echo "Instance A PID: $INSTANCE_A_PID"
wait_for_instance $PORT_A "Instance A"
success "Instance A started on port $PORT_A"

# Step 4: Start Instance B
step_with_explanation \
    "Start Instance B (Destination)" \
    "Instance B acts as the 'destination' - it will request files from A
│ and store them locally. Its local changes will be overwritten by A."

./build/linux/x64/release/bundle/geogram \
    --headless \
    --data-dir "$DATA_DIR_B" \
    --port $PORT_B \
    --debug-api \
    --skip-intro \
    --new-identity &
INSTANCE_B_PID=$!
echo "Instance B PID: $INSTANCE_B_PID"
wait_for_instance $PORT_B "Instance B"
success "Instance B started on port $PORT_B"

# Step 5: Get Instance B's NPUB
step_with_explanation \
    "Get Instance B's Identity" \
    "We need B's NOSTR public key (npub) to add it as an allowed peer
│ on Instance A. Only allowed peers can request syncs."

STATUS_B=$(api_request $PORT_B GET "/api/status")
NPUB_B=$(echo "$STATUS_B" | jq -r '.npub // empty')
CALLSIGN_B=$(echo "$STATUS_B" | jq -r '.callsign // empty')

if [ -z "$NPUB_B" ] || [ "$NPUB_B" = "null" ]; then
    echo "Status response: $STATUS_B"
    error "Could not get Instance B's npub"
fi

success "Instance B identity: $CALLSIGN_B"
echo "  NPUB: ${NPUB_B:0:30}..."

# Step 6: Enable mirror on Instance A and add B as allowed peer
step_with_explanation \
    "Configure Instance A to Allow Sync from B" \
    "Instance A must explicitly allow B to sync from it. This is a
│ security measure - only trusted peers can access files."

RESULT=$(debug_action $PORT_A "mirror_enable" "enabled=true")
echo "Enable result: $RESULT"

RESULT=$(debug_action $PORT_A "mirror_add_allowed_peer" "npub=$NPUB_B" "callsign=$CALLSIGN_B")
echo "Add peer result: $RESULT"

# Verify configuration
RESULT=$(debug_action $PORT_A "mirror_get_status")
echo "Mirror status: $RESULT"
success "Instance A configured as source"

# Step 7: Request sync from B to A
step_with_explanation \
    "Instance B Requests Sync from Instance A" \
    "B initiates the sync by: (1) requesting a challenge from A,
│ (2) signing the challenge with its NSEC (private key),
│ (3) sending the signed response to prove identity,
│ (4) receiving a token, then (5) downloading files."

RESULT=$(debug_action $PORT_B "mirror_request_sync" "peer_url=http://localhost:$PORT_A" "folder=$TEST_FOLDER")
echo "Sync result: $RESULT"

SYNC_SUCCESS=$(echo "$RESULT" | jq -r '.success')
FILES_ADDED=$(echo "$RESULT" | jq -r '.files_added // 0')

if [ "$SYNC_SUCCESS" != "true" ]; then
    error "Sync failed: $(echo "$RESULT" | jq -r '.error')"
fi

success "Sync completed: $FILES_ADDED files added"

# Step 8: Verify files transferred correctly
step_with_explanation \
    "Verify Transferred Files Match (SHA1 Integrity)" \
    "Each file's SHA1 hash must match the original. This ensures:
│ (1) Files transferred completely without corruption,
│ (2) The manifest SHA1 was verified during download."

# Check file1.txt
if [ ! -f "$DATA_DIR_B/$TEST_FOLDER/file1.txt" ]; then
    error "file1.txt not transferred"
fi
SHA1_B_FILE1=$(compute_sha1 "$DATA_DIR_B/$TEST_FOLDER/file1.txt")
if [ "$SHA1_B_FILE1" != "$SHA1_FILE1" ]; then
    error "file1.txt SHA1 mismatch: expected $SHA1_FILE1, got $SHA1_B_FILE1"
fi
success "file1.txt: SHA1 matches ($SHA1_FILE1)"

# Check file2.txt
if [ ! -f "$DATA_DIR_B/$TEST_FOLDER/file2.txt" ]; then
    error "file2.txt not transferred"
fi
SHA1_B_FILE2=$(compute_sha1 "$DATA_DIR_B/$TEST_FOLDER/file2.txt")
if [ "$SHA1_B_FILE2" != "$SHA1_FILE2" ]; then
    error "file2.txt SHA1 mismatch: expected $SHA1_FILE2, got $SHA1_B_FILE2"
fi
success "file2.txt: SHA1 matches ($SHA1_FILE2)"

# Check nested.txt
if [ ! -f "$DATA_DIR_B/$TEST_FOLDER/subdir/nested.txt" ]; then
    error "subdir/nested.txt not transferred"
fi
SHA1_B_NESTED=$(compute_sha1 "$DATA_DIR_B/$TEST_FOLDER/subdir/nested.txt")
if [ "$SHA1_B_NESTED" != "$SHA1_NESTED" ]; then
    error "subdir/nested.txt SHA1 mismatch: expected $SHA1_NESTED, got $SHA1_B_NESTED"
fi
success "subdir/nested.txt: SHA1 matches ($SHA1_NESTED)"

# Step 9: Modify file on A and re-sync
step_with_explanation \
    "Test Update Sync (Modify File on A)" \
    "When a file changes on A, B should detect it via SHA1 mismatch
│ in the manifest and download only the changed file."

echo "Updated content from A" > "$DATA_DIR_A/$TEST_FOLDER/file1.txt"
NEW_SHA1_FILE1=$(compute_sha1 "$DATA_DIR_A/$TEST_FOLDER/file1.txt")
echo "New SHA1 for file1.txt: ${NEW_SHA1_FILE1:0:8}..."

RESULT=$(debug_action $PORT_B "mirror_request_sync" "peer_url=http://localhost:$PORT_A" "folder=$TEST_FOLDER")
FILES_MODIFIED=$(echo "$RESULT" | jq -r '.files_modified // 0')
success "Update sync completed: $FILES_MODIFIED files modified"

# Verify the update
SHA1_B_FILE1=$(compute_sha1 "$DATA_DIR_B/$TEST_FOLDER/file1.txt")
if [ "$SHA1_B_FILE1" != "$NEW_SHA1_FILE1" ]; then
    error "file1.txt not updated: expected $NEW_SHA1_FILE1, got $SHA1_B_FILE1"
fi
success "file1.txt: Update verified (new SHA1: $NEW_SHA1_FILE1)"

# Step 10: Test that B's local changes are overwritten
step_with_explanation \
    "Test One-Way Mirror (B's Changes Overwritten)" \
    "Simple Mirror is ONE-WAY: A is the source of truth. If B modifies
│ a file locally, the next sync should overwrite B's changes with
│ A's version. This is the key 'mirror' behavior."

echo "Local change on B (should be discarded)" > "$DATA_DIR_B/$TEST_FOLDER/file1.txt"
LOCAL_SHA1=$(compute_sha1 "$DATA_DIR_B/$TEST_FOLDER/file1.txt")
echo "B's local SHA1 (will be overwritten): ${LOCAL_SHA1:0:8}..."

RESULT=$(debug_action $PORT_B "mirror_request_sync" "peer_url=http://localhost:$PORT_A" "folder=$TEST_FOLDER")
FILES_MODIFIED=$(echo "$RESULT" | jq -r '.files_modified // 0')
success "Re-sync completed: $FILES_MODIFIED files modified"

# Verify B's changes were overwritten
SHA1_B_FILE1=$(compute_sha1 "$DATA_DIR_B/$TEST_FOLDER/file1.txt")
if [ "$SHA1_B_FILE1" != "$NEW_SHA1_FILE1" ]; then
    error "B's changes were not overwritten: expected $NEW_SHA1_FILE1, got $SHA1_B_FILE1"
fi
success "B's local changes correctly overwritten by A's content"

# ============================================================
# Run Dart Security Tests
# ============================================================

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Running Dart Security Test Suite                            ║${NC}"
echo -e "${BLUE}║         Tests: Challenge-Response, Replay Prevention, Auth          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════╝${NC}"

cd "$PROJECT_DIR"

# Find dart command
if ! command -v dart &> /dev/null; then
    DART_CMD="$HOME/flutter/bin/dart"
    if [ ! -f "$DART_CMD" ]; then
        echo -e "${YELLOW}Warning: Dart not found. Skipping Dart security tests.${NC}"
        echo "Install Flutter or add dart to PATH to run security tests."
        DART_AVAILABLE=false
    else
        DART_AVAILABLE=true
    fi
else
    DART_CMD="dart"
    DART_AVAILABLE=true
fi

if [ "$DART_AVAILABLE" = true ]; then
    # Run Dart tests
    $DART_CMD run tests/mirror/mirror_sync_test.dart --port-a $PORT_A --port-b $PORT_B
    DART_EXIT_CODE=$?

    if [ $DART_EXIT_CODE -ne 0 ]; then
        error "Dart security tests failed!"
    fi
fi

# ============================================================
# Summary
# ============================================================

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         All Tests Passed!                                           ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════════╝${NC}"

echo -e "\n${BLUE}Test Summary:${NC}"
echo "  ✓ Initial sync: 3 files transferred"
echo "  ✓ SHA1 verification: All files match"
echo "  ✓ Update sync: Modified files detected and transferred"
echo "  ✓ One-way mirror: Local changes on B correctly overwritten"
if [ "$DART_AVAILABLE" = true ]; then
    echo "  ✓ Security tests: Challenge-response authentication verified"
    echo "  ✓ Security tests: Replay attack prevention verified"
fi

echo -e "\n${BLUE}Instance URLs (still running):${NC}"
echo "  Instance A (source):      http://localhost:$PORT_A"
echo "  Instance B (destination): http://localhost:$PORT_B"

echo -e "\n${YELLOW}Note: Instances will be stopped on script exit${NC}"
