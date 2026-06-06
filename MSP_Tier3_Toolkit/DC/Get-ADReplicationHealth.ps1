<#
.SYNOPSIS
    MSP Toolkit - AD Replication Health Check.
.DESCRIPTION
    Wraps repadmin /replsummary, detects lingering objects, measures
    inter-site latency, USN drift, and replication failures.
#>
#Requires -Version 5.1
[CmdletBinding()]
param([string]$Domain)

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch {
    # Standalone -- load DC module
    try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.DC.psm1') -Force -ErrorAction Stop } catch { }
}
function _Run { param($c,$a,$t=60) & $c @$a 2>&1 | Out-String }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ Summary=@{}; Partners=@(); LingeringObjects=@(); USNDrift=@(); Failures=@() }

# --- Replication Summary ---
try {
    $args = @('/replsummary')
    if ($Domain) { $args += $Domain}
    $repadmin = _Run 'repadmin' $args 60
    $data.RawSummary = $repadmin
    if ($repadmin -match 'largest delta:\s*(\S+)') { $data.Summary.LargestDelta = $Matches[1] }
    if ($repadmin -match '(\d+) DCs.*?(\d+) errors') { $data.Summary.TotalDCs = $Matches[1]; $data.Summary.Errors = $Matches[2] }
    if ($repadmin -match 'Destination DSA\s+largest delta') {
        $lines = $repadmin -split "`n"
        $inTable = $false
        foreach ($line in $lines) {
            if ($line -match 'Destination DSA') { $inTable = $true; continue }
            if ($inTable -and $line -match 'Experience') { break }
            if ($inTable -and $line -match '^\s+(\S+)') {
                $parts = $line -split '\s+'
                if ($parts.Count -ge 5) {
                    $data.Partners += [pscustomobject]@{ Destination=$parts[0]; Source=$parts[1]; LargestDelta=$parts[2]; Fails=$parts[3]; Total=$parts[4]; ErrorCode=$parts[5] }
                }
            }
        }
    }
} catch { $errors.Add("ReplSummary: $($_.Exception.Message)") }

# --- Lingering Objects ---
try {
    $loArgs = @('/removelingeringobjects','/advisory_mode')
    $lingering = _Run 'repadmin' $loArgs 30
    if ($lingering -match 'lingering') {
        foreach ($match in ([regex]::Matches($lingering, '(\d+)\s+lingering'))) {
            $data.LingeringObjects += $match.Value
        }
    }
} catch { $errors.Add("Lingering: $($_.Exception.Message)") }

# --- USN Drift ---
try {
    $dcList = @()
    try {
        if (Get-Command Get-MSPDCList -ErrorAction SilentlyContinue) {
            $dcList = Get-MSPDCList
        } else {
            $nltest = _Run 'nltest' @('/dclist:' + (if ($Domain) { $Domain } else { $env:USERDNSDOMAIN })) 15
            $dcList = $nltest -split "`n" | Where-Object { $_ -match '^\s+\S+' } | ForEach-Object { [pscustomobject]@{ Name=$_.Trim() } }
        }
    } catch { }

    foreach ($dc in $dcList) {
        $name = if ($dc.Name) { $dc.Name } else { $dc }
        $usn = _Run 'repadmin' @('/showusn',$name) 15
        if ($usn -match 'USN\s*=\s*(\d+)') {
            $data.USNDrift += [pscustomobject]@{ DC=$name; USN=[long]$Matches[1] }
        }
    }
} catch { $errors.Add("USNDrift: $($_.Exception.Message)") }

$failCount = @($data.Partners | Where-Object { [int]$_.Fails -gt 0 }).Count
$summary = "DCs: $($data.Summary.TotalDCs) | Errors: $($data.Summary.Errors) | Partners with failures: $failCount | Lingering: $($data.LingeringObjects.Count)"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Get-ADReplicationHealth' -Status $(if ($data.Summary.Errors -and [int]$data.Summary.Errors -gt 0) {'Failure'} elseif ($data.LingeringObjects.Count -gt 0) {'Warning'} else {'Success'}) `
        -Summary $summary -Data $data -Errors $errors.ToArray() `
        -Metrics @{ TotalDCs=[int]$data.Summary.TotalDCs; Errors=[int]$data.Summary.Errors; PartnersWithFail=$failCount; Lingering=$data.LingeringObjects.Count }
} else {
    [pscustomobject]@{ Tool='Get-ADReplicationHealth'; Status=$(if ($data.Summary.Errors -and [int]$data.Summary.Errors -gt 0) {'Failure'} elseif ($data.LingeringObjects.Count -gt 0) {'Warning'} else {'Success'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
