<#
.SYNOPSIS
    MSP Toolkit - Playbook engine.
.DESCRIPTION
    Runs decision-tree style remediation playbooks. A playbook is JSON
    describing a precondition test, an ordered list of steps (each with
    its own retry/verify/rollback), and an overall success criterion.

    Schema (msp-playbook/v1):
      {
        "name": "Fix-Printing",
        "version": "1.0",
        "description": "Common print-failure remediation in order",
        "stopOnSuccess": true,        # exit once verify passes
        "requireAdmin": true,
        "verify": { "type":"script", "script":"Get-Service Spooler | ? Status -eq Running" },
        "steps": [
          { "name":"restart-spooler", "script":"...", "verify":"...", "rollback":"..." },
          { ... }
        ]
      }

    Each step has:
      - script:    PowerShell scriptblock body (string)
      - verify:    optional scriptblock; truthy result = step succeeded
      - rollback:  optional scriptblock on failure
      - retry:     int (default 1)
      - timeoutSec:int (default 60)
      - admin:     bool, refuse to run if not elevated

    Output: structured MSP result with per-step trace and verify result.
#>

Set-StrictMode -Version Latest

function Invoke-MSPPlaybook {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ParameterSetName='Path')] [string]$Path,
        [Parameter(Mandatory, ParameterSetName='Inline')] [object]$Playbook,
        [hashtable]$Variables = @{}
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        if (-not (Test-Path $Path)) { throw "Playbook not found: $Path" }
        $pb = Get-Content $Path -Raw | ConvertFrom-Json
    } else {
        $pb = $Playbook
    }

    if ($pb.PSObject.Properties.Name -contains 'requireAdmin' -and $pb.requireAdmin -and -not (Test-MSPElevation)) {
        throw "Playbook '$($pb.name)' requires Administrator."
    }

    $steps = New-Object System.Collections.Generic.List[pscustomobject]
    $stopOnSuccess = if ($pb.PSObject.Properties.Name -contains 'stopOnSuccess') { [bool]$pb.stopOnSuccess } else { $true }

    function _Run([string]$Body, [int]$TimeoutSec) {
        $sb = [scriptblock]::Create($Body)
        $job = Start-Job -ScriptBlock $sb
        if (-not (Wait-Job $job -Timeout $TimeoutSec)) {
            Stop-Job $job; Remove-Job $job -Force
            throw "Timed out after $TimeoutSec s"
        }
        $output = Receive-Job $job -ErrorAction Continue
        Remove-Job $job -Force
        return $output
    }

    function _VerifyPasses($Verify) {
        if (-not $Verify) { return $true }
        try {
            $vTo = 30
            if ($Verify.PSObject.Properties.Name -contains 'timeoutSec' -and $Verify.timeoutSec) { $vTo = [int]$Verify.timeoutSec }
            $v = _Run -Body $Verify.script -TimeoutSec $vTo
            if ($v -is [bool]) { return $v }
            return [bool]$v
        } catch { return $false }
    }

    # Check overall verify first -- if already healthy, no-op
    if ($pb.PSObject.Properties.Name -contains 'verify' -and $pb.verify) {
        if (_VerifyPasses $pb.verify) {
            return New-MSPResult -Tool "Playbook/$($pb.name)" -Status 'Success' `
                   -Summary "Already healthy -- no remediation needed." `
                   -Data @{ Skipped = $true; Steps = @() } `
                   -Metrics @{ StepsRun = 0 }
        }
    }

    $overallSuccess = $false
    foreach ($s in $pb.steps) {
        if ($s.PSObject.Properties.Name -contains 'admin' -and $s.admin -and -not (Test-MSPElevation)) {
            $steps.Add([pscustomobject]@{
                Step=$s.name; Status='Skipped'; Reason='Admin required'; DurationMs=0
            })
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($s.name, 'Run playbook step')) {
            $steps.Add([pscustomobject]@{ Step=$s.name; Status='Skipped'; Reason='WhatIf'; DurationMs=0 })
            continue
        }

        $retry = if ($s.PSObject.Properties.Name -contains 'retry') { [int]$s.retry } else { 1 }
        $timeout = if ($s.PSObject.Properties.Name -contains 'timeoutSec') { [int]$s.timeoutSec } else { 60 }
        $verify = if ($s.PSObject.Properties.Name -contains 'verify') { $s.verify } else { $null }
        $rollback = if ($s.PSObject.Properties.Name -contains 'rollback') { $s.rollback } else { $null }

        $sw = [Diagnostics.Stopwatch]::StartNew()
        $stepOk = $false
        $lastErr = $null
        for ($attempt = 1; $attempt -le $retry; $attempt++) {
            try {
                _Run -Body $s.script -TimeoutSec $timeout | Out-Null
                if (_VerifyPasses $verify) { $stepOk = $true; break }
            } catch { $lastErr = $_.Exception.Message }
        }

        $row = [pscustomobject]@{
            Step       = $s.name
            Status     = if ($stepOk) { 'Succeeded' } else { 'Failed' }
            Attempts   = $attempt
            DurationMs = $sw.ElapsedMilliseconds
            Error      = $lastErr
            Reason     = $null
        }
        $steps.Add($row)

        if (-not $stepOk -and $rollback) {
            try { _Run -Body $rollback -TimeoutSec 30 | Out-Null } catch { }
        }

        # Check overall health after each step
        if (_VerifyPasses $pb.verify) {
            $overallSuccess = $true
            if ($stopOnSuccess) { break }
        }
    }

    if (-not $overallSuccess) {
        $overallSuccess = _VerifyPasses $pb.verify
    }

    $failedSteps = @($steps | Where-Object { $_.Status -eq 'Failed' })
    $status = if ($overallSuccess) { 'Success' } elseif ($failedSteps.Count -gt 0) { 'Failure' } else { 'Warning' }
    New-MSPResult `
        -Tool "Playbook/$($pb.name)" `
        -Status $status `
        -Summary "Ran $($steps.Count) steps; overall verify $(if ($overallSuccess) {'PASSED'} else {'FAILED'})." `
        -Data @{ Playbook = $pb.name; Steps = $steps.ToArray(); OverallHealthy = $overallSuccess } `
        -Metrics @{ StepsRun = $steps.Count; StepsFailed = $failedSteps.Count }
}

Export-ModuleMember -Function 'Invoke-MSPPlaybook'
