#!/bin/bash
# Geogram Blog Feedback Test Runner
#
# This script runs the blog feedback test suite which verifies:
#   - Like, Point, Dislike, Subscribe actions
#   - Emoji reactions
#   - Feedback API endpoints
#   - File-based feedback persistence
#
# The test creates two temporary instances and tests feedback
# functionality between them.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo ""
echo "================================================"
echo "  Geogram Blog Feedback Test"
echo "================================================"
echo ""

# Check if build exists
if [ ! -f "build/linux/x64/release/bundle/geogram_desktop" ]; then
  echo -e "${RED}ERROR: Desktop build not found${NC}"
  echo ""
  echo "Please build first:"
  echo "  flutter build linux --release"
  echo ""
  exit 1
fi

echo -e "${GREEN}✓${NC} Desktop build found"
echo ""

# Run the test
echo "Running feedback test suite..."
echo ""

dart run tests/app_blog_feedback_test.dart

exit_code=$?

echo ""
if [ $exit_code -eq 0 ]; then
  echo -e "${GREEN}All tests passed!${NC}"
else
  echo -e "${RED}Some tests failed.${NC}"
  echo ""
  echo "Tip: Check the data directories for debugging:"
  echo "  /tmp/geogram-feedback-test-a"
  echo "  /tmp/geogram-feedback-test-b"
fi

exit $exit_code
