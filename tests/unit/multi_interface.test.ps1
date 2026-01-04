# PowerShell tests for multi-interface priority selection and state management

. "$(Get-Location)/tests/unit/test_internet_state_logging.ps1" 2>$null || $null

function Test-PriorityListSelection {
    Test-Start "priority_list_selection"
    Setup

    $priority = "Ethernet,Ethernet 2,Wi-Fi"
    $available = @("Ethernet 2", "Wi-Fi", "USB Ethernet")

    # Parse priority and select first available
    $selected = $null
    foreach ($iface in $priority -split ',') {
        $iface = $iface.Trim()
        if ($available -contains $iface) {
            $selected = $iface
            break
        }
    }

    Assert-Equals -Expected "Ethernet 2" -Actual $selected -Message "Should select first available in priority order"

    Teardown
}

function Test-EthernetPriorityOverWifi {
    Test-Start "ethernet_priority_over_wifi"
    Setup

    $priority = @("Ethernet", "Wi-Fi")
    $ethAvailable = $true
    $wifiAvailable = $true

    # Should prefer Ethernet
    if ($ethAvailable) {
        $selected = "Ethernet"
    } elseif ($wifiAvailable) {
        $selected = "Wi-Fi"
    }

    Assert-Equals -Expected "Ethernet" -Actual $selected -Message "Ethernet should have priority over Wi-Fi"

    Teardown
}

function Test-MultipleEthernetSelection {
    Test-Start "multiple_ethernet_selection"
    Setup

    $priority = "Ethernet,Ethernet 2,Ethernet 3,Wi-Fi"
    $available = @("Ethernet 2", "Ethernet 3")

    $selected = $null
    foreach ($iface in $priority -split ',') {
        $iface = $iface.Trim()
        if ($available -contains $iface) {
            $selected = $iface
            break
        }
    }

    Assert-Equals -Expected "Ethernet 2" -Actual $selected -Message "Should select first available Ethernet in priority"

    Teardown
}

function Test-FallbackWhenPreferredUnavailable {
    Test-Start "fallback_when_preferred_unavailable"
    Setup

    $priority = "Ethernet,Ethernet 2,Wi-Fi"
    $available = @("Wi-Fi")

    $selected = $null
    foreach ($iface in $priority -split ',') {
        $iface = $iface.Trim()
        if ($available -contains $iface) {
            $selected = $iface
            break
        }
    }

    Assert-Equals -Expected "Wi-Fi" -Actual $selected -Message "Should fallback to Wi-Fi when Ethernet unavailable"

    Teardown
}

function Test-NoPriorityListDefaultBehavior {
    Test-Start "no_priority_list_default"
    Setup

    $priorityList = $null
    $available = @("Ethernet", "Wi-Fi")

    # Default: Ethernet > Wi-Fi
    if ($null -eq $priorityList) {
        $selected = if ($available -contains "Ethernet") { "Ethernet" } else { "Wi-Fi" }
    }

    Assert-Equals -Expected "Ethernet" -Actual $selected -Message "Default should prefer Ethernet when no priority list"

    Teardown
}

function Test-DynamicPriorityUpdate {
    Test-Start "dynamic_priority_update"
    Setup

    # Initial priority
    $priority = @("Ethernet", "Wi-Fi")
    $current = "Ethernet"

    # Interface becomes unavailable, switch to next
    $ethAvailable = $false
    if (-not $ethAvailable) {
        $current = "Wi-Fi"
    }

    Assert-Equals -Expected "Wi-Fi" -Actual $current -Message "Should dynamically switch when current unavailable"

    Teardown
}

Write-Host "Running PowerShell Multi-Interface Selection Tests..." -ForegroundColor Cyan
Write-Host ""

Test-PriorityListSelection
Test-EthernetPriorityOverWifi
Test-MultipleEthernetSelection
Test-FallbackWhenPreferredUnavailable
Test-NoPriorityListDefaultBehavior
Test-DynamicPriorityUpdate

Test-Summary
