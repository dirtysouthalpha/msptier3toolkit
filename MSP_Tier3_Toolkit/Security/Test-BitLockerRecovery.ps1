<#
.SYNOPSIS
    Test BitLocker recovery key availability in AD and Azure AD.
.DESCRIPTION
    Verifies that BitLocker recovery keys are properly escrowed for all protected volumes.
    Checks Active Directory (msFVE-RecoveryInformation) and Azure AD / Entra ID
    (via Microsoft Graph) for recovery key existence. Returns compliance status.
.PARAMETER ComputerName
    Target computer name (default: local computer).
.PARAMETER CheckAzureAD
    Also check Azure AD / Entra ID via Microsoft Graph (requires Graph module + app registration).
.PARAMETER TenantId
    Azure AD tenant ID (required if CheckAzureAD specified).
.PARAMETER AsJson
    Emit raw JSON to stdout.
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ComputerName = $env:COMPUTERNAME,
    [switch]$CheckAzureAD,
    [string]$TenantId,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$errors  = New-Object System.Collections.Generic.List[string]
$data    = @{ ComputerName=$ComputerName; Volumes=@(); ADKeysFound=0; AzureKeysFound=0; Compliant=$false }

# Get local BitLocker volumes
try {
    $volumes = Get-BitLockerVolume -ErrorAction Stop | Where-Object { $_.ProtectionStatus -eq 'On' }
    foreach ($vol in $volumes) {
        $data.Volumes += [pscustomobject]@{
            MountPoint       = $vol.MountPoint
            VolumeType       = "$($vol.VolumeType)"
            KeyProtectorTypes = @($vol.KeyProtector | ForEach-Object { "$($_.KeyProtectorType)" })
            HasRecoveryKey   = ($vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }).Count -gt 0
        }
    }
} catch {
    $errors.Add("Local BitLocker query failed: $($_.Exception.Message)")
}

# Check AD for recovery keys
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $computer = Get-ADComputer -Identity $ComputerName -Properties 'msFVE-RecoveryInformation' -ErrorAction Stop
    if ($computer.'msFVE-RecoveryInformation') {
        $data.ADKeysFound = $computer.'msFVE-RecoveryInformation'.Count
        # Mark volumes as having AD recovery key
        foreach ($v in $data.Volumes) {
            $v.HasADRecoveryKey = $true
        }
    }
} catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
    $errors.Add("Computer '$ComputerName' not found in AD.")
} catch {
    $errors.Add("AD recovery key query failed: $($_.Exception.Message)")
}

# Check Azure AD / Entra ID via Graph
if ($CheckAzureAD) {
    if (-not $TenantId) {
        $errors.Add('TenantId required when CheckAzureAD is specified.')
    } else {
        try {
            # Check if Graph module is available
            if (Get-Command Get-MgDevice -ErrorAction SilentlyContinue) {
                $device = Get-MgDevice -Filter "displayName eq '$ComputerName'" -ErrorAction SilentlyContinue
                if ($device) {
                    $keys = Get-MgDeviceBitLockerRecoveryKey -DeviceId $device.Id -ErrorAction SilentlyContinue
                    $data.AzureKeysFound = $keys.Count
                    foreach ($v in $data.Volumes) {
                        $v.HasAzureRecoveryKey = $keys.Count -gt 0
                    }
                } else {
                    $errors.Add("Device '$ComputerName' not found in Azure AD.")
                }
            } else {
                $errors.Add('Microsoft Graph PowerShell SDK not installed. Run: Install-Module Microsoft.Graph')
            }
        } catch {
            $errors.Add("Azure AD recovery key query failed: $($_.Exception.Message)")
        }
    }
}

# Determine compliance: every protected volume must have at least one recovery key source
$protectedVolumes = $data.Volumes | Where-Object { $_.HasRecoveryKey }
$compliantVolumes = $protectedVolumes | Where-Object { $_.HasADRecoveryKey -or $_.HasAzureRecoveryKey }
$data.Compliant = ($protectedVolumes.Count -eq $compliantVolumes.Count) -and ($protectedVolumes.Count -gt 0)

$status = if ($errors.Count -and $data.Volumes.Count -eq 0) { 'Failure' }
          elseif ($data.Compliant) { 'Success' }
          elseif ($protectedVolumes.Count -gt 0) { 'Warning' }
          else { 'Skipped' }

$summary = if ($data.Volumes.Count -eq 0) { 'No BitLocker-protected volumes found.' }
           elseif ($data.Compliant) { "All $($protectedVolumes.Count) protected volume(s) have recovery keys escrowed (AD: $($data.ADKeysFound), Azure: $($data.AzureKeysFound))." }
           else { "$($compliantVolumes.Count) of $($protectedVolumes.Count) protected volumes have recovery keys. Remediation needed." }

$result = New-MSPResult -Tool 'Test-BitLockerRecovery' -Status $status -Summary $summary -Data $data -Errors $errors.ToArray() `
    -Metrics @{ ProtectedVolumes=$protectedVolumes.Count; CompliantVolumes=$compliantVolumes.Count; ADKeys=$data.ADKeysFound; AzureKeys=$data.AzureKeysFound }

[void](Save-MSPResult -Result $result -Subfolder 'Security')
if ($AsJson) { $result | ConvertTo-Json -Depth 5 } else { $result }