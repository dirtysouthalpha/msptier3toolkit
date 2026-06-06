<#
.SYNOPSIS
    MSP Toolkit - macOS FileVault Status Check.
.DESCRIPTION
    Checks FileVault full-disk encryption status, institutional recovery
    key presence, conversion progress, and user-level key escrow.
#>
#Requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }

function _Run { param($c,$a,$t=15) & $c @$a 2>&1 | Out-String }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ Status=''; ConversionPercent=0; RecoveryKeyUsers=@(); InstitutionalKey=$false; EligibleUsers=@() }

# --- Primary Status ---
try {
    $status = _Run 'fdesetup' @('status') 10
    if ($status -match 'FileVault is (On|Off)') {
        $data.Status = $Matches[1]
    } else {
        $data.Status = 'Unknown'
    }
    if ($status -match 'Deferred enablement appears to be active') {
        $data.Status = 'Deferred'
    }
    if ($status -match 'Encryption in progress') {
        $data.EncryptionProgress = 'In Progress'
        if ($status -match 'Percent completed = (\d+)') { $data.ConversionPercent = [int]$Matches[1] }
    }
    if ($status -match 'Encryption complete' -or $status -eq 'On' -and -not $data.EncryptionProgress) {
        $data.ConversionPercent = 100
    }
} catch { $errors.Add("fdesetup status: $($_.Exception.Message)") }

# --- Institutional Recovery Key ---
try {
    $irk = _Run 'fdesetup' @('hasinstitutionalrecoverykey') 5
    $data.InstitutionalKey = ($irk -match 'true' -or $LASTEXITCODE -eq 0)
} catch { $errors.Add("IRK: $($_.Exception.Message)") }

# --- Eligible Users ---
try {
    $users = _Run 'fdesetup' @('list') 10
    $lines = $users -split "`n" | Where-Object { $_ -match ',' }
    foreach ($line in $lines) {
        $parts = $line -split ','
        if ($parts.Count -ge 3) {
            $data.EligibleUsers += @{ Username=$parts[0].Trim(); UUID=$parts[1].Trim(); Type=$parts[2].Trim() }
        }
    }
} catch { $errors.Add("fdesetup list: $($_.Exception.Message)") }

# --- Recovery Key Escrow per User ---
try {
    $secureTokenUsers = _Run 'sysadminctl' @('-secureTokenStatus','') 3 2>&1
    foreach ($user in $data.EligibleUsers) {
        $escrow = _Run 'security' @('find-generic-password','-s',"FileVaultRecoveryKey-$($user.Username)",'-w') 5
        $user.RecoveryKeyEscrowed = ($escrow -and $escrow -notmatch 'not found')
    }
} catch { }

$score = 0
$checksTotal = 4
if ($data.Status -eq 'On') { $score++ }
if ($data.ConversionPercent -ge 100) { $score++ }
if ($data.InstitutionalKey) { $score++ }
if ($data.EligibleUsers.Count -gt 0) { $score++ }

$summary = "FileVault: $($data.Status) ($($data.ConversionPercent)% encrypted) | IRK: $(if($data.InstitutionalKey){'Yes'}else{'No'}) | Eligible users: $($data.EligibleUsers.Count)"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Get-MacFileVaultStatus' -Status $(if ($data.Status -eq 'On' -and $data.InstitutionalKey) {'Success'} elseif ($data.Status -eq 'On') {'Warning'} else {'Failure'}) `
        -Summary $summary -Data $data -Errors $errors.ToArray() `
        -Metrics @{ Score=$score; Total=$checksTotal; Encrypted=($data.Status -eq 'On'); Users=$data.EligibleUsers.Count }
} else {
    [pscustomobject]@{ Tool='Get-MacFileVaultStatus'; Status=$(if ($data.Status -eq 'On' -and $data.InstitutionalKey) {'Success'} elseif ($data.Status -eq 'On') {'Warning'} else {'Failure'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
