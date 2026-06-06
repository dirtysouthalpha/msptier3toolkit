<#
.SYNOPSIS
    MSP Toolkit - LAPS Deployment Check.
.DESCRIPTION
    Checks LAPS presence, local admin password rotation age,
    and managed password account configuration.
#>
#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ LAPSPresent=$false; ManagedAccount=''; PasswordAgeHours=0; PasswordExpired=$false; ADBacked=$false; Issues=@() }

# Check local LAPS installation
try {
    $lapsReg = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS'
    if (-not $lapsReg) { $lapsReg = Test-Path 'HKLM:\SOFTWARE\Microsoft\Policies\LAPS' }
    $data.LAPSPresent = $lapsReg
    
    if ($lapsReg) {
        try {
            $lapsCfg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS' -ErrorAction SilentlyContinue
            if ($lapsCfg) {
                $data.ManagedAccount = $lapsCfg.AdminAccountName
                $data.PasswordLength = $lapsCfg.PasswordLength
                $data.PasswordAgeDays = $lapsCfg.PasswordAgeDays
            }
        } catch { }
    }
} catch { $errors.Add("LAPS registry: $($_.Exception.Message)") }

# Check password age via event log
try {
    $lapsEvents = Get-WinEvent -LogName 'Microsoft-Windows-LAPS/Operational' -MaxEvents 20 -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -in 10018,10017,10020 }
    if ($lapsEvents) {
        $lastRotation = $lapsEvents | Where-Object Id -eq 10018 | Sort-Object TimeCreated -Descending | Select-Object -First 1
        if ($lastRotation) {
            $data.LastRotation = $lastRotation.TimeCreated.ToString('o')
            $data.PasswordAgeHours = [math]::Round(((Get-Date) - $lastRotation.TimeCreated).TotalHours, 1)
            if ($data.PasswordAgeHours -gt (($data.PasswordAgeDays -as [int]) * 24)) {
                $data.PasswordExpired = $true; $data.Issues += "Password age ($([math]::Round($data.PasswordAgeHours/24,1)) days) exceeds configured maximum"
            }
        }
    }
} catch { }

# AD-backed check
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $adLaps = Get-ADObject -Filter { ObjectClass -eq 'msLAPS-Password' } -Properties msLAPS-Password, msLAPS-PasswordExpirationTime, msLAPS-EncryptedPassword -ErrorAction SilentlyContinue
    if ($adLaps) {
        $data.ADBacked = $true
        $data.ADPasswordObjects = $adLaps.Count
    }
} catch { $data.ADBacked = $false }

$summary = "LAPS: $(if($data.LAPSPresent){'Present'}else{'Not found'}) | Managed account: $(if($data.ManagedAccount){$data.ManagedAccount}else{'Unknown'}) | AD-backed: $(if($data.ADBacked){'Yes'}else{'No'})"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Test-LAPSDeployment' -Status $(if ($data.LAPSPresent -and -not $data.PasswordExpired) {'Success'} elseif ($data.LAPSPresent) {'Warning'} else {'Failure'}) `
        -Summary $summary -Data $data -Errors $errors.ToArray() `
        -Metrics @{ Present=$data.LAPSPresent; ADBacked=$data.ADBacked; PasswordAgeHours=$data.PasswordAgeHours }
} else {
    [pscustomobject]@{ Tool='Test-LAPSDeployment'; Status=$(if ($data.LAPSPresent -and -not $data.PasswordExpired) {'Success'} elseif ($data.LAPSPresent) {'Warning'} else {'Failure'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
