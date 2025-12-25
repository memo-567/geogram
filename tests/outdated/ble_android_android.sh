#!/bin/bash
# BLE Test: Android to Android (Fully Automated)
#
# This script automates BLE testing between two Android devices.
# It handles ADB setup, APK installation, app launching, and BLE tests.
#
# Prerequisites:
#   - Two Android devices connected via USB with USB debugging enabled
#   - Both devices on WiFi (can be same or different networks)
#   - ADB installed (in Android SDK platform-tools)
#
# Usage:
#   ./tests/ble_android_android.sh              # Full automated test
#   ./tests/ble_android_android.sh --skip-install  # Skip APK installation
#   ./tests/ble_android_android.sh --verbose       # Show all logs
#   ./tests/ble_android_android.sh --cleanup       # Just cleanup

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Add common Android SDK paths to PATH
ANDROID_SDK_PATHS=(
    "$HOME/Android/Sdk/platform-tools"
    "$HOME/android-sdk/platform-tools"
    "/opt/android-sdk/platform-tools"
    "$ANDROID_HOME/platform-tools"
    "$ANDROID_SDK_ROOT/platform-tools"
)

for sdk_path in "${ANDROID_SDK_PATHS[@]}"; do
    if [ -d "$sdk_path" ]; then
        export PATH="$sdk_path:$PATH"
        break
    fi
done

# Configuration
ANDROID_PORT=3456
STARTUP_TIMEOUT=30
ADVERTISE_DELAY=2
SCAN_TIMEOUT=15
HELLO_TIMEOUT=10
DATA_TIMEOUT=30
TEST_DATA_SIZE=2000

# APK paths (try release first, then debug)
APK_RELEASE="${PROJECT_DIR}/build/app/outputs/flutter-apk/app-release.apk"
APK_DEBUG="${PROJECT_DIR}/build/app/outputs/flutter-apk/app-debug.apk"
APK_PATH=""

# Android package info
ANDROID_PACKAGE="dev.geogram.geogram_desktop"
ANDROID_ACTIVITY="${ANDROID_PACKAGE}.MainActivity"

# Device state
DEVICE_A_SERIAL=""
DEVICE_B_SERIAL=""
DEVICE_A_IP=""
DEVICE_B_IP=""
DEVICE_A_MODEL=""
DEVICE_B_MODEL=""
CALLSIGN_A=""
CALLSIGN_B=""

# Options
SKIP_INSTALL=false
VERBOSE=false
CLEANUP_ONLY=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Log directory
LOG_DIR="${PROJECT_DIR}/test_results/$(date +%Y%m%d_%H%M%S)"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_subheader() {
    echo ""
    echo -e "${CYAN}--- $1 ---${NC}"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++)) || true
}

print_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++)) || true
}

print_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    ((TESTS_SKIPPED++)) || true
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_debug() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
    fi
}

# ============================================================================
# ADB HELPER FUNCTIONS
# ============================================================================

adb_a() {
    adb -s "$DEVICE_A_SERIAL" "$@"
}

adb_b() {
    adb -s "$DEVICE_B_SERIAL" "$@"
}

# ============================================================================
# CLEANUP
# ============================================================================

cleanup() {
    print_info "Cleaning up..."

    if [ -n "$DEVICE_A_SERIAL" ]; then
        print_info "Stopping app on Device A"
        adb_a shell am force-stop "$ANDROID_PACKAGE" 2>/dev/null || true
    fi

    if [ -n "$DEVICE_B_SERIAL" ]; then
        print_info "Stopping app on Device B"
        adb_b shell am force-stop "$ANDROID_PACKAGE" 2>/dev/null || true
    fi

    print_info "Cleanup complete"
}

trap cleanup EXIT

# ============================================================================
# DEVICE DETECTION
# ============================================================================

