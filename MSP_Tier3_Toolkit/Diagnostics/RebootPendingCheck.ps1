<#
.SYNOPSIS
    Detect whether the system needs a reboot, and why.
.DESCRIPTION
    Thin wrapper around Test-MSPPendingReboot that emits a structured result
    object. Use locally, schedule it via Task Scheduler, or fan out via fleet.
.EXAMPLE
    .\RebootPendingCheck.ps1
#>
#Requires -Version 5.1
[CmdletBinding()]
param([switch]$AsJson)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$check  = Test-MSPPendingReboot
$status = if ($check.PendingReboot) { 'Warning' } else { 'Success' }
$summary = if ($check.PendingReboot) {
    "Reboot pending: $($check.Reasons -join ', ')"
} else {
    'No pending reboot detected.'
}

$result = New-MSPResult `
    -Tool 'RebootPendingCheck' `
    -Status $status `
    -Summary $summary `
    -Data $check `
    -Metrics @{ ReasonCount = $check.Reasons.Count }

[void](Save-MSPResult -Result $result -Subfolder 'Diagnostics')

if ($AsJson) { $result | ConvertTo-Json -Depth 6 } else { $result }
