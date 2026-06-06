<#
.SYNOPSIS
    MSP Toolkit - Shadow Copy Report.
.DESCRIPTION
    Enumerates per-volume shadow copies, schedule configuration,
    space usage, and oldest/newest snapshot age.
#>
#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ Volumes=@(); Summary=@{} }

try {
    $volumes = Get-CimInstance Win32_Volume -Filter 'DriveType=3' -ErrorAction SilentlyContinue
    foreach ($vol in $volumes) {
        $volData = @{
            Drive           = $vol.DriveLetter
            Label           = $vol.Label
            CapacityGB      = [math]::Round($vol.Capacity / 1GB, 1)
            FreeGB          = [math]::Round($vol.FreeSpace / 1GB, 1)
            Shadows         = @()
            ShadowCount     = 0
            OldestShadow    = $null
            NewestShadow    = $null
            ShadowStorage   = ''
            Schedule        = ''
        }

        # Enumerate shadow copies
        try {
            $shadows = Get-CimInstance Win32_ShadowCopy -ErrorAction SilentlyContinue | Where-Object { $_.VolumeName -eq $vol.DeviceID }
            foreach ($sh in $shadows) {
                $volData.Shadows += [pscustomobject]@{
                    ID            = $sh.ID
                    ClientAccessible = $sh.ClientAccessible
                    Count         = $sh.Count
                    DeviceObject  = $sh.DeviceObject
                    InstallDate   = $sh.InstallDate
                }
            }
            $volData.ShadowCount = $volData.Shadows.Count
            if ($volData.Shadows.Count -gt 0) {
                $sorted = $volData.Shadows | Sort-Object InstallDate
                $volData.OldestShadow = $sorted[0].InstallDate
                $volData.NewestShadow = $sorted[-1].InstallDate
            }
        } catch { $errors.Add("Shadow query for $($vol.DriveLetter): $($_.Exception.Message)") }

        # Shadow storage
        try {
            $vssStorage = vssadmin list shadowstorage 2>&1 | Out-String
            foreach ($line in ($vssStorage -split "`n")) {
                if ($line -match "$($vol.DriveLetter):\\\\") {
                    $volData.ShadowStorage += $line.Trim() + "`n"
                }
            }
        } catch { }

        $data.Volumes += [pscustomobject]$volData
    }

    $totalShadows = ($data.Volumes | ForEach-Object { $_.ShadowCount } | Measure-Object -Sum).Sum
    $data.Summary = @{
        TotalVolumes  = $data.Volumes.Count
        TotalShadows  = $totalShadows
        VolumesWithShadows = ($data.Volumes | Where-Object { $_.ShadowCount -gt 0 }).Count
    }
} catch { $errors.Add("Shadow copy enumeration: $($_.Exception.Message)") }

$summary = "Volumes: $($data.Summary.TotalVolumes) | Shadows: $($data.Summary.TotalShadows) | With shadows: $($data.Summary.VolumesWithShadows)"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Get-ShadowCopyReport' -Status 'Success' -Summary $summary -Data $data -Errors $errors.ToArray() `
        -Metrics @{ Volumes=$data.Summary.TotalVolumes; TotalShadows=$data.Summary.TotalShadows; WithShadows=$data.Summary.VolumesWithShadows }
} else {
    [pscustomobject]@{ Tool='Get-ShadowCopyReport'; Status='Success'; Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
