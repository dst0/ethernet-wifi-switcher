# Ethernet Wi-Fi Switcher

[![Release](https://img.shields.io/github/v/release/dst0/ethernet-wifi-switcher)](https://github.com/dst0/ethernet-wifi-switcher/releases)
[![Build Status](https://github.com/dst0/ethernet-wifi-switcher/actions/workflows/release.yml/badge.svg)](https://github.com/dst0/ethernet-wifi-switcher/actions)
[![License](https://img.shields.io/badge/license-Proprietary-blue.svg)](LICENSE)
[![EMF Safe](https://img.shields.io/badge/EMF-Safe-success)](#environmental-and-health-impact)
[![Energy Efficient](https://img.shields.io/badge/Energy-Efficient-success)](#environmental-and-health-impact)

[![Support Ukraine](https://img.shields.io/badge/Support-Ukraine-FFD700?style=flat&labelColor=0057B7)](https://standforukraine.com/)

This tool automatically manages your Wi-Fi connection based on Ethernet availability across **macOS, Linux, and Windows**. It ensures that Wi-Fi is turned off when a stable Ethernet connection is detected and turned back on when Ethernet is disconnected.

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

During installation (interactive prompt):
```bash
DHCP timeout in seconds [7]: 10
```

Via environment variable (non-interactive):
```bash
# macOS/Linux
TIMEOUT=10 sudo bash ./install-macos.sh

# Windows
$env:TIMEOUT=10; .\install-windows.ps1
```

**Recommended values:**
- Fast home network: 5 seconds
- Normal network: 7 seconds (default)
- Slow/enterprise network: 10-15 seconds

### Event-Driven Architecture
The app remains idle and consumes zero CPU cycles until a network event is triggered by the OS.

## ⚠️ Important Requirement

For this tool to work seamlessly, ensure that at least one of your Wi-Fi networks is configured to **connect automatically**:

- **macOS**: Enable **"Auto-Join"** in System Settings > Wi-Fi > [Your Network] > Details.
- **Linux**: Enable **"Connect automatically"** in your NetworkManager connection settings.
- **Windows**: Check **"Connect automatically when in range"** in your Wi-Fi network properties.

If no network is set to auto-connect, the Wi-Fi interface will turn on but will not establish a connection until you manually select a network.

## 🚀 Quick Install (One-Liner)

Choose your platform and run the command in your terminal:

### macOS
```bash
curl -fsSL https://github.com/dst0/ethernet-wifi-switcher/releases/latest/download/install-macos.sh | sudo bash
```

### Linux
```bash
curl -fsSL https://github.com/dst0/ethernet-wifi-switcher/releases/latest/download/install-linux.sh | sudo bash
```

### Windows (PowerShell Admin)
```powershell
iwr https://github.com/dst0/ethernet-wifi-switcher/releases/latest/download/install-windows.ps1 -useb | iex
```

---

## 📦 Downloads

You can download the latest pre-packaged versions from the [Releases](https://github.com/dst0/ethernet-wifi-switcher/releases) page:

- 🍎 **macOS**: [install-macos.sh](https://github.com/dst0/ethernet-wifi-switcher/releases/latest/download/install-macos.sh)
- 🐧 **Linux**: [install-linux.sh](https://github.com/dst0/ethernet-wifi-switcher/releases/latest/download/install-linux.sh)
- 🪟 **Windows**: [install-windows.ps1](https://github.com/dst0/ethernet-wifi-switcher/releases/latest/download/install-windows.ps1)

## 🛡️ Security & Code Signing

Since this is an open-source project provided as scripts and a pre-compiled binary, you should be aware of the following:

### macOS
The pre-compiled Swift watcher is **ad-hoc signed**. When you run the installer, macOS might show a "Developer cannot be verified" warning. The installer automatically attempts to bypass this using `codesign -s -`, but if you encounter issues, you can build from source locally to ensure the binary is signed with your own local identity.

### Windows
The PowerShell scripts are not digitally signed. To run the installer, you must use the `-ExecutionPolicy Bypass` flag (included in the quick install command). Windows may show a "SmartScreen" warning because the script is downloaded from the internet; you may need to click "Run anyway".

### Linux
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

## Installation & Uninstallation

If you downloaded the script manually, you may need to grant it execution permissions first:
`chmod +x install-macos.sh` (or `install-linux.sh`).

### 🍎 macOS
**Install:**
```bash
sudo bash ./dist/install-macos.sh
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

### 🪟 Windows (PowerShell Admin)
**Install:**
```powershell
.\dist\install-windows.ps1
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

## Project Structure

- `src/macos/`: macOS source files (Swift watcher, installer template, plist).
- `src/linux/`: Linux source files (Switcher logic, uninstaller, installer template).
- `src/windows/`: Windows source files (Switcher logic, uninstaller, installer template).
- `build.sh`: Root build coordinator that triggers platform-specific builds.
- `dist/`: Contains the generated self-contained installers for all platforms.

## License

This project is licensed under a Proprietary Non-Commercial License. Commercial usage, usage within business units, and redistribution of the software are strictly prohibited without a written agreement with the owner (dst0). You are welcome to share links to this repository or the installation instructions. See the [LICENSE](LICENSE) file for full details.
