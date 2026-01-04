# PowerShell test for internet state logging
# Tests the state tracking logic for Windows switcher

# Test framework variables
$script:TestCount = 0
$script:TestPassCount = 0
$script:TestFailCount = 0
$script:CurrentTest = ""
$script:CurrentTestAssertions = 0
$script:CurrentTestPassed = 0
$script:CurrentTestFailed = 0

# Mock function for state tracking (extracted from switcher.ps1)
function Test-InternetWithStateTracking {
    param(
        [string]$InterfaceName,
        [bool]$Result
    )

    $StateFile = $env:STATE_FILE
    if (-not $StateFile) { $StateFile = "$env:TEMP\test-eth-wifi-state" }
    $LastCheckStateFile = "$StateFile.last_check"

    # Log state changes (always logged regardless of LogCheckAttempts)
    $lastCheckState = ""
    if (Test-Path $LastCheckStateFile) {
        $lastCheckState = Get-Content $LastCheckStateFile -ErrorAction SilentlyContinue
    }
    $currentCheckState = if ($Result) { "success" } else { "failed" }

    if ([string]::IsNullOrEmpty($lastCheckState)) {
        # First run - initialize state with specific message based on result
        if ($currentCheckState -eq "success") {
            Write-Output "Internet check: $InterfaceName is active and has internet"
        } else {
            Write-Output "Internet check: $InterfaceName connection is not active"
        }
        Set-Content -Path $LastCheckStateFile -Value $currentCheckState
    } elseif ($lastCheckState -ne $currentCheckState) {
        # State changed - log the transition
        if ($currentCheckState -eq "success") {
            Write-Output "Internet check: $InterfaceName is now reachable (recovered from failure)"
        } else {
            Write-Output "Internet check: $InterfaceName is now unreachable (was working before)"
        }
        Set-Content -Path $LastCheckStateFile -Value $currentCheckState
    }
}

function Test-Start {
    param([string]$Name)

    if ($script:CurrentTest) {
        Test-End
    }

    $script:CurrentTest = $Name
    $script:TestCount++
    $script:CurrentTestAssertions = 0
    $script:CurrentTestPassed = 0
    $script:CurrentTestFailed = 0
}

function Test-End {
    if ($script:CurrentTestFailed -gt 0) {
        $script:TestFailCount++
        Write-Host "✗ $script:CurrentTest ($script:CurrentTestPassed/$script:CurrentTestAssertions assertions passed)" -ForegroundColor Red
    } else {
        $script:TestPassCount++
        Write-Host "✓ $script:CurrentTest ($script:CurrentTestAssertions/$script:CurrentTestAssertions assertions)" -ForegroundColor Green
    }
}

function Assert-Equals {
    param(
        [string]$Expected,
        [string]$Actual,
        [string]$Message
    )

    $script:CurrentTestAssertions++

    if ($Expected -eq $Actual) {
        $script:CurrentTestPassed++
    } else {
        Write-Host "  ✗ $Message (expected: '$Expected', got: '$Actual')" -ForegroundColor Red
        $script:CurrentTestFailed++
    }
}

function Assert-Contains {
    param(
        [string]$Haystack,
        [string]$Needle,
        [string]$Message
    )

    $script:CurrentTestAssertions++

    if ($Haystack -like "*$Needle*") {
        $script:CurrentTestPassed++
    } else {
        Write-Host "  ✗ $Message (string not found: '$Needle')" -ForegroundColor Red
        $script:CurrentTestFailed++
    }
}

function Setup {
    # Ensure we have a writable temp dir (pwsh on macOS may not set $env:TEMP)
    $temp = $env:TEMP
    if (-not $temp -or $temp -eq "") {
        if ($env:TMPDIR) { $temp = $env:TMPDIR } elseif ($env:HOME) { $temp = $env:HOME } else { $temp = "/tmp" }
    }
    $script:StateFile = Join-Path $temp "test-eth-wifi-state-$PID"
    $script:LastCheckStateFile = "$script:StateFile.last_check"
    $env:STATE_FILE = $script:StateFile

    if (Test-Path $script:StateFile) { Remove-Item $script:StateFile -Force -ErrorAction SilentlyContinue }
    if (Test-Path $script:LastCheckStateFile) { Remove-Item $script:LastCheckStateFile -Force -ErrorAction SilentlyContinue }
}

function Teardown {
    if (Test-Path $script:StateFile) { Remove-Item $script:StateFile -Force }
    if (Test-Path $script:LastCheckStateFile) { Remove-Item $script:LastCheckStateFile -Force }
}

function Test-Summary {
    if ($script:CurrentTest) {
        Test-End
    }

    Write-Host ""
    Write-Host "=================================="
    Write-Host "Test Summary"
    Write-Host "=================================="
    if ($script:TestFailCount -eq 0) {
        Write-Host "Tests: $script:TestPassCount passed ($script:TestCount total)" -ForegroundColor Green
    } else {
        Write-Host "Tests: $script:TestPassCount passed, $script:TestFailCount failed ($script:TestCount total)" -ForegroundColor Yellow
    }
    Write-Host "=================================="

    if ($script:TestFailCount -gt 0) {
        exit 1
    }
}

