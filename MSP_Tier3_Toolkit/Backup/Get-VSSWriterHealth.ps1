<#
.SYNOPSIS
    MSP Toolkit - VSS Writer Health Check.
.DESCRIPTION
    Enumerates all VSS writers, checks their state, last error,
    and flags writers in non-stable states. Auto-retries on failures.
#>
#Requires -Version 5.1
[CmdletBinding()]
param([switch]$AutoRetry)

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ Writers=@(); Healthy=0; Unstable=0; Failed=0; Retried=@() }

try {
    $writers = vssadmin list writers 2>&1 | Out-String
    $currentWriter = $null

    foreach ($line in ($writers -split "`n")) {
        if ($line -match "Writer name:\s+'(.+)'") {
            if ($currentWriter) { $data.Writers += $currentWriter }
            $currentWriter = [pscustomobject]@{ Name=$Matches[1]; ID=''; InstanceID=''; State='Unknown'; LastError=''; Healthy=$false }
        }
        if (-not $currentWriter) { continue }
        if ($line -match "Writer Id:\s+{(.+)}") { $currentWriter.ID = $Matches[1] }
        if ($line -match "Writer Instance Id:\s+{(.+)}") { $currentWriter.InstanceID = $Matches[1] }
        if ($line -match "State:\s+\[(\d+)\]\s+(.+)") { $currentWriter.State = $Matches[2].Trim(); $currentWriter.Healthy = ($Matches[1] -eq '1') }
        if ($line -match "Last error:\s+(.+)") { $currentWriter.LastError = $Matches[1].Trim() }
    }
    if ($currentWriter) { $data.Writers += $currentWriter }

    $data.Healthy = ($data.Writers | Where-Object Healthy).Count
    $data.Unstable = ($data.Writers | Where-Object { -not $_.Healthy -and $_.State -ne 'Unknown' }).Count
    $data.Failed = ($data.Writers | Where-Object { -not $_.Healthy }).Count

    # Auto-retry: restart VSS service and recheck
    if ($AutoRetry -and $data.Failed -gt 0) {
        try {
            Restart-Service -Name 'VSS' -Force -ErrorAction Stop
            Start-Sleep -Seconds 5
            $retryWriters = vssadmin list writers 2>&1 | Out-String
            $data.Retried = ($retryWriters -split "`n" | Where-Object { $_ -match "State:\s+\[1\]" }).Count
        } catch { $errors.Add("Auto-retry failed: $($_.Exception.Message)") }
    }
} catch { $errors.Add("VSS enumeration failed: $($_.Exception.Message)") }

$summary = "VSS Writers: $($data.Healthy)/$($data.Writers.Count) healthy | Failed: $($data.Failed)"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Get-VSSWriterHealth' -Status $(if ($data.Failed -eq 0) {'Success'} else {'Warning'}) `
        -Summary $summary -Data $data -Errors $errors.ToArray() `
        -Metrics @{ Total=$data.Writers.Count; Healthy=$data.Healthy; Failed=$data.Failed; Retried=$data.Retried.Count }
} else {
    [pscustomobject]@{ Tool='Get-VSSWriterHealth'; Status=$(if ($data.Failed -eq 0) {'Success'} else {'Warning'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
