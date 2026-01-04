# Network Backend Modularization

## Status: Partially Complete

### Completed:
- ✅ Created modular backend system in `src/linux/lib/`:
  - `network-nmcli.sh` - NetworkManager/nmcli backend
  - `network-ip.sh` - ip command + rfkill fallback backend
- ✅ Updated build system to include backend files
- ✅ Updated install template to extract backend libraries
- ✅ Added backend detection and loading in switcher.sh
- ✅ Refactored interface detection functions to use backends

### Remaining Work:
The switcher.sh still has many hardcoded nmcli calls that need to be replaced with backend function calls:

1. **WiFi radio control** (lines ~249, 292, 330, 353, 359):
   - `nmcli radio wifi` → `is_wifi_enabled()`
   - `nmcli radio wifi on` → `enable_wifi()`
   - `nmcli radio wifi off` → `disable_wifi()`

2. **Interface state checking** (lines ~257, 285, 298, 321, 336, 348):
   - `nmcli device | grep "^$iface " | awk '{print $2/$3}'` → `get_iface_state()` or `is_ethernet_iface()`/`is_wifi_iface()`

3. **Event monitoring** (end of file):
   - `nmcli monitor` → `monitor_events()`

### Backend Functions Available:
Both backends provide these functions:
- `is_ethernet_iface(iface)` - Check if interface is ethernet
- `is_wifi_iface(iface)` - Check if interface is wifi
- `get_first_ethernet_iface()` - Get first ethernet interface
- `get_first_wifi_iface()` - Get first wifi interface
- `get_all_eth_devs()` - Get all ethernet devices
- `get_all_wifi_devs()` - Get all wifi devices
- `get_all_network_devs()` - Get all network devices
- `get_iface_state(iface)` - Get interface state (connected/disconnected/etc)
- `get_iface_ip(iface)` - Get IP address of interface
- `is_wifi_enabled()` - Check if wifi radio is enabled
- `enable_wifi()` - Enable wifi radio
- `disable_wifi()` - Disable wifi radio
- `monitor_events()` - Monitor network events (nmcli monitor or polling)

### Testing:
Once the remaining nmcli calls are replaced, the system should work on:
- ✅ Systems with NetworkManager (nmcli available)
- ✅ Systems without NetworkManager (using ip + rfkill fallback)
- ✅ Systems without rfkill (basic operation, but can't control wifi radio)

### Notes:
- The ip backend uses `/sys/class/net` for wireless detection
- The ip backend uses polling for event monitoring (no native event system)
- WiFi radio control requires rfkill when not using NetworkManager
