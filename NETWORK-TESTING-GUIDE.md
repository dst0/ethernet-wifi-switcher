# macOS Network Interface Testing Guide

## Overview

This guide provides a comprehensive testing framework for investigating how macOS handles network interface switching, internet connectivity detection, and behavior with multiple network connections. It's designed to help gather real-world data that can be used to improve the `ethernet-wifi-switcher` application.

## Why This Tester Exists

When developing network switching applications, it's crucial to understand:
- How quickly macOS detects network changes
- Which detection methods are most reliable
- How the OS prioritizes multiple interfaces
- Timing considerations for DHCP and link detection
- Real-world behavior vs. theoretical assumptions

Without this baseline data, improvements can inadvertently break working functionality. This tester helps gather empirical evidence about macOS network behavior.

## Quick Start

### Prerequisites

- macOS system (tested on 10.14+)
- Terminal access
- Sudo privileges (for full testing capabilities)
- Ethernet and Wi-Fi interfaces available

### Running the Tester

1. **Make the script executable:**
   ```bash
   chmod +x macos-network-tester.sh
   ```

2. **Run with sudo for full functionality:**
   ```bash
   sudo bash macos-network-tester.sh
   ```

3. **Or run without sudo (limited tests):**
   ```bash
   bash macos-network-tester.sh
   ```

### Output

The tester creates a log directory at `~/.macos-network-tester/` with:
- Detailed test logs: `test-YYYYMMDD-HHMMSS.log`
- Summary file: `latest-summary.txt`

## What the Tester Checks

### Test Categories

#### 1. **Interface Discovery**
- Lists all network interfaces
- Identifies Ethernet vs Wi-Fi interfaces
- Detects which interfaces have IP addresses
- Shows interface status (active/inactive)

**Key Commands Tested:**
```bash
ifconfig -a
networksetup -listallhardwareports
ipconfig getifaddr <interface>
```

#### 2. **Internet Connectivity Detection**
- Ping tests to reliable hosts (8.8.8.8, 1.1.1.1, Google)
- DNS resolution tests
- HTTP connectivity tests
- Apple's captive portal detection
- Default route checking

**Key Commands Tested:**
```bash
ping -c 2 -W 3 8.8.8.8
nslookup google.com
curl -s http://captive.apple.com
netstat -rn | grep default
```

#### 3. **Interface State Monitoring**
- Interface up/down status
- Link quality metrics
- SCDynamicStore network state
- Service order and priorities

**Key Commands Tested:**
```bash
ifconfig <interface> | grep "status:"
scutil --nc list
networksetup -listnetworkserviceorder
```

#### 4. **Wi-Fi Management**
- Detects Wi-Fi interface
- Checks Wi-Fi power state
- Lists current and preferred networks
- Tests Wi-Fi toggle commands (requires sudo)

**Key Commands Tested:**
```bash
networksetup -getairportpower <interface>
networksetup -setairportpower <interface> on|off
networksetup -getairportnetwork <interface>
```

#### 5. **Ethernet Detection**
- Identifies Ethernet interfaces
- Checks link status
- Measures IP acquisition
- Media/speed information

**Key Commands Tested:**
```bash
ifconfig <interface> | grep "status: active"
ipconfig getifaddr <interface>
```

#### 6. **Multi-Interface Scenarios**
- Counts active interfaces
- Checks routing priorities
- Identifies which interface handles traffic

**Key Commands Tested:**
```bash
netstat -rn | grep default
networksetup -listnetworkserviceorder
```

#### 7. **Network Change Event Detection**
- SCDynamicStore keys for monitoring
- Current network state from scutil
- Interface-specific state information

**Key Commands Tested:**
```bash
echo "show State:/Network/Global/IPv4" | scutil
echo "show State:/Network/Interface/<interface>/IPv4" | scutil
```

#### 8. **Manual Testing Procedures**
Detailed step-by-step instructions for:
- Ethernet plug/unplug testing
- Wi-Fi disable/enable testing
- Multi-interface priority testing
- Internet loss detection (without physical disconnect)
- DHCP timeout measurement

#### 9. **Command Performance**
Measures execution time of key commands to identify the fastest detection methods.

## Manual Test Scenarios

After running the automated tests, perform these manual scenarios:

### Scenario 1: Ethernet Plug/Unplug

**Purpose:** Measure how quickly macOS detects physical Ethernet changes.

**Steps:**
```bash
# 1. Find your Ethernet interface
networksetup -listallhardwareports | grep -A 1 Ethernet

# 2. Monitor IP address in real-time
watch -n 1 'ipconfig getifaddr en5'  # Replace en5 with your interface

# 3. Unplug Ethernet cable and observe
# 4. Plug back in and time DHCP acquisition
```

**Expected Results:**
- IP disappears within 1-2 seconds of unplug
- New IP appears within 2-7 seconds of plug
- Interface status changes immediately

