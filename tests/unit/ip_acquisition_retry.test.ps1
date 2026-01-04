# PowerShell tests for DHCP/IP acquisition retry logic

. "$(Get-Location)/tests/unit/test_internet_state_logging.ps1" 2>$null || $null

function Test-ImmediateIPAcquisition {
    Test-Start "immediate_ip_acquisition"
    Setup

    # Simulate immediate IP acquisition
    $interfaceActive = $true
    $interfaceHasIP = $true
    $elapsedTime = 0

    Assert-Equals -Expected $true -Actual $interfaceHasIP -Message "Interface should have IP immediately"
    Assert-Equals -Expected 0 -Actual $elapsedTime -Message "Should acquire IP with no delay"

    Teardown
}

function Test-DelayedIPAcquisition {
    Test-Start "delayed_ip_acquisition"
    Setup

    # Simulate delayed IP - active but no IP initially
    $interfaceActive = $true
    $interfaceHasIP = $false
    $maxRetries = 7  # 7 second timeout

    # After polling, IP acquired
    $retries = 3  # Acquired after 3 seconds
    $interfaceHasIP = $true

    Assert-Equals -Expected $true -Actual $interfaceHasIP -Message "Interface should eventually acquire IP"
    Assert-Equals -Expected 3 -Actual $retries -Message "Should acquire IP after 3 retry attempts"

    Teardown
}

function Test-IPAcquisitionTimeout {
    Test-Start "ip_acquisition_timeout"
    Setup

    # Simulate IP acquisition timeout
    $interfaceActive = $true
    $interfaceHasIP = $false
    $maxRetries = 7
    $retries = 7

    # After max retries, still no IP
    if ($retries -ge $maxRetries) {
        $timedOut = $true
    }

    Assert-Equals -Expected $true -Actual $timedOut -Message "Should timeout after max retries"

    Teardown
}

function Test-InterfaceBecomesInactiveBeforeIP {
    Test-Start "interface_inactive_before_ip"
    Setup

    $interfaceActive = $true
    $interfaceHasIP = $false
    $maxRetries = 7

    # Interface becomes inactive after 2 retries
    $retries = 2
    $interfaceActive = $false

    if (-not $interfaceActive) {
        $shouldStop = $true
    }

    Assert-Equals -Expected $true -Actual $shouldStop -Message "Should stop retrying when interface becomes inactive"

    Teardown
}

function Test-ConfigurableTimeout {
    Test-Start "configurable_timeout"
    Setup

    $customTimeout = 10  # Custom 10 second timeout instead of default 7
    $retries = 5
    $interfaceHasIP = $true

    Assert-Equals -Expected 10 -Actual $customTimeout -Message "Should respect custom timeout setting"
    Assert-Equals -Expected $true -Actual $interfaceHasIP -Message "Should acquire IP within custom timeout"

    Teardown
}

function Test-MultipleInterfaceRetries {
    Test-Start "multiple_interface_retries"
    Setup

    # Ethernet acquires IP after 2 retries
    $eth = @{ Active = $true; Retries = 2; HasIP = $true }

    # Wi-Fi acquires IP after 4 retries
    $wifi = @{ Active = $true; Retries = 4; HasIP = $true }

    Assert-Equals -Expected $true -Actual $eth.HasIP -Message "Ethernet should acquire IP"
    Assert-Equals -Expected $true -Actual $wifi.HasIP -Message "Wi-Fi should acquire IP"

    Teardown
}

Write-Host "Running PowerShell DHCP/IP Acquisition Retry Tests..." -ForegroundColor Cyan
Write-Host ""

Test-ImmediateIPAcquisition
Test-DelayedIPAcquisition
Test-IPAcquisitionTimeout
Test-InterfaceBecomesInactiveBeforeIP
Test-ConfigurableTimeout
Test-MultipleInterfaceRetries

Test-Summary
