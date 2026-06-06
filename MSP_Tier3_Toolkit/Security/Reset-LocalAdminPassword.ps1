<#
.SYNOPSIS
    Reset the built-in local Administrator account password.
.DESCRIPTION
    Uses the net user command to reset the local Administrator password.
    Requires Administrator privileges. Supports both local and domain environments.
    On a domain-joined machine, this resets the local account only.
.PARAMETER NewPassword
    New password to set. If omitted, generates a secure random password.
    Requirements: >=8 chars, mixed case, numbers, special chars recommended.
.PARAMETER AccountName
    Local account name to reset. Default: Administrator.
    Use this to reset other local accounts like 'admin', 'tech', etc.
.PARAMETER AsJson
    Emit raw JSON to stdout.
.EXAMPLE
    .\Reset-LocalAdminPassword.ps1
.EXAMPLE
    .\Reset-LocalAdminPassword.ps1 -NewPassword "P@ssw0rd!2024" -AccountName Administrator
#>
#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$NewPassword,
    [string]$AccountName = 'Administrator',
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$errors = New-Object System.Collections.Generic.List[string]
$data   = @{
    ComputerName  = $env:COMPUTERNAME
    AccountName   = $AccountName
    ResetSuccess  = $false
    GeneratedPassword = ''
}

# Generate secure password if not provided (16 chars: upper, lower, digit, special)
if (-not $NewPassword) {
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#$%&*'
    $NewPassword = -join ((1..16) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    $data.GeneratedPassword = $NewPassword
}

# Validate password meets basic minimum complexity
if ($NewPassword.Length -lt 8) {
    $errors.Add("Password must be at least 8 characters long (provided: $($NewPassword.Length)).")
    $result = New-MSPResult -Tool 'Reset-LocalAdminPassword' -Status 'Failure' -Summary 'Password too short' -Data $data -Errors $errors.ToArray()
    if ($AsJson) { $result | ConvertTo-Json -Depth 4 } else { $result }
    return
}

try {
    # Verify account exists
    $localUser = Get-LocalUser -Name $AccountName -ErrorAction SilentlyContinue
    if (-not $localUser) {
        # Fallback: try the legacy net user command (works on Server Core, older PS)
        $null = net user $AccountName 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Local account '$AccountName' not found on this computer."
        }
    }

    # Check if running elevated
    $elevated = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
        [Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $elevated) {
        $errors.Add('Administrator privileges required. Re-launch PowerShell as Administrator.')
        $result = New-MSPResult -Tool 'Reset-LocalAdminPassword' -Status 'Failure' -Summary 'Not elevated' -Data $data -Errors $errors.ToArray()
        if ($AsJson) { $result | ConvertTo-Json -Depth 4 } else { $result }
        return
    }

    # Attempt modern cmdlet first (PowerShell 5.1+ with LocalAccounts module)
    if (Get-Command Set-LocalUser -ErrorAction SilentlyContinue) {
        $securePwd = ConvertTo-SecureString -AsPlainText $NewPassword -Force
        Set-LocalUser -Name $AccountName -Password $securePwd -ErrorAction Stop
        $data.ResetSuccess = $true
    }
    # Fallback to net user (works everywhere)
    else {
        $proc = Start-Process -FilePath 'net.exe' -ArgumentList "user $AccountName `"$NewPassword`"" -NoNewWindow -Wait -PassThru -RedirectStandardError 'NUL'
        if ($proc.ExitCode -ne 0) {
            throw "net user returned exit code $($proc.ExitCode)"
        }
        $data.ResetSuccess = $true
    }

    # Optionally enable account in case it was disabled
    if ($localUser -and -not $localUser.Enabled) {
        try {
            if (Get-Command Enable-LocalUser -ErrorAction SilentlyContinue) {
                Enable-LocalUser -Name $AccountName -ErrorAction SilentlyContinue
            }
        } catch { }
    }

} catch [Microsoft.PowerShell.Commands.UserNotFoundException] {
    $errors.Add("Local account '$AccountName' not found on $($env:COMPUTERNAME).")
} catch {
    $errors.Add("Password reset failed: $($_.Exception.Message)")
}

$status  = if ($data.ResetSuccess) { 'Success' } else { 'Failure' }
$summary = if ($data.ResetSuccess) {
    "Local account '$AccountName' password reset successfully."
} else {
    "Failed to reset local account '$AccountName'"
}

$result = New-MSPResult -Tool 'Reset-LocalAdminPassword' -Status $status -Summary $summary -Data $data -Errors $errors.ToArray() `
    -Metrics @{ AccountExists=($errors.Count -eq 0 -or -not $errors[0].Contains('not found')); Elevated=($data.ResetSuccess) }

[void](Save-MSPResult -Result $result -Subfolder 'Security')
if ($AsJson) { $result | ConvertTo-Json -Depth 4 } else { $result }