**Document:**
- Your actual timing measurements
- Any delays or anomalies
- Network-specific variations

### Scenario 2: Wi-Fi Toggle

**Purpose:** Measure Wi-Fi enable/disable timing and reliability.

**Steps:**
```bash
# 1. Ensure Wi-Fi is your only connection
# 2. Check current state
networksetup -getairportpower en0  # Replace en0 with your Wi-Fi interface

# 3. Turn off
sudo networksetup -setairportpower en0 off

# 4. Verify internet is down
ping -c 3 8.8.8.8

# 5. Turn on
sudo networksetup -setairportpower en0 on

# 6. Time reconnection to network
```

**Expected Results:**
- Disable: Immediate (< 1 second)
- Enable: 2-3 seconds
- Auto-join reconnection: 5-10 seconds

**Document:**
- Actual timing
- Whether auto-join works
- Any connection failures

### Scenario 3: Both Interfaces Active

**Purpose:** Understand interface priority and failover.

**Steps:**
```bash
# 1. Connect both Ethernet and Wi-Fi
# 2. Check which is used
netstat -rn | grep default
traceroute -m 1 8.8.8.8

# 3. Monitor during transitions
sudo tcpdump -i any -n host 8.8.8.8 &
ping 8.8.8.8

# 4. Unplug Ethernet while pinging
# 5. Observe failover behavior
# 6. Reconnect Ethernet
# 7. Observe priority restoration
```

**Expected Results:**
- Ethernet preferred when both active
- Seamless failover to Wi-Fi (1-2 lost pings)
- Automatic switch back to Ethernet

**Document:**
- Packet loss during transitions
- Failover timing
- Any routing anomalies

### Scenario 4: Internet Loss Without Disconnect

**Purpose:** Test detection of internet failure when interface remains "active".

**Setup:**
```bash
# This requires one of:
# - Disconnecting router from internet
# - Blocking gateway MAC on router
# - Using network link conditioner
# - Firewall rules
```

**Steps:**
```bash
# 1. Note your gateway
netstat -rn | grep default

# 2. Cause internet failure at gateway/router level
# 3. Observe interface still shows "active"
ifconfig en5 | grep status

# 4. Test detection methods
ping -c 3 8.8.8.8                    # Should fail
ping -c 3 <gateway-ip>               # May succeed or fail
curl -s http://captive.apple.com     # Should fail
nslookup google.com                  # Should fail

# 5. Time how long to detect failure
```

**Expected Results:**
- Interface status: still "active"
- IP address: still assigned
- Gateway ping: may work or fail
- Internet ping: fails
- DNS: fails
- HTTP: fails

**Document:**
- Which detection method is fastest
- Reliability of each method
- False positive scenarios

### Scenario 5: DHCP Timeout Measurement

**Purpose:** Determine appropriate timeout values for your networks.

**Steps:**
```bash
# 1. Disconnect Ethernet
# 2. Start timing script
while true; do
    TIME=$(date +%s)
    IP=$(ipconfig getifaddr en5 2>&1)
    echo "[$TIME] $IP"
    sleep 1
done

# 3. Connect Ethernet
# 4. Note when IP appears
# 5. Repeat on different networks
```

**Networks to Test:**
- Home network
- Office/enterprise network  
- Public Wi-Fi hotspot
- Mobile hotspot
- Different router brands

**Document:**
- Fastest acquisition time
- Slowest acquisition time
- Average for each network type
- Recommended timeout value

## Analyzing Results

### Reading the Log Files

```bash
# View the latest test log
cat ~/.macos-network-tester/test-*.log | tail -1

# View summary
cat ~/.macos-network-tester/latest-summary.txt

# Search for specific information
grep "Interface" ~/.macos-network-tester/test-*.log
grep "SUCCESS\|FAILED" ~/.macos-network-tester/test-*.log
```

### Key Metrics to Extract

1. **Interface Detection Speed:**
   - Which commands are fastest?
   - Which are most reliable?
   - Any that give false positives/negatives?

2. **Connectivity Detection:**
   - Which method detects internet loss fastest?
   - Which has no false positives?
   - Tradeoff between speed and reliability?

3. **Timing Values:**
   - Interface state change: ___ seconds
   - IP loss on disconnect: ___ seconds
   - DHCP acquisition: ___ seconds (min/max/avg)
   - Wi-Fi toggle: ___ seconds

4. **System Behavior:**
   - Default routing priority
   - Failover timing
   - Unexpected edge cases

## Improving ethernet-wifi-switcher

### Using Test Results

Based on your test results, you can:

1. **Adjust Timeouts:**
   ```bash
   # If your DHCP is slower than 7 seconds
   TIMEOUT=10 sudo bash install-macos.sh
   ```

