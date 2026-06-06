<#
.SYNOPSIS
    Report BitLocker encryption status for every fixed drive on the local machine.
.DESCRIPTION
    Returns a structured MSP-result object listing protection status, encryption
    method, key protector types, and percentage encrypted per volume. Designed
    to be run locally or fanned out via Invoke-MSPFleet.
.PARAMETER AsJson
    Emit raw JSON to stdout instead of a PSObject -- useful when called from the
    REST API.
.EXAMPLE
    .\BitLockerStatusCheck.ps1
.EXAMPLE
    .\BitLockerStatusCheck.ps1 -AsJson | Out-File report.json
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$volumes = @()
$errors  = New-Object System.Collections.Generic.List[string]

try {
    if (-not (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
        $errors.Add('Get-BitLockerVolume not available -- BitLocker feature missing or non-Pro SKU.')
    } else {
        $volumes = Get-BitLockerVolume | ForEach-Object {
            [pscustomobject]@{
                MountPoint        = $_.MountPoint
                VolumeType        = "$($_.VolumeType)"
                EncryptionMethod  = "$($_.EncryptionMethod)"
                ProtectionStatus  = "$($_.ProtectionStatus)"
                LockStatus        = "$($_.LockStatus)"
                EncryptionPercent = $_.EncryptionPercentage
                VolumeStatus      = "$($_.VolumeStatus)"
                KeyProtectors     = @($_.KeyProtector | ForEach-Object { "$($_.KeyProtectorType)" })
                AutoUnlockEnabled = [bool]$_.AutoUnlockEnabled
            }
        }
    }
}
catch {
    $errors.Add($_.Exception.Message)
}

$unprotected = @($volumes | Where-Object { $_.ProtectionStatus -ne 'On' -and $_.VolumeType -eq 'OperatingSystem' })
$status = if ($errors.Count) { 'Failure' }
          elseif ($unprotected.Count) { 'Warning' }
          else { 'Success' }

$summary = if ($volumes.Count -eq 0) {
    'No BitLocker volumes detected.'
} elseif ($unprotected.Count) {
    "OS drive not fully protected -- $($unprotected.Count) at-risk volume(s)."
} else {
    "All $($volumes.Count) volume(s) protected."
}

$result = New-MSPResult `
    -Tool 'BitLockerStatusCheck' `
    -Status $status `
    -Summary $summary `
    -Data @{ Volumes = $volumes } `
    -Errors $errors.ToArray() `
    -Metrics @{ VolumeCount = $volumes.Count; Unprotected = $unprotected.Count }

[void](Save-MSPResult -Result $result -Subfolder 'Security')

if ($AsJson) {
    $result | ConvertTo-Json -Depth 6
} else {
    $result
}
