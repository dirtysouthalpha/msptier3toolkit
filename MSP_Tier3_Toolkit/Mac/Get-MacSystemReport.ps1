<#
.SYNOPSIS
    MSP Toolkit - macOS System Report.
.DESCRIPTION
    Runs system_profiler and wraps key hardware, software, network, and
    storage details into the standard MSP result envelope.
.NOTES
    Requires PowerShell 7+ on macOS.
#>
#Requires -Version 7.0
[CmdletBinding()]
param([switch]$FullReport)

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch {
    # Standalone mode -- embed the minimum
    if (-not (Get-Command Get-MSPPlatform -ErrorAction SilentlyContinue)) {
        function Get-MSPPlatform { [pscustomobject]@{ Platform='macOS'; Version=try { sw_vers -productVersion } catch { '' }; IsWindows=$false; IsMacOS=$true; IsLinux=$false } }
    }
    if (-not (Get-Command Invoke-MSPNativeCommand -ErrorAction SilentlyContinue)) {
        function Invoke-MSPNativeCommand { param($Command,$Arguments,$TimeoutSec=30) & $Command @Arguments 2>&1 | Out-String }
    }
}

$plat = Get-MSPPlatform
$errors = New-Object System.Collections.Generic.List[string]
$data = @{}

# --- Hardware ---
try {
    $hw = Invoke-MSPNativeCommand -Command 'system_profiler' -Arguments @('SPHardwareDataType') -TimeoutSec 30
    $data.Hardware = @{
        ModelName     = if ($hw -match 'Model Name:\s+(.+)')     { $Matches[1].Trim() } else { '' }
        ModelID       = if ($hw -match 'Model Identifier:\s+(.+)') { $Matches[1].Trim() } else { '' }
        Chip          = if ($hw -match 'Chip:\s+(.+)')            { $Matches[1].Trim() } else { '' }
        Memory        = if ($hw -match 'Memory:\s+(.+)')          { $Matches[1].Trim() } else { '' }
        SerialNumber  = if ($hw -match 'Serial Number.*?:\s+(.+)'){ $Matches[1].Trim() } else { '' }
        UUID          = if ($hw -match 'Hardware UUID:\s+(.+)')   { $Matches[1].Trim() } else { '' }
        Processor     = if ($hw -match 'Processor Name:\s+(.+)')  { $Matches[1].Trim() } else { '' }
        ProcessorSpeed= if ($hw -match 'Processor Speed:\s+(.+)') { $Matches[1].Trim() } else { '' }
        CoreCount     = if ($hw -match 'Number of Processors:\s+(.+)') { $Matches[1].Trim() } else { '' }
    }
} catch { $errors.Add("Hardware: $($_.Exception.Message)") }

# --- Software ---
try {
    $sw = Invoke-MSPNativeCommand -Command 'system_profiler' -Arguments @('SPSoftwareDataType') -TimeoutSec 30
    $data.Software = @{
        SystemVersion    = if ($sw -match 'System Version:\s+(.+)')    { $Matches[1].Trim() } else { '' }
        KernelVersion    = if ($sw -match 'Kernel Version:\s+(.+)')    { $Matches[1].Trim() } else { '' }
        BootVolume       = if ($sw -match 'Boot Volume:\s+(.+)')       { $Matches[1].Trim() } else { '' }
        BootMode         = if ($sw -match 'Boot Mode:\s+(.+)')         { $Matches[1].Trim() } else { '' }
        SecureVM         = if ($sw -match 'Secure Virtual Memory:\s+(.+)') { $Matches[1].Trim() } else { '' }
        TimeSinceBoot    = if ($sw -match 'Time since boot:\s+(.+)')   { $Matches[1].Trim() } else { '' }
    }
} catch { $errors.Add("Software: $($_.Exception.Message)") }

