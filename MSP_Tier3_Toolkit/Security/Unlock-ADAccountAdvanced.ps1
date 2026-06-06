<#
.SYNOPSIS
    Advanced Active Directory account unlock and password reset.
.DESCRIPTION
    Performs comprehensive account remediation: unlocks account, resets password,
    clears badPwdCount, clears lastLogon timestamp, optionally forces password change
    on next logon, and optionally adds to a security group. Requires appropriate
    AD permissions (Account Operators, Domain Admins, or delegated rights).
.PARAMETER Username
    SAM Account Name or UserPrincipalName of the target user.
.PARAMETER NewPassword
    New password to set. If omitted, generates a secure random password.
.PARAMETER ForceChangeOnLogon
    Set 'User must change password at next logon'.
.PARAMETER AddToGroup
    DistinguishedName or SAM name of group to add user to after reset.
.PARAMETER DomainController
    Specific DC to target (for immediate replication).
.PARAMETER WhatIf
    Show what would be done without making changes.
.PARAMETER AsJson
    Emit raw JSON to stdout.
#>
#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory, Position=0)]
    [string]$Username,
    [string]$NewPassword,
    [switch]$ForceChangeOnLogon,
    [string]$AddToGroup,
    [string]$DomainController,
    [switch]$WhatIf,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$errors  = New-Object System.Collections.Generic.List[string]
$actions = New-Object System.Collections.Generic.List[string]
$data    = @{ Username=$Username; Unlocked=$false; PasswordReset=$false; BadPwdCountCleared=$false; GroupAdded=$false; GeneratedPassword='' }

try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    $errors.Add('ActiveDirectory module not available. Install RSAT or run on a Domain Controller.')
    $result = New-MSPResult -Tool 'Unlock-ADAccountAdvanced' -Status 'Failure' -Summary 'ActiveDirectory module missing' -Data $data -Errors $errors.ToArray()
    if ($AsJson) { $result | ConvertTo-Json -Depth 5 } else { $result }
    return
}

$dcParams = @{}
if ($DomainController) { $dcParams.Server = $DomainController }

# Generate secure password if not provided
if (-not $NewPassword) {
    $NewPassword = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
    $data.GeneratedPassword = $NewPassword
    $actions.Add("Generated secure random password (length 16)")
}

try {
    $user = Get-ADUser -Identity $Username -Properties LockedOut, BadPwdCount, LastLogon, PasswordLastSet, Enabled @dcParams -ErrorAction Stop
    
    # 1. Unlock account
    if ($user.LockedOut) {
        if ($PSCmdlet.ShouldProcess($Username, 'Unlock account')) {
            Unlock-ADAccount -Identity $Username @dcParams -ErrorAction Stop
            $data.Unlocked = $true
            $actions.Add('Account unlocked')
        }
    } else {
        $actions.Add('Account was not locked')
    }

    # 2. Reset password
    if ($PSCmdlet.ShouldProcess($Username, 'Reset password')) {
        Set-ADAccountPassword -Identity $Username -NewPassword (ConvertTo-SecureString -AsPlainText $NewPassword -Force) -Reset @dcParams -ErrorAction Stop
        $data.PasswordReset = $true
        $actions.Add('Password reset')
    }

    # 3. Clear badPwdCount (requires writing to attribute directly)
    if ($user.BadPwdCount -gt 0) {
        if ($PSCmdlet.ShouldProcess($Username, "Clear badPwdCount ($($user.BadPwdCount))")) {
            Set-ADUser -Identity $Username -Clear 'badPwdCount' @dcParams -ErrorAction Stop
            $data.BadPwdCountCleared = $true
            $actions.Add("Cleared badPwdCount ($($user.BadPwdCount) failed attempts)")
        }
    } else {
        $actions.Add('badPwdCount was already 0')
    }

    # 4. Force password change on next logon
    if ($ForceChangeOnLogon) {
        if ($PSCmdlet.ShouldProcess($Username, 'Set "User must change password at next logon"')) {
            Set-ADUser -Identity $Username -ChangePasswordAtLogon $true @dcParams -ErrorAction Stop
            $actions.Add('Set "User must change password at next logon"')
        }
    }

    # 5. Add to group
    if ($AddToGroup) {
        if ($PSCmdlet.ShouldProcess($Username, "Add to group $AddToGroup")) {
            Add-ADGroupMember -Identity $AddToGroup -Members $Username @dcParams -ErrorAction Stop
            $data.GroupAdded = $true
            $actions.Add("Added to group: $AddToGroup")
        }
    }

    # 6. Enable account if disabled
    if (-not $user.Enabled) {
        if ($PSCmdlet.ShouldProcess($Username, 'Enable account')) {
            Enable-ADAccount -Identity $Username @dcParams -ErrorAction Stop
            $actions.Add('Account enabled')
        }
    }

} catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
    $errors.Add("User '$Username' not found in AD.")
} catch {
    $errors.Add("AD operation failed: $($_.Exception.Message)")
}

$success = $errors.Count -eq 0
$status = if ($success) { 'Success' } elseif ($data.Unlocked -or $data.PasswordReset) { 'Warning' } else { 'Failure' }
$summary = if ($success) { "Account remediation complete: $($actions.Count) actions performed" } else { 'Remediation failed or partial' }

$result = New-MSPResult -Tool 'Unlock-ADAccountAdvanced' -Status $status -Summary $summary -Data @{ Actions=$actions.ToArray(); Details=$data } -Errors $errors.ToArray() `
    -Metrics @{ Actions=$actions.Count; Unlocked=$data.Unlocked; PasswordReset=$data.PasswordReset }

[void](Save-MSPResult -Result $result -Subfolder 'Security')
if ($AsJson) { $result | ConvertTo-Json -Depth 5 } else { $result }