<#
.SYNOPSIS
    Verify ransomware canary files have not been modified.
.DESCRIPTION
    Reads the canary registry (cached SHA256 + path), re-hashes each file,
    and triggers alerts on ANY mismatch or missing file. Designed to be
    called from the scheduled task installed by Install-RansomwareCanary.
#>
#Requires -Version 5.1
[CmdletBinding()]
param([switch]$AsJson)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$paths = Get-MSPPaths
$registryPath = Join-Path $paths.Cache 'CanaryFiles.json'
if (-not (Test-Path $registryPath)) {
    Write-Warning 'No canary registry -- run Install-RansomwareCanary first.'
    return
}

$reg = Get-Content $registryPath -Raw | ConvertFrom-Json
$drift = @()
foreach ($c in $reg) {
    if (-not (Test-Path $c.Path)) {
        $drift += [pscustomobject]@{ Path=$c.Path; Issue='MISSING'; ExpectedSHA256=$c.SHA256; ActualSHA256=$null }
        continue
    }
    $h = (Get-FileHash $c.Path -Algorithm SHA256).Hash
    if ($h -ne $c.SHA256) {
        $drift += [pscustomobject]@{ Path=$c.Path; Issue='MODIFIED'; ExpectedSHA256=$c.SHA256; ActualSHA256=$h }
    }
}

$status = if ($drift.Count) { 'Failure' } else { 'Success' }
$summary = if ($drift.Count) { "RANSOMWARE CANARY TRIGGERED: $($drift.Count) file(s) modified or missing." } else { "All $($reg.Count) canary file(s) intact." }

$result = New-MSPResult `
    -Tool 'Test-RansomwareCanary' `
    -Status $status `
    -Summary $summary `
    -Data @{ Drift = $drift; CanariesChecked = $reg.Count } `
    -Metrics @{ Drift = $drift.Count }

[void](Save-MSPResult -Result $result -Subfolder 'Security')

if ($drift.Count -gt 0) {
    # Fan out alerts -- Send-MSPNotification is fire-and-forget, won't throw
    try { $result | Send-MSPNotification -ExtraFacts @{ Drift = "$($drift.Count) file(s)" } } catch { }
    try { $result | New-MSPTicket -Priority 'Critical' } catch { }
}

if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
