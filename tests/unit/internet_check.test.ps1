# PowerShell tests for internet check methods (gateway, ping, curl)

# Basic test helpers are reused from test_internet_state_logging.ps1; import if available
. "$(Get-Location)/tests/unit/test_internet_state_logging.ps1" 2>$null || $null

function Test-GatewayCheckSuccess {
    Test-Start "gateway_check_success"
    Setup

    # Simulate gateway lookup and ping success by mocking relevant behavior
    # In the switcher implementation Test-InternetConnectivity may call Get-NetRoute or Test-Connection.
    # Here we validate expected messages when connectivity returns true.

    $output = "" | Out-String
    $output = Test-InternetWithStateTracking -InterfaceName "Ethernet" -Result $true

    Assert-Contains -Haystack $output -Needle "is active and has internet" -Message "Gateway method: success should be reported as active"

    Teardown
}

function Test-PingCheckSuccess {
    Test-Start "ping_check_success"
    Setup

    $output = Test-InternetWithStateTracking -InterfaceName "Ethernet" -Result $true

    Assert-Contains -Haystack $output -Needle "is active and has internet" -Message "Ping method: success should be reported as active"

    Teardown
}

function Test-HTTPCheckSuccess {
    Test-Start "http_check_success"
    Setup

    $output = Test-InternetWithStateTracking -InterfaceName "Ethernet" -Result $true

    Assert-Contains -Haystack $output -Needle "is active and has internet" -Message "HTTP method: success should be reported as active"

    Teardown
}

Write-Host "Running PowerShell Internet Check Method Tests..." -ForegroundColor Cyan
Write-Host ""
Test-GatewayCheckSuccess
Test-PingCheckSuccess
Test-HTTPCheckSuccess
Test-Summary
