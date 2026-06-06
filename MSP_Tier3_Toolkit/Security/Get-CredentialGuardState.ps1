<#
.SYNOPSIS
    MSP Toolkit - Credential Guard & VBS State Check.
.DESCRIPTION
    Checks Virtualization-Based Security status, Credential Guard,
    LSASS protection, HVCI (Memory Integrity), and Secure Launch.
#>
#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ VBSEnabled=$false; CredentialGuard=$false; HVCI=$false; SecureLaunch=$false; LSASSProtection=$false; Issues=@(); Score=0; MaxScore=5 }

# Check VBS/Credential Guard via registry
try {
    $hvci = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -ErrorAction SilentlyContinue
    $data.HVCI = ($hvci.Enabled -eq 1)
    if ($data.HVCI) { $data.Score++ } else { $data.Issues += 'HVCI/Memory Integrity is disabled' }
} catch { $data.Issues += 'HVCI registry key not found' }

try {
    $cg = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard' -ErrorAction SilentlyContinue
    $data.CredentialGuard = ($cg.Enabled -eq 1)
    if ($data.CredentialGuard) { $data.Score++ } else { $data.Issues += 'Credential Guard is not enabled' }
} catch { $data.Issues += 'Credential Guard registry key not found' }

try {
    $vbs = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -ErrorAction SilentlyContinue
    $data.VBSEnabled = ($vbs.EnableVirtualizationBasedSecurity -eq 1)
    if ($data.VBSEnabled) { $data.Score++ } else { $data.Issues += 'VBS is not enabled' }
} catch { $data.Issues += 'VBS registry key not found' }

try {
    $secLaunch = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\SystemGuard' -ErrorAction SilentlyContinue
    $data.SecureLaunch = ($secLaunch.Enabled -eq 1)
    if ($data.SecureLaunch) { $data.Score++ }
} catch { }

# LSASS protection (RunAsPPL)
try {
    $lsa = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -ErrorAction SilentlyContinue
    $lsaProtection = [int]($lsa.RunAsPPL -as [int])
    $data.LSASSProtection = ($lsaProtection -eq 1)
    if ($data.LSASSProtection) { $data.Score++ } else { $data.Issues += 'LSASS not running as protected process (RunAsPPL)' }
} catch { $data.Issues += 'LSASS protection not configured' }

# Get actual DG info via WMI
try {
    $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue
    if ($dg) {
        $data.VBSSecurityServicesConfigured = $dg.SecurityServicesConfigured
        $data.VBSSecurityServicesRunning = $dg.SecurityServicesRunning
        $data.VBSStatus = [int]$dg.VirtualizationBasedSecurityStatus
        $data.HardwareSecureBoot = ($dg.RequiredSecurityProperties -contains 1)
    }
} catch { }

$summary = "Credential Guard: $(if($data.CredentialGuard){'ON'}else{'OFF'}) | HVCI: $(if($data.HVCI){'ON'}else{'OFF'}) | LSASS Prot: $(if($data.LSASSProtection){'ON'}else{'OFF'}) | Score: $($data.Score)/$($data.MaxScore)"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Get-CredentialGuardState' -Status $(if ($data.Score -ge 3) {'Success'} elseif ($data.Score -ge 1) {'Warning'} else {'Failure'}) `
        -Summary $summary -Data $data -Errors $errors.ToArray() -Metrics @{ Score=$data.Score; MaxScore=$data.MaxScore }
} else {
    [pscustomobject]@{ Tool='Get-CredentialGuardState'; Status=$(if ($data.Score -ge 3) {'Success'} elseif ($data.Score -ge 1) {'Warning'} else {'Failure'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
