<#
.SYNOPSIS
    MSP Toolkit - Secure Boot & TPM State Check.
.DESCRIPTION
    Validates UEFI Secure Boot, TPM version and status,
    PCR bank configuration, and attestation readiness.
#>
#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ SecureBoot=$false; TPM=@{}; PCR=@(); Issues=@(); Score=0; MaxScore=0 }

# Secure Boot
try {
    $sb = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
    $data.SecureBoot = $sb
    $data.MaxScore += 15; if ($sb) { $data.Score += 15 } else { $data.Issues += 'Secure Boot is NOT enabled' }
} catch { $data.Issues += 'Secure Boot check failed (not UEFI or unsupported)' }

# TPM
try {
    $tpm = Get-Tpm -ErrorAction SilentlyContinue
    $tpmDetail = @{
        Present          = $tpm.TpmPresent
        Ready            = $tpm.TpmReady
        Enabled          = $tpm.TpmEnabled
        Activated        = $tpm.TpmActivated
        Owned            = $tpm.TpmOwned
        Version          = $tpm.ManufacturerVersion
        ManufacturerVersion = if ($tpm.SpecVersion) { $tpm.SpecVersion } else { 'Unknown' }
        LockoutInfo      = $tpm.LockoutHealTime
    }
    $data.TPM = $tpmDetail
    $data.MaxScore += 15
    if ($tpm.TpmPresent -and $tpm.TpmReady -and $tpm.TpmEnabled) { $data.Score += 15 }
    elseif ($tpm.TpmPresent -and $tpm.TpmEnabled) { $data.Score += 10; $data.Issues += 'TPM present but not ready' }
    else { $data.Issues += 'TPM not present or not enabled' }
} catch { $data.Issues += 'TPM check failed' }

# TPM version from WMI
try {
    $tpmWmi = Get-CimInstance -ClassName Win32_Tpm -Namespace root\CIMv2\Security\MicrosoftTpm -ErrorAction SilentlyContinue
    if ($tpmWmi) {
        $data.TPM.SpecVersion = if ($tpmWmi.SpecVersion) { "$($tpmWmi.SpecVersion.Split('.')[0]).$($tpmWmi.SpecVersion.Split('.')[1])" } else { 'Unknown' }
        $data.TPM.ManufacturerId = $tpmWmi.ManufacturerId
        $data.TPM.PhysicalPresenceVersion = $tpmWmi.PhysicalPresenceVersionInfo
        $isTpm20 = ([Version]$data.TPM.SpecVersion).Major -ge 2
        if (-not $isTpm20) { $data.Issues += 'TPM version < 2.0 - upgrade recommended for Windows 11' }
    }
} catch { }

# PCR banks
try {
    $pcrOutput = tpmtool /GetDeviceInformation 2>&1 | Out-String
    if ($pcrOutput -match 'PCR') {
        $lines = $pcrOutput -split "`n" | Where-Object { $_ -match 'PCR\d' }
        foreach ($line in $lines) {
            $name = if ($line -match 'PCR\d+') { $Matches[0] } else { 'Unknown' }
            $data.PCR += [pscustomobject]@{ Bank=$name; Info=$line.Trim() }
        }
    }
} catch { }

# UEFI firmware
try {
    $fwType = (Get-FirmwareType -ErrorAction SilentlyContinue)
    $data.FirmwareType = $fwType.ToString()
    $data.MaxScore += 5; if ($fwType -eq 'UEFI') { $data.Score += 5 } else { $data.Issues += 'Not UEFI firmware (Legacy BIOS)' }
} catch { }

# BitLocker requirement check
try {
    $blv = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
    $data.BitLockerOnSystem = ($blv.ProtectionStatus -eq 'On')
    $data.MaxScore += 5; if ($data.BitLockerOnSystem) { $data.Score += 5 } else { $data.Issues += 'System drive not BitLocker-protected' }
} catch { }

$scoreVal = if ($data.MaxScore -gt 0) { [math]::Round(($data.Score / $data.MaxScore) * 100, 0) } else { 0 }
$summary = "Secure Boot: $(if($data.SecureBoot){'ON'}else{'OFF'}) | TPM: $(if($data.TPM.Present){'v' + $data.TPM.SpecVersion}else{'Not present'}) | Score: $scoreVal%"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Get-SecureBootTPMState' -Status $(if ($data.SecureBoot -and $data.TPM.Ready) {'Success'} elseif ($data.SecureBoot) {'Warning'} else {'Failure'}) `
        -Summary $summary -Data $data -Errors $errors.ToArray() -Metrics @{ Score=$scoreVal; SecureBoot=$data.SecureBoot; TPM=$data.TPM.Ready }
} else {
    [pscustomobject]@{ Tool='Get-SecureBootTPMState'; Status=$(if ($data.SecureBoot -and $data.TPM.Ready) {'Success'} elseif ($data.SecureBoot) {'Warning'} else {'Failure'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
