# macOS Network Tester

## 🧪 Purpose

This testing toolkit helps developers and users understand how macOS handles network interface switching in real-world scenarios. It's designed to:

- **Investigate** macOS network behavior with actual hardware
- **Measure** timing of network state changes
- **Test** various detection methods for reliability
- **Document** system-specific quirks and behaviors
- **Improve** the ethernet-wifi-switcher application with empirical data

## 📋 Why This Exists

The `ethernet-wifi-switcher` application makes assumptions about how macOS detects and handles network changes. Without real-world testing data, improvements can break working functionality. This tester provides a scientific approach to understanding network behavior before making code changes.

**Problem it solves:** Previous attempts to improve the application with tests failed because there was no baseline understanding of how macOS actually behaves in real scenarios.

## 🚀 Quick Start

### Run the Full Test Suite

```bash
# Make executable
chmod +x macos-network-tester.sh

# Run with sudo for full functionality
sudo bash macos-network-tester.sh
```

**Output:** Creates detailed logs in `~/.macos-network-tester/`

### View Results

```bash
# View summary
cat ~/.macos-network-tester/latest-summary.txt

# View full log
less ~/.macos-network-tester/test-*.log
```

## 📚 Documentation

Three comprehensive guides are provided:

### 1. **NETWORK-TESTING-GUIDE.md** (Comprehensive Guide)
- Complete testing methodology
- Detailed explanation of all tests
- Manual testing procedures
- Analysis techniques
- Advanced topics

[→ Read the Full Guide](./NETWORK-TESTING-GUIDE.md)

### 2. **QUICK-REFERENCE.md** (Quick Reference Card)
- Essential commands
- One-liners for quick tests
- Live monitoring scripts
- Common troubleshooting
- Interface names reference

[→ View Quick Reference](./QUICK-REFERENCE.md)

### 3. **macos-network-tester.sh** (Automated Test Script)
- Runs 9 categories of automated tests
- Tests 40+ different commands and scenarios
- Measures command performance
- Provides recommendations
- Colorized, logged output

## 🧬 What Gets Tested

The automated tester checks:

1. **Interface Discovery** - Find all network interfaces, identify Ethernet vs Wi-Fi
2. **Internet Connectivity** - Test multiple detection methods (ping, DNS, HTTP, captive portal)
3. **Interface State Monitoring** - Check status, link quality, routing
4. **Wi-Fi Management** - Test power controls, network listing, toggle commands
5. **Ethernet Detection** - Identify wired interfaces, check link status
6. **Multi-Interface Scenarios** - Handle multiple active connections, priority testing
7. **Network Change Events** - Monitor SCDynamicStore, system notifications
8. **Manual Test Procedures** - Step-by-step instructions for real-world scenarios
9. **Command Performance** - Measure execution speed of detection methods

## 🎯 Use Cases

### For Users

**Before installing ethernet-wifi-switcher:**
```bash
# Run tester to find your interface names
sudo bash macos-network-tester.sh

# Look for Wi-Fi and Ethernet interfaces in the output
# Use these names during installation
```

**Troubleshooting connection issues:**
```bash
# Run tester to diagnose problems
sudo bash macos-network-tester.sh

# Check logs for failures
cat ~/.macos-network-tester/latest-summary.txt
```

### For Developers

**Before making code changes:**
```bash
# Establish baseline behavior
sudo bash macos-network-tester.sh

# Document current timings and behaviors
# Make changes
# Test again to verify improvements
```

**Testing on new hardware/macOS versions:**
```bash
# Run full test suite
sudo bash macos-network-tester.sh

# Document any behavioral changes
# Adjust code if needed
```

## 🔍 Key Insights

The tester helps answer critical questions:

- **How fast** does macOS detect an unplugged Ethernet cable?
- **Which commands** reliably detect internet connectivity?
- **How long** does DHCP take on your network?
- **What happens** when both interfaces are active?
- **Which interface** gets priority for routing?
- **How quickly** can Wi-Fi be toggled?

## 📊 Example Output

