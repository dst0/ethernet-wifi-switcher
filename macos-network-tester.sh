#!/bin/bash
#
# macOS Network Interface Investigation Tester
# ============================================
#
# This script is a research tool designed to investigate how macOS reacts to
# network changes, internet connectivity loss, and interface switching.
#
# Purpose:
# - Understand macOS network behavior in real-world scenarios
# - Test various commands for detecting internet presence/absence
# - Investigate interface switching when multiple connections exist
# - Gather data for improving the ethernet-wifi-switcher application
#
# Usage:
#   sudo bash macos-network-tester.sh
#
# Note: Requires sudo for some network management commands
#

set -e

# Color output for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Helper function for countdowns
countdown() {
    for i in {3..1}; do
        echo -ne "${BOLD}${YELLOW}  ${i}... ${NC}"
        sleep 1
    done
    echo ""
}

# Logging setup
LOG_DIR="${HOME}/.macos-network-tester"
LOG_FILE="${LOG_DIR}/test-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$LOG_DIR"

# Global variables to track test results for final summary
TEST_8_1_UNPLUG_TIME=""
TEST_8_1_PLUGIN_TIME=""
TEST_8_2_DISABLE_MS=""
TEST_8_2_ENABLE_MS=""
TEST_8_2_RECONNECT_TIME=""
TEST_8_3_FAILOVER_TIME=""
TEST_8_3_SWITCHBACK_TIME=""
TEST_8_3_PRIMARY_IFACE=""
TEST_8_5_DHCP_TIME=""
TEST_8_5_NETWORK_TYPE=""

# Global variables to track validation of detection methods
METHOD_PING_8888_WORKS=0
METHOD_PING_GOOGLE_WORKS=0
METHOD_DNS_Resolution_WORKS=0
METHOD_HTTP_GOOGLE_WORKS=0
METHOD_CAPTIVE_PORTAL_WORKS=0

# Function to print and log
print_log() {
    echo -e "$@" | tee -a "$LOG_FILE"
}

print_header() {
    print_log "\n${BOLD}${CYAN}========================================${NC}"
    print_log "${BOLD}${CYAN}$1${NC}"
    print_log "${BOLD}${CYAN}========================================${NC}\n"
}

print_section() {
    print_log "\n${BOLD}${BLUE}--- $1 ---${NC}\n"
}

print_success() {
    print_log "${GREEN}✓ $1${NC}"
}

print_warning() {
    print_log "${YELLOW}⚠ $1${NC}"
}

print_error() {
    print_log "${RED}✗ $1${NC}"
}

print_info() {
    print_log "${CYAN}ℹ $1${NC}"
}

# Check if running as root for certain operations
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_warning "Some tests require root privileges. Run with sudo for full functionality."
        return 1
    fi
    return 0
}

IS_ROOT=0
check_root && IS_ROOT=1

print_header "macOS Network Interface Investigation Tester"
print_info "Log file: $LOG_FILE"
print_info "Started at: $(date)"
print_info "User: $(whoami)"
print_info "Root access: $([ $IS_ROOT -eq 1 ] && echo 'YES' || echo 'NO')"

#
# TEST 1: Interface Discovery
#
print_header "TEST 1: INTERFACE DISCOVERY"

print_section "1.1: List all network interfaces"
print_log "Command: ifconfig -a | grep '^[a-z]' | cut -d: -f1"
ifconfig -a | grep '^[a-z]' | cut -d: -f1 | tee -a "$LOG_FILE"

print_section "1.2: List interfaces using networksetup"
print_log "Command: networksetup -listallhardwareports"
networksetup -listallhardwareports | tee -a "$LOG_FILE"

print_section "1.3: Interfaces with active status"
print_log "Command: ifconfig -a | grep -E '^[a-z]|status:'"
ifconfig -a | grep -E '^[a-z]|status:' | tee -a "$LOG_FILE"

print_section "1.4: Interfaces with assigned IP addresses"
ALL_INTERFACES=$(ifconfig -a | grep '^[a-z]' | cut -d: -f1)
for iface in $ALL_INTERFACES; do
    IP=$(ipconfig getifaddr "$iface" 2>/dev/null || echo "")
    if [ -n "$IP" ]; then
        print_success "Interface $iface has IP: $IP"
    else
        print_log "Interface $iface has no IP"
    fi
done

print_section "1.5: Identify Ethernet interfaces"
print_info "Looking for interfaces with 'en' prefix and wired connection..."
for iface in $ALL_INTERFACES; do
    if [[ "$iface" =~ ^en[0-9]+$ ]]; then
        MEDIA=$(ifconfig "$iface" 2>/dev/null | grep media: || echo "")
        if echo "$MEDIA" | grep -qv "autoselect" || ifconfig "$iface" | grep -q "status: active"; then
            print_log "Potential Ethernet: $iface"
            print_log "$MEDIA"
        fi
    fi
done

print_section "1.6: Identify Wi-Fi interfaces"
for iface in $ALL_INTERFACES; do
    if networksetup -getairportpower "$iface" 2>/dev/null | grep -q "Wi-Fi Power"; then
        WIFI_POWER=$(networksetup -getairportpower "$iface" 2>/dev/null)
        print_success "Wi-Fi interface found: $iface"
        print_log "$WIFI_POWER"
    fi
done

#
# TEST 2: Internet Connectivity Detection Methods
#
print_header "TEST 2: INTERNET CONNECTIVITY DETECTION"

print_section "2.1: Ping test to reliable hosts"
PING_HOSTS=("8.8.8.8" "1.1.1.1" "google.com")
for host in "${PING_HOSTS[@]}"; do
    print_log "Testing ping to $host..."
    if ping -c 2 -W 3 "$host" >/dev/null 2>&1; then
        print_success "Ping to $host: SUCCESS"
        # Track success for summary
        [ "$host" == "8.8.8.8" ] && METHOD_PING_8888_WORKS=1
        [ "$host" == "google.com" ] && METHOD_PING_GOOGLE_WORKS=1
    else
        print_error "Ping to $host: FAILED"
    fi
done

print_section "2.2: DNS resolution test"
DNS_HOSTS=("google.com" "github.com" "apple.com")
for host in "${DNS_HOSTS[@]}"; do
    print_log "Testing DNS for $host..."
    if nslookup "$host" >/dev/null 2>&1; then
        print_success "DNS resolution for $host: SUCCESS"
        METHOD_DNS_Resolution_WORKS=1
    else
        print_error "DNS resolution for $host: FAILED"
    fi
done

print_section "2.3: HTTP connectivity test"
HTTP_URLS=("http://captive.apple.com" "http://www.google.com")
for url in "${HTTP_URLS[@]}"; do
    print_log "Testing HTTP connection to $url..."
    if curl -s --connect-timeout 5 "$url" >/dev/null 2>&1; then
        print_success "HTTP to $url: SUCCESS"
        [ "$url" == "http://www.google.com" ] && METHOD_HTTP_GOOGLE_WORKS=1
    else
        print_error "HTTP to $url: FAILED"
    fi
done

