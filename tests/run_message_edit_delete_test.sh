#!/bin/bash
# Test runner for message edit/delete API tests
#
# This script starts a Geogram Desktop instance and runs the edit/delete tests
#
# Usage:
#   ./tests/run_message_edit_delete_test.sh
#
# Prerequisites:
#   - Built Geogram Desktop binary in build/linux/x64/release/bundle/

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BINARY="$PROJECT_DIR/build/linux/x64/release/bundle/geogram_desktop"
DART="${DART:-/home/brito/flutter/bin/dart}"
DATA_DIR="/tmp/geogram-edit-delete-test-$$"
PORT=5689

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null || true
        wait "$PID" 2>/dev/null || true
    fi
    rm -rf "$DATA_DIR"
}

trap cleanup EXIT

# Check binary exists
if [ ! -f "$BINARY" ]; then
    echo "Error: Binary not found at $BINARY"
    echo "Please build the project first with: flutter build linux --release"
    exit 1
fi

# Create data directory
mkdir -p "$DATA_DIR"

echo "=============================================="
echo "Message Edit/Delete API Test"
echo "=============================================="
echo ""
echo "Starting Geogram Desktop instance..."
echo "  Port: $PORT"
echo "  Data: $DATA_DIR"
echo ""

# Start Geogram Desktop in background
"$BINARY" \
    --port=$PORT \
    --data-dir="$DATA_DIR" \
    --new-identity \
    --skip-intro \
    --http-api \
    --debug-api \
    &>/dev/null &
PID=$!

echo "Started with PID: $PID"

# Wait for server to be ready
echo "Waiting for server to start..."
MAX_WAIT=30
WAITED=0
while ! curl -s "http://localhost:$PORT/api/" > /dev/null 2>&1; do
    sleep 1
    WAITED=$((WAITED + 1))
    if [ $WAITED -ge $MAX_WAIT ]; then
        echo "Error: Server did not start within $MAX_WAIT seconds"
        exit 1
    fi
    echo "  Waiting... ($WAITED/$MAX_WAIT)"
done

echo "Server is ready!"
echo ""

# Get package dependencies
echo "Getting Dart dependencies..."
cd "$PROJECT_DIR"
"$DART" pub get --no-precompile >/dev/null 2>&1 || true

# Run the test
echo ""
echo "Running message edit/delete tests..."
echo ""

"$DART" run "$SCRIPT_DIR/message_edit_delete_test.dart" \
    --port=$PORT \
    --data-dir="$DATA_DIR"

EXIT_CODE=$?

echo ""
echo "=============================================="
if [ $EXIT_CODE -eq 0 ]; then
    echo "All tests passed!"
else
    echo "Some tests failed (exit code: $EXIT_CODE)"
fi
echo "=============================================="

exit $EXIT_CODE
