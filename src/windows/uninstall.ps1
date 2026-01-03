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

# Remove scheduled task if exists
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Scheduled task removed."
}

# Kill any running helper processes
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*eth-wifi-auto.ps1*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

if (Test-Path $InstallDir) {
    Write-Host "Removing installation directory..."

    # Create a temporary script that will delete the installation directory after this script exits.
    $tempRemovePath = Join-Path ([System.IO.Path]::GetTempPath()) "ethwifi_remove.ps1"
    $removeScript = @"
Start-Sleep -Milliseconds 500
try {
    Remove-Item -Path `"$InstallDir`" -Recurse -Force -ErrorAction SilentlyContinue
} catch {}
try {
    Remove-Item -Path `"$tempRemovePath`" -Force -ErrorAction SilentlyContinue
} catch {}
"@
    $removeScript | Out-File -FilePath $tempRemovePath -Encoding UTF8 -Force
    # Launch the temp script in a new background PowerShell process
    Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$tempRemovePath`"" -WindowStyle Hidden
}

Write-Host "✅ Uninstalled completely."
Write-Host ""