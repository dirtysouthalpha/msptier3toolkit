<#
.SYNOPSIS
    Report antivirus state via SecurityCenter2 + Microsoft Defender.
.DESCRIPTION
    Queries WMI's SecurityCenter2 namespace for every registered AV product
    (true on workstations) and Microsoft Defender's own status (works on
    Server). Reports real-time protection, signature freshness, and last
    scan times.
.EXAMPLE
    .\AVStatusCheck.ps1
#>
#Requires -Version 5.1
[CmdletBinding()]
param([switch]$AsJson)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$errors = New-Object System.Collections.Generic.List[string]
$avs    = @()
$defender = $null

# SecurityCenter2 is only present on client SKUs
try {
    $avs = Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction SilentlyContinue |
        ForEach-Object {
            $state = $_.productState
            # productState bit decoding -- Microsoft never documented this
            # officially; community decodes are reliable. Bit 0x1000 = enabled,
            # 0x0010 in low byte = up-to-date.
            $enabled    = ($state -band 0x1000) -ne 0
            $upToDate   = (($state -shr 4) -band 0x10) -eq 0
            [pscustomobject]@{
                DisplayName    = $_.displayName
                ProductState   = '0x{0:X}' -f $state
                Enabled        = $enabled
                SignaturesCurrent = $upToDate
                PathToSignedProductExe = $_.pathToSignedProductExe
            }
        }
}
catch { $errors.Add("SecurityCenter2: $($_.Exception.Message)") }

if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
    try {
        $d = Get-MpComputerStatus
        $defender = [pscustomobject]@{
            Enabled               = $d.AntivirusEnabled
            RealTime              = $d.RealTimeProtectionEnabled
            NIS                   = $d.NISEnabled
            TamperProtection      = $d.IsTamperProtected
            SignatureAge          = $d.AntivirusSignatureAge
            SignatureLastUpdated  = $d.AntivirusSignatureLastUpdated
            QuickScanAgeDays      = $d.QuickScanAge
            FullScanAgeDays       = $d.FullScanAge
            EngineVersion         = $d.AMEngineVersion
            SignatureVersion      = $d.AntivirusSignatureVersion
        }
    } catch { $errors.Add("Defender: $($_.Exception.Message)") }
}

$problems = New-Object System.Collections.Generic.List[string]
if ($avs.Count -eq 0 -and -not $defender) { $problems.Add('No AV product detected.') }
if ($defender -and -not $defender.RealTime) { $problems.Add('Defender real-time protection disabled.') }
if ($defender -and $defender.SignatureAge -gt 7) { $problems.Add("Defender signatures $($defender.SignatureAge) days old.") }
foreach ($a in $avs) {
    if (-not $a.Enabled)           { $problems.Add("$($a.DisplayName) disabled.") }
    if (-not $a.SignaturesCurrent) { $problems.Add("$($a.DisplayName) signatures out of date.") }
}

$status = if ($errors.Count) { 'Failure' } elseif ($problems.Count) { 'Warning' } else { 'Success' }
$summary = if ($problems.Count) { ($problems -join ' / ') } else { 'AV healthy.' }

$result = New-MSPResult `
    -Tool 'AVStatusCheck' `
    -Status $status `
    -Summary $summary `
    -Data @{ Products = $avs; Defender = $defender; Problems = $problems.ToArray() } `
    -Errors $errors.ToArray() `
    -Metrics @{ ProductCount = $avs.Count }

[void](Save-MSPResult -Result $result -Subfolder 'Security')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