# --- Storage ---
try {
    $st = Invoke-MSPNativeCommand -Command 'system_profiler' -Arguments @('SPStorageDataType') -TimeoutSec 30
    $volumes = @()
    $currentVol = $null
    foreach ($line in ($st -split "`n")) {
        if ($line -match '^\s{4}([^:]+):\s+(.+)' -and $line -notmatch 'Mount Point') {
            if ($currentVol) { $volumes += $currentVol }
            $currentVol = @{ Name = $Matches[1].Trim(); Detail = $Matches[2].Trim() }
        } elseif ($line -match 'Mount Point:\s+(.+)') {
            if (-not $currentVol) { $currentVol = @{Name='Unknown'} }
            $currentVol.MountPoint = $Matches[1].Trim()
        } elseif ($line -match 'Capacity:\s+(.+)') {
            if (-not $currentVol) { $currentVol = @{Name='Unknown'} }
            $currentVol.Capacity = $Matches[1].Trim()
        } elseif ($line -match 'Available:\s+(.+)') {
            if (-not $currentVol) { $currentVol = @{Name='Unknown'} }
            $currentVol.Available = $Matches[1].Trim()
        } elseif ($line -match 'File System:\s+(.+)') {
            if (-not $currentVol) { $currentVol = @{Name='Unknown'} }
            $currentVol.FileSystem = $Matches[1].Trim()
        }
    }
    if ($currentVol) { $volumes += $currentVol }
    $data.Storage = $volumes
} catch { $errors.Add("Storage: $($_.Exception.Message)") }

# --- Disk Health (diskutil) ---
try {
    $diskutil = Invoke-MSPNativeCommand -Command 'diskutil' -Arguments @('list') -TimeoutSec 15
    $data.DiskList = ($diskutil -split "`n") | Where-Object { $_ -match '/dev/' }
} catch { $errors.Add("DiskUtil: $($_.Exception.Message)") }

# --- Network ---
try {
    $net = Invoke-MSPNativeCommand -Command 'system_profiler' -Arguments @('SPNetworkDataType') -TimeoutSec 30
    $adapters = @()
    $currentAdapter = $null
    foreach ($line in ($net -split "`n")) {
        if ($line -match '^\s{4}([^:]+):') {
            if ($currentAdapter) { $adapters += $currentAdapter }
            $currentAdapter = @{ Interface = $Matches[1].Trim() }
        } elseif ($line -match 'Type:\s+(.+)') {
            if (-not $currentAdapter) { $currentAdapter = @{Interface='Unknown'} }
            $currentAdapter.Type = $Matches[1].Trim()
        } elseif ($line -match 'MAC Address:\s+(.+)') {
            if (-not $currentAdapter) { $currentAdapter = @{Interface='Unknown'} }
            $currentAdapter.MAC = $Matches[1].Trim()
        } elseif ($line -match 'IPv4 Addresses:\s+(.+)') {
            if (-not $currentAdapter) { $currentAdapter = @{Interface='Unknown'} }
            $currentAdapter.IPs = $Matches[1].Trim()
        }
    }
    if ($currentAdapter) { $adapters += $currentAdapter }
    $data.Network = $adapters
} catch { $errors.Add("Network: $($_.Exception.Message)") }

# --- Full report option ---
if ($FullReport) {
    try {
        $data.FullSystemProfiler = Invoke-MSPNativeCommand -Command 'system_profiler' -Arguments @('-detailLevel','basic') -TimeoutSec 60
    } catch { $errors.Add("FullReport: $($_.Exception.Message)") }
}

$summary = "macOS $($data.Software.SystemVersion) | $($data.Hardware.Chip) | $($data.Hardware.Memory) | $(@($data.Storage).Count) volumes"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Get-MacSystemReport' -Status $(if ($errors.Count -gt 0) { 'Warning' } else { 'Success' }) `
        -Summary $summary -Data $data -Errors $errors.ToArray() `
        -Metrics @{ VolumeCount = $volumes.Count; AdapterCount = $adapters.Count; Errors = $errors.Count }
} else {
    [pscustomobject]@{ Tool='Get-MacSystemReport'; Status=$(if ($errors.Count -gt 0) { 'Warning' } else { 'Success' }); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
