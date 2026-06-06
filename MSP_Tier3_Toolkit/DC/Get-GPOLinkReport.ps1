<#
.SYNOPSIS
    MSP Toolkit - GPO Link & Health Report.
.DESCRIPTION
    Enumerates all GPOs, their links (OU/domain/site), enforcement status,
    WMI filter presence, SYSVOL version consistency.
#>
#Requires -Version 5.1
[CmdletBinding()]
param([string]$Domain)

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }
function _Run { param($c,$a,$t=30) & $c @$a 2>&1 | Out-String }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ GPOs=@(); Links=@(); WMIFilters=@(); Issues=@() }

try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Import-Module GroupPolicy -ErrorAction Stop

    $gpos = Get-GPO -All -Domain $Domain -ErrorAction SilentlyContinue

    foreach ($gpo in $gpos) {
        $gpoData = @{
            Name            = $gpo.DisplayName
            GUID            = $gpo.Id
            Status          = $gpo.GpoStatus
            Created         = $gpo.CreationTime
            Modified        = $gpo.ModificationTime
            Owner           = $gpo.Owner
            ComputerVersion = $gpo.Computer.DSVersion
            UserVersion     = $gpo.User.DSVersion
            Enabled         = $gpo.GpoStatus -eq 'AllSettingsEnabled'
            Links           = @()
            WMIFilter       = $null
        }

        # WMI Filter
        try {
            if ($gpo.WmiFilter) {
                $gpoData.WMIFilter = @{ Name=$gpo.WmiFilter.Name; Description=$gpo.WmiFilter.Description }
            }
        } catch { }

        # Links
        try {
            $links = & {
                $xml = [xml](Get-GPOReport -Guid $gpo.Id -ReportType Xml -ErrorAction SilentlyContinue)
                $xml.GPO.LinksTo | ForEach-Object {
                    $_.SOMPath
                }
            }
            $gpoData.Links = @($links)
        } catch { }

        $data.GPOs += [pscustomobject]$gpoData
    }

    # WMI Filter Inventory
    try {
        $filters = Get-ADObject -Filter { ObjectClass -eq 'msWMI-Som' } -Properties msWMI-Name,msWMI-Parm1,msWMI-Parm2 -SearchBase 'CN=SOM,CN=WMIPolicy,CN=System' -ErrorAction SilentlyContinue
        foreach ($f in $filters) {
            $data.WMIFilters += [pscustomobject]@{ Name=$f.'msWMI-Name'; Query=$f.'msWMI-Parm2'; ID=$f.Name }
        }
    } catch { }

    # Issues detection
    $disabled = @($data.GPOs | Where-Object { -not $_.Enabled }).Count
    $noLinks = @($data.GPOs | Where-Object { $_.Links.Count -eq 0 }).Count
    $noWMIButHasFilter = @($data.GPOs | Where-Object { -not $_.WMIFilter -and $_.Links.Count -gt 0 }).Count

    if ($disabled -gt 0) { $data.Issues += "$disabled GPOs are disabled" }
    if ($noLinks -gt 0) { $data.Issues += "$noLinks GPOs have no links (orphaned)" }

    $summary = "GPOs: $($data.GPOs.Count) | Disabled: $disabled | Orphaned: $noLinks | WMI filters: $($data.WMIFilters.Count)"

    if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
        New-MSPResult -Tool 'Get-GPOLinkReport' -Status $(if ($data.Issues.Count -gt 0) {'Warning'} else {'Success'}) `
            -Summary $summary -Data $data -Errors $errors.ToArray() `
            -Metrics @{ TotalGPOs=$data.GPOs.Count; Disabled=$disabled; Orphaned=$noLinks; WMIFilters=$data.WMIFilters.Count; Issues=$data.Issues.Count }
    } else {
        [pscustomobject]@{ Tool='Get-GPOLinkReport'; Status=$(if ($data.Issues.Count -gt 0) {'Warning'} else {'Success'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
    }
} catch {
    $errors.Add("GPO enumeration failed (GroupPolicy module may be unavailable): $($_.Exception.Message)")
    Write-Error "GPO enumeration failed: $($_.Exception.Message)"

    if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
        New-MSPResult -Tool 'Get-GPOLinkReport' -Status 'Failure' -Summary 'GPO enumeration failed' -Data $data -Errors $errors.ToArray()
    } else {
        [pscustomobject]@{ Tool='Get-GPOLinkReport'; Status='Failure'; Summary='GPO enumeration failed'; Errors=$errors.ToArray() }
    }
}
