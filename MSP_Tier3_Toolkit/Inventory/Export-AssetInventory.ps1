<#
.SYNOPSIS
    Build a PSA-ready hardware/software inventory snapshot.
.DESCRIPTION
    One-call inventory export designed to drop directly into Autotask, CW
    Manage, Halo, Hudu, or a CSV onboarding sheet. Includes:
      - Hardware: manufacturer/model/serial/CPU/RAM
      - Storage: per-volume size + free + SMART status when available
      - Network: NICs, IPs, gateway, DNS, public IP (skip with -SkipPublic)
      - OS: edition, build, install date, key (where exposed)
      - Installed software: name, version, publisher, install date
      - Local users / local admins
      - BitLocker + AV summary

    Output as JSON (default), CSV (-Format Csv splits into multiple files),
    or HTML (-Format Html -- single self-contained client-facing report).
.PARAMETER OutputPath
    Where to write. Defaults to <Reports>\Inventory\<host>_<stamp>.<ext>.
.PARAMETER Format
    Json (default), Csv, or Html.
.PARAMETER SkipPublic
    Skip the outbound HTTP call that fetches your public IP.
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Json','Csv','Html')]
    [string]$Format = 'Json',
    [string]$OutputPath,
    [switch]$SkipPublic
)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$paths = Get-MSPPaths
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'

$facts = Get-MSPOSFacts -Refresh

$publicIP = $null
if (-not $SkipPublic) {
    try {
        $publicIP = (Invoke-RestMethod -Uri 'https://api.ipify.org?format=json' -TimeoutSec 5).ip
    } catch { }
}

$installed = @()
$keys = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
foreach ($k in $keys) {
    Get-ItemProperty $k -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
        ForEach-Object {
            $installed += [pscustomobject]@{
                DisplayName    = $_.DisplayName
                DisplayVersion = $_.DisplayVersion
                Publisher      = $_.Publisher
                InstallDate    = $_.InstallDate
                EstimatedSize  = $_.EstimatedSize
                UninstallString= $_.UninstallString
            }
        }
}
$installed = $installed | Sort-Object DisplayName -Unique

$localUsers = @()
if (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) {
    $localUsers = Get-LocalUser | Select-Object Name, Enabled, LastLogon, PasswordRequired, PasswordExpires, Description
}
$localAdmins = @()
if (Get-Command Get-LocalGroupMember -ErrorAction SilentlyContinue) {
    try {
        $localAdmins = Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue |
            Select-Object Name, ObjectClass, PrincipalSource
    } catch { }
}

$bitLockerSummary = @()
if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
    try {
        $bitLockerSummary = Get-BitLockerVolume |
            Select-Object MountPoint, @{n='Protection';e={"$($_.ProtectionStatus)"}}, EncryptionPercentage,
                          @{n='Method';e={"$($_.EncryptionMethod)"}}
    } catch { }
}

$inventory = [pscustomobject]@{
    Schema       = 'msp-inventory/v1'
    GeneratedAt  = (Get-Date).ToString('o')
    Hardware     = $facts
    PublicIP     = $publicIP
    Software     = $installed
    LocalUsers   = $localUsers
    LocalAdmins  = $localAdmins
    BitLocker    = $bitLockerSummary
    PendingReboot = (Test-MSPPendingReboot)
}

if (-not $OutputPath) {
    $name = "$($facts.ComputerName)_$stamp"
    $OutputPath = Join-Path $paths.Inventory "$name.$($Format.ToLower())"
}

switch ($Format) {
    'Json' {
        $inventory | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    }
    'Csv' {
        $base = [System.IO.Path]::ChangeExtension($OutputPath, $null).TrimEnd('.')
        $installed   | Export-Csv "$base.software.csv"   -NoTypeInformation -Encoding UTF8
        $localUsers  | Export-Csv "$base.users.csv"      -NoTypeInformation -Encoding UTF8
        $localAdmins | Export-Csv "$base.localadmins.csv" -NoTypeInformation -Encoding UTF8
        $bitLockerSummary | Export-Csv "$base.bitlocker.csv" -NoTypeInformation -Encoding UTF8
        @($facts) | Export-Csv "$base.hardware.csv" -NoTypeInformation -Encoding UTF8
        $OutputPath = "$base.*.csv"
    }
    'Html' {
        $css = @'
<style>
body{font-family:Segoe UI,Arial,sans-serif;background:#f4f6fb;color:#1f2740;margin:0;padding:24px;}
h1{margin:0 0 4px 0;font-size:26px;}
h2{margin-top:32px;border-bottom:2px solid #4a5b8f;padding-bottom:4px;color:#27375f;}
table{border-collapse:collapse;width:100%;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.06);margin-top:12px;}
th{background:#27375f;color:#fff;text-align:left;padding:8px 12px;font-weight:600;}
td{padding:6px 12px;border-bottom:1px solid #e2e6ef;font-size:13px;}
tr:nth-child(even) td{background:#f8f9fc;}
.meta{color:#7a839c;font-size:12px;margin-bottom:18px;}
.badge{display:inline-block;padding:2px 8px;border-radius:10px;background:#dde6ff;color:#27375f;font-size:11px;}
</style>
'@
        $html = @"
<!doctype html><html><head><meta charset='utf-8'><title>Asset Inventory - $($facts.ComputerName)</title>$css</head><body>
<h1>Asset Inventory</h1>
<div class='meta'>$($facts.ComputerName) &middot; $($facts.OSName) &middot; generated $(Get-Date -Format 'yyyy-MM-dd HH:mm')</div>
<h2>Hardware</h2>
$((@($facts) | ConvertTo-Html -As List -Fragment) -join '')
<h2>BitLocker</h2>
$(($bitLockerSummary | ConvertTo-Html -Fragment) -join '')
<h2>Local Admins</h2>
$(($localAdmins | ConvertTo-Html -Fragment) -join '')
<h2>Installed Software ($($installed.Count))</h2>
$(($installed | Select-Object DisplayName,DisplayVersion,Publisher | ConvertTo-Html -Fragment) -join '')
</body></html>
"@
        $html | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    }
}

$result = New-MSPResult `
    -Tool 'Export-AssetInventory' `
    -Status 'Success' `
    -Summary "Inventory written to $OutputPath" `
    -Data @{ OutputPath = $OutputPath; SoftwareCount = $installed.Count } `
    -Metrics @{ SoftwareCount = $installed.Count; AdminCount = $localAdmins.Count }

[void](Save-MSPResult -Result $result -Subfolder 'Inventory')
$result
