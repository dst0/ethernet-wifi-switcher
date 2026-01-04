# Ethernet Wi-Fi Switcher

[![Release](https://img.shields.io/github/v/release/dst0/ethernet-wifi-switcher)](https://github.com/dst0/ethernet-wifi-switcher/releases)
[![Build Status](https://github.com/dst0/ethernet-wifi-switcher/actions/workflows/release.yml/badge.svg)](https://github.com/dst0/ethernet-wifi-switcher/actions)
[![License](https://img.shields.io/badge/license-Proprietary-blue.svg)](LICENSE)
[![EMF Safe](https://img.shields.io/badge/EMF-Safe-success)](#environmental-and-health-impact)
[![Energy Efficient](https://img.shields.io/badge/Energy-Efficient-success)](#environmental-and-health-impact)

[![Support Ukraine](https://img.shields.io/badge/Support-Ukraine-FFD700?style=flat&labelColor=0057B7)](https://standforukraine.com/)

This tool automatically manages your Wi-Fi connection based on Ethernet availability across **macOS, Linux, and Windows**. It ensures that Wi-Fi is turned off when a stable Ethernet connection is detected and turned back on when Ethernet is disconnected.

> **Note:** The macOS version is the most actively maintained and tested platform, as it's primarily used by the author. It provides the most reliable experience.

## 🚀 Quick Install (One-Liner)

Choose your platform and run the command in your terminal:

### macOS
```bash
# Interactive installation (recommended for first-time users)
curl -fsSL https://github.com/dst0/ethernet-wifi-switcher/releases/latest/download/install-macos.sh | sudo bash

# Quick install with all defaults (auto-detects interfaces, enables internet monitoring)
curl -fsSL https://github.com/dst0/ethernet-wifi-switcher/releases/latest/download/install-macos.sh | sudo bash -s -- --auto
```
> **Note:** `curl` is required and should be pre-installed on macOS. It's critical for multi-interface internet monitoring.
> Use `--auto` or `--defaults` for hands-free installation with recommended settings.

### Linux
```bash
# Interactive installation (recommended for first-time users)
curl -fsSL https://github.com/dst0/ethernet-wifi-switcher/releases/latest/download/install-linux.sh | sudo bash

# Quick install with all defaults (auto-installs dependencies, enables internet monitoring)
curl -fsSL https://github.com/dst0/ethernet-wifi-switcher/releases/latest/download/install-linux.sh | sudo bash -s -- --auto
```
> **Note:** If `curl` is not installed: `sudo apt install curl` or `sudo yum install curl`
> Use `--auto` or `--defaults` for hands-free installation with automatic dependency installation.

### Windows (PowerShell Admin)
**Important:** Right-click PowerShell → "Run as administrator" before running this command.

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; curl -Uri https://github.com/dst0/ethernet-wifi-switcher/releases/latest/download/install-windows.ps1 -UseBasicParsing | iex
```
> **Note:** All required tools are built into Windows - no additional dependencies needed.

---

## 📦 Downloads

You can download the latest pre-packaged versions from the [Releases](https://github.com/dst0/ethernet-wifi-switcher/releases) page:

- 🍎 **macOS**: [install-macos.sh](https://github.com/dst0/ethernet-wifi-switcher/releases/latest/download/install-macos.sh)
- 🐧 **Linux**: [install-linux.sh](https://github.com/dst0/ethernet-wifi-switcher/releases/latest/download/install-linux.sh)
- 🪟 **Windows**: [install-windows.ps1](https://github.com/dst0/ethernet-wifi-switcher/releases/latest/download/install-windows.ps1)

## 🪟 Windows PowerShell Execution Policy

By default, Windows blocks PowerShell script execution for security. **You must run PowerShell as Administrator** and use `-ExecutionPolicy Bypass` to install.

**Quick Install (recommended):**

1. **Open PowerShell as Administrator:**
   - Press `Win + X` → Select "Windows PowerShell (Admin)" or "Terminal (Admin)"
   - Or: Search "PowerShell" → Right-click → "Run as administrator"

2. **Run the install command:**
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; curl -Uri https://github.com/dst0/ethernet-wifi-switcher/releases/latest/download/install-windows.ps1 -UseBasicParsing | iex
```

> Use `-Auto` or `-Defaults` for hands-free installation with recommended settings.

**What this does:**
- ✅ Safe: Only affects the current PowerShell window
- ✅ Temporary: Reverts when you close PowerShell
- ✅ No permanent changes to your system security settings

**After installation - the service will work automatically:**
The scheduled task is configured with `-ExecutionPolicy Bypass` built into its command and runs as SYSTEM account. This means:
- ✅ The background service runs automatically on login
- ✅ Works on ALL systems regardless of execution policy settings
- ✅ No manual intervention needed after installation
- ✅ Survives reboots and continues working

**Alternative: Download and run manually**

If you prefer not to use the one-liner, download the script and run it:

1. Download [install-windows.ps1](https://github.com/dst0/ethernet-wifi-switcher/releases/latest/download/install-windows.ps1)
2. **Open PowerShell as Administrator** (see step 1 above)
3. Navigate to the download folder: `cd ~/Downloads`
4. Run:
```powershell
# Interactive mode (prompts for configuration)
powershell.exe -ExecutionPolicy Bypass -File ".\install-windows.ps1"

# Auto mode (uses recommended defaults)
powershell.exe -ExecutionPolicy Bypass -File ".\install-windows.ps1" -Auto
```

**Note:** Do NOT double-click the .ps1 file - it will fail due to execution policy. Always run from PowerShell with `-ExecutionPolicy Bypass`.

---

## Environmental and Health Impact

This application is designed to optimize energy efficiency and minimize the user's exposure to non-ionizing electromagnetic radiation (EMF). By automating the deactivation of the Wi-Fi radio when a wired connection is available, the software:
- **Reduces Power Consumption**: Lowers the energy footprint of the device by disabling inactive wireless hardware.
- **Minimizes EMF Exposure**: Limits the emission of radiofrequency (RF) signals within the immediate workspace, contributing to a reduced electromagnetic environment.

## Features

- **Event-Driven (All Platforms)**:
  - **macOS**: Uses `SCDynamicStore` (Native Swift).
  - **Linux**: Uses `nmcli monitor` (NetworkManager).
  - **Windows**: Uses `CIM Indication Events` (PowerShell).
- **Intelligent Interface Detection**: Automatically identifies and prioritizes network interfaces with active IP addresses.
- **Smart State Tracking**: Persistent state management enables instant Wi-Fi activation on disconnect and retry logic only when connecting.
- **Configurable Timeout**: Adjustable IP acquisition timeout (default 7s) via `TIMEOUT` environment variable for slow routers.
- **Optional Internet Connectivity Monitoring**: Monitor actual internet availability instead of just link status. Switches to Wi-Fi if Ethernet loses internet access.
- **Universal Linux Support**: Fallback detection using `nmcli` → `ip` command → `/sys/class/net` for maximum compatibility.
- **Zero CPU Idle Usage**: All implementations sleep until the system notifies them of a network change.
- **POSIX Compliant**: Shell scripts work across different shells and minimal Linux distributions.

## How it Works

### Interface Detection
The scripts automatically identify network interfaces using native system tools:
- **macOS**: `networksetup` with IP address filtering via `ipconfig`
- **Linux**: Multi-tier detection (NetworkManager, `ip` command, or `/sys/class/net`)
- **Windows**: `Get-NetAdapter` with IP address filtering via `Get-NetIPAddress`

Interfaces are prioritized by active IP address presence to ensure reliable detection.

### State Tracking & Retry Logic
The system maintains a persistent state file to track ethernet connection status:
- **Connected → Disconnected**: Wi-Fi enabled immediately (no delay)
- **Disconnected → Connected**: Polls every 1 second up to configurable timeout waiting for IP address acquisition
- Logs when interface is active but no IP assigned yet (helpful for DHCP debugging)

### DHCP Timeout Configuration
The timeout parameter controls how long to wait for IP address acquisition when ethernet connects:

**What it does:**
- When ethernet is plugged in, the interface becomes active immediately
- However, obtaining an IP address via DHCP takes additional time (typically 2-7 seconds)
- The script polls every 1 second until either an IP is acquired or the timeout is reached
- If no IP is obtained within the timeout, Wi-Fi stays enabled

**When to adjust:**
- **Slow DHCP servers**: Some routers/networks take 10+ seconds to assign IPs
- **Enterprise networks**: Corporate networks with authentication may need longer timeouts
- **Fast networks**: Home networks with modern routers typically work fine with default 7s

**Configuration options:**

During installation, you will be prompted to enter the DHCP timeout or accept the default:
```bash
DHCP timeout in seconds [7]: 10
```

For non-interactive/automated installations, you can set the timeout via environment variable:
```bash
# macOS/Linux
TIMEOUT=10 sudo bash ./install-macos.sh

# Windows
$env:TIMEOUT=10; powershell.exe -ExecutionPolicy Bypass -File ".\install-windows.ps1"
```

**Recommended values:**
- Fast home network: 5 seconds
- Normal network: 7 seconds (default)
- Slow/enterprise network: 10-15 seconds

### Internet Connectivity Monitoring (Optional)

In addition to monitoring interface link status, you can optionally enable **Internet Connectivity Monitoring** to detect when an interface has an active connection but no actual internet access (e.g., captive portals, authentication required, upstream network issues).

**What it does:**
- Checks actual internet connectivity using one of three methods
- If Ethernet has a connection but no internet, switches to Wi-Fi automatically
- Supports multiple ethernet or wifi interfaces with priority ordering

**Check Methods:**

1. **Ping to Gateway (Recommended - Default)**
   - Most reliable and provider-safe option
   - Pings the local network gateway (router)
   - Works even with restrictive firewalls
   - Minimal overhead (single ICMP packet)
   - **Best for:** All scenarios, especially corporate/restricted networks

2. **Ping to Domain/IP**
   - Pings an external host (e.g., 8.8.8.8, 1.1.1.1)
   - Verifies internet-wide connectivity
   - May be blocked by some firewalls
   - **Best for:** Home networks, unrestricted environments

3. **HTTP/HTTPS Check (curl)**
   - Makes HTTP request to a URL
   - Can detect captive portals
   - ⚠️ **WARNING:** May be blocked by:
     - Corporate firewalls
     - ISP content filtering
     - Deep packet inspection systems
     - Captive portals (ironically)
   - **Best for:** Detecting captive portal states when other methods work

**When to enable:**
- **Corporate networks**: Networks that require authentication or have intermittent connectivity
- **Public hotspots**: Environments with captive portals that may cause false "connected" states
- **Unreliable ISPs**: When you need automatic failover to backup connectivity
- **Multi-WAN setups**: When you have both wired and wireless internet sources
- **Multiple interfaces**: Systems with 2+ ethernet or 2+ wifi adapters

**Configuration options:**

During installation, you will be prompted whether to enable internet monitoring:
```bash
Enable internet monitoring? (y/N): y

Select connectivity check method:
  1) Gateway ping - Tests LOCAL connectivity to router (not actual internet)
  2) Ping to domain/IP - Tests internet connectivity (may fail on non-active interfaces on macOS)
  3) HTTP/HTTPS check (curl) - Tests actual internet (RECOMMENDED for macOS multi-interface)
Enter choice [1]: 1
Selected: Gateway ping (auto-detected per interface)

Log every check attempt? (y/N) [logs only state changes by default]: N
Default: Will log only state changes (failure/recovery)

# Linux and Windows:
Enter check interval in seconds [30]: 30
Check interval: 30s

# macOS (additional prompt for periodic checking):
Periodic Internet Check (Optional):
  In addition to event-driven checks, enable periodic checks.
  This helps detect internet failures that don't trigger network events.
  Note: Uses minimal resources (timer-based, not polling).

Enable periodic checks? (y/N): y
Enter check interval in seconds [30]: 30
Enabled: Will check every 30 seconds

Multi-Interface Configuration (Optional):
  Configure priority for multiple ethernet or wifi interfaces.

Configure interface priority? (y/N): y
Available interfaces:
  eth0 (ethernet)
  eth1 (ethernet)
  wlan0 (wifi)

Enter interfaces in priority order (comma-separated, highest first) [eth0,wlan0]:
Example: eth0,eth1,wlan0
Interface priority: eth0,eth1,wlan0
Priority configured: eth0,eth1,wlan0
```

For non-interactive/automated installations, set environment variables:
```bash
# Linux - Gateway ping (tests local connectivity)
CHECK_INTERNET=1 CHECK_METHOD=gateway CHECK_INTERVAL=30 sudo bash ./install-linux.sh

# Linux - Ping to 8.8.8.8 (tests actual internet)
CHECK_INTERNET=1 CHECK_METHOD=ping CHECK_TARGET=8.8.8.8 CHECK_INTERVAL=30 sudo bash ./install-linux.sh

# Linux - Auto-install missing dependencies (non-interactive)
AUTO_INSTALL_DEPS=1 sudo bash ./install-linux.sh

# Linux - Full automation with dependency install
AUTO_INSTALL_DEPS=1 CHECK_INTERNET=1 CHECK_METHOD=gateway CHECK_INTERVAL=30 sudo bash ./install-linux.sh

# macOS - Any method works (automatically uses curl for inactive interfaces)
CHECK_INTERNET=1 CHECK_METHOD=ping CHECK_TARGET=8.8.8.8 CHECK_INTERVAL=30 INTERFACE_PRIORITY="en5,en0" sudo bash src/macos/install-template.sh

# macOS - Auto-install (requires Xcode CLI tools pre-installed)
AUTO_INSTALL_DEPS=1 CHECK_INTERNET=1 CHECK_METHOD=gateway sudo bash src/macos/install-template.sh

# macOS - Curl method (tests actual internet on active interface too)
CHECK_INTERNET=1 CHECK_METHOD=curl CHECK_INTERVAL=30 INTERFACE_PRIORITY="en5,en0" sudo bash src/macos/install-template.sh

# With verbose logging
CHECK_INTERNET=1 CHECK_METHOD=curl CHECK_INTERVAL=30 LOG_CHECK_ATTEMPTS=1 INTERFACE_PRIORITY="en5,en0" sudo bash src/macos/install-template.sh

# Windows examples
$env:CHECK_INTERNET=1; $env:CHECK_METHOD="gateway"; $env:CHECK_INTERVAL=30; powershell.exe -ExecutionPolicy Bypass -File ".\install-windows.ps1"
```

**Auto-Install Dependencies:**

Set `AUTO_INSTALL_DEPS=1` to automatically install missing dependencies in non-interactive mode:

- **Linux**: Installs NetworkManager, iproute2, rfkill, ping, curl as needed
  - Detects distribution and uses appropriate package manager (apt, dnf, pacman, etc.)
  - Defaults to NetworkManager when both options are available

- **macOS**: Cannot auto-install Xcode Command Line Tools (requires GUI dialog)
  - Must be pre-installed: `xcode-select --install`
  - Alternative: Install via Homebrew: `brew install swift`

**Logging behavior:**

By default, internet connectivity checks only log state changes:
- When internet becomes unreachable (was working before)
- When internet recovers (working again after failure)

Enable verbose logging (`LOG_CHECK_ATTEMPTS=1`) to log every single check attempt:
```bash
LOG_CHECK_ATTEMPTS=1 sudo bash ./install-linux.sh
```

This is useful for debugging but creates more log entries. Example logs:
```
[2026-01-03 18:00:00] Internet check: eth0 is now unreachable (was working before)
[2026-01-03 18:00:30] Internet check: eth0 is now reachable (recovered from failure)
```

With verbose logging enabled:
```
[2026-01-03 18:00:00] Internet check: gateway ping to 192.168.1.1 via eth0 succeeded
[2026-01-03 18:00:30] Internet check: gateway ping to 192.168.1.1 via eth0 failed
[2026-01-03 18:01:00] Internet check: gateway ping to 192.168.1.1 via eth0 succeeded
```

**Multi-interface support:**

Configure multiple ethernet or wifi interfaces with priority ordering during installation:
- Interactive prompt shows available interfaces
- Specify priority order (comma-separated, highest priority first)
- System tries interfaces in order until one with connectivity is found

Example configuration: `eth0,eth1,wlan0` means:
1. Try eth0 first
2. If eth0 unavailable/no internet, try eth1
3. If eth1 unavailable/no internet, fall back to wlan0

The system will try interfaces in order until one with internet connectivity is found.

**Platform-specific behavior:**
- **Linux**: Event-driven with optional periodic background checks every `CHECK_INTERVAL` seconds (default: 30s)
- **macOS**: Event-driven with optional periodic timer-based checks every `CHECK_INTERVAL` seconds (default: 30s, disabled by default)
  - **Automatic Method Selection**: When checking inactive/higher-priority interfaces, macOS automatically uses HTTP/curl regardless of CHECK_METHOD to avoid routing limitations. The configured CHECK_METHOD is used only for the currently active interface.
- **Windows**: Event-driven with periodic timer-based checks every `CHECK_INTERVAL` seconds (default: 30s)

**Recommended settings:**

**Check method:**
- `gateway` - Tests if interface can reach its router (LOCAL connectivity only, not actual internet)
  - ✓ Fast, reliable, works everywhere
  - ✗ Doesn't verify actual internet access (router could be offline)
  - **Use case**: Basic connectivity monitoring

- `curl` - Tests actual internet connectivity via HTTP/HTTPS
  - ✓ Verifies real internet access
  - ✓ Works reliably on all platforms
  - ✗ May be blocked by some ISPs/firewalls
  - **Use case**: When you need to verify actual internet (recommended)

- `ping` - Tests internet by pinging a domain/IP (requires CHECK_TARGET)
  - ✓ Verifies real internet access
  - ✓ Works well on Linux/Windows
  - **Use case**: When curl is not available

**Note for macOS multi-interface setups**: The system automatically uses HTTP/curl for checking inactive interfaces regardless of your CHECK_METHOD, then switches to your configured method once an interface becomes active. This solves macOS routing limitations transparently.

**Note:** This feature is **disabled by default** to maintain backward compatibility and minimize overhead for users who don't need it.

### Event-Driven Architecture
The app remains idle and consumes zero CPU cycles until a network event is triggered by the OS.

## ⚠️ Important Requirement

For this tool to work seamlessly, ensure that at least one of your Wi-Fi networks is configured to **connect automatically**:

- **macOS**: Enable **"Auto-Join"** in System Settings > Wi-Fi > [Your Network] > Details.
- **Linux**: Enable **"Connect automatically"** in your NetworkManager connection settings.
- **Windows**: Check **"Connect automatically when in range"** in your Wi-Fi network properties.

If no network is set to auto-connect, the Wi-Fi interface will turn on but will not establish a connection until you manually select a network.


No signing issues, but the installer requires `sudo` to create the `systemd` service and copy files to `/opt/eth-wifi-auto`.

## Building from Source

The project uses a modular build system to generate self-contained installers.

1.  **Prerequisites**:
    - macOS: Xcode Command Line Tools (`xcode-select --install`).
    - Linux/Windows: No special tools required for building (uses `base64` and `sed`).
2.  **Run the build**:
    ```bash
    ./build.sh
    ```
3.  **Output**: The generated installers will be in the `dist/` directory.

## Testing

Comprehensive test suite with unit tests and integration tests.

**Run all tests:**
```bash
./tests/run_all_tests.sh
```

**Run unit tests only:**
```bash
for test in tests/unit/test_*.sh; do sh "$test"; done
```

**Run integration tests (requires Docker):**
```bash
./tests/integration/test_linux_integration.sh
```

See [TESTING.md](TESTING.md) for detailed information about the test framework.

## System Requirements & Dependencies

### macOS
**Required (built-in on all macOS systems):**
- `networksetup` - Network configuration tool
- `ipconfig` - IP configuration utility
- `ifconfig` - Network interface configuration
- `bash` or `sh` - Shell interpreter

**Critical for multi-interface internet monitoring:**
- `curl` - **Required** for checking internet on inactive interfaces (standard on macOS 10.3+)
  - If missing, only the active interface can be tested for internet connectivity
  - Install via: `brew install curl` (if somehow missing)

**Optional (improves functionality):**
- `ping` - For ping-based internet checks (standard on all systems)

### Linux
**Required:**
- `bash` - Shell interpreter
- `ip` or `ifconfig` - Network interface tools (usually pre-installed)
- One of: `nmcli` (NetworkManager) or `connmanctl` (ConnMan) - Network management

**For internet monitoring:**
- `ping` - Internet connectivity checks (standard)
- `curl` - For HTTP-based internet checks (install: `apt install curl` / `yum install curl`)

**Optional backends:**
- `nmcli` - NetworkManager CLI (recommended, most common)
- `connmanctl` - ConnMan CLI (alternative)
- Raw `ip` commands - Fallback if NetworkManager not available

### Windows
**Required (built-in on Windows 7+):**
- PowerShell 5.1 or higher
- `Get-NetAdapter` cmdlet (built-in)
- `Set-NetAdapterBinding` cmdlet (built-in)
- `Test-Connection` cmdlet (built-in)

**All dependencies are built into Windows** - no additional software needed.

### Verification
To verify your system has required dependencies:

**macOS/Linux:**
```bash
# Check curl availability (important for macOS multi-interface)
command -v curl && echo "✓ curl available" || echo "✗ curl missing"

# Check network tools
command -v networksetup && echo "✓ networksetup available" || echo "✗ networksetup missing"  # macOS
command -v nmcli && echo "✓ nmcli available" || echo "✗ nmcli missing"  # Linux
```

**Windows PowerShell:**
```powershell
Get-Command Test-Connection -ErrorAction SilentlyContinue
Get-Command Get-NetAdapter -ErrorAction SilentlyContinue
```

**Note:** The installer will warn if critical dependencies are missing, especially curl on macOS when internet monitoring is enabled.

## Installation & Uninstallation

If you downloaded the script manually, you may need to grant it execution permissions first:
`chmod +x install-macos.sh` (or `install-linux.sh`).

### Installation Modes

**Interactive Mode** (Default):
- Prompts for each configuration option
- Recommended for first-time users
- Allows customization of interfaces, timeouts, and monitoring

**Auto Mode** (Quick & Simple):
```bash
# Linux - All defaults with automatic dependency installation
sudo bash ./install-linux.sh --auto

# macOS - All defaults (Xcode CLI tools must be pre-installed)
sudo bash ./install-macos.sh --defaults

# Windows - All defaults (PowerShell as Administrator)
powershell.exe -ExecutionPolicy Bypass -File ".\install-windows.ps1" -Auto

# You can also use --defaults flag (same as --auto)
sudo bash ./install-linux.sh --defaults
```

**Auto Mode Features:**
- ✅ Auto-detects network interfaces
- ✅ Enables internet connectivity monitoring (ping to 8.8.8.8 every 30s)
- ✅ Uses recommended defaults for all settings
- ✅ Installs missing dependencies automatically (Linux)
- ✅ No prompts - fully automated
- ✅ Perfect for CI/CD, scripting, or users who trust automation

### 🍎 macOS
**Install (Interactive):**
```bash
sudo bash ./dist/install-macos.sh
```

**Install (Auto Mode):**
```bash
sudo bash ./dist/install-macos.sh --auto
```

Output:
```
...
Installation directory: /Users/dst0/.ethernet-wifi-auto-switcher

Extracting helper script...
Extracting watcher binary...
Installing system binaries...
Generating LaunchDaemon plist...
Loading LaunchDaemon...

✅ Installation complete.

The service is now running. It will automatically:
  • Turn Wi-Fi off when Ethernet is connected
  • Turn Wi-Fi on when Ethernet is disconnected
  • Continue working after OS reboot

To uninstall, run:
  sudo bash ~/.ethernet-wifi-auto-switcher/uninstall.sh
```

**Uninstall:**
```bash
sudo bash ~/.ethernet-wifi-auto-switcher/uninstall.sh
```
Output:
```
Stopping LaunchDaemon...
Stopping any running processes...
Removing system files...
Removing workspace...
✅ Uninstalled completely.
```

---

### 🐧 Linux
**Install:**
```bash
sudo bash ./dist/install-linux.sh
```
Output:
```
...
Installation directory: /opt/eth-wifi-auto

...
Extracting switcher...
Creating systemd service...
Starting service...

✅ Installation complete.

The service is now running. It will automatically:
  • Turn Wi-Fi off when Ethernet is connected
  • Turn Wi-Fi on when Ethernet is disconnected
  • Continue working after OS reboot

To uninstall, run:
  sudo bash "/opt/eth-wifi-auto/uninstall.sh"
```

**Uninstall:**
```bash
sudo bash "/opt/eth-wifi-auto/uninstall.sh"
```
Output:
```
Detected installation directory: /opt/eth-wifi-auto
Uninstalling Ethernet/Wi-Fi Auto Switcher...
Uninstallation complete.
```

---


1. Open PowerShell as Administrator
2. Navigate to the build directory
3. Run:
### 🪟 Windows (PowerShell Admin)
**Install:**
```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\dist\install-windows.ps1"
```
Output:
```
...
Installation directory: C:\Program Files\EthWifiAuto

Creating Scheduled Task...

✅ Installation complete.

The task is now running. It will automatically:
  • Turn Wi-Fi off when Ethernet is connected
  • Turn Wi-Fi on when Ethernet is disconnected
  • Continue working after OS reboot

To uninstall, run:
  powershell.exe -ExecutionPolicy Bypass -File "C:\Program Files\EthWifiAuto\uninstall.ps1"
```

**Uninstall:**
```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Program Files\EthWifiAuto\uninstall.ps1"
```
Output:
```
Detected installation directory: C:\Program Files\EthWifiAuto
Uninstalling Ethernet/Wi-Fi Auto Switcher...
Scheduled task removed.
Installation directory removed.
✅ Uninstalled completely.
```

---

## CI/CD Pipeline

The project uses GitHub Actions to automate the build and release process across all platforms:
- **macOS**: Automatically compiles the Swift watcher into a Universal Binary and generates the `install-macos.sh` distribution script.
- **Linux & Windows**: Packages the latest scripts for distribution.
- **Releases**: Every time a new tag (e.g., `v1.0.0`) is pushed, the pipeline creates a GitHub Release with all necessary files for all three platforms.

## System Efficiency & Performance

This micro-app is designed with extreme efficiency in mind:
- **Zero CPU Idle Usage**: All versions are event-driven. They do not "poll" the system; they wait for the OS to push notifications.
- **Low Memory Footprint**:
  - macOS: < 10MB (Native Swift)
  - Linux: < 5MB (Bash/nmcli)
  - Windows: < 20MB (PowerShell)

## Logging

- **Windows**: `%ProgramData%\EthWifiAuto\switcher.log` (created after first run). View with `Get-Content -Path "$env:ProgramData\EthWifiAuto\switcher.log" -Wait`.
- **macOS**: Logs in your workdir (default `~/.ethernet-wifi-auto-switcher`): `watch.log` (watcher) and `helper.log` (helper). View with `tail -f ~/.ethernet-wifi-auto-switcher/watch.log ~/.ethernet-wifi-auto-switcher/helper.log`.
- **Linux**: Systemd journal for the service. View with `sudo journalctl -u eth-wifi-auto -f`.

## Project Structure

- `src/macos/`: macOS source files (Swift watcher, installer template, plist).
- `src/linux/`: Linux source files (Switcher logic, uninstaller, installer template).
- `src/windows/`: Windows source files (Switcher logic, uninstaller, installer template).
- `build.sh`: Root build coordinator that triggers platform-specific builds.
- `dist/`: Contains the generated self-contained installers for all platforms.

## License

This project is licensed under a Proprietary Non-Commercial License. Commercial usage, usage within business units, and redistribution of the software are strictly prohibited without a written agreement with the owner (dst0). You are welcome to share links to this repository or the installation instructions. See the [LICENSE](LICENSE) file for full details.
