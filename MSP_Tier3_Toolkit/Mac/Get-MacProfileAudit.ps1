<#
.SYNOPSIS
    MSP Toolkit - macOS Profile & MDM Audit.
.DESCRIPTION
    Enumerates configuration profiles, MDM enrollment state,
    managed preferences, and DEP activation lock status.
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

# --- Configuration Profiles ---
$data.Profiles = @()
try {
    $profiles = _Run 'profiles' @('show') 10
    $currentProfile = $null
    foreach ($line in ($profiles -split "`n")) {
        if ($line -match '^\s{2}_attributes') {
            if ($currentProfile) { $data.Profiles += $currentProfile }
            $currentProfile = @{ Name=''; Ver=''; Source=''; Signed='' }
        }
        if (-not $currentProfile) { continue }
        if ($line -match 'profileDisplayName\s*=\s*"(.+)"') { $currentProfile.Name = $Matches[1] }
        if ($line -match 'profileVersion\s*=\s*(\d+)') { $currentProfile.Ver = $Matches[1] }
        if ($line -match 'profileInstallSource\s*=\s*"(.+)"') { $currentProfile.Source = $Matches[1] }
        if ($line -match 'isSignerVerified\s*=\s*(\d+)') { $currentProfile.Signed = if ($Matches[1] -eq '1') {'Yes'} else {'No'} }
    }
    if ($currentProfile) { $data.Profiles += $currentProfile }
} catch { $errors.Add("Profiles: $($_.Exception.Message)") }

# --- MDM Enrollment ---
try {
    $mdm = _Run 'profiles' @('status','-type','enrollment') 10
    $data.MDM = @{
        Enrolled        = ($mdm -match 'MDM enrollment:\s+Yes')
        UserApproved    = ($mdm -match 'User Approved')
        DEPEnrolled     = ($mdm -match 'Enrolled via DEP:\s+Yes')
        MDMServerURL    = if ($mdm -match 'MDM server:\s+(.+)') { $Matches[1].Trim() } else { '' }
    }
} catch { $errors.Add("MDM: $($_.Exception.Message)") }

# --- Managed Preferences (MCX-style) ---
try {
    $managed = _Run 'defaults' @('read','/Library/Managed Preferences/com.apple.SoftwareUpdate') 5
    $data.ManagedPrefs = if ($managed -and $managed -notmatch 'does not exist') { 'Present' } else { 'None detected' }
} catch { $data.ManagedPrefs = 'None' }

# --- Activation Lock / Find My ---
try {
    $alock = _Run 'system_profiler' @('SPHardwareDataType') 5
    $data.ActivationLock = if ($alock -match 'Activation Lock Status:\s+(.+)') { $Matches[1].Trim() } else { 'Unknown' }
} catch { $errors.Add("ActivationLock: $($_.Exception.Message)") }

$enrolled = if ($data.MDM.Enrolled) { 'MDM enrolled' } else { 'Not MDM enrolled' }
$summary = "$enrolled | Profiles: $($data.Profiles.Count) | ActivationLock: $($data.ActivationLock)"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Get-MacProfileAudit' -Status $(if ($data.Profiles.Count -gt 0) { 'Success' } else { 'Warning' }) `
        -Summary $summary -Data $data -Errors $errors.ToArray() `
        -Metrics @{ ProfileCount=$data.Profiles.Count; MDMEnrolled=$data.MDM.Enrolled; DEP=$data.MDM.DEPEnrolled }
} else {
    [pscustomobject]@{ Tool='Get-MacProfileAudit'; Status=$(if ($data.Profiles.Count -gt 0) { 'Success' } else { 'Warning' }); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
