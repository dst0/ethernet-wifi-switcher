# Uninstaller for Ethernet/Wi-Fi Auto Switcher (Windows)

$TaskName = "EthWifiAutoSwitcher"
$DefaultInstallDir = "$env:ProgramFiles\EthWifiAuto"

Write-Host "Uninstalling Ethernet/Wi-Fi Auto Switcher..."

# Try to detect installation path from the scheduled task
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    # Extract path from arguments: -WindowStyle Hidden -File "C:\Path\To\switcher.ps1"
    if ($task.Actions[0].Arguments -match '-File "(.*)"') {
        $SwitcherPath = $matches[1]
        $InstallDir = Split-Path $SwitcherPath
        Write-Host "Detected installation directory: $InstallDir"
    } else {
        $InstallDir = $DefaultInstallDir
    }
} else {
    $InstallDir = $DefaultInstallDir
}

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Scheduled task removed."
}

# Kill any orphaned processes
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*eth-wifi-auto.ps1*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

if (Test-Path $InstallDir) {
    Remove-Item -Path $InstallDir -Recurse -Force
    Write-Host "Installation directory removed."
}

Write-Host "✅ Uninstalled completely."
Write-Host ""
