<#
.SYNOPSIS
    Cross-stack password reset: AD + Entra ID + revoke MFA tokens + revoke
    refresh tokens -- in a single operation.
.DESCRIPTION
    When you get the "I can't log into anything" ticket and the user is
    hybrid-synced. Resets AD password (which syncs to Entra), but also
    explicitly resets the cloud password (insurance), revokes refresh
    tokens (kills cached sign-ins on phones), and optionally resets MFA
    methods (clears stale Authenticator devices).

    The MFA reset uses Graph's authenticationMethods endpoint -- requires
    UserAuthenticationMethod.ReadWrite.All app permission.
.PARAMETER UserPrincipalName
    Cloud UPN; AD lookup tries UPN then sAMAccountName.
.PARAMETER NewPassword
    Plain text password; if omitted, a strong 16-char one is generated.
.PARAMETER ResetMFA
    Also wipe ALL authentication methods (forces re-registration).
#>
#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
    [Parameter(Mandatory)] [string]$UserPrincipalName,
    [string]$NewPassword,
    [switch]$ResetMFA,
    [switch]$ForceChangeAtNextSignIn,
    [switch]$AsJson
)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

if (-not $NewPassword) {
    Add-Type -AssemblyName System.Web
    $NewPassword = [System.Web.Security.Membership]::GeneratePassword(16,4)
}

$steps  = New-Object System.Collections.Generic.List[pscustomobject]
$errors = New-Object System.Collections.Generic.List[string]
function Step([string]$Name, [scriptblock]$Body) {
    try { & $Body | Out-Null; $steps.Add([pscustomobject]@{Step=$Name;Ok=$true;Detail=''}) }
    catch { $errors.Add("$Name : $($_.Exception.Message)"); $steps.Add([pscustomobject]@{Step=$Name;Ok=$false;Detail=$_.Exception.Message}) }
}

# 1. AD reset
if (Get-Module ActiveDirectory -ListAvailable) {
    Step 'AD reset' {
        Import-Module ActiveDirectory -ErrorAction Stop
        $sam = ($UserPrincipalName -split '@')[0]
        $u = Get-ADUser -Filter "UserPrincipalName -eq '$UserPrincipalName'" -ErrorAction SilentlyContinue
        if (-not $u) { $u = Get-ADUser -Identity $sam -ErrorAction SilentlyContinue }
        if (-not $u) { throw "User not found in AD." }
        if ($PSCmdlet.ShouldProcess($u.SamAccountName, 'Set-ADAccountPassword')) {
            $sec = ConvertTo-SecureString $NewPassword -AsPlainText -Force
            Set-ADAccountPassword -Identity $u -NewPassword $sec -Reset -ErrorAction Stop
            if ($ForceChangeAtNextSignIn) { Set-ADUser $u -ChangePasswordAtLogon $true }
            Unlock-ADAccount -Identity $u
        }
    }
}

# 2. Entra reset (insurance for sync delays)
Step 'Entra reset' {
    Connect-MSPGraph
    if ($PSCmdlet.ShouldProcess($UserPrincipalName, 'Graph password reset')) {
        Reset-MSPGraphUserPassword -UserPrincipalName $UserPrincipalName -NewPassword $NewPassword -ForceChangeAtNextSignIn:$ForceChangeAtNextSignIn
    }
}

# 3. Revoke refresh tokens
Step 'Revoke sessions' {
    Connect-MSPGraph
    if ($PSCmdlet.ShouldProcess($UserPrincipalName, 'revokeSignInSessions')) {
        Invoke-MSPGraph -Path "users/$UserPrincipalName/revokeSignInSessions" -Method POST | Out-Null
    }
}

# 4. Optional MFA reset
if ($ResetMFA) {
    Step 'MFA reset' {
        Connect-MSPGraph
        # List then DELETE each non-password method
        $methods = Invoke-MSPGraph -Path "users/$UserPrincipalName/authentication/methods"
        foreach ($m in $methods) {
            $type = ($m.'@odata.type' -split '\.')[-1]
            if ($type -eq 'passwordAuthenticationMethod') { continue }
            $endpoint = switch ($type) {
                'microsoftAuthenticatorAuthenticationMethod' { 'microsoftAuthenticatorMethods' }
                'phoneAuthenticationMethod'                  { 'phoneMethods' }
                'fido2AuthenticationMethod'                  { 'fido2Methods' }
                'softwareOathAuthenticationMethod'           { 'softwareOathMethods' }
                'windowsHelloForBusinessAuthenticationMethod'{ 'windowsHelloForBusinessMethods' }
                'emailAuthenticationMethod'                  { 'emailMethods' }
                default                                       { $null }
            }
            if (-not $endpoint) { continue }
            if ($PSCmdlet.ShouldProcess("$UserPrincipalName / $type", 'DELETE')) {
                try {
                    Invoke-MSPGraph -Path "users/$UserPrincipalName/authentication/$endpoint/$($m.id)" -Method DELETE | Out-Null
                } catch { $errors.Add("MFA $type $($m.id): $($_.Exception.Message)") }
            }
        }
    }
}

$status = if ($errors.Count) { 'Warning' } else { 'Success' }
$result = New-MSPResult `
    -Tool 'Reset-UserPasswordEverywhere' `
    -Status $status `
    -Summary "Reset $UserPrincipalName across $($steps.Count) layers. New password length: $($NewPassword.Length)." `
    -Data @{
        UPN          = $UserPrincipalName
        NewPassword  = $NewPassword
        Steps        = $steps.ToArray()
        ResetMFA     = $ResetMFA.IsPresent
    } `
    -Errors $errors.ToArray() `
    -Metrics @{ StepsRun = $steps.Count; StepsFailed = $errors.Count }

[void](Save-MSPResult -Result $result -Subfolder 'Lifecycle')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
