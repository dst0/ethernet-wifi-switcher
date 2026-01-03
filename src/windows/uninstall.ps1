# Uninstaller for Ethernet/Wi-Fi Auto Switcher (Windows)

$TaskName = "EthWifiAutoSwitcher"
$DefaultInstallDir = if ($env:TEST_MODE -eq "1") { Join-Path $env:TEMP "EthWifiAutoTest" } else { "$env:ProgramFiles\EthWifiAuto" }
$LogDir = if ($env:ProgramData) { Join-Path $env:ProgramData "EthWifiAuto" } else { Join-Path $env:TEMP "EthWifiAuto" }

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

$originalLocation = Get-Location
if ($InstallDir) {
    $originalPath = [System.IO.Path]::GetFullPath($originalLocation.Path)
    $installPath = [System.IO.Path]::GetFullPath($InstallDir)
    $isInside = $false
    try {
        if (([System.IO.Path]).GetMethod("GetRelativePath")) {
            $relative = [System.IO.Path]::GetRelativePath($installPath, $originalPath)
            $isInside = (-not [string]::IsNullOrEmpty($relative)) -and (-not $relative.StartsWith("..", [System.StringComparison]::OrdinalIgnoreCase))
        }
    } catch {
        # GetRelativePath not available on older PowerShell; fallback to string prefix
        $installPathWithSep = if ($installPath.EndsWith('\')) { $installPath } else { "$installPath\" }
        $isInside = $originalPath.StartsWith($installPathWithSep, [System.StringComparison]::OrdinalIgnoreCase)
    }
    # Avoid deleting the current working directory during uninstall by moving away if inside install path
    if ($isInside) {
        Set-Location $env:TEMP
    }
}

if (Test-Path $InstallDir) {
    try {
        Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction Stop
    } catch {
        # Brief pause allows helper/AV processes to release file handles before retrying
        Start-Sleep -Milliseconds 500
        Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Installation directory removed."
}

if (Test-Path $LogDir) {
    Remove-Item -Path $LogDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "✅ Uninstalled completely."
Write-Host ""
