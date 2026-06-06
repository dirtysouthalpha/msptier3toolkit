<#
.SYNOPSIS
    MSP Toolkit - macOS MDM Status Check.
.DESCRIPTION
    Comprehensive MDM enrollment verification: MDM profile presence,
    DEP activation, user-approved enrollment, and managed update settings.
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

# --- MDM Enrollment Status ---
$data.Enrollment = @{ Enrolled=$false; UserApproved=$false; DEP=$false; ServerURL=''; Method='' }
try {
    $status = _Run 'profiles' @('status','-type','enrollment') 10
    $data.Enrollment.Enrolled = ($status -match 'MDM enrollment:\s+Yes')
    $data.Enrollment.UserApproved = ($status -match 'MDM enrollment:\s+Yes \(User Approved\)')
    $data.Enrollment.DEP = ($status -match 'Enrolled via DEP:\s+Yes')
    $data.Enrollment.ServerURL = if ($status -match 'MDM server:\s+(.+)') { $Matches[1].Trim() } else { '' }
    $data.Enrollment.UAMDM = ($status -match 'Enrolled via DEP:\s+Yes \(User Approved\)')
} catch { $errors.Add("Enrollment: $($_.Exception.Message)") }

# --- Configuration Profiles ---
$data.Profiles = @()
try {
    $profileList = _Run 'profiles' @('-C') 5
    foreach ($line in ($profileList -split "`n")) {
        if ($line -match '^\s{4}([^(]+)\s+\(([^)]+)\)\s+(\S+)\s+(\S+)') {
            $data.Profiles += @{ Name=$Matches[1].Trim(); Identifier=$Matches[2]; Version=$Matches[3]; Source=$Matches[4] }
        }
    }
} catch { $errors.Add("Profiles: $($_.Exception.Message)") }

# --- Managed Software Update Settings ---
try {
    $swUpdate = _Run 'defaults' @('read','/Library/Managed Preferences/com.apple.SoftwareUpdate') 5
    $data.ManagedSWUpdate = if ($swUpdate -match 'does not exist') { 'Not managed' } else { 'Managed' }
    $data.SWUpdate = @{
        AutoUpdate       = if ($swUpdate -match 'AutomaticCheckEnabled\s*=\s*(\d+)') { $Matches[1] -eq '1' } else { $false }
        AutoDownload     = if ($swUpdate -match 'AutomaticDownload\s*=\s*(\d+)') { $Matches[1] -eq '1' } else { $false }
        AutoInstallOS    = if ($swUpdate -match 'AutomaticallyInstallMacOSUpdates\s*=\s*(\d+)') { $Matches[1] -eq '1' } else { $false }
        CriticalUpdate   = if ($swUpdate -match 'CriticalUpdateInstall\s*=\s*(\d+)') { $Matches[1] -eq '1' } else { $false }
        ConfigDataInstall= if ($swUpdate -match 'ConfigDataInstall\s*=\s*(\d+)') { $Matches[1] -eq '1' } else { $false }
    }
} catch { $data.ManagedSWUpdate = 'Not managed' }

# --- Bootstrap Token ---
try {
    $bt = _Run 'profiles' @('status','-type','bootstraptoken') 5
    $data.BootstrapToken = @{ Escrowed=($bt -match 'Bootstrap Token escrowed to server:\s+Yes'); Supported=($bt -match 'Bootstrap Token supported') }
} catch { $errors.Add("BootstrapToken: $($_.Exception.Message)") }

# --- KEXT / System Extension Policy ---
try {
    $kextPolicy = _Run 'spctl' @('kext-consent','list') 5
    $data.KextPolicy = if ($kextPolicy -match 'Allow Apps') { 'User-Approved MDM Enabled' } elseif ($kextPolicy -match 'No Team IDs') { 'None approved' } else { $kextPolicy.Trim() }
} catch { $errors.Add("KextPolicy: $($_.Exception.Message)") }

$summary = "MDM: $(if($data.Enrollment.Enrolled){'Enrolled'+(if($data.Enrollment.UserApproved){' (User Approved)'}else{''})}else{'Not enrolled'}) | Profiles: $($data.Profiles.Count) | BootstrapToken: $(if($data.BootstrapToken.Escrowed){'Yes'}else{'No'})"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Get-MacMDMStatus' -Status $(if ($data.Enrollment.Enrolled) { 'Success' } else { 'Warning' }) `
        -Summary $summary -Data $data -Errors $errors.ToArray() `
        -Metrics @{ ProfileCount=$data.Profiles.Count; Enrolled=$data.Enrollment.Enrolled; DEP=$data.Enrollment.DEP }
} else {
    [pscustomobject]@{ Tool='Get-MacMDMStatus'; Status=$(if ($data.Enrollment.Enrolled) { 'Success' } else { 'Warning' }); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
