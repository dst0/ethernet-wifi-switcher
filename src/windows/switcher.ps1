# Event-driven Ethernet/Wi-Fi switcher for Windows
# Uses CIM Indication Events for 0% CPU idle.

$StateFile = "$env:TEMP\eth-wifi-state.txt"
$Timeout = if ($env:TIMEOUT) { [int]$env:TIMEOUT } else { 7 }
$LogDir = if ($env:ProgramData) { Join-Path $env:ProgramData "EthWifiAuto" } else { Split-Path $StateFile }
$LogFile = Join-Path $LogDir "switcher.log"

function Log-Message {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] $Message"
    Write-Host $line
    try {
        if (-not (Test-Path $LogDir)) {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        }
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
    } catch {
        # Logging failures should not break functionality
    }
}

function Read-LastState {
    # If file doesn't exist or can't be read, treat as disconnected
    if (Test-Path $StateFile) {
        $state = Get-Content $StateFile -ErrorAction SilentlyContinue
        if ($state) { return $state } else { return "disconnected" }
    }
    return "disconnected"
}

function Write-State {
    param([string]$State)
    Set-Content -Path $StateFile -Value $State
}

function Get-EthernetAdapter {
    Get-NetAdapter | Where-Object { $_.PhysicalMediaType -eq "802.3" -and $_.Status -ne "Not Present" } | Select-Object -First 1
}

function Get-WifiAdapter {
    Get-NetAdapter | Where-Object { $_.PhysicalMediaType -eq "Native 802.11" -and $_.Status -ne "Not Present" } | Select-Object -First 1
}

function Set-WifiSoftState {
    param(
        [object]$Adapter,
        [bool]$Enable
    )

    if ($null -eq $Adapter) { return }

    $target = if ($Enable) { "ENABLED" } else { "DISABLED" }
    $adapterName = $Adapter.Name
    $args = @("interface", "set", "interface", "name=$adapterName", "admin=$target")
    $output = & netsh @args 2>&1

    if ($LASTEXITCODE -ne 0) {
        Log-Message "Failed to set Wi-Fi $target: $output"
    }
}

function Test-WifiNeedsEnable {
    param([object]$Adapter)
    return ($null -ne $Adapter -and ($Adapter.Status -eq "Disabled" -or $Adapter.Status -eq "Down" -or $Adapter.Status -eq "Disconnected"))
}

function Test-EthernetConnected {
    param([object]$Adapter)
    if ($null -eq $Adapter -or $Adapter.Status -ne "Up") {
        return $false
    }
    # Check if adapter has an IP address
    $ipConfig = Get-NetIPAddress -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    return ($null -ne $ipConfig)
}

function Test-EthernetConnectedWithRetry {
    param([object]$Adapter)

    # Try immediate check
    if (Test-EthernetConnected -Adapter $Adapter) {
        return $true
    }

    # Check if adapter is up but no IP yet
    if ($Adapter.Status -eq "Up") {
        Log-Message "Ethernet adapter active but no IP yet, waiting..."
    }

    # Poll every second until timeout
    $elapsed = 0
    while ($elapsed -lt $Timeout) {
        Start-Sleep -Seconds 1
        $elapsed++

        if (Test-EthernetConnected -Adapter $Adapter) {
            Log-Message "Ethernet acquired IP after $($elapsed)s"
            return $true
        }
    }

    return $false
}

function Check-And-Switch {
    $eth = Get-EthernetAdapter
    $wifi = Get-WifiAdapter

    if ($null -eq $eth -or $null -eq $wifi) {
        $ethName = if ($eth) { $eth.Name } else { "null" }
        $wifiName = if ($wifi) { $wifi.Name } else { "null" }
        Log-Message "Missing adapters (Ethernet: $ethName, Wi-Fi: $wifiName). Waiting..."
        return
    }

    $lastState = Read-LastState

    # Quick check without retry
    $currentState = if (Test-EthernetConnected -Adapter $eth) { "connected" } else { "disconnected" }

    # If state changed from connected to disconnected, enable wifi immediately
    if ($lastState -eq "connected" -and $currentState -eq "disconnected") {
        Log-Message "Ethernet disconnected, enabling Wi-Fi immediately"
        Write-State "disconnected"
        if (Test-WifiNeedsEnable -Adapter $wifi) {
            Set-WifiSoftState -Adapter $wifi -Enable $true
        }
        return
    }

    # If currently disconnected, use retry logic to wait for IP
    if ($lastState -eq "disconnected" -and $currentState -eq "disconnected") {
        # Try with retry for new connection
        if (Test-EthernetConnectedWithRetry -Adapter $eth) {
            $currentState = "connected"
        }
    }

    # Update state and manage wifi
    Write-State $currentState

    if ($currentState -eq "connected") {
        if ($wifi.Status -ne "Disabled") {
            Log-Message "Ethernet connected ($($eth.Name)). Disabling Wi-Fi..."
            Set-WifiSoftState -Adapter $wifi -Enable $false
        }
    } else {
        if (Test-WifiNeedsEnable -Adapter $wifi) {
            Log-Message "Ethernet disconnected ($($eth.Name)). Enabling Wi-Fi..."
            Set-WifiSoftState -Adapter $wifi -Enable $true
        }
    }
}

# Initial check
Log-Message "Starting switcher (timeout ${Timeout}s)"
Check-And-Switch

# Register for CIM events (Network Adapter status changes)
$query = "SELECT * FROM MSFT_NetAdapter"
Register-CimIndicationEvent -Namespace "root\StandardCimv2" -Query $query -SourceIdentifier "NetAdapterChange"

Log-Message "Starting event monitor..."
try {
    while ($true) {
        $event = Wait-Event -SourceIdentifier "NetAdapterChange"
        Check-And-Switch
        Remove-Event -SourceIdentifier "NetAdapterChange"
    }
} finally {
    Unregister-Event -SourceIdentifier "NetAdapterChange"
}
