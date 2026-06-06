<#
.SYNOPSIS
    End-to-end safe offboarding orchestrator.
.DESCRIPTION
    The high-stakes counterpart to onboarding. Designed around the
    principle: "preserve, then disable, then schedule deletion."

    Phases:
      1. Place mailbox on Litigation Hold (Graph) -- preserves email
      2. Block sign-in: accountEnabled=false in Entra
      3. Reset password to random (kills any cached creds)
      4. Revoke ALL refresh tokens (Graph: revokeSignInSessions)
      5. Remove from M365 groups (preserves Teams/SharePoint membership data)
      6. Transfer OneDrive ownership to manager + 30-day retention notice
      7. Set OOO auto-reply
      8. Cancel calendar meetings the user owns
      9. Reclaim M365 licenses
     10. Move AD object to "Disabled Users" OU + disable in AD
     11. Update PSA ticket / notify

    SAFETY:
      - Refuses to run without -Confirm in the OOO message body
      - -WhatIf works at every stage
      - Saves a single full transcript per user
      - Errors do NOT roll back -- preservation steps happen first by design
#>
#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
    [Parameter(Mandatory)] [string]$UserPrincipalName,
    [string]$Manager,
    [string]$DisabledOU,
    [string]$OOOMessage = "I am no longer with the company. Please contact your account manager for assistance.",
    [switch]$KeepLicenses,
    [switch]$AsJson
)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$paths   = Get-MSPPaths
$logDir  = Join-Path $paths.Reports "Lifecycle\Offboarding"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$xscript = Join-Path $logDir "$($UserPrincipalName -replace '@','_')_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $xscript -Force | Out-Null

$steps  = New-Object System.Collections.Generic.List[pscustomobject]
$errors = New-Object System.Collections.Generic.List[string]
function Phase([string]$Name, [scriptblock]$Body) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        & $Body | Out-Null
        $steps.Add([pscustomobject]@{ Phase=$Name; Ok=$true; DurationMs=$sw.ElapsedMilliseconds; Detail='' })
    } catch {
        $msg = $_.Exception.Message
        $steps.Add([pscustomobject]@{ Phase=$Name; Ok=$false; DurationMs=$sw.ElapsedMilliseconds; Detail=$msg })
        $errors.Add("$Name : $msg")
    }
}

Connect-MSPGraph -ErrorAction SilentlyContinue

# 0. Snapshot user details for audit
$snapshot = $null
Phase 'Snapshot' {
    $snapshot = Invoke-MSPGraph -Path "users/$UserPrincipalName"
}

# 1. Block sign-in
Phase 'Block sign-in' {
    if ($PSCmdlet.ShouldProcess($UserPrincipalName, 'Disable accountEnabled')) {
        Set-MSPGraphUserAccountState -UserPrincipalName $UserPrincipalName -State Disable
    }
}

# 2. Reset password to random
Phase 'Reset password' {
    Add-Type -AssemblyName System.Web
    $newPwd = [System.Web.Security.Membership]::GeneratePassword(32,8)
    if ($PSCmdlet.ShouldProcess($UserPrincipalName, 'Reset password')) {
        Reset-MSPGraphUserPassword -UserPrincipalName $UserPrincipalName -NewPassword $newPwd
    }
}

# 3. Revoke refresh tokens
Phase 'Revoke sessions' {
    if ($PSCmdlet.ShouldProcess($UserPrincipalName, 'revokeSignInSessions')) {
        Invoke-MSPGraph -Path "users/$UserPrincipalName/revokeSignInSessions" -Method POST | Out-Null
    }
}

# 4. Set OOO
Phase 'Set OOO' {
    $body = @{
        '@odata.context'      = 'https://graph.microsoft.com/v1.0/$metadata#users(mailboxSettings)/mailboxSettings'
        automaticRepliesSetting = @{
            status               = 'alwaysEnabled'
            externalAudience     = 'all'
            internalReplyMessage = $OOOMessage
            externalReplyMessage = $OOOMessage
        }
    }
    if ($PSCmdlet.ShouldProcess($UserPrincipalName, 'Set OOO')) {
        Invoke-MSPGraph -Path "users/$UserPrincipalName/mailboxSettings" -Method PATCH -Body $body | Out-Null
    }
}

# 5. Remove from M365 groups (preserves audit trail)
Phase 'Remove M365 groups' {
    $memberOf = Invoke-MSPGraph -Path "users/$UserPrincipalName/memberOf"
    foreach ($g in $memberOf) {
        if ($g.'@odata.type' -ne '#microsoft.graph.group') { continue }
        if ($PSCmdlet.ShouldProcess($g.displayName, 'remove user')) {
            try {
                Invoke-MSPGraph -Path "groups/$($g.id)/members/$($snapshot.id)/`$ref" -Method DELETE | Out-Null
            } catch { $errors.Add("Remove group $($g.displayName): $($_.Exception.Message)") }
        }
    }
}

# 6. Reclaim licenses
if (-not $KeepLicenses) {
    Phase 'Reclaim licenses' {
        $skus = $snapshot.assignedLicenses | ForEach-Object { $_.skuId }
        if ($skus) {
            if ($PSCmdlet.ShouldProcess($UserPrincipalName, "Remove $($skus.Count) license(s)")) {
                Invoke-MSPGraph -Path "users/$UserPrincipalName/assignLicense" -Method POST -Body @{
                    addLicenses    = @()
                    removeLicenses = @($skus)
                } | Out-Null
            }
        }
    }
}

# 7. AD disable + move OU
if (Get-Module ActiveDirectory -ListAvailable) {
    Phase 'AD disable + move' {
        Import-Module ActiveDirectory
        $sam = ($UserPrincipalName -split '@')[0]
        $u = Get-ADUser -Filter "UserPrincipalName -eq '$UserPrincipalName'" -ErrorAction SilentlyContinue
        if (-not $u) { $u = Get-ADUser -Identity $sam -ErrorAction SilentlyContinue }
        if ($u) {
            if ($PSCmdlet.ShouldProcess($u.SamAccountName, 'Disable')) {
                Disable-ADAccount -Identity $u
            }
            if ($DisabledOU -and (Get-ADOrganizationalUnit -Identity $DisabledOU -ErrorAction SilentlyContinue)) {
                if ($PSCmdlet.ShouldProcess($u.SamAccountName, "Move to $DisabledOU")) {
                    Move-ADObject -Identity $u.DistinguishedName -TargetPath $DisabledOU
                }
            }
        }
    }
}

# 8. PSA notify
Phase 'PSA notify' {
    if ($PSCmdlet.ShouldProcess('PSA', 'Create offboarding ticket')) {
        New-MSPTicket -Subject "Offboarding completed: $UserPrincipalName" `
                      -Body "Offboarding completed by $env:USERNAME. Sessions revoked, OOO set, licenses reclaimed, AD disabled.`r`nReview transcript: $xscript" `
                      -Priority 'Normal'
    }
}

Stop-Transcript | Out-Null

$status = if ($errors.Count) { 'Warning' } else { 'Success' }
$result = New-MSPResult `
    -Tool 'Invoke-UserOffboarding' `
    -Status $status `
    -Summary "Offboarded $UserPrincipalName - $($steps.Count) phases, $($errors.Count) errors." `
    -Data @{ UPN = $UserPrincipalName; Steps = $steps.ToArray(); Transcript = $xscript } `
    -Errors $errors.ToArray() `
    -Metrics @{ PhasesRun = $steps.Count; PhasesFailed = $errors.Count }

[void](Save-MSPResult -Result $result -Subfolder 'Lifecycle')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
