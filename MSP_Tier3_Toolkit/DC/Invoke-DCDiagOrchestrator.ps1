<#
.SYNOPSIS
    MSP Toolkit - DCDiag Orchestrator.
.DESCRIPTION
    Runs targeted DCDiag tests (or all), parses results into MSP
    result envelope with per-test pass/fail detail.
.PARAMETER Tests
    Specific tests to run (e.g., 'DNS','Replications','NetLogons'). Default: all.
.PARAMETER ComputerName
    Target DC. Default: localhost.
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string[]]$Tests,
    [string]$ComputerName = $env:COMPUTERNAME
)

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }
function _Run { param($c,$a,$t=120) & $c @$a 2>&1 | Out-String }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ TestResults=@(); Summary=@{}; Passed=0; Failed=0; Total=0; Failures=@() }

try {
    $args = @('/s:' + $ComputerName, '/c')
    if ($Tests) { $args += '/test:' + ($Tests -join ',') }
    $dcdiag = _Run 'dcdiag' $args 120

    $data.Raw = $dcdiag
    $currentTest = $null

    foreach ($line in ($dcdiag -split "`n")) {
        # Test start: "Starting test: Replications"
        if ($line -match 'Starting test:\s+(.+)') {
            if ($currentTest) {
                $data.TestResults += $currentTest
                $data.Total++
                if ($currentTest.Passed) { $data.Passed++ } else { $data.Failed++; $data.Failures += $currentTest.Name }
            }
            $currentTest = [pscustomobject]@{ Name=$Matches[1].Trim(); Passed=$true; Detail=''; Errors=@() }
            continue
        }
        # Test passed/failed
        if ($currentTest) {
            if ($line -match 'passed test') {
                $currentTest.Passed = $true
                $currentTest.Detail = $line.Trim()
            } elseif ($line -match 'failed test|error|fail') {
                $currentTest.Passed = $false
                $currentTest.Detail = $line.Trim()
                $currentTest.Errors += $line.Trim()
            }
        }
    }
    if ($currentTest) {
        $data.TestResults += $currentTest
        $data.Total++
        if ($currentTest.Passed) { $data.Passed++ } else { $data.Failed++; $data.Failures += $currentTest.Name }
    }

    # Overall summary line
    if ($dcdiag -match '(\d+)\s+tests.*?(\d+)\s+failed.*?(\d+)\s+passed') {
        $data.Summary = @{ Total=$Matches[1]; Failed=$Matches[2]; Passed=$Matches[3] }
    }

    $summary = "DCDiag: $($data.Passed)/$($data.Total) passed | Failed: $($data.Failed)"

    if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
        New-MSPResult -Tool 'Invoke-DCDiagOrchestrator' -Status $(if ($data.Failed -eq 0) {'Success'} else {'Failure'}) `
            -Summary $summary -Data $data -Errors $errors.ToArray() `
            -Metrics @{ Total=$data.Total; Passed=$data.Passed; Failed=$data.Failed }
    } else {
        [pscustomobject]@{ Tool='Invoke-DCDiagOrchestrator'; Status=$(if ($data.Failed -eq 0) {'Success'} else {'Failure'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
    }
} catch {
    $errors.Add("DCDiag failed: $($_.Exception.Message)")
    if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
        New-MSPResult -Tool 'Invoke-DCDiagOrchestrator' -Status 'Failure' -Summary 'DCDiag execution failed' -Data $data -Errors $errors.ToArray()
    } else {
        [pscustomobject]@{ Tool='Invoke-DCDiagOrchestrator'; Status='Failure'; Summary='DCDiag execution failed'; Errors=$errors.ToArray() }
    }
}
