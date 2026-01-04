# Event-driven Ethernet/Wi-Fi switcher for Windows
# Uses CIM Indication Events for 0% CPU idle.

$StateFile = "$env:TEMP\eth-wifi-state.txt"
$Timeout = if ($env:TIMEOUT) { [int]$env:TIMEOUT } else { 7 }
$CheckInternet = if ($env:CHECK_INTERNET) { [int]$env:CHECK_INTERNET } else { 0 }
$CheckInterval = if ($env:CHECK_INTERVAL) { [int]$env:CHECK_INTERVAL } else { 30 }
$CheckMethod = if ($env:CHECK_METHOD) { $env:CHECK_METHOD } else { "gateway" }
$CheckTarget = if ($env:CHECK_TARGET) { $env:CHECK_TARGET } else { "" }
$LogCheckAttempts = if ($env:LOG_CHECK_ATTEMPTS) { [int]$env:LOG_CHECK_ATTEMPTS } else { 0 }
$InterfacePriority = if ($env:INTERFACE_PRIORITY) { $env:INTERFACE_PRIORITY } else { "" }
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
    # If INTERFACE_PRIORITY is set, use it; otherwise default behavior
    if (-not [string]::IsNullOrEmpty($InterfacePriority)) {
        # Parse priority list and return first available ethernet adapter
        $interfaces = $InterfacePriority -split ',' | ForEach-Object { $_.Trim() }
        foreach ($ifaceName in $interfaces) {
            if (-not [string]::IsNullOrEmpty($ifaceName)) {
                $adapter = Get-NetAdapter | Where-Object {
                    $_.Name -eq $ifaceName -and
                    $_.PhysicalMediaType -match 'Ethernet|802.3' -and
                    $_.Status -ne "Not Present"
                } | Select-Object -First 1
                if ($adapter) {
                    return $adapter
                }
            }
        }
    }
    # Default: get first ethernet adapter
    Get-NetAdapter | Where-Object { $_.PhysicalMediaType -match 'Ethernet|802.3' -and $_.Status -ne "Not Present" } | Select-Object -First 1
}