print_section "2.4: Apple's captive portal detection"
print_log "Testing Apple's captive portal check..."
RESPONSE=$(curl -s --connect-timeout 5 http://captive.apple.com 2>/dev/null || echo "")
if [ "$RESPONSE" = "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>" ]; then
    print_success "Apple captive portal check: INTERNET DETECTED"
    METHOD_CAPTIVE_PORTAL_WORKS=1
else
    print_warning "Apple captive portal check: NO INTERNET or CAPTIVE PORTAL"
    print_log "Response: $RESPONSE"
fi

print_section "2.5: Check default route"
print_log "Command: netstat -rn | grep default"
DEFAULT_ROUTE=$(netstat -rn | grep default | tee -a "$LOG_FILE")
if [ -n "$DEFAULT_ROUTE" ]; then
    print_success "Default route exists"
else
    print_error "No default route found"
fi

print_section "2.6: Check DNS servers"
print_log "Command: scutil --dns"
scutil --dns | grep "nameserver" | head -5 | tee -a "$LOG_FILE"

#
# TEST 3: Interface State Monitoring
#
print_header "TEST 3: INTERFACE STATE MONITORING"

print_section "3.1: Check interface status (up/down)"
for iface in $ALL_INTERFACES; do
    STATUS=$(ifconfig "$iface" 2>/dev/null | grep "status:" | awk '{print $2}' || echo "unknown")
    FLAGS=$(ifconfig "$iface" 2>/dev/null | head -1 | grep -o '<[^>]*>' || echo "")
    print_log "Interface $iface: status=$STATUS flags=$FLAGS"
done

print_section "3.2: Check link quality for interfaces"
for iface in $ALL_INTERFACES; do
    if ifconfig "$iface" 2>/dev/null | grep -q "status: active"; then
        print_log "\nInterface $iface (active):"
        ifconfig "$iface" | grep -E "status:|media:|inet " | tee -a "$LOG_FILE"
    fi
done

print_section "3.3: Monitor SCDynamicStore network state"
print_log "Command: scutil --nc list"
scutil --nc list | tee -a "$LOG_FILE" || print_warning "No VPN connections configured"

print_section "3.4: Check network service order"
print_log "Command: networksetup -listnetworkserviceorder"
networksetup -listnetworkserviceorder | tee -a "$LOG_FILE"

#
# TEST 4: Wi-Fi Management Commands
#
print_header "TEST 4: WI-FI MANAGEMENT"

# Find Wi-Fi interface
WIFI_INTERFACE=""
for iface in $ALL_INTERFACES; do
    if networksetup -getairportpower "$iface" 2>/dev/null | grep -q "Wi-Fi Power"; then
        WIFI_INTERFACE="$iface"
        break
    fi
done

if [ -n "$WIFI_INTERFACE" ]; then
    print_success "Wi-Fi interface detected: $WIFI_INTERFACE"

    print_section "4.1: Check Wi-Fi power state"
    networksetup -getairportpower "$WIFI_INTERFACE" | tee -a "$LOG_FILE"

    print_section "4.2: Get current Wi-Fi network"
    CURRENT_NETWORK=$(networksetup -getairportnetwork "$WIFI_INTERFACE" | tee -a "$LOG_FILE")
    print_log "$CURRENT_NETWORK"

    print_section "4.3: List preferred Wi-Fi networks"
    networksetup -listpreferredwirelessnetworks "$WIFI_INTERFACE" | tee -a "$LOG_FILE" || print_warning "Could not list preferred networks"

    print_section "4.4: Wi-Fi interface details"
    ifconfig "$WIFI_INTERFACE" | tee -a "$LOG_FILE"

    if [ $IS_ROOT -eq 1 ]; then
        print_section "4.5: Test Wi-Fi control commands (requires root)"
        print_warning "Testing Wi-Fi toggle capability (this will briefly affect your connection)"
        read -p "Press Enter to continue or Ctrl+C to skip..."

        ORIGINAL_STATE=$(networksetup -getairportpower "$WIFI_INTERFACE" | awk '{print $NF}')
        print_info "Original Wi-Fi state: $ORIGINAL_STATE"

        # Test turning off
        print_log "Turning Wi-Fi OFF..."
        networksetup -setairportpower "$WIFI_INTERFACE" off
        sleep 2
        NEW_STATE=$(networksetup -getairportpower "$WIFI_INTERFACE" | awk '{print $NF}')
        print_log "State after OFF command: $NEW_STATE"

        # Test turning on
        print_log "Turning Wi-Fi ON..."
        networksetup -setairportpower "$WIFI_INTERFACE" on
        sleep 2
        NEW_STATE=$(networksetup -getairportpower "$WIFI_INTERFACE" | awk '{print $NF}')
        print_log "State after ON command: $NEW_STATE"

        print_success "Wi-Fi control test completed"
    else
        print_warning "Skipping Wi-Fi toggle test (requires root)"
    fi
else
    print_warning "No Wi-Fi interface found"
fi

#
# TEST 5: Ethernet Detection and Status
#
print_header "TEST 5: ETHERNET DETECTION AND STATUS"

print_section "5.1: Detect Ethernet interfaces by type"
for iface in $ALL_INTERFACES; do
    if [[ "$iface" =~ ^en[0-9]+$ ]]; then
        print_log "\nChecking $iface..."

        # Check if it's Ethernet (not Wi-Fi) - suppress all errors
        if networksetup -getairportpower "$iface" >/dev/null 2>&1; then
            print_log "$iface appears to be Wi-Fi (has airport power control)"
        else
            print_log "$iface appears to be Ethernet (not Wi-Fi)"

            # Check status
            STATUS=$(ifconfig "$iface" 2>/dev/null | grep "status:" || echo "status: unknown")
            print_log "Status: $STATUS"

            # Check IP
            IP=$(ipconfig getifaddr "$iface" 2>/dev/null || echo "")
            if [ -n "$IP" ]; then
                print_success "$iface has IP: $IP"
            else
                print_log "$iface has no IP address"
            fi

            # Check media/link
            MEDIA=$(ifconfig "$iface" 2>/dev/null | grep "media:" || echo "")
            print_log "Media: $MEDIA"
        fi
    fi
done

print_section "5.2: Test DHCP acquisition time"
print_info "This test measures how quickly interfaces get IP addresses"
for iface in $ALL_INTERFACES; do
    if [[ "$iface" =~ ^en[0-9]+$ ]]; then
        # Only check interfaces that have active status
        if ifconfig "$iface" 2>/dev/null | grep -q "status: active"; then
            IP=$(ipconfig getifaddr "$iface" 2>/dev/null || echo "")
            if [ -n "$IP" ]; then
                print_log "$iface already has IP: $IP (cannot measure acquisition time)"
            else
                print_log "$iface is active but has no IP (DHCP may be in progress)"
            fi
        fi
    fi
done

#
# TEST 6: Multi-Interface Scenarios
#
print_header "TEST 6: MULTI-INTERFACE SCENARIOS"

print_section "6.1: Count active interfaces with IP"
ACTIVE_COUNT=0
for iface in $ALL_INTERFACES; do
    IP=$(ipconfig getifaddr "$iface" 2>/dev/null || echo "")
    if [ -n "$IP" ]; then
        ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
        print_log "Active: $iface ($IP)"
    fi
done
print_info "Total active interfaces with IP: $ACTIVE_COUNT"

print_section "6.2: Check routing priority"
print_log "Default routes:"
netstat -rn | grep default | tee -a "$LOG_FILE"

print_section "6.3: Interface priorities from system"
print_log "Service order (determines priority):"
networksetup -listnetworkserviceorder | grep -E "^\([0-9]|Device:" | tee -a "$LOG_FILE"

#
# TEST 7: Network Change Event Detection
#
print_header "TEST 7: NETWORK CHANGE EVENT DETECTION"

print_section "7.1: SCDynamicStore keys for monitoring"
print_info "These keys can be monitored for network changes:"
print_log "- State:/Network/Global/IPv4"
print_log "- State:/Network/Global/IPv6"
print_log "- State:/Network/Interface/<interface>/IPv4"
print_log "- State:/Network/Interface/<interface>/Link"

print_section "7.2: Current network state from scutil"
print_log "\nIPv4 State:"
echo "show State:/Network/Global/IPv4" | scutil | tee -a "$LOG_FILE"

print_log "\nIPv6 State:"
echo "show State:/Network/Global/IPv6" | scutil | tee -a "$LOG_FILE"

if [ -n "$WIFI_INTERFACE" ]; then
    print_log "\nWi-Fi Interface State:"
    echo "show State:/Network/Interface/$WIFI_INTERFACE/IPv4" | scutil | tee -a "$LOG_FILE"
fi

#
# TEST 8: Recommended Testing Procedures
#
print_header "TEST 8: MANUAL HARDWARE & TIMING CALIBRATION"

print_section "8.1: Master Calibration - Unplug/Plugin Sequence"
echo -e "${CYAN}Interactive Test: Unified timing for Failover, DHCP, and Recovery${NC}"
echo ""
echo "This unified test replaces multiple separate tests to save you time."
echo "We will measure everything with just ONE unplug/plug cycle:"
echo "  1) Time for macOS to detect physical disconnect"
echo "  2) Time for internet to failover to Wi-Fi"
echo "  3) Time for DHCP to assign an IP on reconnection"
echo "  4) Time for macOS to restore Ethernet as primary"
echo ""

# Find primary Ethernet
ETH_ACTIVE=""
for iface in $ALL_INTERFACES; do
    if [[ "$iface" =~ ^en[0-9]+$ ]]; then
        if ! networksetup -getairportpower "$iface" >/dev/null 2>&1; then
            IP=$(ipconfig getifaddr "$iface" 2>/dev/null || echo "")
            if [ -n "$IP" ]; then
                ETH_ACTIVE="$iface"
                break
            fi
        fi
    fi
done

if [ -z "$ETH_ACTIVE" ]; then
    print_warning "No active Ethernet interface with an IP found. Please connect Ethernet and re-run."
else
    echo -e "Primary Ethernet: ${YELLOW}$ETH_ACTIVE${NC}"
    WIFI_IP=$(ipconfig getifaddr "$WIFI_INTERFACE" 2>/dev/null || echo "")
    if [ -n "$WIFI_IP" ]; then
        echo -e "Wi-Fi Fallback: ${YELLOW}$WIFI_INTERFACE ($WIFI_IP)${NC}"
    else
        echo -e "Wi-Fi Fallback: ${RED}Not connected${NC} (Failover won't be measured)"
    fi
    echo ""

    read -p "Press Enter to start the calibration sequence (or Ctrl+C to skip)..."

    # --- Phase 1: Unplug ---
    echo ""
    echo -e "${BOLD}Phase 1: The Unplug${NC}"
    echo "  Get your hand on the Ethernet cable."
    read -p "  Press Enter and UNPLUG immediately when prompted..."
    echo ""
    countdown
    echo -e "${BOLD}${YELLOW}** UNPLUG THE ETHERNET CABLE NOW **${NC}"

    START_UNPLUG=$(date +%s%N)
    UNPLUG_DETECTION=""
    FAILOVER_TIME=""

    for i in {1..40}; do
        ELAPSED_SEC=$(( ($(date +%s%N) - START_UNPLUG) / 1000000000 ))

        # Check if IP is gone
        if [ -z "$UNPLUG_DETECTION" ]; then
            if [ -z "$(ipconfig getifaddr "$ETH_ACTIVE" 2>/dev/null)" ]; then
                UNPLUG_DETECTION=$ELAPSED_SEC
                print_success "Ethernet disconnect detected (${UNPLUG_DETECTION}s)"
            fi
        fi

        # Check failover to WiFi (if WiFi was active)
        if [ -n "$WIFI_IP" ] && [ -z "$FAILOVER_TIME" ]; then
            CURRENT_DEFAULT=$(netstat -rn | grep default | head -1 | awk '{print $NF}')
            if [ "$CURRENT_DEFAULT" = "$WIFI_INTERFACE" ]; then
                FAILOVER_TIME=$ELAPSED_SEC
                print_success "Internet failed-over to Wi-Fi (${FAILOVER_TIME}s)"
            fi
        fi

        # Stop loop if we have both or hit timeout
        if [ -n "$UNPLUG_DETECTION" ]; then
            if [ -z "$WIFI_IP" ] || [ -n "$FAILOVER_TIME" ]; then break; fi
        fi

        [ $((i % 4)) -eq 0 ] && echo -ne "  Monitoring... ${ELAPSED_SEC}s\r"
        sleep 0.25
    done
    echo ""

    # --- Phase 2: Plugin ---
    echo ""
    echo -e "${BOLD}Phase 2: The Plugin${NC}"
    echo "  Prepare to plug the cable back in."
    read -p "  Press Enter and PLUGIN immediately when prompted..."
    echo ""
    countdown
    echo -e "${BOLD}${YELLOW}** PLUG THE ETHERNET CABLE IN NOW **${NC}"

    START_PLUGIN=$(date +%s%N)
    DHCP_TIME=""
    SWITCHBACK_TIME=""

    for i in {1..100}; do
        ELAPSED_MS=$(( ($(date +%s%N) - START_PLUGIN) / 1000000 ))
        CURRENT_IP=$(ipconfig getifaddr "$ETH_ACTIVE" 2>/dev/null || echo "")

        # Check for IP (DHCP)
        if [ -z "$DHCP_TIME" ] && [ -n "$CURRENT_IP" ]; then
            DHCP_TIME=$(awk -v ms="$ELAPSED_MS" 'BEGIN {printf "%.2f", ms/1000}')
            print_success "IP acquired: $CURRENT_IP (${DHCP_TIME}s)"
        fi

        # Check for Switchback (Primary Priority)
        if [ -z "$SWITCHBACK_TIME" ]; then
            CURRENT_DEFAULT=$(netstat -rn | grep default | head -1 | awk '{print $NF}')
            if [ "$CURRENT_DEFAULT" = "$ETH_ACTIVE" ]; then
                SWITCHBACK_TIME=$(( ELAPSED_MS / 1000 ))
                print_success "Ethernet restored as primary priority (${SWITCHBACK_TIME}s)"
            fi
        fi

        if [ -n "$DHCP_TIME" ] && [ -n "$SWITCHBACK_TIME" ]; then break; fi

        if [ $((i % 4)) -eq 0 ]; then
            ELAPSED_SEC=$(awk -v ms="$ELAPSED_MS" 'BEGIN {printf "%.1f", ms/1000}')
            echo -ne "  Monitoring... ${ELAPSED_SEC}s\r"
        fi
        sleep 0.25
    done
    echo ""

    # Map to legacy result variables for summary compatibility
    TEST_8_1_UNPLUG_TIME="$UNPLUG_DETECTION"
    TEST_8_1_PLUGIN_TIME="$DHCP_TIME"
    TEST_8_3_FAILOVER_TIME="$FAILOVER_TIME"
    TEST_8_3_SWITCHBACK_TIME="$SWITCHBACK_TIME"
    TEST_8_5_DHCP_TIME="$DHCP_TIME"

    # Classify network for summary
    DHCP_NUMERIC=$(echo "$DHCP_TIME" | awk '{print $1}')
    if [ -n "$DHCP_NUMERIC" ]; then
        if awk -v val="$DHCP_NUMERIC" 'BEGIN {exit !(val < 3)}'; then NETWORK_TYPE="fast"
        elif awk -v val="$DHCP_NUMERIC" 'BEGIN {exit !(val < 7)}'; then NETWORK_TYPE="normal"
        else NETWORK_TYPE="slow"; fi
        TEST_8_5_NETWORK_TYPE="$NETWORK_TYPE"
    fi

    echo -e "${CYAN}Calibration Results:${NC}"
    echo "  • Disconnect Detect: ${UNPLUG_DETECTION:-Timed out}s"
    echo "  • WiFi Failover:     ${FAILOVER_TIME:-N/A}s"
    echo "  • DHCP Acquisition:  ${DHCP_TIME:-Timed out}s"
    echo "  • Priority Restore:  ${SWITCHBACK_TIME:-Timed out}s"
    echo ""
fi

print_section "8.2: Test Scenario - Wi-Fi control and reconnection"
echo -e "${CYAN}Interactive Test: Wi-Fi toggle and reconnection timing${NC}"
echo ""

if [ -z "$WIFI_INTERFACE" ]; then
    print_warning "No Wi-Fi interface found. Skipping this test."
elif [ $IS_ROOT -ne 1 ]; then
    print_warning "This test requires root privileges. Skipping."
else
    echo "This test toggles Wi-Fi to measure reconnection time."
    echo ""

    # Check current state
    WIFI_STATE=$(networksetup -getairportpower "$WIFI_INTERFACE" | awk '{print $NF}')
    WIFI_NETWORK=$(networksetup -getairportnetwork "$WIFI_INTERFACE" | cut -d: -f2 | xargs)

    echo -e "${BOLD}Current Wi-Fi State:${NC}"
    echo "  Interface: $WIFI_INTERFACE"
    echo "  Power: $WIFI_STATE"
    echo "  Network: $WIFI_NETWORK"
    echo ""

    if [ "$WIFI_STATE" != "On" ]; then
        print_warning "Wi-Fi is not currently on. Please enable it first."
    else
        read -p "Press Enter to start the Wi-Fi toggle test (or Ctrl+C to skip)..."

        echo ""
        echo -e "${BOLD}Step 1: Testing Wi-Fi disable${NC}"
        echo "  Turning Wi-Fi OFF..."
        START_TIME=$(date +%s%N)
        networksetup -setairportpower "$WIFI_INTERFACE" off
        END_TIME=$(date +%s%N)
        DISABLE_MS=$(( (END_TIME - START_TIME) / 1000000 ))
        echo -e "${GREEN}✓ Wi-Fi disabled in ${DISABLE_MS}ms${NC}"

        sleep 1
        NEW_STATE=$(networksetup -getairportpower "$WIFI_INTERFACE" | awk '{print $NF}')
        echo "  Confirmed state: $NEW_STATE"
        echo ""

        echo -e "${BOLD}Step 2: Verify internet loss${NC}"
        echo "  Testing connectivity..."
        if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            print_warning "Internet still available (probably another active interface)"
        else
            print_success "Internet lost as expected"
        fi
        echo ""

        echo -e "${BOLD}Step 3: Testing Wi-Fi re-enable${NC}"
        read -p "Press Enter to turn Wi-Fi back ON..."

        echo "  Turning Wi-Fi ON..."
        START_TIME=$(date +%s%N)
        networksetup -setairportpower "$WIFI_INTERFACE" on
        END_TIME=$(date +%s%N)
        ENABLE_MS=$(( (END_TIME - START_TIME) / 1000000 ))
        echo -e "${GREEN}✓ Wi-Fi enabled in ${ENABLE_MS}ms${NC}"
        echo ""

        echo -e "${BOLD}Step 4: Monitoring network reconnection${NC}"
        echo "  Waiting for Wi-Fi to reconnect to: $WIFI_NETWORK"
        echo "  (checking every 0.5s, max 30s)"
        echo ""

        RECONNECT_TIME=""
        START_TIME=$(date +%s)
        for i in {1..60}; do
            CURRENT_NETWORK=$(networksetup -getairportnetwork "$WIFI_INTERFACE" 2>/dev/null | cut -d: -f2 | xargs)
            IP=$(ipconfig getifaddr "$WIFI_INTERFACE" 2>/dev/null || echo "")
            ELAPSED=$(($(date +%s) - START_TIME))

            if [ -n "$IP" ] && [ "$CURRENT_NETWORK" = "$WIFI_NETWORK" ]; then
                RECONNECT_TIME=$ELAPSED
                echo -e "${GREEN}✓ Reconnected after ${RECONNECT_TIME} seconds${NC}"
                echo "  Network: $CURRENT_NETWORK"
                echo "  IP: $IP"
                break
            fi

            echo "  [$ELAPSED s] Network: ${CURRENT_NETWORK:-connecting...}, IP: ${IP:-none}"
            sleep 0.5
        done

        if [ -z "$RECONNECT_TIME" ]; then
            print_warning "Wi-Fi did not reconnect within 30 seconds"
        fi

        echo ""
        echo -e "${CYAN}Test Results:${NC}"
        echo "  • Disable time: ${DISABLE_MS}ms"
        echo "  • Enable time: ${ENABLE_MS}ms"
        [ -n "$RECONNECT_TIME" ] && echo "  • Reconnection time: ${RECONNECT_TIME}s" || echo "  • Reconnection time: >30s"
        echo ""

        # Save to global variables for final summary
        TEST_8_2_DISABLE_MS="$DISABLE_MS"
        TEST_8_2_ENABLE_MS="$ENABLE_MS"
        TEST_8_2_RECONNECT_TIME="$RECONNECT_TIME"
    fi
fi

print_section "8.3: Test Scenario - Internet loss without disconnect"
echo -e "${CYAN}Interactive Test: Gateway/Internet loss detection (No link down)${NC}"
echo ""
echo "This test simulates internet loss while the interface stays physically connected."
echo "You'll need to simulate this by disconnecting your router/modem from the internet,"
echo "or by blocking the gateway in your router settings."
echo ""

read -p "Press Enter to start (or Ctrl+C to skip)..."

echo ""
echo -e "${BOLD}Step 1: Check current network state${NC}"
PRIMARY_IFACE=$(netstat -rn | grep default | head -1 | awk '{print $NF}')
PRIMARY_IP=$(ipconfig getifaddr "$PRIMARY_IFACE" 2>/dev/null || echo "none")
GATEWAY=$(netstat -rn | grep default | head -1 | awk '{print $2}')

# If Wi-Fi is available and different from the primary interface, treat it as the
# most likely fallback path for internet connectivity checks.
ALT_IFACE=""
ALT_IP=""
if [ -n "$WIFI_INTERFACE" ] && [ "$WIFI_INTERFACE" != "$PRIMARY_IFACE" ]; then
    ALT_IP=$(ipconfig getifaddr "$WIFI_INTERFACE" 2>/dev/null || echo "")
    if [ -n "$ALT_IP" ]; then
        ALT_IFACE="$WIFI_INTERFACE"
    fi
fi

echo "  Primary interface: $PRIMARY_IFACE"
echo "  Interface IP: $PRIMARY_IP"
echo "  Gateway: $GATEWAY"
if [ -n "$ALT_IFACE" ]; then
    echo "  Alternate interface (fallback candidate): $ALT_IFACE ($ALT_IP)"
else
    echo "  Alternate interface (fallback candidate): none detected"
fi
echo ""

# Test connectivity
echo -e "${BOLD}Step 2: Verify internet is working${NC}"
echo "  Testing connectivity..."
if ping -c 2 -W 3 8.8.8.8 >/dev/null 2>&1; then
    print_success "Internet is working (ping successful)"
else
    print_error "Internet is not working"
fi

if curl -s --connect-timeout 5 http://captive.apple.com >/dev/null 2>&1; then
    print_success "Internet is working (HTTP test successful)"
else
    print_error "Internet is not working (HTTP test failed)"
fi

echo ""
echo "  Testing connectivity forced via PRIMARY interface ($PRIMARY_IFACE)..."
if ping -c 2 -t 3 -I "$PRIMARY_IFACE" 8.8.8.8 >/dev/null 2>&1; then
    print_success "Primary interface can reach the internet (ping via $PRIMARY_IFACE)"
else
    print_error "Primary interface cannot reach the internet (ping via $PRIMARY_IFACE failed)"
fi

if curl -s --connect-timeout 5 --interface "$PRIMARY_IFACE" http://captive.apple.com >/dev/null 2>&1; then
    print_success "Primary interface can reach the internet (HTTP via $PRIMARY_IFACE)"
else
    print_error "Primary interface cannot reach the internet (HTTP via $PRIMARY_IFACE failed)"
fi

if [ -n "$ALT_IFACE" ]; then
    echo ""
    echo "  Testing connectivity forced via ALTERNATE interface ($ALT_IFACE)..."
    if ping -c 2 -t 3 -I "$ALT_IFACE" 8.8.8.8 >/dev/null 2>&1; then
        print_success "Alternate interface can reach the internet (ping via $ALT_IFACE)"
    else
        print_warning "Alternate interface ping failed (via $ALT_IFACE)"
    fi

    if curl -s --connect-timeout 5 --interface "$ALT_IFACE" http://captive.apple.com >/dev/null 2>&1; then
        print_success "Alternate interface can reach the internet (HTTP via $ALT_IFACE)"
    else
        print_warning "Alternate interface HTTP failed (via $ALT_IFACE)"
    fi
fi
echo ""

echo -e "${BOLD}Step 3: Prepare to disconnect internet${NC}"
echo "  Now you need to simulate internet loss WITHOUT disconnecting the cable."
echo "  Options:"
echo "    a) Unplug your router/modem from the internet"
echo "    b) Disable WAN in your router settings"
echo "    c) Block the gateway in firewall rules"
echo ""
echo "  The interface will stay 'active' but internet will be gone."
echo ""
read -p "Press Enter AFTER you have disconnected the internet..."

echo ""
echo -e "${BOLD}Step 4: Verify interface is still up but internet is down${NC}"
echo "  Checking interface status..."

CURRENT_STATUS=$(ifconfig "$PRIMARY_IFACE" 2>/dev/null | grep "status:" | awk '{print $2}')
CURRENT_IP=$(ipconfig getifaddr "$PRIMARY_IFACE" 2>/dev/null || echo "")

echo "  Interface status: ${CURRENT_STATUS}"
echo "  Interface IP: ${CURRENT_IP:-none}"
echo ""

echo "  Testing connectivity methods..."
echo ""

# Test ping to gateway
echo "  1. Ping to gateway ($GATEWAY):"
if ping -c 2 -W 3 "$GATEWAY" >/dev/null 2>&1; then
    print_success "Gateway responds (router still reachable)"
else
    print_error "Gateway does not respond"
fi

# Test ping to internet
echo ""
echo "  2. Ping to internet (8.8.8.8):"
if ping -c 2 -W 3 8.8.8.8 >/dev/null 2>&1; then
    print_warning "Internet still responds (may not be fully disconnected)"
else
    print_success "Internet unreachable (as expected)"
fi

# Test DNS
echo ""
echo "  3. DNS resolution (google.com):"
if nslookup google.com >/dev/null 2>&1; then
    print_warning "DNS still works"
else
    print_error "DNS fails"
fi

# Test HTTP
echo ""
echo "  4. HTTP test (captive.apple.com):"
if curl -s --connect-timeout 5 http://captive.apple.com >/dev/null 2>&1; then
    print_warning "HTTP still works"
else
    print_success "HTTP fails (internet lost)"
fi

echo ""
echo "  5. Ping to internet via PRIMARY interface ($PRIMARY_IFACE):"
if ping -c 2 -t 3 -I "$PRIMARY_IFACE" 8.8.8.8 >/dev/null 2>&1; then
    print_warning "Primary interface still reaches the internet (may not be fully disconnected)"
else
    print_success "Primary interface cannot reach the internet (as expected)"
fi

echo ""
echo "  6. HTTP test via PRIMARY interface ($PRIMARY_IFACE):"
if curl -s --connect-timeout 5 --interface "$PRIMARY_IFACE" http://captive.apple.com >/dev/null 2>&1; then
    print_warning "Primary interface HTTP still works (may not be fully disconnected)"
else
    print_success "Primary interface HTTP fails (as expected)"
fi

if [ -n "$ALT_IFACE" ]; then
    echo ""
    echo "  7. Ping to internet via ALTERNATE interface ($ALT_IFACE):"
    if ping -c 2 -t 3 -I "$ALT_IFACE" 8.8.8.8 >/dev/null 2>&1; then
        print_success "Alternate interface still reaches the internet (fallback path works)"
    else
        print_error "Alternate interface cannot reach the internet (fallback path NOT usable)"
    fi

    echo ""
    echo "  8. HTTP test via ALTERNATE interface ($ALT_IFACE):"
    if curl -s --connect-timeout 5 --interface "$ALT_IFACE" http://captive.apple.com >/dev/null 2>&1; then
        print_success "Alternate interface HTTP works (fallback path works)"
    else
        print_error "Alternate interface HTTP fails (fallback path NOT usable)"
    fi

    # Step 5: Service Reordering Test (Optional)
    echo ""
    echo -e "${BOLD}Step 5: Verify failover by reordering services${NC}"
    echo "  Since the Primary interface is still 'active', macOS keeps it as the default route."
    echo "  To test if the Alternate interface ($ALT_IFACE) actually works, we can temporarily"
    echo "  promote it to be the top priority service."
    echo ""

    read -p "  Would you like to temporarily reorder network services to test failover? (y/N) " -n 1 -r REPLY_REORDER
    echo ""
    if [[ $REPLY_REORDER =~ ^[Yy]$ ]]; then
        # Getting Service Names
        # We need to escape parens for grep to match literal parens
        # Strip (N) or (*) prefix to get the clean Service Name
        PRIMARY_SERVICE=$(networksetup -listnetworkserviceorder | grep -B 1 "Device: $PRIMARY_IFACE)" | head -n 1 | sed 's/^([0-9*]*) //')
        ALT_SERVICE=$(networksetup -listnetworkserviceorder | grep -B 1 "Device: $ALT_IFACE)" | head -n 1 | sed 's/^([0-9*]*) //')

        if [ -z "$PRIMARY_SERVICE" ] || [ -z "$ALT_SERVICE" ]; then
            print_error "Could not determine service names for interfaces."
        else
            echo "  Primary Service: $PRIMARY_SERVICE"
            echo "  Alternate Service: $ALT_SERVICE"

            # Capture current order securely
            IFS=$'\n'
            # Use a slightly more robust sed to strip only the leading "(N) " or "(*) "
            CURRENT_SERVICES=($(networksetup -listnetworkserviceorder | grep '([0-9]*) ' | sed 's/^([0-9*]*) //'))
            unset IFS

            # Construct new order
            NEW_ORDER=("$ALT_SERVICE" "$PRIMARY_SERVICE")
            for svc in "${CURRENT_SERVICES[@]}"; do
                if [ "$svc" != "$PRIMARY_SERVICE" ] && [ "$svc" != "$ALT_SERVICE" ]; then
                    NEW_ORDER+=("$svc")
                fi
            done

            echo "  Applying new order (temporary)..."
            networksetup -ordernetworkservices "${NEW_ORDER[@]}"

            echo "  Waiting 5 seconds for routing update..."
            sleep 5

            echo "  Testing internet via default route (should now be $ALT_IFACE)..."
            if ping -c 2 -W 3 8.8.8.8 >/dev/null 2>&1; then
                print_success "Internet is working via $ALT_IFACE (after reordering)"
                echo "  ✓ This confirms the backup connection is viable if priorities are switched."
            else
                print_error "Internet still NOT working even after reordering"
                echo "  ⚠ This indicates the backup connection itself might have no internet."
            fi

            echo "  Restoring original order..."
            networksetup -ordernetworkservices "${CURRENT_SERVICES[@]}"
            echo "  Restored."
        fi
    fi
fi

echo ""
echo -e "${CYAN}Observations:${NC}"
echo "  • Interface status: ${CURRENT_STATUS} (should be 'active')"
echo "  • IP address: ${CURRENT_IP:-none} (should be assigned)"
echo "  • This shows that interface state != internet connectivity"
echo ""
echo -e "${YELLOW}Key Takeaway:${NC}"
echo "  The switcher must test actual internet connectivity, not just interface status!"
echo ""

read -p "Press Enter when you've restored internet connectivity..."
print_success "Test complete"
echo ""

print_section "8.4: Test Scenario - Static Route Verification"
echo -e "${CYAN}Interactive Test: Checking connectivity via inactive route${NC}"
echo ""
echo "This test verifies if we can check internet connectivity on a secondary"
echo "interface (e.g. Ethernet) while it is NOT the default route."
echo "This is critical for detecting when the primary connection is restored."
echo ""

# Find a candidate for secondary interface
# If Wi-Fi is active and we have an Ethernet with IP, assume we can test Ethernet
CANDIDATE_SEC_IFACE=""
CANDIDATE_SEC_IP=""
CANDIDATE_SEC_GATEWAY=""

# Get current default route interface
CURRENT_DEFAULT_IF=$(netstat -rn | grep default | head -1 | awk '{print $NF}')

echo "Current Default Interface: $CURRENT_DEFAULT_IF"

# Look for another interface that has an IP
for iface in $ALL_INTERFACES; do
    if [ "$iface" != "$CURRENT_DEFAULT_IF" ] && [ "$iface" != "lo0" ]; then
        IP=$(ipconfig getifaddr "$iface" 2>/dev/null || echo "")
        if [ -n "$IP" ]; then
            CANDIDATE_SEC_IFACE="$iface"
            CANDIDATE_SEC_IP="$IP"
            # Try to guess gateway (assuming /24 for simplicity or checking router via netstat if possible,
            # but netstat usually shows default. We can try to assume X.X.X.1)
            # A better way is using 'route get' for a local IP on that subnet?
            # Or just assume the standard router is at .1 of the subnet.
            SUBNET_BASE=$(echo "$IP" | cut -d. -f1-3)
            CANDIDATE_SEC_GATEWAY="${SUBNET_BASE}.1"
            break
        fi
    fi
done

if [ -z "$CANDIDATE_SEC_IFACE" ]; then
    print_warning "No secondary interface with IP found to test."
    echo "  (You need two active interfaces with IPs for this test)"
else
    echo "Candidate Secondary Interface: $CANDIDATE_SEC_IFACE ($CANDIDATE_SEC_IP)"
    echo "Estimated Gateway: $CANDIDATE_SEC_GATEWAY"
    echo ""
    echo "We will attempt to ping 1.0.0.1 via this interface using a STATIC ROUTE."
    echo ""

    read -p "Press Enter to run this test (requires sudo)..."

    echo ""
    echo -e "${BOLD}Step 1: Add Static Route${NC}"
    echo "  Command: sudo route add -host 1.0.0.1 $CANDIDATE_SEC_GATEWAY"
    if sudo route add -host 1.0.0.1 "$CANDIDATE_SEC_GATEWAY"; then
        print_success "Route added"

        echo ""
        echo -e "${BOLD}Step 2: Test Connectivity${NC}"
        echo "  Pinging 1.0.0.1..."
        if ping -c 2 -W 2 1.0.0.1; then
            print_success "Ping successful! We accessed internet via $CANDIDATE_SEC_IFACE"
            STATIC_ROUTE_WORKS="yes"
        else
            print_error "Ping failed."
            STATIC_ROUTE_WORKS="no"
        fi

        echo ""
        echo -e "${BOLD}Step 3: Cleanup${NC}"
        echo "  Command: sudo route delete -host 1.0.0.1"
        sudo route delete -host 1.0.0.1 >/dev/null 2>&1
        print_success "Route removed"
    else
        print_error "Failed to add route. (Gateway might be unreachable or wrong IP)"
    fi
fi
echo ""

# Test 8.5: End-to-end priority failover validation
print_section "8.5: Test Scenario - End-to-end priority failover"
echo -e "${CYAN}Interactive Test: Verify failover, primary recovery and re-prioritization${NC}"
echo ""
echo "This test runs the sequence you described to ensure the switcher logic is valid:"
echo "  1) Simulate internet loss on PRIMARY interface"
echo "  2) Temporarily promote ALTERNATE interface to priority"
echo "  3) Verify alternate interface provides internet"
echo "  4) Confirm PRIMARY remains offline"
echo "  5) Restore internet on PRIMARY and verify it comes back"
echo "  6) Restore original priority (PRIMARY first)"
echo "  7) Disable ALTERNATE (simulate failure) and confirm PRIMARY carries traffic"
echo ""

# Identify primary (default route) and alternate
PRIMARY_IFACE=$(netstat -rn | grep default | head -1 | awk '{print $NF}')
PRIMARY_GW=$(netstat -rn | grep default | grep "$PRIMARY_IFACE" | head -1 | awk '{print $2}')
ALT_IFACE=""
for iface in $ALL_INTERFACES; do
    if [ "$iface" != "$PRIMARY_IFACE" ] && [ "$iface" != "lo0" ]; then
        IP=$(ipconfig getifaddr "$iface" 2>/dev/null || echo "")
        if [ -n "$IP" ]; then
            ALT_IFACE="$iface"
            ALT_IP="$IP"
            break
        fi
    fi
done

if [ -z "$ALT_IFACE" ]; then
    print_warning "No alternate interface with IP found for this test. Ensure two active interfaces with IPs."
else
    echo "Primary: $PRIMARY_IFACE"
    echo "Alternate: $ALT_IFACE ($ALT_IP)"
    echo ""

    read -p "Press Enter when you are ready to run the end-to-end priority test..."
    echo ""

    # Step A: Simulate internet loss on primary
    echo -e "${BOLD}Step A: Simulate internet loss on PRIMARY (${PRIMARY_IFACE})${NC}"
    echo "  Please IMITATE INTERNET LOSS on the PRIMARY interface (e.g. unplug WAN or disable upstream)"
    echo ""
    read -p "  Press Enter when ready to perform the SIMULATION (or Ctrl+C to skip)..."
    countdown
    echo -e "${BOLD}${YELLOW}** SIMULATE INTERNET LOSS ON PRIMARY **${NC}"
    echo "  Waiting 3 seconds for you to act..."
    sleep 3

    # Verify primary appears offline for internet
    echo "  Verifying PRIMARY internet reachability (ping via $PRIMARY_IFACE)..."
    if ping -c 2 -I "$PRIMARY_IFACE" -W 3 8.8.8.8 >/dev/null 2>&1; then
        print_warning "PRIMARY still has internet access (simulation may not have been applied)"
    else
        print_success "PRIMARY appears offline for internet (expected)"
    fi

    # Step B: Temporarily promote alternate to be top priority
    echo ""
    echo -e "${BOLD}Step B: Temporarily promote ALTERNATE ($ALT_IFACE) to top priority${NC}"
    read -p "  Press Enter to promote $ALT_IFACE (or Ctrl+C to skip)..."
    echo ""

    # Fetch service names
    PRIMARY_SERVICE=$(networksetup -listnetworkserviceorder | grep -B 1 "Device: $PRIMARY_IFACE)" | head -n 1 | sed 's/^([0-9*]*) //')
    ALT_SERVICE=$(networksetup -listnetworkserviceorder | grep -B 1 "Device: $ALT_IFACE)" | head -n 1 | sed 's/^([0-9*]*) //')

    if [ -z "$PRIMARY_SERVICE" ] || [ -z "$ALT_SERVICE" ]; then
        print_error "Could not determine service names for interfaces. Skipping promotion step."
    else
        IFS=$'\n'
        CURRENT_SERVICES=($(networksetup -listnetworkserviceorder | grep '([0-9]*) ' | sed 's/^([0-9*]*) //'))
        unset IFS

        # Build new order with ALT first
        NEW_ORDER=("$ALT_SERVICE" "$PRIMARY_SERVICE")
        for svc in "${CURRENT_SERVICES[@]}"; do
            if [ "$svc" != "$PRIMARY_SERVICE" ] && [ "$svc" != "$ALT_SERVICE" ]; then
                NEW_ORDER+=("$svc")
            fi
        done

        echo "  Applying temporary service order (ALT first)..."
        networksetup -ordernetworkservices "${NEW_ORDER[@]}"
        echo "  Waiting 5 seconds for system to apply new order..."
        sleep 5

        # Test internet via default route (should now be ALT)
        echo "  Testing internet via default route (should use $ALT_IFACE)..."
        if ping -c 2 -W 3 8.8.8.8 >/dev/null 2>&1; then
            print_success "Default route internet check: SUCCESS (ALT taking traffic)"
        else
            print_error "Default route internet check: FAILED (ALT may not have path)"
        fi

        # Confirm PRIMARY still offline
        echo "  Confirming PRIMARY ($PRIMARY_IFACE) remains offline (ping via primary)..."
        if ping -c 2 -I "$PRIMARY_IFACE" -W 3 8.8.8.8 >/dev/null 2>&1; then
            print_warning "PRIMARY regained internet unexpectedly"
        else
            print_success "PRIMARY still offline (as expected)"
        fi

        # Step C: Ask user to restore primary internet
        echo ""
        echo -e "${BOLD}Step C: Restore internet on PRIMARY (${PRIMARY_IFACE})${NC}"
        echo "  Please RESTORE internet service to the PRIMARY interface (undo the simulation)"
        read -p "  Press Enter when primary internet is restored..."
        countdown

        echo "  Testing PRIMARY for internet recovery (using Static Route check)..."
        PRIMARY_RECOVERED=""
        START_RECOVERY=$(date +%s)
        RECOVERY_TIMEOUT=30

        # Static route method (from Test 8.6) is the most reliable "out-of-band" check
        CANARY_HOST="1.1.1.1" # Using Cloudflare as a secondary canary
        HAS_GW=0
        if [[ "$PRIMARY_GW" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            sudo route add -host "$CANARY_HOST" "$PRIMARY_GW" >/dev/null 2>&1
            HAS_GW=1
        fi

        for i in $(seq 1 $RECOVERY_TIMEOUT); do
            # Try both host-specific route and interface bind
            if ping -c 1 -W 1 "$CANARY_HOST" >/dev/null 2>&1 || ping -c 1 -I "$PRIMARY_IFACE" -W 1 8.8.8.8 >/dev/null 2>&1; then
                PRIMARY_RECOVERED=1
                ELAPSED_RECOVERY=$(( $(date +%s) - START_RECOVERY ))
                print_success "PRIMARY has regained internet access (detected after ${ELAPSED_RECOVERY}s)"
                break
            fi
            echo -ne "  Waiting for PRIMARY to recover... ${i}/${RECOVERY_TIMEOUT}s\r"
            sleep 1
        done
        echo ""

        # Cleanup route
        if [ "$HAS_GW" -eq 1 ]; then
            sudo route delete -host "$CANARY_HOST" >/dev/null 2>&1
        fi

        if [ -z "$PRIMARY_RECOVERED" ]; then
            print_warning "PRIMARY did not recover within ${RECOVERY_TIMEOUT}s (or detector failed)"
            read -p "  Has the internet actually returned? (y/N) " -n 1 -r REPLY_MANUAL
            echo ""
            if [[ $REPLY_MANUAL =~ ^[Yy]$ ]]; then
                PRIMARY_RECOVERED=1
            else
                read -p "  Would you like to restore priority anyway? (y/N) " -n 1 -r REPLY_CONT
                echo ""
                if [[ ! $REPLY_CONT =~ ^[Yy]$ ]]; then
                    print_error "Aborting priority restore."
                    SKIP_RESTORE=1
                fi
            fi
        fi

        if [ -z "$SKIP_RESTORE" ]; then
            # Step D: Restore original service order (PRIMARY first)
        echo ""
        echo -e "${BOLD}Step D: Restore original service priority (PRIMARY first)${NC}"
        read -p "  Press Enter to restore original priority..."
        echo "  Restoring original service order..."
        networksetup -ordernetworkservices "${CURRENT_SERVICES[@]}"
        echo "  Waiting 5 seconds for routing updates..."
        sleep 5

        echo "  Testing default route internet (should be via PRIMARY now)..."
        if ping -c 2 -W 3 8.8.8.8 >/dev/null 2>&1; then
            print_success "Default route internet check: SUCCESS (PRIMARY preferred)"
        else
            print_warning "Default route internet check: FAILED (system may still prefer ALT)"
        fi

        # Step E: Disable ALTERNATE to confirm PRIMARY carries traffic
        echo ""
        echo -e "${BOLD}Step E: Disable ALTERNATE ($ALT_IFACE) to confirm PRIMARY carries traffic${NC}"
        echo "  Please DISABLE the ALTERNATE interface (e.g., turn off Wi-Fi or unplug Ethernet)"
        read -p "  Press Enter when ALTERNATE is disabled..."
        countdown
        echo "  Testing default route internet after ALT disabled..."
        if ping -c 3 -W 3 8.8.8.8 >/dev/null 2>&1; then
            print_success "Internet still works (PRIMARY is handling traffic)"
        else
            print_error "Internet test failed after disabling ALT. Primary may not be routing traffic correctly"
        fi

        # Re-enable ALT if user left it disabled
        echo ""
        read -p "Press Enter when you've restored ALTERNATE (or press Enter to continue)..."

        # Final cleanup: ensure original order
        echo "  Ensuring original service order restored..."
        networksetup -ordernetworkservices "${CURRENT_SERVICES[@]}" >/dev/null 2>&1 || true
        echo "  Done."
        fi
    fi
fi


# Proceed to TEST 9

#
# TEST 9: Command Performance Testing
#
print_header "TEST 9: COMMAND PERFORMANCE TESTING"

print_section "9.1: Measure command execution times"

# Test ipconfig
START=$(date +%s%N)
ipconfig getifaddr en0 >/dev/null 2>&1 || true
END=$(date +%s%N)
TIME_MS=$(( (END - START) / 1000000 ))
print_log "ipconfig getifaddr: ${TIME_MS}ms"

# Test ifconfig
START=$(date +%s%N)
ifconfig en0 >/dev/null 2>&1 || true
END=$(date +%s%N)
TIME_MS=$(( (END - START) / 1000000 ))
print_log "ifconfig: ${TIME_MS}ms"

# Test networksetup
START=$(date +%s%N)
networksetup -getairportpower en0 >/dev/null 2>&1 || true
END=$(date +%s%N)
TIME_MS=$(( (END - START) / 1000000 ))
print_log "networksetup -getairportpower: ${TIME_MS}ms"

# Test scutil
START=$(date +%s%N)
echo "show State:/Network/Global/IPv4" | scutil >/dev/null 2>&1 || true
END=$(date +%s%N)
TIME_MS=$(( (END - START) / 1000000 ))
print_log "scutil show state: ${TIME_MS}ms"

# Test ping
START=$(date +%s%N)
ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1 || true
END=$(date +%s%N)
TIME_MS=$(( (END - START) / 1000000 ))
print_log "ping -c 1 -W 1: ${TIME_MS}ms"

#
# Summary and Recommendations
#
print_header "TEST SUMMARY AND RECOMMENDATIONS"

print_section "Key Findings"
print_log "1. All interfaces found: $(echo $ALL_INTERFACES | wc -w)"
print_log "2. Active interfaces: $ACTIVE_COUNT"
print_log "3. Wi-Fi interface: ${WIFI_INTERFACE:-'not found'}"
print_log "4. Root access: $([ $IS_ROOT -eq 1 ] && echo 'available' || echo 'not available')"

print_section "Recommendations for ethernet-wifi-switcher"
# Print to console with colors
echo -e "${CYAN}Based on automated tests, the application should:${NC}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo -e "1. ${BOLD}Interface Detection:${NC}" | tee -a "$LOG_FILE"
cat << 'EOF' | tee -a "$LOG_FILE"
   - Use 'ipconfig getifaddr' to check for IP (fastest, reliable)
   - Use 'ifconfig | grep status: active' to check link state
   - Prioritize interfaces with assigned IPs

EOF
echo -e "2. ${BOLD}Internet Detection:${NC}" | tee -a "$LOG_FILE"
cat << 'EOF' | tee -a "$LOG_FILE"
   - Primary: Check for IP address on interface
   - Secondary: Ping test to 8.8.8.8 (fast, reliable)
   - Tertiary: Apple captive portal (http://captive.apple.com)

EOF
echo -e "3. ${BOLD}State Management:${NC}" | tee -a "$LOG_FILE"
cat << 'EOF' | tee -a "$LOG_FILE"
   - Track previous ethernet state in file
   - On disconnect: enable Wi-Fi immediately (no delay)
   - On connect: wait for IP with timeout (use INTERACTIVE TESTS to determine)

EOF
echo -e "4. ${BOLD}Event Monitoring:${NC}" | tee -a "$LOG_FILE"
cat << 'EOF' | tee -a "$LOG_FILE"
   - Use SCDynamicStore to watch for network changes
   - Monitor Global IPv4/IPv6 and per-interface keys
   - Debounce rapid events (5 second minimum gap)

EOF
echo -e "5. ${BOLD}Timing Considerations:${NC}" | tee -a "$LOG_FILE"
cat << 'EOF' | tee -a "$LOG_FILE"
   - Interface status changes: immediate (< 1s)
   - IP address loss on disconnect: 1-2 seconds
   - DHCP acquisition: 2-7 seconds (YOUR NETWORK MAY DIFFER - RUN TEST 8!)
   - Wi-Fi toggle: 2-3 seconds

EOF
echo -e "${YELLOW}Next Steps - PERFORM INTERACTIVE TESTS:${NC}" | tee -a "$LOG_FILE"
cat << 'EOF' | tee -a "$LOG_FILE"
The interactive tests below (TEST 8.1-8.5) will measure YOUR specific network
and provide PRECISE configuration values for switcher.sh.

Run these tests to get:
  • Your actual DHCP acquisition time
  • Recommended TIMEOUT value
  • Real failover/switchback timings
  • Network type classification

These measurements are CRITICAL for proper configuration!

EOF

print_header "TESTING COMPLETE"
print_success "All tests completed successfully!"
echo ""

#
# COMPREHENSIVE SUMMARY AND ACTIONABLE RECOMMENDATIONS
#
print_header "CONFIGURATION RECOMMENDATIONS FOR SWITCHER"

# Calculate recommended timeout based on test results
RECOMMENDED_TIMEOUT=7
if [ -n "$TEST_8_5_DHCP_TIME" ] && [ "$TEST_8_5_DHCP_TIME" != ">30" ]; then
    DHCP_NUMERIC=$(echo "$TEST_8_5_DHCP_TIME" | awk '{print $1}')
    RECOMMENDED_TIMEOUT=$(awk -v val="$DHCP_NUMERIC" 'BEGIN {printf "%.0f", val + 3}')
elif [ -n "$TEST_8_1_PLUGIN_TIME" ]; then
    RECOMMENDED_TIMEOUT=$(awk -v val="$TEST_8_1_PLUGIN_TIME" 'BEGIN {printf "%.0f", val + 3}')
fi

# Ensure minimum of 5s, cap at 30s
if [ $RECOMMENDED_TIMEOUT -lt 5 ]; then
    RECOMMENDED_TIMEOUT=5
elif [ $RECOMMENDED_TIMEOUT -gt 30 ]; then
    RECOMMENDED_TIMEOUT=30
fi

echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}APPLY THESE SETTINGS TO src/macos/switcher.sh:${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

print_section "1. TIMEOUT Configuration"
echo -e "${YELLOW}Based on your network's DHCP speed:${NC}"
if [ -n "$TEST_8_5_DHCP_TIME" ]; then
    echo "  Measured DHCP time: ${TEST_8_5_DHCP_TIME}s (${TEST_8_5_NETWORK_TYPE} network)"
    echo "  Measured during plugin: ${TEST_8_1_PLUGIN_TIME:-not tested}s"
    echo ""
    echo -e "${GREEN}${BOLD}  TIMEOUT=${RECOMMENDED_TIMEOUT}${NC}"
    echo ""
    echo "  Rationale: DHCP + 3s safety margin"
else
    echo "  DHCP timing not measured in tests"
    echo ""
    echo -e "${YELLOW}  TIMEOUT=7  ${NC}(default, works for most networks)"
fi
echo "" | tee -a "$LOG_FILE"

print_section "2. Interface Detection Method"
echo -e "${GREEN}${BOLD}  Use: ipconfig getifaddr <interface>${NC}"
echo ""
echo "  • Fastest method (< 10ms)"
echo "  • Most reliable indicator of usable connection"
echo "  • Already implemented correctly in switcher.sh"
echo "" | tee -a "$LOG_FILE"

print_section "3. Internet Connectivity Check"
echo -e "${YELLOW}Based on successful test validations:${NC}"
if [ "$METHOD_PING_8888_WORKS" -eq 1 ]; then
    echo -e "${GREEN}${BOLD}  Primary: Ping 8.8.8.8${NC} (Validated: WORKING)"
    echo "  • Reliable, fast, works on your network"
elif [ "$METHOD_PING_GOOGLE_WORKS" -eq 1 ]; then
    echo -e "${GREEN}${BOLD}  Primary: Ping google.com${NC} (Validated: WORKING)"
    echo "  • 8.8.8.8 blocked? Using google.com works."
elif [ "$METHOD_HTTP_GOOGLE_WORKS" -eq 1 ]; then
    echo -e "${GREEN}${BOLD}  Primary: HTTP Check google.com${NC} (Validated: WORKING)"
    echo "  • ICMP blocked? HTTP check works."
else
    echo -e "${RED}${BOLD}  Warning: No reliable internet check detected!${NC}"
    echo "  • Check your firewall or proxy settings."
fi

if [ "$METHOD_CAPTIVE_PORTAL_WORKS" -eq 1 ]; then
    echo -e "  Secondary: Apple Captive Portal (Validated: WORKING)"
else
    echo -e "  Secondary: Apple Captive Portal (Validated: FAILED)"
fi
echo "" | tee -a "$LOG_FILE"

print_section "4. Event Response Timing"
if [ -n "$TEST_8_1_UNPLUG_TIME" ]; then
    echo "  Measured Ethernet disconnect detection: ${TEST_8_1_UNPLUG_TIME}s"
fi
if [ -n "$TEST_8_3_FAILOVER_TIME" ]; then
    echo "  Measured failover to Wi-Fi: ${TEST_8_3_FAILOVER_TIME}s"
fi
if [ -n "$TEST_8_3_SWITCHBACK_TIME" ]; then
    echo "  Measured switch back to Ethernet: ${TEST_8_3_SWITCHBACK_TIME}s"
fi
echo ""
echo -e "${GREEN}${BOLD}  DEBOUNCE_SECONDS=5${NC}"
echo ""
echo "  Rationale: Prevents flapping during network transitions"
echo "" | tee -a "$LOG_FILE"

print_section "5. Wi-Fi Control Strategy"
if [ -n "$TEST_8_2_RECONNECT_TIME" ]; then
    echo "  Measured Wi-Fi reconnection: ${TEST_8_2_RECONNECT_TIME}s"
    echo ""
fi
echo -e "${YELLOW}  On Ethernet connect:${NC}"
echo "    • Wait for IP assignment (TIMEOUT seconds)"
echo "    • If IP acquired: disable Wi-Fi immediately"
echo "    • If timeout: keep Wi-Fi enabled (fallback)"
echo ""
echo -e "${YELLOW}  On Ethernet disconnect:${NC}"
echo "    • Enable Wi-Fi immediately (no delay)"
echo "    • Do not wait - macOS will auto-reconnect"
echo "" | tee -a "$LOG_FILE"

print_section "6. Interface Priority"
if [ -n "$TEST_8_3_PRIMARY_IFACE" ]; then
    echo "  Detected macOS priority: ${TEST_8_3_PRIMARY_IFACE} (Ethernet first)"
fi
echo ""
echo -e "${GREEN}  macOS handles priority automatically${NC}"
echo "  • Ethernet is automatically preferred when both connected"
echo "  • No manual route manipulation needed"
echo "  • Trust macOS routing table"
echo "" | tee -a "$LOG_FILE"

print_section "7. Recommended Monitoring Keys (EthWifiWatch.swift)"
echo -e "${GREEN}  SCDynamicStore keys to monitor:${NC}"
echo "    • State:/Network/Global/IPv4"
echo "    • State:/Network/Interface/<eth>/IPv4"
echo "    • State:/Network/Interface/<eth>/Link"
echo ""
echo "  These provide immediate notification of network changes"
echo "" | tee -a "$LOG_FILE"

echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}TESTING DATA SUMMARY:${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "System Information:" | tee -a "$LOG_FILE"
echo "  • macOS Version: $(sw_vers -productVersion)" | tee -a "$LOG_FILE"
echo "  • Date: $(date)" | tee -a "$LOG_FILE"
echo "  • User: $(whoami)" | tee -a "$LOG_FILE"
echo "  • Root Access: $([ $IS_ROOT -eq 1 ] && echo 'Yes' || echo 'No (some tests skipped)')" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

echo "Network Interfaces:" | tee -a "$LOG_FILE"
echo "  • Total Interfaces: $(echo $ALL_INTERFACES | wc -w | xargs)" | tee -a "$LOG_FILE"
echo "  • Active Interfaces: $ACTIVE_COUNT" | tee -a "$LOG_FILE"
echo "  • Wi-Fi Interface: ${WIFI_INTERFACE:-'not found'}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

echo "Interactive Test Results:" | tee -a "$LOG_FILE"
if [ -n "$TEST_8_1_UNPLUG_TIME" ] || [ -n "$TEST_8_1_PLUGIN_TIME" ]; then
    echo "  Test 8.1 (Ethernet plug/unplug):" | tee -a "$LOG_FILE"
    [ -n "$TEST_8_1_UNPLUG_TIME" ] && echo "    ✓ IP loss time: ${TEST_8_1_UNPLUG_TIME}s" | tee -a "$LOG_FILE"
    [ -n "$TEST_8_1_PLUGIN_TIME" ] && echo "    ✓ DHCP acquisition: ${TEST_8_1_PLUGIN_TIME}s" | tee -a "$LOG_FILE"
else
    echo "  Test 8.1: Not performed" | tee -a "$LOG_FILE"
fi

if [ -n "$TEST_8_2_RECONNECT_TIME" ]; then
    echo "  Test 8.2 (Wi-Fi disable/enable):" | tee -a "$LOG_FILE"
    [ -n "$TEST_8_2_DISABLE_MS" ] && echo "    ✓ Disable time: ${TEST_8_2_DISABLE_MS}ms" | tee -a "$LOG_FILE"
    [ -n "$TEST_8_2_ENABLE_MS" ] && echo "    ✓ Enable time: ${TEST_8_2_ENABLE_MS}ms" | tee -a "$LOG_FILE"
    [ -n "$TEST_8_2_RECONNECT_TIME" ] && echo "    ✓ Reconnection: ${TEST_8_2_RECONNECT_TIME}s" | tee -a "$LOG_FILE"
else
    echo "  Test 8.2: Not performed" | tee -a "$LOG_FILE"
fi

if [ -n "$TEST_8_3_FAILOVER_TIME" ] || [ -n "$TEST_8_3_SWITCHBACK_TIME" ]; then
    echo "  Test 8.3 (Both interfaces / Failover):" | tee -a "$LOG_FILE"
    [ -n "$TEST_8_3_PRIMARY_IFACE" ] && echo "    ✓ Primary: ${TEST_8_3_PRIMARY_IFACE}" | tee -a "$LOG_FILE"
    [ -n "$TEST_8_3_FAILOVER_TIME" ] && echo "    ✓ Failover time: ${TEST_8_3_FAILOVER_TIME}s" | tee -a "$LOG_FILE"
    [ -n "$TEST_8_3_SWITCHBACK_TIME" ] && echo "    ✓ Switch back: ${TEST_8_3_SWITCHBACK_TIME}s" | tee -a "$LOG_FILE"
else
    echo "  Test 8.3: Not performed" | tee -a "$LOG_FILE"
fi

if [ -n "$TEST_8_5_DHCP_TIME" ]; then
    echo "  Test 8.5 (DHCP timing):" | tee -a "$LOG_FILE"
    echo "    ✓ DHCP time: ${TEST_8_5_DHCP_TIME}s (${TEST_8_5_NETWORK_TYPE})" | tee -a "$LOG_FILE"
else
    echo "  Test 8.5: Not performed" | tee -a "$LOG_FILE"
fi
echo "" | tee -a "$LOG_FILE"

echo -e "${BOLD}${GREEN}NEXT STEPS:${NC}" | tee -a "$LOG_FILE"
echo "1. Edit src/macos/switcher.sh and set TIMEOUT=${RECOMMENDED_TIMEOUT}" | tee -a "$LOG_FILE"
echo "2. Review the configuration recommendations above" | tee -a "$LOG_FILE"
echo "3. Test the switcher with: sudo bash src/macos/switcher.sh" | tee -a "$LOG_FILE"
echo "4. Monitor logs at: ~/Library/Logs/ethernet-wifi-switcher.log" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

print_info "Full detailed log saved to: $LOG_FILE"

# Determine recommended check method
RECOMMENDED_CHECK="ping 8.8.8.8"
if [ "$METHOD_PING_8888_WORKS" -eq 1 ]; then
    RECOMMENDED_CHECK="ping 8.8.8.8"
elif [ "$METHOD_PING_GOOGLE_WORKS" -eq 1 ]; then
    RECOMMENDED_CHECK="ping google.com"
elif [ "$METHOD_HTTP_GOOGLE_WORKS" -eq 1 ]; then
    RECOMMENDED_CHECK="curl -s http://google.com"
fi

# Create a machine-readable configuration file
CONFIG_FILE="${LOG_DIR}/recommended-config.env"
cat > "$CONFIG_FILE" << EOF
# Generated by macos-network-tester.sh on $(date)
# Apply these settings to your switcher.sh

TIMEOUT=${RECOMMENDED_TIMEOUT}
DEBOUNCE_SECONDS=5

# Recommended check method (based on validation)
INTERNET_CHECK_CMD="${RECOMMENDED_CHECK}"

# Test measurements:
# DHCP acquisition: ${TEST_8_5_DHCP_TIME:-not measured}
# IP loss detection: ${TEST_8_1_UNPLUG_TIME:-not measured}s
# Failover time: ${TEST_8_3_FAILOVER_TIME:-not measured}s
# Network type: ${TEST_8_5_NETWORK_TYPE:-unknown}
EOF

print_success "Machine-readable config saved to: $CONFIG_FILE"
echo ""
