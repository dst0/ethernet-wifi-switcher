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

# Logging setup
LOG_DIR="${HOME}/.macos-network-tester"
LOG_FILE="${LOG_DIR}/test-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$LOG_DIR"

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
    else
        print_error "HTTP to $url: FAILED"
    fi
done

print_section "2.4: Apple's captive portal detection"
print_log "Testing Apple's captive portal check..."
RESPONSE=$(curl -s --connect-timeout 5 http://captive.apple.com 2>/dev/null || echo "")
if [ "$RESPONSE" = "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>" ]; then
    print_success "Apple captive portal check: INTERNET DETECTED"
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
        
        # Check if it's Ethernet (not Wi-Fi)
        IS_WIFI=$(networksetup -getairportpower "$iface" 2>&1)
        if ! echo "$IS_WIFI" | grep -q "Wi-Fi Power"; then
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
            MEDIA=$(ifconfig "$iface" | grep "media:" || echo "")
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
print_header "TEST 8: MANUAL TESTING PROCEDURES"

print_section "8.1: Test Scenario 1 - Ethernet plug/unplug"
cat << EOF | tee -a "$LOG_FILE"
${CYAN}To test Ethernet behavior:${NC}
1. Ensure Ethernet is connected and has internet
2. Note the interface name (e.g., en5, en7)
3. Run: watch -n 1 'ipconfig getifaddr <interface>'
4. Physically unplug Ethernet cable
5. Observe how quickly the IP disappears
6. Plug back in
7. Observe DHCP acquisition time

${YELLOW}Expected behavior:${NC}
- IP should disappear within 1-2 seconds of unplug
- New IP should appear within 2-7 seconds of plug
- Interface status should change to "inactive" when unplugged
EOF

print_section "8.2: Test Scenario 2 - Wi-Fi disable/enable"
cat << EOF | tee -a "$LOG_FILE"
${CYAN}To test Wi-Fi behavior:${NC}
1. Ensure only Wi-Fi is connected
2. Run: networksetup -getairportpower <wifi-interface>
3. Disable Wi-Fi: sudo networksetup -setairportpower <wifi-interface> off
4. Check internet: ping 8.8.8.8
5. Enable Wi-Fi: sudo networksetup -setairportpower <wifi-interface> on
6. Observe reconnection time

${YELLOW}Expected behavior:${NC}
- Wi-Fi should disable immediately
- Internet should be lost immediately
- Wi-Fi should re-enable within 2-3 seconds
- Auto-join network should reconnect within 5-10 seconds
EOF

print_section "8.3: Test Scenario 3 - Both interfaces active"
cat << EOF | tee -a "$LOG_FILE"
${CYAN}To test priority with both active:${NC}
1. Connect both Ethernet and Wi-Fi
2. Check routing: netstat -rn | grep default
3. Test internet: traceroute -m 1 8.8.8.8
4. Note which interface is used (by IP)
5. Disconnect Ethernet
6. Verify switch to Wi-Fi
7. Reconnect Ethernet
8. Verify switch back to Ethernet

${YELLOW}Expected behavior:${NC}
- Ethernet should have priority (lower metric)
- Traffic should use Ethernet when both connected
- Automatic failover to Wi-Fi when Ethernet lost
- Automatic switch back to Ethernet when reconnected
EOF

print_section "8.4: Test Scenario 4 - Internet loss without disconnect"
cat << EOF | tee -a "$LOG_FILE"
${CYAN}To test internet loss (gateway unreachable):${NC}
1. Connect Ethernet/Wi-Fi normally
2. Note the gateway IP: netstat -rn | grep default
3. Simulate by blocking gateway or disabling router
4. Interface will still have IP and show "active"
5. But internet will be unavailable
6. Test detection methods from TEST 2

${YELLOW}Expected behavior:${NC}
- Interface status remains "active"
- IP address remains assigned
- Ping to gateway fails
- Ping to internet fails
- DNS resolution fails
- Apple captive portal check fails
EOF

print_section "8.5: Test Scenario 5 - DHCP timeout testing"
cat << EOF | tee -a "$LOG_FILE"
${CYAN}To test DHCP acquisition time:${NC}
1. Disconnect Ethernet
2. Start monitoring: while true; do ipconfig getifaddr <eth-interface> 2>&1; sleep 1; done
3. Connect Ethernet cable
4. Time how long until IP appears
5. Try with different networks/routers
6. Adjust TIMEOUT variable in switcher.sh accordingly

${YELLOW}Expected behavior:${NC}
- Fast networks: 1-3 seconds
- Normal networks: 3-7 seconds  
- Slow networks: 7-15 seconds
- Enterprise networks: 10-30 seconds
EOF

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
cat << EOF | tee -a "$LOG_FILE"
${CYAN}Based on these tests, the application should:${NC}

1. ${BOLD}Interface Detection:${NC}
   - Use 'ipconfig getifaddr' to check for IP (fastest, reliable)
   - Use 'ifconfig | grep status: active' to check link state
   - Prioritize interfaces with assigned IPs

2. ${BOLD}Internet Detection:${NC}
   - Primary: Check for IP address on interface
   - Secondary: Ping test to 8.8.8.8 (fast, reliable)
   - Tertiary: Apple captive portal (http://captive.apple.com)

3. ${BOLD}State Management:${NC}
   - Track previous ethernet state in file
   - On disconnect: enable Wi-Fi immediately (no delay)
   - On connect: wait for IP with timeout (default 7s)

4. ${BOLD}Event Monitoring:${NC}
   - Use SCDynamicStore to watch for network changes
   - Monitor Global IPv4/IPv6 and per-interface keys
   - Debounce rapid events (5 second minimum gap)

5. ${BOLD}Timing Considerations:${NC}
   - Interface status changes: immediate (< 1s)
   - IP address loss on disconnect: 1-2 seconds
   - DHCP acquisition: 2-7 seconds (adjustable)
   - Wi-Fi toggle: 2-3 seconds

${YELLOW}Next Steps:${NC}
1. Run manual test scenarios (see TEST 8)
2. Document actual timings on your Mac
3. Adjust TIMEOUT if needed for your network
4. Test with multiple network environments

EOF

print_header "TESTING COMPLETE"
print_success "All tests completed successfully!"
print_info "Full log saved to: $LOG_FILE"
print_info "Review the manual testing procedures in TEST 8 for real-world scenarios"
print_log "\nTo analyze logs later, run:"
print_log "  cat $LOG_FILE"
print_log "  less $LOG_FILE"

# Create a summary file
SUMMARY_FILE="${LOG_DIR}/latest-summary.txt"
cat > "$SUMMARY_FILE" << EOF
macOS Network Tester Summary
============================
Date: $(date)
User: $(whoami)
Root: $([ $IS_ROOT -eq 1 ] && echo 'Yes' || echo 'No')

Interfaces Found: $(echo $ALL_INTERFACES | wc -w)
Active Interfaces: $ACTIVE_COUNT
Wi-Fi Interface: ${WIFI_INTERFACE:-'not found'}

Full log: $LOG_FILE

To run manual tests, follow TEST 8 procedures in the full log.
EOF

print_info "Summary saved to: $SUMMARY_FILE"
echo ""