# Test: First initialization with successful internet check
function Test-InitializationWithInternet {
    Test-Start "initialization_with_internet"
    Setup

    $output = Test-InternetWithStateTracking -InterfaceName "Ethernet" -Result $true

    Assert-Contains -Haystack $output -Needle "is active and has internet" -Message "Should show active with internet on first success"

    # Verify state file was created
    $state = Get-Content $script:LastCheckStateFile -ErrorAction SilentlyContinue
    Assert-Equals -Expected "success" -Actual $state -Message "State file should contain 'success'"

    Teardown
}

# Test: First initialization with failed internet check
function Test-InitializationWithoutInternet {
    Test-Start "initialization_without_internet"
    Setup

    $output = Test-InternetWithStateTracking -InterfaceName "Ethernet" -Result $false

    Assert-Contains -Haystack $output -Needle "connection is not active" -Message "Should show not active on first failure"

    # Verify state file was created
    $state = Get-Content $script:LastCheckStateFile -ErrorAction SilentlyContinue
    Assert-Equals -Expected "failed" -Actual $state -Message "State file should contain 'failed'"

    Teardown
}

# Test: Recovery from failure (failed -> success)
function Test-RecoveryFromFailure {
    Test-Start "recovery_from_failure"
    Setup

    # First call - initialize with failure
    Test-InternetWithStateTracking -InterfaceName "Ethernet" -Result $false | Out-Null

    # Second call - recover
    $output = Test-InternetWithStateTracking -InterfaceName "Ethernet" -Result $true

    Assert-Contains -Haystack $output -Needle "recovered from failure" -Message "Should show recovery message"

    # Verify state changed to success
    $state = Get-Content $script:LastCheckStateFile
    Assert-Equals -Expected "success" -Actual $state -Message "State should be 'success' after recovery"

    Teardown
}

# Test: Loss of internet (success -> failed)
function Test-LossOfInternet {
    Test-Start "loss_of_internet"
    Setup

    # First call - initialize with success
    Test-InternetWithStateTracking -InterfaceName "Ethernet" -Result $true | Out-Null

    # Second call - lose internet
    $output = Test-InternetWithStateTracking -InterfaceName "Ethernet" -Result $false

    Assert-Contains -Haystack $output -Needle "was working before" -Message "Should show loss message"

    # Verify state changed to failed
    $state = Get-Content $script:LastCheckStateFile
    Assert-Equals -Expected "failed" -Actual $state -Message "State should be 'failed' after loss"

    Teardown
}

# Test: No logging when state doesn't change (success -> success)
function Test-NoLoggingOnSameStateSuccess {
    Test-Start "no_logging_same_state_success"
    Setup

    # First call - initialize with success
    Test-InternetWithStateTracking -InterfaceName "Ethernet" -Result $true | Out-Null

    # Second call - still success (should produce no output)
    $output = Test-InternetWithStateTracking -InterfaceName "Ethernet" -Result $true

    Assert-Equals -Expected "" -Actual $output -Message "Should not log when state unchanged"

    Teardown
}

# Test: No logging when state doesn't change (failed -> failed)
function Test-NoLoggingOnSameStateFailed {
    Test-Start "no_logging_same_state_failed"
    Setup

    # First call - initialize with failure
    Test-InternetWithStateTracking -InterfaceName "Ethernet" -Result $false | Out-Null

    # Second call - still failed (should produce no output)
    $output = Test-InternetWithStateTracking -InterfaceName "Ethernet" -Result $false

    Assert-Equals -Expected "" -Actual $output -Message "Should not log when state unchanged"

    Teardown
}

# Test: Multiple state changes
function Test-MultipleStateChanges {
    Test-Start "multiple_state_changes"
    Setup

    # Init with success
    $output1 = Test-InternetWithStateTracking -InterfaceName "Ethernet" -Result $true
    Assert-Contains -Haystack $output1 -Needle "is active and has internet" -Message "First message should be initialization"

    # Lose internet
    $output2 = Test-InternetWithStateTracking -InterfaceName "Ethernet" -Result $false
    Assert-Contains -Haystack $output2 -Needle "was working before" -Message "Second message should be loss"

    # Recover
    $output3 = Test-InternetWithStateTracking -InterfaceName "Ethernet" -Result $true
    Assert-Contains -Haystack $output3 -Needle "recovered from failure" -Message "Third message should be recovery"

    # Lose again
    $output4 = Test-InternetWithStateTracking -InterfaceName "Ethernet" -Result $false
    Assert-Contains -Haystack $output4 -Needle "was working before" -Message "Fourth message should be loss again"

    Teardown
}

# Run all tests
Write-Host "Running PowerShell Internet State Logging Tests..." -ForegroundColor Cyan
Write-Host ""

Test-InitializationWithInternet
Test-InitializationWithoutInternet
Test-RecoveryFromFailure
Test-LossOfInternet
Test-NoLoggingOnSameStateSuccess
Test-NoLoggingOnSameStateFailed
Test-MultipleStateChanges

Test-Summary
