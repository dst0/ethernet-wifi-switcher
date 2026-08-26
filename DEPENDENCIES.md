# Dependency Requirements and Limited Functionality

## Overview

This document explains what dependencies are required, what happens when they're missing, and exactly which features are affected.

## Linux Dependencies

### Critical (Installation Blocked Without These)

| Dependency | Purpose | When Missing |
|------------|---------|--------------|
| **NetworkManager (nmcli)** OR **iproute2 (ip)** | Network interface detection and management | Cannot detect or manage network interfaces at all |
| **rfkill** (only if nmcli is missing) | WiFi radio control when using ip backend | Cannot enable/disable WiFi radio - core functionality broken |
| **systemd** | Service management and auto-start | Cannot install as a system service |

### Optional (Installation Continues With Warnings)

| Dependency | Purpose | Limited Functionality When Missing |
|------------|---------|-----------------------------------|
| **ping** | Internet connectivity monitoring | ❌ **Cannot use internet monitoring feature**<br>• `CHECK_INTERNET=1` won't work with `CHECK_METHOD=gateway` or `CHECK_METHOD=ping`<br>• Only basic interface state detection available<br>• No automatic failover based on internet connectivity<br>• Falls back to interface state only (connected/disconnected) |
| **curl** | HTTP/HTTPS connectivity checks | ❌ **Cannot use HTTP connectivity checks**<br>• `CHECK_METHOD=curl` won't work<br>• Cannot detect captive portals via HTTP<br>• Gateway ping and manual ping targets still work |

## macOS Dependencies

### Critical (Installation Blocked Without These)

| Dependency | Purpose | When Missing |
|------------|---------|--------------|
| **networksetup** | Network interface management | Cannot manage network interfaces - macOS system corrupted |
| **ipconfig** | IP address detection | Cannot detect IP addresses - macOS system corrupted |
| **Swift compiler** | Compile network watcher | Cannot build the watcher binary that monitors network events |
| **launchctl** | Service management | Cannot install as a system service |

### Optional (Installation Continues With Warnings)

| Dependency | Purpose | Limited Functionality When Missing |
|------------|---------|-----------------------------------|
| **ping** | Internet connectivity monitoring | ❌ **Cannot use internet monitoring feature**<br>• `CHECK_INTERNET=1` won't work properly<br>• Only basic interface state detection available<br>• No automatic failover based on internet connectivity |
| **curl** | HTTP/HTTPS connectivity checks | ❌ **Cannot use HTTP connectivity checks**<br>• Cannot detect captive portals<br>• Basic connectivity checks still work |

## Windows Dependencies

### Built-in (Should Always Be Available)

| Dependency | Purpose |
|------------|---------|
| **PowerShell** | Script execution and system management |
| **netsh** | Network interface management |
| **Test-Connection** | Connectivity testing |

## Detailed Impact Analysis

### Missing `ping` (Most Common Optional Dependency)

**What Still Works:**
- ✅ Basic ethernet/wifi switching based on cable connection
- ✅ Interface state detection (connected/disconnected)
- ✅ WiFi radio control
- ✅ Event-driven switching when cable is plugged/unplugged

**What Doesn't Work:**
- ❌ Internet connectivity monitoring (`CHECK_INTERNET=1`)
- ❌ Automatic failover when ethernet has no internet
- ❌ Gateway ping checks (`CHECK_METHOD=gateway`)
- ❌ Custom ping target checks (`CHECK_METHOD=ping`)
- ❌ Detecting "connected but no internet" scenarios

**Use Case Impact:**
- **Simple setups** (just switch when cable is plugged/unplugged): ✅ **No impact**
- **Advanced setups** (monitor internet and failover): ❌ **Major impact** - this is the primary use case for the new features

### Missing `curl`

**What Still Works:**
- ✅ All basic functionality
- ✅ Internet monitoring with ping/gateway methods
- ✅ All switching logic

**What Doesn't Work:**
- ❌ HTTP/HTTPS connectivity checks (`CHECK_METHOD=curl`)
- ❌ Captive portal detection via HTTP probes
- ❌ Custom HTTP endpoint monitoring

**Use Case Impact:**
- **Most users**: ✅ **No impact** (gateway/ping methods are recommended anyway)
- **Corporate/captive portal scenarios**: ⚠️ **Minor impact** (may need HTTP checks for special cases)

### Missing `rfkill` (Linux without NetworkManager)

**Impact:** This is CRITICAL when NetworkManager is not available because:
- ❌ Cannot enable/disable WiFi radio
- ❌ Core functionality completely broken
- ❌ WiFi will either stay always on or always off

This is why `rfkill` is now a **critical dependency** when using the `ip` backend.

## Recommendation

### For Basic Use (Just Cable Switching)
**Required only:**
- Linux: `nmcli` OR `ip`, `systemd`
- macOS: Built-in tools + Xcode Command Line Tools
- Optional dependencies: Not needed

### For Internet Monitoring (New Features)
**Required:**
- Linux: `nmcli` OR (`ip` + `rfkill`), `systemd`, **`ping`**
- macOS: Built-in tools + Xcode Command Line Tools + **`ping`**
- Optional: `curl` (for HTTP checks)

## Installation Behavior

### Interactive Mode (Default)
1. **Critical dependencies missing + User accepts install** → Installs automatically, continues
2. **Critical dependencies missing + User declines** → Installation cancelled with explanation
3. **Optional dependencies missing + User accepts install** → Installs automatically, continues
4. **Optional dependencies missing + User declines** → Continues with warning about limited functionality

### Non-Interactive Mode
**Without AUTO_INSTALL_DEPS:**
- Blocks on critical dependencies (with clear error message)
- Continues with optional dependencies missing

**With AUTO_INSTALL_DEPS:**
```bash
# Linux: Auto-install all missing dependencies
sudo AUTO_INSTALL_DEPS=1 sh install.sh

# macOS: Cannot auto-install Xcode (requires dialog interaction)
# But will proceed if Xcode is already installed
sudo AUTO_INSTALL_DEPS=1 sh install.sh
```

**Behavior with AUTO_INSTALL_DEPS=1:**
- **Linux**: Automatically installs all missing dependencies (critical + optional)
  - Uses appropriate package manager (apt, dnf, pacman, etc.)
  - Defaults to NetworkManager when both nmcli and ip are missing
  - Installs without prompts
- **macOS**:
  - Cannot auto-install Xcode Command Line Tools (requires GUI dialog)
  - Must be pre-installed or user must run installer interactively
  - Alternative: Pre-install via Homebrew (`brew install swift`)

### Environment Variables

| Variable | Values | Default | Description |
|----------|--------|---------|-------------|
| `AUTO_INSTALL_DEPS` | `0` or `1` | `0` | Enable automatic dependency installation in non-interactive mode |
| `ETHERNET_INTERFACE` | Interface name | Auto-detect | Override ethernet interface detection |
| `WIFI_INTERFACE` | Interface name | Auto-detect | Override wifi interface detection |
| `CHECK_INTERNET` | `0` or `1` | `0` | Enable internet connectivity monitoring |
| `CHECK_METHOD` | `gateway`, `ping`, `curl` | `gateway` | Connectivity check method |
| `CHECK_TARGET` | IP/domain/URL | Auto | Target for ping/curl checks |
| `CHECK_INTERVAL` | Seconds | `30` | Interval between connectivity checks |
| `TIMEOUT` | Seconds | `7` | DHCP timeout for IP acquisition |

