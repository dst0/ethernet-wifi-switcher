# macOS Network Testing - Quick Reference Card

## Quick Commands for Live Testing

### 1. Find Your Interfaces
```bash
# List all interfaces
ifconfig -a | grep '^[a-z]' | cut -d: -f1

# Find Wi-Fi interface
networksetup -listallhardwareports | grep -A 1 Wi-Fi

# Find Ethernet interfaces (usually en5, en7, etc.)
networksetup -listallhardwareports | grep -A 1 "Thunderbolt Ethernet\|USB Ethernet\|Ethernet"
```

### 2. Check Interface Status
```bash
# Quick status check
ifconfig <interface> | grep "status:"

# Check if has IP
ipconfig getifaddr <interface>

# Full interface details
ifconfig <interface>
```

### 3. Monitor in Real-Time
```bash
# Watch IP address (install with: brew install watch)
watch -n 1 'ipconfig getifaddr en5'

# Monitor all interfaces
watch -n 1 'for i in en0 en5; do echo "$i: $(ipconfig getifaddr $i 2>&1)"; done'

# Continuous ping while testing
ping 8.8.8.8

# Monitor interface status
watch -n 1 'ifconfig en5 | grep -E "status:|inet "'
```

### 4. Test Internet Connectivity
```bash
# Fast ping test
ping -c 3 -W 2 8.8.8.8

# Apple captive portal check (most reliable)
curl -s http://captive.apple.com

# DNS test
nslookup google.com

# Check routing
netstat -rn | grep default
```

### 5. Wi-Fi Control
```bash
# Check Wi-Fi state
networksetup -getairportpower en0

# Turn Wi-Fi off
sudo networksetup -setairportpower en0 off

# Turn Wi-Fi on
sudo networksetup -setairportpower en0 on

# Current network
networksetup -getairportnetwork en0
```

### 6. Live Testing Script
```bash
# Copy and paste this for live monitoring
echo "Starting network monitor..."
while true; do
    clear
    echo "=== Network Status at $(date +%H:%M:%S) ==="
    echo ""
    
    # Ethernet
    ETH="en5"  # Change to your interface
    ETH_IP=$(ipconfig getifaddr $ETH 2>&1 || echo "no-ip")
    ETH_STATUS=$(ifconfig $ETH 2>/dev/null | grep "status:" | awk '{print $2}')
    echo "Ethernet ($ETH): IP=$ETH_IP Status=$ETH_STATUS"
    
    # Wi-Fi
    WIFI="en0"  # Change to your interface
    WIFI_IP=$(ipconfig getifaddr $WIFI 2>&1 || echo "no-ip")
    WIFI_POWER=$(networksetup -getairportpower $WIFI 2>&1 | awk '{print $NF}')
    echo "Wi-Fi ($WIFI): IP=$WIFI_IP Power=$WIFI_POWER"
    
    # Internet
    if ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
        echo "Internet: ✓ CONNECTED"
    else
        echo "Internet: ✗ DISCONNECTED"
    fi
    
    # Route
    DEFAULT=$(netstat -rn | grep default | head -1 | awk '{print $2, $6}')
    echo "Default route: $DEFAULT"
    
    echo ""
    echo "Press Ctrl+C to stop"
    sleep 2
done
```

## Test Procedures

### Test 1: Ethernet Unplug
1. Run monitor script above
2. Note current state
3. Unplug Ethernet cable
4. Watch how fast IP disappears
5. Plug back in
6. Time DHCP acquisition

**Expected:** 
- Unplug detection: < 2 seconds
- IP acquisition: 2-7 seconds

### Test 2: Wi-Fi Toggle
1. Ensure only Wi-Fi connected
2. Run: `sudo networksetup -setairportpower en0 off`
3. Verify internet lost: `ping 8.8.8.8`
4. Run: `sudo networksetup -setairportpower en0 on`
5. Time until auto-reconnect

**Expected:**
- Toggle time: < 3 seconds
- Reconnect: 5-10 seconds

### Test 3: Priority Test
1. Connect both Ethernet and Wi-Fi
2. Check which is used: `netstat -rn | grep default`
3. Start continuous ping: `ping 8.8.8.8`
4. Unplug Ethernet
5. Count lost packets (should be 1-2)
6. Reconnect Ethernet
7. Verify switch back

**Expected:**
- Ethernet has priority
- Quick failover (1-2 lost pings)
- Auto switch back

### Test 4: DHCP Timing
1. Disconnect Ethernet
2. Start: `time (while ! ipconfig getifaddr en5 >/dev/null 2>&1; do sleep 0.1; done)`
3. Connect Ethernet immediately
4. Note time to get IP
5. Repeat 5 times for average

**Document:** min/avg/max times for your network

## Troubleshooting Commands

### Interface Issues
```bash
# Reset interface (if stuck)
sudo ifconfig en5 down
sudo ifconfig en5 up

# Renew DHCP
sudo ipconfig set en5 DHCP

# Clear DNS cache
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

### Check Running Switcher
```bash
# macOS service status
sudo launchctl list | grep wifi

# View logs
tail -f ~/.ethernet-wifi-auto-switcher/*.log

# Restart service
sudo launchctl unload ~/Library/LaunchDaemons/com.eth-wifi-auto.plist
sudo launchctl load ~/Library/LaunchDaemons/com.eth-wifi-auto.plist
```

### System Information
```bash
# macOS version
sw_vers

# Network hardware
system_profiler SPNetworkDataType

# All network services
networksetup -listnetworkserviceorder
```

## Common Interface Names

- `en0` - Usually Wi-Fi
- `en1` - Sometimes Thunderbolt/Ethernet
- `en5` - USB/Thunderbolt Ethernet
- `en7` - Additional Ethernet
- `bridge0` - Network bridge
- `lo0` - Loopback

**Find yours:** `networksetup -listallhardwareports`

## One-Liners for Quick Tests

```bash
# Test all interfaces for IP
for i in $(ifconfig -a | grep '^[a-z]' | cut -d: -f1); do echo "$i: $(ipconfig getifaddr $i 2>&1)"; done

# Show active interfaces only
for i in $(ifconfig -a | grep '^[a-z]' | cut -d: -f1); do ifconfig $i | grep -q "status: active" && echo "$i is active"; done

# Quick connectivity test (all methods)
echo "Ping:" && ping -c 1 -W 1 8.8.8.8 >/dev/null && echo "OK" || echo "FAIL"
echo "DNS:" && nslookup google.com >/dev/null 2>&1 && echo "OK" || echo "FAIL"
echo "HTTP:" && curl -s --connect-timeout 2 http://captive.apple.com >/dev/null && echo "OK" || echo "FAIL"

# Measure command speed
for cmd in "ipconfig getifaddr en0" "ifconfig en0" "networksetup -getairportpower en0"; do
    time (for i in {1..10}; do eval $cmd >/dev/null 2>&1; done)
done
```

## Tips

1. **Always test on your actual hardware/network** - timings vary
2. **Document your specific interface names** - they differ per Mac
3. **Test with your actual router** - DHCP timing varies
4. **Run tests when first setting up** - get baseline measurements
5. **Retest after macOS updates** - behavior can change
6. **Test on different networks** - home, office, public WiFi

## Getting Detailed Logs

```bash
# Run full tester
sudo bash macos-network-tester.sh

# View results
cat ~/.macos-network-tester/latest-summary.txt
less ~/.macos-network-tester/test-*.log
```

---

**Quick Start:** Just run `sudo bash macos-network-tester.sh` for comprehensive automated tests!