detect_devices() {
    print_subheader "Detecting Android Devices"

    # Start ADB server
    adb start-server 2>/dev/null || true

    # Get list of devices
    local devices=($(adb devices | grep -E "device$" | awk '{print $1}'))
    local count=${#devices[@]}

    if [ $count -eq 0 ]; then
        print_error "No Android devices connected"
        echo ""
        echo "Please:"
        echo "  1. Connect two Android devices via USB"
        echo "  2. Enable USB debugging in Developer Options"
        echo "  3. Accept USB debugging prompts on devices"
        exit 1
    fi

    if [ $count -eq 1 ]; then
        print_error "Only one Android device connected (need two)"
        echo ""
        echo "Connected device: ${devices[0]}"
        echo "Please connect a second Android device."
        exit 1
    fi

    if [ $count -gt 2 ]; then
        print_warning "More than 2 devices connected, using first two"
    fi

    DEVICE_A_SERIAL="${devices[0]}"
    DEVICE_B_SERIAL="${devices[1]}"

    # Get device info
    DEVICE_A_MODEL=$(adb_a shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    DEVICE_B_MODEL=$(adb_b shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    local android_a=$(adb_a shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
    local android_b=$(adb_b shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')

    print_info "Device A: $DEVICE_A_MODEL ($DEVICE_A_SERIAL) - Android $android_a"
    print_info "Device B: $DEVICE_B_MODEL ($DEVICE_B_SERIAL) - Android $android_b"
}

# ============================================================================
# IP ADDRESS DETECTION
# ============================================================================

get_device_ip() {
    local serial="$1"
    local ip=""

    # Method 1: WiFi IP via ip command
    ip=$(adb -s "$serial" shell ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | tr -d '\r' | head -1)

    if [ -z "$ip" ] || [ "$ip" = "" ]; then
        # Method 2: Any non-loopback IP
        ip=$(adb -s "$serial" shell ip addr show 2>/dev/null | grep "inet " | grep -v "127.0.0.1" | head -1 | awk '{print $2}' | cut -d/ -f1 | tr -d '\r')
    fi

    if [ -z "$ip" ] || [ "$ip" = "" ]; then
        # Method 3: Using ifconfig (older devices)
        ip=$(adb -s "$serial" shell ifconfig wlan0 2>/dev/null | grep "inet addr" | awk -F: '{print $2}' | awk '{print $1}' | tr -d '\r')
    fi

    if [ -z "$ip" ] || [ "$ip" = "" ]; then
        # Method 4: dumpsys wifi
        ip=$(adb -s "$serial" shell dumpsys wifi 2>/dev/null | grep "ip_address" | awk -F= '{print $2}' | tr -d '\r' | head -1)
    fi

    echo "$ip"
}

get_device_ips() {
    print_subheader "Getting Device IP Addresses"

    DEVICE_A_IP=$(get_device_ip "$DEVICE_A_SERIAL")
    DEVICE_B_IP=$(get_device_ip "$DEVICE_B_SERIAL")

    if [ -z "$DEVICE_A_IP" ] || [ "$DEVICE_A_IP" = "" ]; then
        print_error "Could not get IP for Device A ($DEVICE_A_MODEL)"
        echo "Please ensure WiFi is connected"
        exit 1
    fi

    if [ -z "$DEVICE_B_IP" ] || [ "$DEVICE_B_IP" = "" ]; then
        print_error "Could not get IP for Device B ($DEVICE_B_MODEL)"
        echo "Please ensure WiFi is connected"
        exit 1
    fi

    print_info "Device A IP: $DEVICE_A_IP"
    print_info "Device B IP: $DEVICE_B_IP"
}

# ============================================================================
# APK INSTALLATION
# ============================================================================

check_app_installed() {
    local serial="$1"
    adb -s "$serial" shell pm list packages 2>/dev/null | grep -q "$ANDROID_PACKAGE"
}

install_apk() {
    print_subheader "Installing APK on Both Devices"

    # Find APK
    if [ -f "$APK_RELEASE" ]; then
        APK_PATH="$APK_RELEASE"
    elif [ -f "$APK_DEBUG" ]; then
        APK_PATH="$APK_DEBUG"
        print_warning "Using debug APK"
    else
        print_warning "APK not found, checking if already installed..."
        if check_app_installed "$DEVICE_A_SERIAL" && check_app_installed "$DEVICE_B_SERIAL"; then
            print_info "App already installed on both devices"
            return 0
        else
            print_error "APK not found and app not installed"
            echo "Build APK with: flutter build apk"
            exit 1
        fi
    fi

    print_info "Installing APK: $(basename "$APK_PATH")"

    # Install on Device A
    print_info "Installing on Device A..."
    adb_a install -r "$APK_PATH" 2>&1 | grep -v "Streaming\|pkg:" || true

    # Install on Device B
    print_info "Installing on Device B..."
    adb_b install -r "$APK_PATH" 2>&1 | grep -v "Streaming\|pkg:" || true

    print_info "Installation complete"
}

# ============================================================================
# PERMISSIONS
# ============================================================================

grant_permissions() {
    print_subheader "Granting Permissions"

    local permissions=(
        "android.permission.BLUETOOTH"
        "android.permission.BLUETOOTH_ADMIN"
        "android.permission.BLUETOOTH_SCAN"
        "android.permission.BLUETOOTH_CONNECT"
        "android.permission.BLUETOOTH_ADVERTISE"
        "android.permission.ACCESS_FINE_LOCATION"
        "android.permission.ACCESS_COARSE_LOCATION"
    )

    for perm in "${permissions[@]}"; do
        adb_a shell pm grant "$ANDROID_PACKAGE" "$perm" 2>/dev/null || true
        adb_b shell pm grant "$ANDROID_PACKAGE" "$perm" 2>/dev/null || true
    done

    print_info "Permissions granted on both devices"
}

# ============================================================================
# APP LAUNCH
# ============================================================================

launch_app() {
    local serial="$1"
    local name="$2"

    # Force stop first
    adb -s "$serial" shell am force-stop "$ANDROID_PACKAGE" 2>/dev/null || true
    sleep 1

    # Launch app with test_mode intent extra
    # test_mode=true enables: http_api, debug_api, new_identity, skip_intro
    print_info "Starting Geogram on $name (test mode)..."
    adb -s "$serial" shell am start -n "$ANDROID_PACKAGE/$ANDROID_ACTIVITY" \
        --ez "test_mode" true \
        2>/dev/null || {
        # Fallback: just start the app normally
        adb -s "$serial" shell monkey -p "$ANDROID_PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null || true
    }
}

wait_for_api() {
    local ip="$1"
    local name="$2"
    local waited=0

    print_info "Waiting for $name API to be ready (max ${STARTUP_TIMEOUT}s)..."

    while [ $waited -lt $STARTUP_TIMEOUT ]; do
        if curl -s --connect-timeout 2 "http://${ip}:${ANDROID_PORT}/api/status" > /dev/null 2>&1; then
            echo ""
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
        echo -n "."
    done
    echo ""
    return 1
}

launch_apps() {
    print_subheader "Launching Apps"

    launch_app "$DEVICE_A_SERIAL" "Device A"
    launch_app "$DEVICE_B_SERIAL" "Device B"

    if ! wait_for_api "$DEVICE_A_IP" "Device A"; then
        print_error "Device A API not ready"
        print_info "Check if app needs manual interaction (permissions dialog, etc.)"
        return 1
    fi
    print_info "Device A API ready!"

    if ! wait_for_api "$DEVICE_B_IP" "Device B"; then
        print_error "Device B API not ready"
        print_info "Check if app needs manual interaction"
        return 1
    fi
    print_info "Device B API ready!"

    # Get callsigns
    CALLSIGN_A=$(get_callsign "$DEVICE_A_IP")
    CALLSIGN_B=$(get_callsign "$DEVICE_B_IP")

    print_info "Device A callsign: $CALLSIGN_A"
    print_info "Device B callsign: $CALLSIGN_B"
}

# ============================================================================
# API HELPER FUNCTIONS
# ============================================================================

trigger_action() {
    local ip="$1"
    local action="$2"
    shift 2
    local params="$@"

    local json="{\"action\": \"$action\""
    if [ -n "$params" ]; then
        json="$json, $params"
    fi
    json="$json}"

    print_debug "API call to $ip: $json"

    curl -s -X POST "http://${ip}:${ANDROID_PORT}/api/debug" \
        -H "Content-Type: application/json" \
        -d "$json" 2>/dev/null
}

get_status() {
    local ip="$1"
    curl -s "http://${ip}:${ANDROID_PORT}/api/status" 2>/dev/null
}

get_callsign() {
    local ip="$1"
    get_status "$ip" | jq -r '.callsign // "unknown"'
}

get_logs() {
    local ip="$1"
    local filter="${2:-}"
    local limit="${3:-100}"

    local url="http://${ip}:${ANDROID_PORT}/api/log?limit=$limit"
    if [ -n "$filter" ]; then
        url="$url&filter=$(echo -n "$filter" | jq -sRr @uri)"
    fi

    curl -s "$url" 2>/dev/null
}

get_devices_list() {
    local ip="$1"
    curl -s "http://${ip}:${ANDROID_PORT}/api/devices" 2>/dev/null
}

log_contains() {
    local ip="$1"
    local pattern="$2"
    local filter="${3:-}"

    get_logs "$ip" "$filter" 100 | jq -r '.logs[]' 2>/dev/null | grep -q "$pattern"
}

wait_for_log() {
    local ip="$1"
    local pattern="$2"
    local timeout="${3:-15}"
    local filter="${4:-}"
    local waited=0

    while [ $waited -lt $timeout ]; do
        if log_contains "$ip" "$pattern" "$filter"; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

show_toast() {
    local ip="$1"
    local message="$2"
    local duration="${3:-3}"

    curl -s -X POST "http://${ip}:${ANDROID_PORT}/api/debug" \
        -H "Content-Type: application/json" \
        -d "{\"action\": \"toast\", \"message\": \"$message\", \"duration\": $duration}" 2>/dev/null > /dev/null
}

# ============================================================================
# DEBUG OUTPUT
# ============================================================================

dump_logs() {
    local name="$1"
    local ip="$2"
    local filter="${3:-BLE}"

    echo ""
    echo -e "${CYAN}=== $name Logs (filter: $filter) ===${NC}"
    get_logs "$ip" "$filter" 50 | jq -r '.logs[]' 2>/dev/null | tail -30 || echo "(no logs)"
    echo ""
}

dump_debug_info() {
    echo ""
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}DEBUG INFORMATION${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"

    dump_logs "Device A ($DEVICE_A_MODEL)" "$DEVICE_A_IP" "BLE"
    dump_logs "Device B ($DEVICE_B_MODEL)" "$DEVICE_B_IP" "BLE"

    echo -e "${CYAN}=== Device A Discovered Devices ===${NC}"
    get_devices_list "$DEVICE_A_IP" | jq -r '.devices[] | "\(.callsign) - \(.connectionMethods | join(", "))"' 2>/dev/null || echo "(none)"

    echo ""
    echo -e "${CYAN}=== Device B Discovered Devices ===${NC}"
    get_devices_list "$DEVICE_B_IP" | jq -r '.devices[] | "\(.callsign) - \(.connectionMethods | join(", "))"' 2>/dev/null || echo "(none)"
}

save_logs() {
    mkdir -p "$LOG_DIR"

    echo "Test completed at $(date)" > "$LOG_DIR/summary.txt"
    echo "Device A: $DEVICE_A_MODEL ($DEVICE_A_SERIAL) - $DEVICE_A_IP - $CALLSIGN_A" >> "$LOG_DIR/summary.txt"
    echo "Device B: $DEVICE_B_MODEL ($DEVICE_B_SERIAL) - $DEVICE_B_IP - $CALLSIGN_B" >> "$LOG_DIR/summary.txt"
    echo "Passed: $TESTS_PASSED, Failed: $TESTS_FAILED, Skipped: $TESTS_SKIPPED" >> "$LOG_DIR/summary.txt"

    get_logs "$DEVICE_A_IP" "BLE" 200 > "$LOG_DIR/device_a_ble_logs.json" 2>/dev/null || true
    get_logs "$DEVICE_B_IP" "BLE" 200 > "$LOG_DIR/device_b_ble_logs.json" 2>/dev/null || true
    get_logs "$DEVICE_A_IP" "" 500 > "$LOG_DIR/device_a_all_logs.json" 2>/dev/null || true
    get_logs "$DEVICE_B_IP" "" 500 > "$LOG_DIR/device_b_all_logs.json" 2>/dev/null || true

    print_info "Logs saved to: $LOG_DIR"
}

# ============================================================================
# TEST FUNCTIONS
# ============================================================================

test_api_connectivity() {
    print_subheader "Test 1: API Connectivity"

    # Test Device A API
    local status_a=$(get_status "$DEVICE_A_IP")
    if [ -n "$status_a" ]; then
        local cs=$(echo "$status_a" | jq -r '.callsign // "unknown"')
        print_success "Device A API responding (callsign: $cs)"
    else
        print_error "Device A API not responding"
        return 1
    fi

    # Test Device B API
    local status_b=$(get_status "$DEVICE_B_IP")
    if [ -n "$status_b" ]; then
        local cs=$(echo "$status_b" | jq -r '.callsign // "unknown"')
        print_success "Device B API responding (callsign: $cs)"
    else
        print_error "Device B API not responding"
        return 1
    fi
}

test_ble_advertise_b() {
    print_subheader "Test 2: BLE Advertising (Device B)"

    print_info "Triggering BLE advertise on Device B..."
    local result=$(trigger_action "$DEVICE_B_IP" "ble_advertise")
    print_debug "Result: $result"

    sleep $ADVERTISE_DELAY

    if wait_for_log "$DEVICE_B_IP" "advertising" 5 "BLE"; then
        print_success "Device B started advertising"
    else
        print_warning "Could not confirm advertising started (may still be working)"
    fi
}

test_ble_scan_a() {
    print_subheader "Test 3: BLE Scanning (Device A)"

    print_info "Triggering BLE scan on Device A..."
    local result=$(trigger_action "$DEVICE_A_IP" "ble_scan")
    print_debug "Result: $result"

    print_info "Waiting for scan to complete (${SCAN_TIMEOUT}s)..."
    sleep $SCAN_TIMEOUT
}

test_discovery_a_finds_b() {
    print_subheader "Test 4: Discovery (A finds B)"

    # Check devices list
    local devices=$(get_devices_list "$DEVICE_A_IP")
    print_debug "Devices: $devices"

    if echo "$devices" | jq -r '.devices[].callsign' 2>/dev/null | grep -qi "$CALLSIGN_B"; then
        print_success "Device A discovered Device B ($CALLSIGN_B)"
        return 0
    fi

    # Check logs for discovery
    if log_contains "$DEVICE_A_IP" "$CALLSIGN_B" "BLE"; then
        print_success "Device A found Device B in BLE logs"
        return 0
    fi

    if log_contains "$DEVICE_A_IP" "Found device" "BLE"; then
        print_warning "Device A found some BLE device, but not confirmed as Device B"
        dump_debug_info
        return 0
    fi

    print_error "Device A did not discover Device B"
    dump_debug_info
    return 1
}

test_hello_a_to_b() {
    print_subheader "Test 5: HELLO Handshake (A → B)"

    print_info "Triggering HELLO from Device A..."
    local result=$(trigger_action "$DEVICE_A_IP" "ble_hello")
    print_debug "Result: $result"

    print_info "Waiting for handshake (${HELLO_TIMEOUT}s)..."

    if wait_for_log "$DEVICE_A_IP" "handshake.*success\|HELLO.*success\|HELLO_ACK" $HELLO_TIMEOUT "BLE"; then
        print_success "HELLO handshake successful (A → B)"
        return 0
    fi

    # Check for HELLO on B side
    if log_contains "$DEVICE_B_IP" "HELLO" "BLE"; then
        print_warning "Device B received HELLO, but handshake may not have completed"
        dump_debug_info
        return 1
    fi

    print_error "HELLO handshake failed"
    dump_debug_info
    return 1
}

test_data_transfer() {
    print_subheader "Test 6: Data Transfer (${TEST_DATA_SIZE} bytes)"

    print_info "Sending ${TEST_DATA_SIZE} bytes from Device A to Device B..."
    local result=$(trigger_action "$DEVICE_A_IP" "ble_send" "\"size\": $TEST_DATA_SIZE")
    print_debug "Result: $result"

    print_info "Waiting for transfer (${DATA_TIMEOUT}s)..."

    if wait_for_log "$DEVICE_A_IP" "transfer.*complete\|sent.*success\|Data.*sent" $DATA_TIMEOUT "BLE"; then
        print_success "Data transfer completed successfully"
        return 0
    fi

    # Check for partial progress
    if log_contains "$DEVICE_A_IP" "parcel\|sending" "BLE"; then
        print_warning "Data transfer started but may not have completed"
        dump_debug_info
        return 1
    fi

    print_error "Data transfer failed"
    dump_debug_info
    return 1
}

test_bidirectional() {
    print_subheader "Test 7: Bidirectional (B → A)"

    print_info "Now testing reverse direction (Device B → Device A)..."

    # Device A advertises
    print_info "Triggering BLE advertise on Device A..."
    trigger_action "$DEVICE_A_IP" "ble_advertise" > /dev/null
    sleep $ADVERTISE_DELAY

    # Device B scans
    print_info "Triggering BLE scan on Device B..."
    trigger_action "$DEVICE_B_IP" "ble_scan" > /dev/null
    sleep $SCAN_TIMEOUT

    # Check if B found A
    local devices=$(get_devices_list "$DEVICE_B_IP")
    if echo "$devices" | jq -r '.devices[].callsign' 2>/dev/null | grep -qi "$CALLSIGN_A"; then
        print_success "Device B discovered Device A (bidirectional works)"
        return 0
    fi

    if log_contains "$DEVICE_B_IP" "$CALLSIGN_A" "BLE"; then
        print_success "Device B found Device A in BLE logs"
        return 0
    fi

    print_error "Bidirectional discovery failed (B did not find A)"
    dump_debug_info
    return 1
}

# ============================================================================
# MAIN
# ============================================================================

print_summary() {
    print_header "Test Summary"

    echo -e "Device A: $DEVICE_A_MODEL ($CALLSIGN_A)"
    echo -e "Device B: $DEVICE_B_MODEL ($CALLSIGN_B)"
    echo ""
    echo -e "  ${GREEN}Passed:${NC}  $TESTS_PASSED"
    echo -e "  ${RED}Failed:${NC}  $TESTS_FAILED"
    echo -e "  ${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
    else
        echo -e "${RED}Some tests failed. Check logs above for details.${NC}"
    fi
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-install)
                SKIP_INSTALL=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --cleanup)
                CLEANUP_ONLY=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --skip-install  Skip APK installation"
                echo "  --verbose       Show debug output"
                echo "  --cleanup       Just cleanup and exit"
                echo "  --help          Show this help"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    print_header "BLE Test: Android to Android"

    # Prerequisites check
    if ! command -v adb &> /dev/null; then
        print_error "ADB not found"
        echo "Please install Android SDK platform-tools"
        exit 1
    fi

    if ! command -v curl &> /dev/null; then
        print_error "curl not found"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        print_error "jq not found. Please install: sudo apt install jq"
        exit 1
    fi

    # Detect devices
    detect_devices

    if [ "$CLEANUP_ONLY" = true ]; then
        cleanup
        exit 0
    fi

    # Get IPs
    get_device_ips

    # Install APK
    if [ "$SKIP_INSTALL" = false ]; then
        install_apk
    fi

    # Grant permissions
    grant_permissions

    # Launch apps
    launch_apps

    print_header "Running Tests"

    # Run tests
    test_api_connectivity || true
    test_ble_advertise_b || true
    test_ble_scan_a || true
    test_discovery_a_finds_b || true
    test_hello_a_to_b || true
    test_data_transfer || true
    test_bidirectional || true

    # Save logs
    save_logs

    # Summary
    print_summary

    # Exit code
    if [ $TESTS_FAILED -gt 0 ]; then
        exit 1
    fi
}

main "$@"
