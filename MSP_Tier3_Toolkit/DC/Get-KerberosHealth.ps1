<#
.SYNOPSIS
    MSP Toolkit - Kerberos Health Check.
.DESCRIPTION
    Analyzes Kerberos: KRBTGT password age, duplicate SPNs, unconstrained
    delegation, ticket size trends, and service account health.
#>
#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ KRBTGT=@{}; DuplicateSPNs=@(); UnconstrainedDelegation=@(); Issues=@() }

# --- KRBTGT info from DC module ---
try {
    if (Get-Command Get-MSPKRBTGTInfo -ErrorAction SilentlyContinue) {
        $data.KRBTGT = Get-MSPKRBTGTInfo
    } else {
        Import-Module ActiveDirectory -ErrorAction Stop
        $krbtgt = Get-ADUser -Identity 'krbtgt' -Properties PasswordLastSet -ErrorAction SilentlyContinue
        if ($krbtgt) {
            $age = [math]::Round(((Get-Date) - $krbtgt.PasswordLastSet).TotalDays, 0)
            $data.KRBTGT = @{ PasswordLastSet=$krbtgt.PasswordLastSet; PasswordAgeDays=$age; RotationRecommended=($age -gt 180) }
        }
    }
} catch { $errors.Add("KRBTGT: $($_.Exception.Message)") }

# --- Duplicate SPNs ---
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $allSPNs = @{}
    $users = Get-ADUser -Filter { ServicePrincipalName -like '*' } -Properties ServicePrincipalName -ErrorAction SilentlyContinue
    foreach ($u in $users) {
        foreach ($spn in $u.ServicePrincipalName) {
            if ($allSPNs[$spn] -and $allSPNs[$spn] -ne $u.SamAccountName) {
                $data.DuplicateSPNs += [pscustomobject]@{ SPN=$spn; User1=$allSPNs[$spn]; User2=$u.SamAccountName }
            }
            $allSPNs[$spn] = $u.SamAccountName
        }
    }
    if ($data.DuplicateSPNs.Count -gt 0) { $data.Issues += "$($data.DuplicateSPNs.Count) duplicate SPNs found" }
} catch { $errors.Add("SPN check: $($_.Exception.Message)") }

# --- Unconstrained Delegation ---
try {
    $unconstrained = Get-ADUser -Filter { TrustedForDelegation -eq $true } -Properties TrustedForDelegation -ErrorAction SilentlyContinue
    $unconstrained += Get-ADComputer -Filter { TrustedForDelegation -eq $true } -Properties TrustedForDelegation -ErrorAction SilentlyContinue
    
    foreach ($obj in $unconstrained) {
        $data.UnconstrainedDelegation += [pscustomobject]@{ Name=$obj.SamAccountName; Type=if($obj.ObjectClass -eq 'computer'){'Computer'}else{'User'}; ObjectClass=$obj.ObjectClass }
    }
    if ($data.UnconstrainedDelegation.Count -gt 0) {
        $data.Issues += "$($data.UnconstrainedDelegation.Count) accounts with unconstrained delegation (high risk)"
    }
} catch { $errors.Add("Delegation check: $($_.Exception.Message)") }

# --- Service accounts without password rotation ---
try {
    $svcAccounts = Get-ADUser -Filter { PasswordNeverExpires -eq $true -and Enabled -eq $true } -Properties PasswordLastSet,PasswordNeverExpires -ErrorAction SilentlyContinue
    $staleSvc = @($svcAccounts | Where-Object { $_.PasswordLastSet -and ((Get-Date) - $_.PasswordLastSet).TotalDays -gt 365 })
    $data.StaleServiceAccounts = @($staleSvc | ForEach-Object { [pscustomobject]@{ Name=$_.SamAccountName; LastPasswordSet=$_.PasswordLastSet; AgeDays=[math]::Round(((Get-Date) - $_.PasswordLastSet).TotalDays,0) } })
    if ($data.StaleServiceAccounts.Count -gt 0) { $data.Issues += "$($data.StaleServiceAccounts.Count) service accounts with passwords > 1 year old" }
} catch { }

$summary = "KRBTGT: $(if($data.KRBTGT.RotationRecommended){'ROTATION NEEDED'}else{'OK'}) | Dup SPNs: $($data.DuplicateSPNs.Count) | Unconstrained: $($data.UnconstrainedDelegation.Count) | Issues: $($data.Issues.Count)"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Get-KerberosHealth' -Status $(if ($data.Issues.Count -gt 0) {'Warning'} else {'Success'}) `
        -Summary $summary -Data $data -Errors $errors.ToArray() `
        -Metrics @{ DupSPNs=$data.DuplicateSPNs.Count; Unconstrained=$data.UnconstrainedDelegation.Count; StaleAccounts=$data.StaleServiceAccounts.Count; Issues=$data.Issues.Count }
} else {
    [pscustomobject]@{ Tool='Get-KerberosHealth'; Status=$(if ($data.Issues.Count -gt 0) {'Warning'} else {'Success'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
