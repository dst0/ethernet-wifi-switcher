# Event-driven Ethernet/Wi-Fi switcher for Windows
# Uses CIM Indication Events for 0% CPU idle.

$StateFile = "$env:TEMP\eth-wifi-state.txt"
$Timeout = if ($env:TIMEOUT) { [int]$env:TIMEOUT } else { 7 }
$CheckInternet = if ($env:CHECK_INTERNET) { [int]$env:CHECK_INTERNET } else { 0 }
$CheckInterval = if ($env:CHECK_INTERVAL) { [int]$env:CHECK_INTERVAL } else { 30 }
$CheckMethod = if ($env:CHECK_METHOD) { $env:CHECK_METHOD } else { "gateway" }
$CheckTarget = if ($env:CHECK_TARGET) { $env:CHECK_TARGET } else { "" }
$LogCheckAttempts = if ($env:LOG_CHECK_ATTEMPTS) { [int]$env:LOG_CHECK_ATTEMPTS } else { 0 }
$LogDir = if ($env:ProgramData) { Join-Path $env:ProgramData "EthWifiAuto" } else { Split-Path $StateFile }
$LogFile = Join-Path $LogDir "switcher.log"
$LastCheckStateFile = "$StateFile.last_check"

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

function Test-InternetConnectivity {
    param([object]$Adapter)
    
    if ($null -eq $Adapter) {
        return $false
    }

    $result = $false
    
    try {
        # Get the IP address of the adapter to ensure we're testing the right interface
        $ipAddress = Get-NetIPAddress -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $ipAddress) {
            if ($LogCheckAttempts -eq 1) {
                Log-Message "No IP address on $($Adapter.Name), cannot check internet"
            }
            return $false
        }

        switch ($CheckMethod) {
            "gateway" {
                # Ping gateway - most reliable and safest method
                $gateway = Get-NetRoute -InterfaceIndex $Adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty NextHop
                if (-not $gateway) {
                    if ($LogCheckAttempts -eq 1) {
                        Log-Message "No gateway found for $($Adapter.Name)"
                    }
                    return $false
                }
                # Ping gateway with short timeout
                $pingResult = Test-Connection -ComputerName $gateway -Count 1 -TimeoutSeconds 2 -Quiet -ErrorAction SilentlyContinue
                $result = $pingResult
                if ($LogCheckAttempts -eq 1) {
                    if ($result) {
                        Log-Message "Internet check: gateway ping to $gateway via $($Adapter.Name) succeeded"
                    } else {
                        Log-Message "Internet check: gateway ping to $gateway via $($Adapter.Name) failed"
                    }
                }
            }
            
            "ping" {
                # Ping domain/IP - requires CHECK_TARGET to be set
                if ([string]::IsNullOrEmpty($CheckTarget)) {
                    Log-Message "CHECK_TARGET not set for ping method"
                    return $false
                }
                $pingResult = Test-Connection -ComputerName $CheckTarget -Count 1 -TimeoutSeconds 3 -Quiet -ErrorAction SilentlyContinue
                $result = $pingResult
                if ($LogCheckAttempts -eq 1) {
                    if ($result) {
                        Log-Message "Internet check: ping to $CheckTarget via $($Adapter.Name) succeeded"
                    } else {
                        Log-Message "Internet check: ping to $CheckTarget via $($Adapter.Name) failed"
                    }
                }
            }
            
            "curl" {
                # HTTP/HTTPS check using curl - may be blocked by providers
                if ([string]::IsNullOrEmpty($CheckTarget)) {
                    $CheckTarget = "http://captive.apple.com/hotspot-detect.html"
                }
                
                # Try curl.exe first (available in Windows 10 1803+ and Windows 11)
                $curlPath = Get-Command curl.exe -ErrorAction SilentlyContinue
                if ($curlPath) {
                    # Use curl with interface binding for accurate testing
                    $curlResult = & curl.exe --interface $Adapter.Name --connect-timeout 5 --max-time 10 -s -f -o nul $CheckTarget 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        $result = $true
                    }
                } else {
                    # Fallback to Invoke-WebRequest
                    $response = Invoke-WebRequest -Uri $CheckTarget -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
                    $result = ($response.StatusCode -eq 200)
                }
                if ($LogCheckAttempts -eq 1) {
                    if ($result) {
                        Log-Message "Internet check: HTTP check to $CheckTarget via $($Adapter.Name) succeeded"
                    } else {
                        Log-Message "Internet check: HTTP check to $CheckTarget via $($Adapter.Name) failed"
                    }
                }
            }
            
            default {
                Log-Message "Unknown CHECK_METHOD: $CheckMethod"
                return $false
            }
        }
        
        # Log state changes (always logged regardless of LogCheckAttempts)
        $lastCheckState = "unknown"
        if (Test-Path $LastCheckStateFile) {
            $lastCheckState = Get-Content $LastCheckStateFile -ErrorAction SilentlyContinue
        }
        $currentCheckState = if ($result) { "success" } else { "failed" }
        
        if ($lastCheckState -ne $currentCheckState) {
            if ($currentCheckState -eq "success") {
                Log-Message "Internet check: $($Adapter.Name) is now reachable (recovered from failure)"
            } else {
                Log-Message "Internet check: $($Adapter.Name) is now unreachable (was working before)"
            }
            Set-Content -Path $LastCheckStateFile -Value $currentCheckState
        }
        
        return $result
    } catch {
        if ($LogCheckAttempts -eq 1) {
            Log-Message "Internet check failed on $($Adapter.Name): $($_.Exception.Message)"
        }
        return $false
    }
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

    # If internet checking is enabled, verify actual internet connectivity
    if ($CheckInternet -eq 1 -and $currentState -eq "connected") {
        Log-Message "Checking internet connectivity on $($eth.Name)..."
        if (-not (Test-InternetConnectivity -Adapter $eth)) {
            Log-Message "No internet on $($eth.Name), treating as disconnected"
            $currentState = "disconnected"
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
Log-Message "Starting switcher (timeout ${Timeout}s, check_internet: $CheckInternet)"
Check-And-Switch

# Start periodic internet check if enabled
if ($CheckInternet -eq 1) {
    $timer = New-Object System.Timers.Timer
    $timer.Interval = $CheckInterval * 1000
    $timer.AutoReset = $true
    Register-ObjectEvent -InputObject $timer -EventName Elapsed -Action {
        Check-And-Switch
    } | Out-Null
    $timer.Start()
    Log-Message "Started periodic internet checker (interval: ${CheckInterval}s)"
}

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
    if ($CheckInternet -eq 1 -and $timer) {
        $timer.Stop()
        $timer.Dispose()
    }
}
