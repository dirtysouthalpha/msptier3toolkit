<#
.SYNOPSIS
    MSP Toolkit - macOS Disk Health Check.
.DESCRIPTION
    Checks APFS volumes, SMART status, FileVault encryption,
    and disk utilization. Wraps diskutil + tmutil for backup info.
#>
#Requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }

function _Run { param($c,$a,$t=15) & $c @$a 2>&1 | Out-String }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{}
$checks = @{ Passed = 0; Total = 0 }

# --- SMART Status ---
$data.SMART = @()
try {
    $disks = (_Run 'diskutil' @('list')) -split "`n" | ForEach-Object { if ($_ -match '^\s+\d+:.*\(internal\)') { ($_ -split '\s+')[0] } }
    foreach ($disk in $disks) {
        if (-not $disk) { continue }
        $info = _Run 'diskutil' @('info',"/dev/disk$disk") 10
        $smart = if ($info -match 'SMART Status:\s+(.+)') { $Matches[1].Trim() } else { 'Unknown' }
        $name  = if ($info -match 'Device / Media Name:\s+(.+)') { $Matches[1].Trim() } else { "disk$disk" }
        $data.SMART += @{ Disk="disk$disk"; Name=$name; SMART=$smart; Healthy=($smart -eq 'Verified') }
        $checks.Total++
        if ($smart -eq 'Verified') { $checks.Passed++ }
    }
} catch { $errors.Add("SMART: $($_.Exception.Message)") }

# --- Volume Info ---
$data.Volumes = @()
try {
    $apfs = _Run 'diskutil' @('apfs','list') 15
    $lines = $apfs -split "`n"
    foreach ($line in $lines) {
        if ($line -match '^\|\s+\+--\s+([A-F0-9\-]+)\s+(\S+)') {
            $volUUID = $Matches[1]
            $volName = $Matches[2].Trim()
            $data.Volumes += @{ Name=$volName; UUID=$volUUID; Container=$null }
        }
    }
} catch { $errors.Add("APFS: $($_.Exception.Message)") }

# --- Disk Usage ---
$data.Usage = @()
try {
    $df = _Run 'df' @('-h','-l') 10
    foreach ($line in ($df -split "`n" | Select-Object -Skip 1)) {
        if ($line -match '^/dev/') {
            $parts = $line -split '\s+'
            if ($parts.Count -ge 9) {
                $data.Usage += @{
                    Filesystem = $parts[0]; Size=$parts[1]; Used=$parts[2]; Avail=$parts[3]
                    UsePct=$parts[4]; MountPoint=$parts[8]
                }
                $checks.Total++
                $useNum = $parts[4] -replace '%',''
                if ([int]$useNum -lt 90) { $checks.Passed++ }
            }
        }
    }
} catch { $errors.Add("DiskUsage: $($_.Exception.Message)") }

# --- FileVault ---
try {
    $fv = _Run 'fdesetup' @('status') 10
    $data.FileVault = @{
        Enabled = ($fv -match 'FileVault is On')
        Status  = if ($fv -match 'FileVault is On') { 'Encrypted' } else { 'Not Encrypted' }
    }
    $checks.Total++
    if ($data.FileVault.Enabled) { $checks.Passed++ }
} catch { $errors.Add("FileVault: $($_.Exception.Message)") }

# --- Time Machine ---
try {
    $tm = _Run 'tmutil' @('destinationinfo') 10
    $data.TimeMachine = @{
        HasDestination = ($tm -match 'Name')
        Destinations = if ($tm -match 'Name\s+:\s+(.+)') { @($Matches[1]) } else { @() }
        LastBackup = if ($tm -match 'Latest\s*:\s*(.+)') { $Matches[1].Trim() } else { 'Unknown' }
    }
} catch { $errors.Add("TimeMachine: $($_.Exception.Message)") }

$score = if ($checks.Total -gt 0) { [math]::Round(($checks.Passed / $checks.Total) * 100, 0) } else { 0 }
$summary = "Disk health: $score% ($($checks.Passed)/$($checks.Total) checks passed) | SMART: $(($data.SMART | Where-Object Healthy).Count)/$($data.SMART.Count) healthy | FileVault: $(if($data.FileVault.Enabled){'On'}else{'Off'})"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Get-MacDiskHealth' -Status $(if ($score -ge 80) {'Success'} elseif ($score -ge 50) {'Warning'} else {'Failure'}) `
        -Summary $summary -Data $data -Errors $errors.ToArray() -Metrics @{ Score=$score; Passed=$checks.Passed; Total=$checks.Total }
} else {
    [pscustomobject]@{ Tool='Get-MacDiskHealth'; Status=$(if ($score -ge 80) {'Success'} elseif ($score -ge 50) {'Warning'} else {'Failure'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