function Get-WifiAdapter {
    # If INTERFACE_PRIORITY is set, check it for wifi adapters
    if (-not [string]::IsNullOrEmpty($InterfacePriority)) {
        # Parse priority list and return first available wifi adapter
        $interfaces = $InterfacePriority -split ',' | ForEach-Object { $_.Trim() }
        foreach ($ifaceName in $interfaces) {
            if (-not [string]::IsNullOrEmpty($ifaceName)) {
                $adapter = Get-NetAdapter | Where-Object {
                    $_.Name -eq $ifaceName -and
                    $_.PhysicalMediaType -match 'Wireless|Native 802.11' -and
                    $_.Status -ne "Not Present"
                } | Select-Object -First 1
                if ($adapter) {
                    return $adapter
                }
            }
        }
    }
    # Default: get first wifi adapter
    Get-NetAdapter | Where-Object { $_.PhysicalMediaType -match 'Wireless|Native 802.11' -and $_.Status -ne "Not Present" } | Select-Object -First 1
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
                    # Use curl with interface IP binding for accurate testing
                    $ipAddress = Get-NetIPAddress -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($ipAddress) {
                        $curlResult = & curl.exe --interface $ipAddress.IPAddress --connect-timeout 5 --max-time 10 -s -f -o nul $CheckTarget 2>$null
                        if ($LASTEXITCODE -eq 0) {
                            $result = $true
                        }
                    }
                } else {
                    # Fallback to Invoke-WebRequest (cannot bind to specific interface reliably)
                    try {
                        $response = Invoke-WebRequest -Uri $CheckTarget -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
                        $result = ($response.StatusCode -eq 200)
                    } catch {
                        $result = $false
                    }
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

function Ensure-WifiOnAndWait {
    param(
        [object]$Adapter
    )

    if ($null -eq $Adapter) { return }

    if (Test-WifiNeedsEnable -Adapter $Adapter) {
        if ($LogCheckAttempts -eq 1) {
            Log-Message "  Enabling WiFi ($($Adapter.Name)) to check for internet..."
        }
        Set-WifiSoftState -Adapter $Adapter -Enable $true

        if ($LogCheckAttempts -eq 1) {
            Log-Message "  Waiting for IP address on $($Adapter.Name)..."
        }

        $retries = 0
        $maxRetries = 15
        while ($retries -lt $maxRetries) {
            $config = Get-NetIPConfiguration -InterfaceIndex $Adapter.ifIndex -ErrorAction SilentlyContinue
            if ($config -and $config.IPv4Address) {
                break
            }
            Start-Sleep -Seconds 1
            $retries++
        }
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

    # Determine current active interface (the one we're currently using)
    $activeAdapter = $null
    $activeType = ""

    # Check ethernet first (higher priority)
    if (Test-EthernetConnected -Adapter $eth) {
        $activeAdapter = $eth
        $activeType = "ethernet"
    } elseif ($wifi.Status -ne "Disabled") {
        # Check if wifi is connected (has IP)
        $wifiConfig = Get-NetIPConfiguration -InterfaceIndex $wifi.ifIndex -ErrorAction SilentlyContinue
        if ($wifiConfig -and $wifiConfig.IPv4Address) {
            $activeAdapter = $wifi
            $activeType = "wifi"
        }
    }

    # If internet checking is enabled, validate the ACTIVE connection
    if ($CheckInternet -eq 1 -and $null -ne $activeAdapter) {
        $activeHasInternet = $false
        if ($LogCheckAttempts -eq 1) {
            Log-Message "Checking internet on active interface: $($activeAdapter.Name) ($activeType)"
        }

        if (Test-InternetConnectivity -Adapter $activeAdapter) {
            $activeHasInternet = $true
            if ($LogCheckAttempts -eq 1) {
                Log-Message "✓ Active interface $($activeAdapter.Name) has internet"
            }
        }

        # Always check higher priority interfaces (whether active has internet or not)
        $foundHigherPriority = $null
        $foundHigherType = ""

        if (-not [string]::IsNullOrEmpty($InterfacePriority)) {
            # Find position of active interface in priority list
            $interfaces = $InterfacePriority -split ',' | ForEach-Object { $_.Trim() }
            $activePosition = -1
            for ($i = 0; $i -lt $interfaces.Count; $i++) {
                if ($interfaces[$i] -eq $activeAdapter.Name) {
                    $activePosition = $i
                    break
                }
            }

            # Check all HIGHER priority interfaces
            if ($activePosition -gt 0) {
                if ($LogCheckAttempts -eq 1) {
                    Log-Message "Checking higher priority interfaces for recovery..."
                }

                for ($i = 0; $i -lt $activePosition; $i++) {
                    $ifaceName = $interfaces[$i]
                    if ([string]::IsNullOrEmpty($ifaceName)) {
                        continue
                    }

                    $testAdapter = Get-NetAdapter | Where-Object { $_.Name -eq $ifaceName } | Select-Object -First 1
                    if ($null -eq $testAdapter) {
                        if ($LogCheckAttempts -eq 1) {
                            Log-Message "  Interface $ifaceName not found"
                        }
                        continue
                    }

                    # Check if this is WiFi and needs enabling
                    if ($testAdapter.InterfaceDescription -match "wireless|wifi|wi-fi|802\.11" -and (Test-WifiNeedsEnable -Adapter $testAdapter)) {
                        Ensure-WifiOnAndWait -Adapter $testAdapter
                        $testAdapter = Get-NetAdapter | Where-Object { $_.Name -eq $ifaceName } | Select-Object -First 1
                    }

                    # Check if connected
                    $testConfig = Get-NetIPConfiguration -InterfaceIndex $testAdapter.ifIndex -ErrorAction SilentlyContinue
                    if ($testConfig -and $testConfig.IPv4Address) {
                        if ($LogCheckAttempts -eq 1) {
                            Log-Message "  Checking $ifaceName..."
                        }
                        if (Test-InternetConnectivity -Adapter $testAdapter) {
                            Log-Message "✓ Higher priority interface $ifaceName has internet, switching..."
                            $foundHigherPriority = $testAdapter
                            if ($testAdapter.InterfaceDescription -match "wireless|wifi|wi-fi|802\.11") {
                                $foundHigherType = "wifi"
                            } else {
                                $foundHigherType = "ethernet"
                            }
                            break
                        } else {
                            if ($LogCheckAttempts -eq 1) {
                                Log-Message "  No internet on $ifaceName"
                            }
                        }
                    } else {
                        if ($LogCheckAttempts -eq 1) {
                            Log-Message "  Interface $ifaceName is not connected"
                        }
                    }
                }
            }

            # If higher priority interface found, switch to it
            if ($null -ne $foundHigherPriority) {
                if ($foundHigherType -eq "ethernet") {
                    Log-Message "→ Switching to Ethernet ($($foundHigherPriority.Name))"
                    Write-State "connected"
                    if ($wifi.Status -ne "Disabled") {
                        Set-WifiSoftState -Adapter $wifi -Enable $false
                    }
                } elseif ($foundHigherType -eq "wifi") {
                    Log-Message "→ Switching to WiFi ($($foundHigherPriority.Name))"
                    Write-State "disconnected"
                    if (Test-WifiNeedsEnable -Adapter $foundHigherPriority) {
                        Set-WifiSoftState -Adapter $foundHigherPriority -Enable $true
                    }
                }
                return
            }
        }

        # If active interface has internet and no higher priority available, we're done
        if ($activeHasInternet) {
            # Ensure WiFi state matches the active interface type
            if ($activeType -eq "ethernet") {
                Write-State "connected"
                if (Test-WiFiEnabled) {
                    Log-Message "eth up with internet, turning wifi off"
                    Set-WiFiState -Enabled $false
                }
            } elseif ($activeType -eq "wifi") {
                Write-State "disconnected"
                # WiFi should be on (it is, since it's active)
            }
            return
        }

        # Active interface has NO internet and no higher priority works - try lower priority
        Log-Message "⚠️  Active interface $($activeAdapter.Name) has NO internet, trying alternatives..."

        # Try to find an interface with working internet
        $foundWorkingAdapter = $null
        $foundWorkingType = ""

        # Try ethernet if we're currently on wifi
        if ($activeType -eq "wifi" -and (Test-EthernetConnected -Adapter $eth)) {
            if ($LogCheckAttempts -eq 1) {
                Log-Message "  Checking $($eth.Name) (ethernet)..."
            }
            if (Test-InternetConnectivity -Adapter $eth) {
                Log-Message "✓ Found working internet on $($eth.Name)"
                $foundWorkingAdapter = $eth
                $foundWorkingType = "ethernet"
            } else {
                Log-Message "  No internet on $($eth.Name)"
            }
        }
        # Try wifi if we're currently on ethernet
        elseif ($activeType -eq "ethernet") {
            # Current ethernet has no internet, try wifi
            if (Test-WifiNeedsEnable -Adapter $wifi) {
                Ensure-WifiOnAndWait -Adapter $wifi
                # Refresh wifi adapter state
                $wifi = Get-WifiAdapter
            }

            $wifiConfig = Get-NetIPConfiguration -InterfaceIndex $wifi.ifIndex -ErrorAction SilentlyContinue
            if ($wifiConfig -and $wifiConfig.IPv4Address) {
                if ($LogCheckAttempts -eq 1) {
                    Log-Message "  Checking $($wifi.Name) (wifi)..."
                }
                if (Test-InternetConnectivity -Adapter $wifi) {
                    Log-Message "✓ Found working internet on $($wifi.Name)"
                    $foundWorkingAdapter = $wifi
                    $foundWorkingType = "wifi"
                } else {
                    Log-Message "  No internet on $($wifi.Name)"
                }
            }
        }

        # Switch to the working interface if found
        if ($null -ne $foundWorkingAdapter) {
            if ($foundWorkingType -eq "ethernet") {
                Log-Message "→ Switching to Ethernet ($($foundWorkingAdapter.Name))"
                Write-State "connected"
                if ($wifi.Status -ne "Disabled") {
                    Set-WifiSoftState -Adapter $wifi -Enable $false
                }
            } elseif ($foundWorkingType -eq "wifi") {
                Log-Message "→ Switching to WiFi ($($foundWorkingAdapter.Name))"
                Write-State "disconnected"
                if (Test-WifiNeedsEnable -Adapter $wifi) {
                    Set-WifiSoftState -Adapter $wifi -Enable $true
                }
            }
            if (-not [string]::IsNullOrEmpty($InterfacePriority)) {
                Log-Message "   Periodic checks will continue monitoring higher priority interfaces for recovery"
            }
            return
        } else {
            Log-Message "⚠️  No interface with working internet found, keeping current: $($activeAdapter.Name)"
            Log-Message "   Will continue checking all interfaces every ${CheckInterval}s until internet is restored"
            # Keep current interface even without internet (better than nothing)
            return
        }
    }

    # Standard logic when not checking internet or internet is OK
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
    if (-not [string]::IsNullOrEmpty($InterfacePriority)) {
        Log-Message "Priority-based monitoring: Will continuously check all interfaces for internet recovery"
        Log-Message "Higher priority interfaces will be preferred when multiple have connectivity"
    } else {
        Log-Message "Will continuously monitor and switch between ethernet and wifi based on connectivity"
    }
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
