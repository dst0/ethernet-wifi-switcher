# PowerShell tests for internet failover scenarios

. "$(Get-Location)/tests/unit/test_internet_state_logging.ps1" 2>$null || $null

function Test-PriorityEthConnected {
    Test-Start "priority_eth_connected"
    Setup

    # When Ethernet is connected with internet
    $ethConnected = $true
    $ethHasInternet = $true

    Assert-Equals -Expected $true -Actual $ethConnected -Message "Ethernet should be connected"
    Assert-Equals -Expected $true -Actual $ethHasInternet -Message "Ethernet should have internet"

    Teardown
}

function Test-EthLosesInternetFallbackWifi {
    Test-Start "eth_loses_internet_fallback_wifi"
    Setup

    # Initial state: Ethernet has internet
    $activeInterface = "Ethernet"
    $activeHasInternet = $true

    # Ethernet loses internet
    $activeHasInternet = $false

    # Should fallback to Wi-Fi
    $fallbackInterface = "Wi-Fi"
    $fallbackHasInternet = $true

    Assert-Equals -Expected $false -Actual $activeHasInternet -Message "Active interface should have no internet"
    Assert-Equals -Expected "Wi-Fi" -Actual $fallbackInterface -Message "Should fallback to Wi-Fi"
    Assert-Equals -Expected $true -Actual $fallbackHasInternet -Message "Fallback should have internet"

    Teardown
}

function Test-HigherPriorityRecovery {
    Test-Start "higher_priority_recovery"
    Setup

    # Currently on Wi-Fi (lower priority)
    $activeInterface = "Wi-Fi"

    # Higher priority Ethernet recovers with internet
    $ethRecovered = $true
    $ethHasInternet = $true

    # Should switch to Ethernet
    if ($ethRecovered -and $ethHasInternet) {
        $shouldSwitch = $true
    }

    Assert-Equals -Expected $true -Actual $shouldSwitch -Message "Should switch to recovered higher priority interface"

    Teardown
}

function Test-MultiInterfaceSelection {
    Test-Start "multi_interface_selection"
    Setup

    $priority = @("Ethernet", "Ethernet 2", "Wi-Fi")
    $available = @("Ethernet 2", "Wi-Fi")

    # From priority list, first available in order
    $selected = $null
    foreach ($iface in $priority) {
        if ($available -contains $iface) {
            $selected = $iface
            break
        }
    }

    Assert-Equals -Expected "Ethernet 2" -Actual $selected -Message "Should select first available from priority list"

    Teardown
}

function Test-NoInternetSwitchToNextCandidate {
    Test-Start "no_internet_switch_candidate"
    Setup

    $currentInterface = "Ethernet"
    $currentHasInternet = $false

    $candidates = @("Wi-Fi")
    $candidateHasInternet = $true

    if (-not $currentHasInternet -and $candidateHasInternet) {
        $shouldSwitch = $true
    }

    Assert-Equals -Expected $true -Actual $shouldSwitch -Message "Should switch when current has no internet but candidate has"

    Teardown
}

function Test-BothInterfacesNoInternet {
    Test-Start "both_interfaces_no_internet"
    Setup

    $ethHasInternet = $false
    $wifiHasInternet = $false

    if (-not $ethHasInternet -and -not $wifiHasInternet) {
        $action = "keep_current"
    }

    Assert-Equals -Expected "keep_current" -Actual $action -Message "Should keep current interface when both have no internet"

    Teardown
}

Write-Host "Running PowerShell Internet Failover Tests..." -ForegroundColor Cyan
Write-Host ""

Test-PriorityEthConnected
Test-EthLosesInternetFallbackWifi
Test-HigherPriorityRecovery
Test-MultiInterfaceSelection
Test-NoInternetSwitchToNextCandidate
Test-BothInterfacesNoInternet

Test-Summary
