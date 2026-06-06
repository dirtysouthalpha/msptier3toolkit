<#
.SYNOPSIS
    MSP Toolkit - AD User Bulk Report.
.DESCRIPTION
    Bulk user report: stale accounts (lastLogon), password expiry pipeline,
    locked-out users, disabled accounts, and password-never-expires accounts.
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [int]$StaleDays = 90,
    [int]$PasswordExpiryDays = 14
)

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{
    TotalUsers = 0
    StaleUsers = @()
    PasswordExpiring = @()
    LockedOut = @()
    Disabled = @()
    PasswordNeverExpires = @()
    Summary = @{}
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $users = Get-ADUser -Filter * -Properties LastLogonDate,PasswordLastSet,PasswordNeverExpires,PasswordExpired,LockedOut,Enabled,AccountExpirationDate -ErrorAction SilentlyContinue
    $data.TotalUsers = $users.Count

    $cutoffStale = (Get-Date).AddDays(-$StaleDays)
    $cutoffExpiry = (Get-Date).AddDays($PasswordExpiryDays)
    $domainPolicy = try { Get-ADDefaultDomainPasswordPolicy -ErrorAction SilentlyContinue } catch { $null }
    $maxAge = if ($domainPolicy -and $domainPolicy.MaxPasswordAge.TotalDays -gt 0) { $domainPolicy.MaxPasswordAge.TotalDays } else { 42 }

    foreach ($u in $users) {
        # Stale
        if ($u.LastLogonDate -and $u.LastLogonDate -lt $cutoffStale -and $u.Enabled) {
            $data.StaleUsers += [pscustomobject]@{ Name=$u.SamAccountName; LastLogon=$u.LastLogonDate; DaysAgo=[math]::Round(((Get-Date) - $u.LastLogonDate).TotalDays,0) }
        }
        # Password Expiring
        if ($u.PasswordLastSet -and -not $u.PasswordNeverExpires -and $u.Enabled) {
            $expiry = $u.PasswordLastSet.AddDays($maxAge)
            $daysLeft = [math]::Round(($expiry - (Get-Date)).TotalDays, 0)
            if ($daysLeft -le $PasswordExpiryDays -and $daysLeft -ge 0) {
                $data.PasswordExpiring += [pscustomobject]@{ Name=$u.SamAccountName; Expires=$expiry; DaysLeft=$daysLeft }
            }
        }
        # Locked Out
        if ($u.LockedOut) {
            $data.LockedOut += [pscustomobject]@{ Name=$u.SamAccountName }
        }
        # Disabled
        if (-not $u.Enabled) {
            $data.Disabled += [pscustomobject]@{ Name=$u.SamAccountName; AccountExpiration=$u.AccountExpirationDate }
        }
        # Password Never Expires
        if ($u.PasswordNeverExpires -and $u.Enabled) {
            $data.PasswordNeverExpires += [pscustomobject]@{ Name=$u.SamAccountName; LastPasswordSet=$u.PasswordLastSet }
        }
    }

    $data.Summary = @{
        Total             = $data.TotalUsers
        Stale             = $data.StaleUsers.Count
        PasswordExpiring  = $data.PasswordExpiring.Count
        LockedOut         = $data.LockedOut.Count
        Disabled          = $data.Disabled.Count
        PasswordNeverExpires = $data.PasswordNeverExpires.Count
    }

    $summary = "Users: $($data.TotalUsers) | Stale: $($data.StaleUsers.Count) | Expiring: $($data.PasswordExpiring.Count) | Locked: $($data.LockedOut.Count) | Disabled: $($data.Disabled.Count)"

    if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
        New-MSPResult -Tool 'Get-ADUserBulkReport' -Status $(if ($data.LockedOut.Count -gt 0) {'Warning'} else {'Success'}) `
            -Summary $summary -Data $data -Errors $errors.ToArray() `
            -Metrics @{ Total=$data.TotalUsers; Stale=$data.StaleUsers.Count; Expiring=$data.PasswordExpiring.Count; Locked=$data.LockedOut.Count; Disabled=$data.Disabled.Count }
    } else {
        [pscustomobject]@{ Tool='Get-ADUserBulkReport'; Status=$(if ($data.LockedOut.Count -gt 0) {'Warning'} else {'Success'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
    }
} catch {
    $errors.Add("AD query failed: $($_.Exception.Message)")
    if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
        New-MSPResult -Tool 'Get-ADUserBulkReport' -Status 'Failure' -Summary 'AD query failed' -Errors $errors.ToArray()
    } else {
        [pscustomobject]@{ Tool='Get-ADUserBulkReport'; Status='Failure'; Summary='AD query failed'; Errors=$errors.ToArray() }
    }
}