```
========================================
macOS Network Interface Investigation Tester
========================================

ℹ Log file: /Users/user/.macos-network-tester/test-20260107-031500.log
ℹ Started at: Tue Jan  7 03:15:00 PST 2026
ℹ User: user
ℹ Root access: YES

========================================
TEST 1: INTERFACE DISCOVERY
========================================

--- 1.1: List all network interfaces ---

en0
en5
lo0
bridge0

--- 1.2: List interfaces using networksetup ---

Hardware Port: Wi-Fi
Device: en0

Hardware Port: Thunderbolt Ethernet
Device: en5

[... continues with detailed tests ...]

✓ Wi-Fi interface found: en0
✓ Ethernet interface: en5 has IP: 192.168.1.100
✓ Ping to 8.8.8.8: SUCCESS
✓ Apple captive portal check: INTERNET DETECTED

[... comprehensive test results ...]
```

## 🛠️ Manual Testing Scenarios

After running automated tests, perform these manual scenarios:

### Scenario 1: Ethernet Unplug Test
1. Monitor IP with: `watch -n 1 'ipconfig getifaddr en5'`
2. Unplug Ethernet cable
3. Time how long until IP disappears
4. Plug back in
5. Time DHCP acquisition

### Scenario 2: Wi-Fi Toggle Test
1. Disable: `sudo networksetup -setairportpower en0 off`
2. Verify internet lost: `ping 8.8.8.8`
3. Enable: `sudo networksetup -setairportpower en0 on`
4. Time reconnection

### Scenario 3: Priority Test
1. Connect both Ethernet and Wi-Fi
2. Check routing: `netstat -rn | grep default`
3. Start ping: `ping 8.8.8.8`
4. Unplug Ethernet, count lost packets
5. Reconnect, verify switch back

[→ See all scenarios in NETWORK-TESTING-GUIDE.md](./NETWORK-TESTING-GUIDE.md#manual-test-scenarios)

## 📈 Using Results to Improve

After running tests, you can:

1. **Optimize Timeout Values**
   ```bash
   # If your DHCP is slower
   TIMEOUT=10 sudo bash install-macos.sh
   ```

2. **Choose Best Detection Methods**
   - Use fastest reliable commands
   - Implement fallback detection
   - Reduce false positives

3. **Document System Behavior**
   - Hardware-specific quirks
   - Network-specific timings
   - Edge cases discovered

## 🐛 Troubleshooting

### Common Issues

**"Permission denied"**
- Run with `sudo`

**"Interface not found"**
- Check actual names with `ifconfig -a`
- Update commands accordingly

**"Wi-Fi toggle doesn't work"**
- Requires root privileges
- Verify interface name with `networksetup -listallhardwareports`

## 🤝 Contributing

If you discover interesting behaviors:

1. Save your test logs
2. Document your environment (macOS version, hardware, network type)
3. Note unusual timing patterns or edge cases
4. Share findings to help improve the application

## 📝 Files in This Toolkit

```
macos-network-tester.sh      - Main automated test script (executable)
NETWORK-TESTING-GUIDE.md     - Comprehensive testing guide (14KB)
QUICK-REFERENCE.md           - Quick reference card (6KB)
README-TESTER.md             - This file
```

## ⚡ Quick Commands

```bash
# Full automated test
sudo bash macos-network-tester.sh

# View results
cat ~/.macos-network-tester/latest-summary.txt

# Monitor live (paste in terminal)
watch -n 1 'for i in en0 en5; do echo "$i: $(ipconfig getifaddr $i 2>&1)"; done'

# Test internet connectivity
ping -c 3 8.8.8.8 && curl -s http://captive.apple.com

# Check interface status
ifconfig en5 | grep "status:"
```

## 🎓 Learning Outcomes

After using this tester, you'll understand:

- How macOS network stack actually works
- Timing considerations for detection
- Reliability of different commands
- System-specific behaviors
- How to make informed improvements

## 🔗 Related Files

- [Main README](./README.md) - Application documentation
- [NETWORK-TESTING-GUIDE.md](./NETWORK-TESTING-GUIDE.md) - Full testing guide
- [QUICK-REFERENCE.md](./QUICK-REFERENCE.md) - Command reference

## 📄 License

Part of the ethernet-wifi-switcher project. See [LICENSE](./LICENSE) for details.

---

**Happy Testing! 🧪**

Understanding your system's behavior is the first step to building reliable network switching automation.