2. **Optimize Detection:**
   - Use fastest reliable commands
   - Add fallback detection methods
   - Reduce false positive triggers

3. **Improve State Logic:**
   - Adjust debounce timing
   - Handle edge cases discovered
   - Better multi-interface handling

4. **Document Quirks:**
   - Network-specific behaviors
   - Hardware variations
   - macOS version differences

### Recommended Configuration

After testing, document your optimal settings:

```bash
# Example: Fast home network
WIFI_DEV=en0
ETH_DEV=en5
TIMEOUT=5
```

```bash
# Example: Slow enterprise network
WIFI_DEV=en0
ETH_DEV=en7
TIMEOUT=15
```

## Troubleshooting

### Common Issues

**Issue:** "Permission denied" errors
- **Solution:** Run with `sudo bash macos-network-tester.sh`

**Issue:** Interface not detected
- **Solution:** Check `ifconfig -a` for actual interface names, update commands accordingly

**Issue:** Wi-Fi toggle doesn't work
- **Solution:** Requires root privileges, check `networksetup -listallhardwareports` for correct interface name

**Issue:** Tests fail on different macOS versions
- **Solution:** Some commands may vary by version, document your macOS version in results

### Getting Help

If you discover unexpected behavior:

1. Save the full test log
2. Document your macOS version: `sw_vers`
3. Document your hardware: `system_profiler SPNetworkDataType`
4. Note any error messages
5. Include manual test results

## Contributing Test Results

Help improve the application by sharing your findings:

1. **Document Your Environment:**
   - macOS version
   - Hardware model
   - Network types tested
   - Router brands/models

2. **Share Key Findings:**
   - Unusual timing patterns
   - Edge cases discovered
   - Commands that work better/worse
   - Network-specific quirks

3. **Suggest Improvements:**
   - Better detection methods
   - Optimized timeouts
   - Additional test scenarios
   - Code improvements

## Advanced Testing

### Automated Long-Term Monitoring

Create a monitoring script:

```bash
#!/bin/bash
# Save as monitor-network.sh

while true; do
    echo "=== $(date) ==="
    
    # Check interfaces
    for iface in en0 en5; do
        IP=$(ipconfig getifaddr $iface 2>/dev/null || echo "no-ip")
        STATUS=$(ifconfig $iface 2>/dev/null | grep "status:" | awk '{print $2}')
        echo "$iface: IP=$IP STATUS=$STATUS"
    done
    
    # Check internet
    if ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
        echo "Internet: OK"
    else
        echo "Internet: DOWN"
    fi
    
    echo ""
    sleep 5
done
```

Run during your work day to capture transition events naturally.

### Network Simulation

Use **Network Link Conditioner** (part of Xcode Additional Tools):
- Simulate packet loss
- Add latency
- Limit bandwidth
- Test various network conditions

### Packet Capture

Monitor traffic during transitions:

```bash
# Capture all network traffic
sudo tcpdump -i any -w /tmp/network-capture.pcap

# Analyze with Wireshark later
# Look for:
# - DHCP request/response timing
# - DNS query patterns
# - Default gateway changes
# - Packet loss during transitions
```

## Reference

### Useful macOS Network Commands

```bash
# Interface management
ifconfig <interface> up|down
networksetup -setairportpower <interface> on|off

# Network information
ipconfig getifaddr <interface>           # Get IP
ipconfig getpacket <interface>           # Get DHCP info
networksetup -getinfo <service>          # Get service info

# Routing
netstat -rn                              # Show routes
route get <ip>                           # Get route to IP

# DNS
scutil --dns                             # Show DNS config
networksetup -getdnsservers <service>    # Get DNS servers

# Advanced
scutil                                   # Interactive network config
airport -I                               # Wi-Fi info (if installed)
```

### SCDynamicStore Keys

Monitor these keys for network changes:

```bash
State:/Network/Global/IPv4              # Global IPv4 state
State:/Network/Global/IPv6              # Global IPv6 state
State:/Network/Interface/<if>/IPv4      # Per-interface IPv4
State:/Network/Interface/<if>/IPv6      # Per-interface IPv6
State:/Network/Interface/<if>/Link      # Link state
Setup:/Network/Service/<svc>/IPv4       # Service configuration
```

### Exit Codes

The tester returns:
- `0`: All tests completed (check log for individual results)
- `1`: Critical error prevented testing

## Conclusion

This testing framework provides the foundation for making informed decisions about network switching logic. By gathering real-world data about your specific hardware, networks, and use cases, you can:

- Optimize timeout values
- Choose the most reliable detection methods
- Handle edge cases appropriately
- Avoid regressions when making changes

Remember: Real-world testing beats theoretical assumptions. Always validate changes with this tester before deploying to production.

---

**Last Updated:** January 2026  
**Compatible with:** macOS 10.14+  
**For:** ethernet-wifi-switcher project
