# Event-driven Ethernet/Wi-Fi switcher for Windows
# Uses CIM Indication Events for 0% CPU idle.

$StateFile = "$env:TEMP\eth-wifi-state.txt"
$Timeout = if ($env:TIMEOUT) { [int]$env:TIMEOUT } else { 7 }

function Log-Message {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
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

# Toggle Wi-Fi radio using Windows.Devices.Radios API. Falls back silently if API is unavailable.
function Set-WifiRadioState {
    [CmdletBinding()]
    param(
        [bool]$Enable
    )
    try {
        # Load Windows Runtime assembly; ignore errors if already loaded
        Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction SilentlyContinue
        $access = [Windows.Devices.Radios.Radio]::RequestAccessAsync().GetAwaiter().GetResult()
        if ($access -eq [Windows.Devices.Radios.RadioAccessStatus]::Allowed) {
            $wifiRadio = [Windows.Devices.Radios.Radio]::GetRadiosAsync().GetAwaiter().GetResult() |
                Where-Object { $_.Kind -eq [Windows.Devices.Radios.RadioKind]::WiFi } |
                Select-Object -First 1
            if ($wifiRadio) {
                $desiredState = if ($Enable) { [Windows.Devices.Radios.RadioState]::On } else { [Windows.Devices.Radios.RadioState]::Off }
                $null = $wifiRadio.SetStateAsync($desiredState).GetAwaiter().GetResult()
            }
        }
    } catch {
        # Ignore any errors; adapter-level commands will act as fallback
    }
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

    if ($null -eq $eth -or $null -eq $wifi) { return }

    $lastState = Read-LastState

    # Quick check without retry
    $currentState = if (Test-EthernetConnected -Adapter $eth) { "connected" } else { "disconnected" }

    # If state changed from connected to disconnected, enable wifi immediately
    if ($lastState -eq "connected" -and $currentState -eq "disconnected") {
        Log-Message "Ethernet disconnected, enabling Wi-Fi immediately"
        Write-State "disconnected"
        if ($wifi.Status -eq "Disabled") {
            # Use radio API to turn on Wi-Fi; fall back to enabling adapter
            Set-WifiRadioState -Enable:$true
            Enable-NetAdapter -Name $wifi.Name -Confirm:$false -ErrorAction SilentlyContinue
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
            # Use radio API to turn off Wi-Fi; fall back to disabling adapter
            Set-WifiRadioState -Enable:$false
            Disable-NetAdapter -Name $wifi.Name -Confirm:$false -ErrorAction SilentlyContinue
        }
    } else {
        if ($wifi.Status -eq "Disabled") {
            Log-Message "Ethernet disconnected ($($eth.Name)). Enabling Wi-Fi..."
            # Use radio API to turn on Wi-Fi; fall back to enabling adapter
            Set-WifiRadioState -Enable:$true
            Enable-NetAdapter -Name $wifi.Name -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}

# Initial check
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