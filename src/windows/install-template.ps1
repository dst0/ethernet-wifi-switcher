# Universal Ethernet/Wi-Fi Auto Switcher for Windows
# This script is self-contained and includes the switcher logic and uninstaller.

param(
    [switch]$Uninstall
)

$TaskName = "EthWifiAutoSwitcher"
$DefaultInstallDir = if ($env:TEST_MODE -eq "1") { Join-Path $env:TEMP "EthWifiAutoTest" } else { "$env:ProgramFiles\EthWifiAuto" }

# Embedded components (Base64)
$SwitcherB64 = "__SWITCHER_B64__"
$UninstallerB64 = "__UNINSTALLER_B64__"

function Stop-HelperProcesses {
    $helperProcs = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*eth-wifi-auto.ps1*" }
    if ($helperProcs) {
        Write-Host "Stopping helper processes..."
        $helperProcs | ForEach-Object {
            $procId = $_.ProcessId
            $procName = $_.Name
            Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 100
            if (-not (Get-Process -Id $procId -ErrorAction SilentlyContinue)) {
                Write-Host "    process $procId $procName stopped"
            } else {
                Write-Host "    process $procId $procName failed to stop"
            }
        }
    }
}

function Install {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "Please run as Administrator."
        return
    }

    # Cleanup existing installation if found
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Host "Old installation detected: Scheduled Task '$TaskName'"

        $OldInstallDir = $null
        $OldUninstaller = $null

        if ($existingTask.Actions[0].Arguments -match '-File "(.*)"') {
            $OldSwitcherPath = $matches[1]
            $OldInstallDir = Split-Path $OldSwitcherPath
            Write-Host "  Installation directory: $OldInstallDir"
            $OldUninstaller = Join-Path $OldInstallDir "uninstall.ps1"
        }

        if ($OldUninstaller -and (Test-Path $OldUninstaller)) {
            Write-Host "  Running existing uninstaller..."
            powershell.exe -ExecutionPolicy Bypass -File "$OldUninstaller"
        } else {
            if (-not $OldInstallDir) {
                Write-Host "  Installation directory not found. Performing manual cleanup..."
            } else {
                Write-Host "  No uninstaller found. Performing manual cleanup..."
            }
            Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Stop-HelperProcesses
        }
    } else {
        Write-Host "No old installation detected."
    }

    $InstallDir = $DefaultInstallDir
    if ([Environment]::UserInteractive) {
        $userInput = Read-Host "Enter installation directory [$DefaultInstallDir]"
        if ($userInput) { $InstallDir = $userInput }
    }

    $LogDir = if ($env:ProgramData) { Join-Path $env:ProgramData "EthWifiAuto" } else { Join-Path $InstallDir "logs" }

    $envEth = $env:ETHERNET_INTERFACE
    $envWifi = $env:WIFI_INTERFACE

    # Detect interfaces - prioritize connected interfaces with IP addresses
    Write-Host ""
    Write-Host "Detecting network interfaces..."

    # Get all network adapters
    $allAdapters = Get-NetAdapter
    $ethCandidates = $allAdapters | Where-Object { $_.PhysicalMediaType -match 'Ethernet|802.3' }
    $wifiCandidates = $allAdapters | Where-Object { $_.PhysicalMediaType -match 'Wireless|Native 802.11' }

    # Method 1: Find Ethernet adapter with IP address (prioritized)
    $ethWithIP = $ethCandidates | Where-Object {
        $_.Status -eq 'Up' -and
        (Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)
    } | Select-Object -First 1

    # Method 2: Fallback to any Ethernet adapter that is up
    if (-not $ethWithIP) {
        $ethWithIP = $ethCandidates | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
    }

    # Method 3: Final fallback - any Ethernet adapter
    if (-not $ethWithIP) {
        $ethWithIP = $ethCandidates | Select-Object -First 1
    }

    # Wi-Fi detection: prefer active adapters, but allow disabled ones too
    $wifiAdapter = $wifiCandidates | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
    if (-not $wifiAdapter) {
        $wifiAdapter = $wifiCandidates | Select-Object -First 1
    }

    $autoEth = if ($ethWithIP) { $ethWithIP.Name } else { "Not detected" }
    $autoWifi = if ($wifiAdapter) { $wifiAdapter.Name } else { "Not detected" }

    if ($envEth) { $autoEth = $envEth }
    if ($envWifi) { $autoWifi = $envWifi }

    Write-Host "  Ethernet: $autoEth"
    Write-Host "  Wi-Fi:    $autoWifi"
    Write-Host ""

    if ([Environment]::UserInteractive -and ($autoEth -ne "Not detected" -or $autoWifi -ne "Not detected")) {
        Write-Host "Press Enter to use auto-detected values, or type interface names to override:"
        $ethInput = Read-Host "Ethernet interface [$autoEth]"
        if (-not $ethInput) { $ethInput = $autoEth }

        $wifiInput = Read-Host "Wi-Fi interface [$autoWifi]"
        if (-not $wifiInput) { $wifiInput = $autoWifi }

        Write-Host ""
        Write-Host "DHCP Timeout Configuration:"
        Write-Host "  When ethernet connects, the adapter becomes active but may not"
        Write-Host "  have an IP address yet (DHCP negotiation in progress)."
        Write-Host "  This timeout controls how long to wait for IP acquisition."
        Write-Host "  Increase for slow routers/DHCP servers (typical: 3-10 seconds)."
        Write-Host ""
        $timeoutInput = Read-Host "DHCP timeout in seconds [7]"
        $timeout = if ($timeoutInput) { [int]$timeoutInput } else { if ($env:TIMEOUT) { [int]$env:TIMEOUT } else { 7 } }
    } else {
        $ethInput = if ($envEth) { $envEth } else { $autoEth }
        $wifiInput = if ($envWifi) { $envWifi } else { $autoWifi }
        $timeout = if ($env:TIMEOUT) { [int]$env:TIMEOUT } else { 7 }
    }

    if ([string]::IsNullOrWhiteSpace($ethInput) -or [string]::IsNullOrWhiteSpace($wifiInput) -or $ethInput -eq "Not detected" -or $wifiInput -eq "Not detected") {
        Write-Error "Both Ethernet and Wi-Fi interfaces must be detected or specified."
        return
    }

    $SwitcherPath = "$InstallDir\eth-wifi-auto.ps1"

    Write-Host "Installation directory: $InstallDir"
    Write-Host ""
    Write-Host "Using configuration:"
    Write-Host "  Ethernet: $ethInput"
    Write-Host "  Wi-Fi:    $wifiInput"
    Write-Host "  Timeout:  $($timeout)s"
    Write-Host ""

    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    # Extract switcher
    $switcherBytes = [System.Convert]::FromBase64String($SwitcherB64)
    [System.IO.File]::WriteAllBytes($SwitcherPath, $switcherBytes)

    # Extract uninstaller
    $UninstallerPath = "$InstallDir\uninstall.ps1"
    $uninstallerBytes = [System.Convert]::FromBase64String($UninstallerB64)
    [System.IO.File]::WriteAllBytes($UninstallerPath, $uninstallerBytes)

    if ($env:TEST_MODE -eq "1") {
        Write-Host "TEST_MODE=1: skipping scheduled task registration."
        Write-Host "Install path (test): $InstallDir"
        return
    }

    # Create Scheduled Task with environment variable
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$SwitcherPath`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 365)

    # Register task
    $task = Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force

    # Set environment variable for the task using XML modification
    $taskXml = Export-ScheduledTask -TaskName $TaskName
    $taskXml = $taskXml -replace '(<Actions>)', "`$1`n    <EnvironmentVariables>`n      <Variable>`n        <Name>TIMEOUT</Name>`n        <Value>$timeout</Value>`n      </Variable>`n    </EnvironmentVariables>"
    $taskXml | Register-ScheduledTask -TaskName $TaskName -Force | Out-Null

    Start-ScheduledTask -TaskName $TaskName

    Write-Host ""
    Write-Host "✅ Installation complete."
    Write-Host ""
    Write-Host "The task is now running. It will automatically:"
    Write-Host "  • Turn Wi-Fi off when Ethernet is connected"
    Write-Host "  • Turn Wi-Fi on when Ethernet is disconnected"
    Write-Host "  • Continue working after OS reboot"
    Write-Host "Logs: $LogDir\switcher.log (created after first run). Tail with: Get-Content -Path `"$LogDir\switcher.log`" -Wait"
    Write-Host ""
    Write-Host "To uninstall, run:"
    Write-Host "  powershell.exe -ExecutionPolicy Bypass -File `"$UninstallerPath`""
}

function Uninstall {
    $uninstallerBytes = [System.Convert]::FromBase64String($UninstallerB64)
    $uninstallerScript = [System.Text.Encoding]::UTF8.GetString($uninstallerBytes)
    Invoke-Expression $uninstallerScript
}

if ($Uninstall) {
    Uninstall
} else {
    Install
}
