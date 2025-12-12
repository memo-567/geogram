#!/bin/bash
# Backup API Test Script
# Tests backup functionality between two Geogram instances
#
# Usage: ./tests/run_backup_test.sh
#
# Prerequisites:
# - Build the app: flutter build linux --release
# - jq installed for JSON parsing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GEOGRAM="$PROJECT_DIR/build/linux/x64/release/bundle/geogram_desktop"

# Configuration
PORT_PROVIDER=5577
PORT_CLIENT=5588
DATA_PROVIDER=/tmp/geogram-backup-provider
DATA_CLIENT=/tmp/geogram-backup-client
STARTUP_WAIT=12
API_WAIT=3

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

cleanup() {
    log_info "Cleaning up..."
    # Kill any existing instances on our ports
    pkill -f "geogram_desktop.*--port=$PORT_PROVIDER" 2>/dev/null || true
    pkill -f "geogram_desktop.*--port=$PORT_CLIENT" 2>/dev/null || true
    sleep 2
    rm -rf "$DATA_PROVIDER" "$DATA_CLIENT"
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
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if curl -s "http://localhost:$port/api/status" > /dev/null 2>&1; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done

    log_error "API not available on port $port after $max_attempts seconds"
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

# Main test flow
main() {
    log_info "=== Geogram Backup Test ==="

    check_dependencies
    cleanup

    # Create data directories
    mkdir -p "$DATA_PROVIDER" "$DATA_CLIENT"

    log_info "Starting provider instance on port $PORT_PROVIDER..."
    "$GEOGRAM" --port=$PORT_PROVIDER --data-dir="$DATA_PROVIDER" \
        --new-identity --nickname="BackupProvider" --skip-intro \
        --http-api --debug-api --scan-localhost=5500-5600 &>/dev/null &
    PID_PROVIDER=$!

    log_info "Starting client instance on port $PORT_CLIENT..."
    "$GEOGRAM" --port=$PORT_CLIENT --data-dir="$DATA_CLIENT" \
        --new-identity --nickname="BackupClient" --skip-intro \
        --http-api --debug-api --scan-localhost=5500-5600 &>/dev/null &
    PID_CLIENT=$!

    log_info "Waiting for instances to start..."
    sleep $STARTUP_WAIT

    # Verify both APIs are up
    if ! wait_for_api $PORT_PROVIDER; then
        log_error "Provider failed to start"
        cleanup
        exit 1
    fi

    if ! wait_for_api $PORT_CLIENT; then
        log_error "Client failed to start"
        cleanup
        exit 1
    fi

    # Get callsigns and npubs
    PROVIDER_STATUS=$(curl -s "http://localhost:$PORT_PROVIDER/api/status")
    CLIENT_STATUS=$(curl -s "http://localhost:$PORT_CLIENT/api/status")

    PROVIDER_CALLSIGN=$(echo "$PROVIDER_STATUS" | jq -r '.callsign')
    CLIENT_CALLSIGN=$(echo "$CLIENT_STATUS" | jq -r '.callsign')
    PROVIDER_NPUB=$(echo "$PROVIDER_STATUS" | jq -r '.npub')
    CLIENT_NPUB=$(echo "$CLIENT_STATUS" | jq -r '.npub')

    log_info "Provider callsign: $PROVIDER_CALLSIGN"
    log_info "Provider npub: ${PROVIDER_NPUB:0:30}..."
    log_info "Client callsign: $CLIENT_CALLSIGN"
    log_info "Client npub: ${CLIENT_NPUB:0:30}..."

    # Step 1: Enable backup provider mode
    log_info "Step 1: Enabling backup provider mode..."
    RESULT=$(debug_action $PORT_PROVIDER "backup_provider_enable" '"max_storage_bytes": 10737418240')
    echo "  Result: $RESULT"
    sleep $API_WAIT

    # Step 2: Create test data on client
    log_info "Step 2: Creating test data on client..."
    RESULT=$(debug_action $PORT_CLIENT "backup_create_test_data" '"file_count": 5, "max_file_size": 8192')
    echo "  Result: $RESULT"
    sleep $API_WAIT

    # Verify test data was created
    TEST_DATA_DIR="$DATA_CLIENT/test-backup-data"
    if [ -d "$TEST_DATA_DIR" ]; then
        FILE_COUNT=$(find "$TEST_DATA_DIR" -type f | wc -l)
        log_info "  Created $FILE_COUNT test files in $TEST_DATA_DIR"
    else
        log_warn "  Test data directory not found at $TEST_DATA_DIR"
    fi

    # Step 3: Wait for device discovery
    log_info "Step 3: Waiting for device discovery..."
    sleep 5

    # Check if devices can see each other
    PROVIDER_DEVICES=$(curl -s "http://localhost:$PORT_PROVIDER/api/devices" | jq '.devices | length')
    CLIENT_DEVICES=$(curl -s "http://localhost:$PORT_CLIENT/api/devices" | jq '.devices | length')
    log_info "  Provider sees $PROVIDER_DEVICES devices, Client sees $CLIENT_DEVICES devices"

    # Step 4: Setup backup relationship directly (LAN testing - no WebSocket relay)
    # Provider adds client as a backup relationship (pass npub since devices don't exchange npubs via localhost scan)
    log_info "Step 4a: Provider adds client relationship..."
    RESULT=$(debug_action $PORT_PROVIDER "backup_accept_invite" "\"client_callsign\": \"$CLIENT_CALLSIGN\", \"client_npub\": \"$CLIENT_NPUB\"")
    echo "  Result: $RESULT"
    sleep $API_WAIT

    # Client adds provider relationship (pass npub since devices don't exchange npubs via localhost scan)
    log_info "Step 4b: Client adds provider relationship..."
    RESULT=$(debug_action $PORT_CLIENT "backup_add_provider" "\"provider_callsign\": \"$PROVIDER_CALLSIGN\", \"provider_npub\": \"$PROVIDER_NPUB\"")
    echo "  Result: $RESULT"
    sleep $API_WAIT

    # Step 5: Start backup
    log_info "Step 5: Starting backup..."
    RESULT=$(debug_action $PORT_CLIENT "backup_start" "\"provider_callsign\": \"$PROVIDER_CALLSIGN\"")
    echo "  Result: $RESULT"

    # Step 6: Monitor backup progress
    log_info "Step 6: Monitoring backup progress..."
    for i in {1..30}; do
        STATUS_JSON=$(debug_action $PORT_CLIENT "backup_get_status")
        STATUS=$(echo "$STATUS_JSON" | jq -r '.backup_status.status // .status // "unknown"')
        PROGRESS=$(echo "$STATUS_JSON" | jq -r '.backup_status.progressPercent // .progress_percent // 0')

        if [ "$STATUS" = "complete" ] || [ "$STATUS" = "completed" ]; then
            log_info "  Backup completed successfully!"
            break
        elif [ "$STATUS" = "failed" ]; then
            log_error "  Backup failed!"
            ERROR=$(echo "$STATUS_JSON" | jq -r '.backup_status.error // .error // "unknown"')
            log_error "  Error: $ERROR"
            break
        else
            echo "  [$i/30] Status: $STATUS, Progress: ${PROGRESS}%"
        fi
        sleep 2
    done

    # Step 7: Verify backup on provider side
    log_info "Step 7: Verifying backup on provider..."
    BACKUP_DIR="$DATA_PROVIDER/backups"
    if [ -d "$BACKUP_DIR" ]; then
        log_info "  Backup directory exists"
        # Check for encrypted files
        ENCRYPTED_FILES=$(find "$BACKUP_DIR" -name "*.enc" 2>/dev/null | wc -l)
        log_info "  Found $ENCRYPTED_FILES encrypted files"

        # Verify files are actually encrypted (should not be readable as text)
        if [ $ENCRYPTED_FILES -gt 0 ]; then
            SAMPLE_FILE=$(find "$BACKUP_DIR" -name "*.enc" 2>/dev/null | head -1)
            if [ -f "$SAMPLE_FILE" ]; then
                if file "$SAMPLE_FILE" | grep -q "data\|binary"; then
                    log_info "  Files appear to be encrypted (binary data)"
                else
                    log_warn "  Files may not be properly encrypted"
                fi
            fi
        fi
    else
        log_warn "  Backup directory not found"
    fi

    # Step 8: List snapshots (on provider, for the client)
    log_info "Step 8: Listing snapshots from provider..."
    RESULT=$(debug_action $PORT_PROVIDER "backup_list_snapshots" "\"client_callsign\": \"$CLIENT_CALLSIGN\"")
    echo "  Result: $RESULT"

    # Step 9: Test restore
    log_info "Step 9: Testing restore..."
    # Get the snapshot ID from the backup
    SNAPSHOT_ID=$(echo "$RESULT" | jq -r '.snapshots[0].snapshot_id // empty')
    if [ -n "$SNAPSHOT_ID" ]; then
        log_info "  Restoring from snapshot: $SNAPSHOT_ID"

        # Delete some test files to verify restore
        if [ -d "$TEST_DATA_DIR" ]; then
            ORIGINAL_COUNT=$(find "$TEST_DATA_DIR" -type f | wc -l)
            rm -f "$TEST_DATA_DIR"/* 2>/dev/null || true
            log_info "  Deleted test files for restore verification"
        fi

        RESULT=$(debug_action $PORT_CLIENT "backup_restore" "\"provider_callsign\": \"$PROVIDER_CALLSIGN\", \"snapshot_id\": \"$SNAPSHOT_ID\"")
        echo "  Restore initiated: $RESULT"

        # Monitor restore progress
        for i in {1..30}; do
            STATUS_JSON=$(debug_action $PORT_CLIENT "backup_get_status")
            RESTORE_STATUS=$(echo "$STATUS_JSON" | jq -r '.restore_status.status // .status // "unknown"')

            if [ "$RESTORE_STATUS" = "complete" ] || [ "$RESTORE_STATUS" = "completed" ] || [ "$RESTORE_STATUS" = "idle" ]; then
                log_info "  Restore completed!"
                break
            elif [ "$RESTORE_STATUS" = "failed" ]; then
                log_error "  Restore failed!"
                break
            else
                echo "  [$i/30] Restore status: $RESTORE_STATUS"
            fi
            sleep 2
        done

        # Verify restored files
        if [ -d "$TEST_DATA_DIR" ]; then
            RESTORED_COUNT=$(find "$TEST_DATA_DIR" -type f | wc -l)
            log_info "  Restored $RESTORED_COUNT files"
        fi
    else
        log_warn "  No snapshots found to restore"
    fi

    # Summary
    echo ""
    log_info "=== Test Summary ==="
    log_info "Provider: $PROVIDER_CALLSIGN (port $PORT_PROVIDER)"
    log_info "Client: $CLIENT_CALLSIGN (port $PORT_CLIENT)"

    # Final cleanup
    log_info "Cleaning up..."
    kill $PID_PROVIDER $PID_CLIENT 2>/dev/null || true

    log_info "Test completed!"
}

# Run main with cleanup on exit
trap cleanup EXIT
main "$@"
