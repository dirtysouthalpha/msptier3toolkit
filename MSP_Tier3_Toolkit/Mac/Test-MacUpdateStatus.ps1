<#
.SYNOPSIS
    MSP Toolkit - macOS Update Status.
.DESCRIPTION
    Checks softwareupdate pending updates, App Store updates,
    XProtect/gatekeeper data freshness, and available macOS upgrades.
#>
#Requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }

function _Run { param($c,$a,$t=30) & $c @$a 2>&1 | Out-String }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ PendingUpdates=@(); RecommendedUpdates=@(); MacOSUpgrades=@(); XProtectAge=''; GateKeeperDataAge=''; ConfigDataAge='' }

# --- Software Update List ---
try {
    $updateList = _Run 'softwareupdate' @('--list','--all') 30
    $currentSection = ''
    foreach ($line in ($updateList -split "`n")) {
        if ($line -match '^\s+\* Label:\s+(.+)') {
            $currentSection = $Matches[1].Trim()
        } elseif ($line -match 'Title:\s+(.+)' -and $currentSection) {
            $title = $Matches[1].Trim()
            $size = if ($line -match '(\d+[.,]?\d*\s*(KB|MB|GB))') { $Matches[1] } else { 'unknown' }
            $recommended = $line -match 'Recommended|Security'
            if ($currentSection -match 'macOS|installer') {
                $data.MacOSUpgrades += @{ Label=$currentSection; Title=$title; Size=$size }
            } elseif ($recommended) {
                $data.RecommendedUpdates += @{ Label=$currentSection; Title=$title; Size=$size }
            } else {
                $data.PendingUpdates += @{ Label=$currentSection; Title=$title; Size=$size }
            }
            $currentSection = ''
        }
    }
} catch { $errors.Add("SoftwareUpdate: $($_.Exception.Message)") }

# Total pending
$data.TotalPending = $data.PendingUpdates.Count + $data.RecommendedUpdates.Count + $data.MacOSUpgrades.Count
$data.AnyPending = $data.TotalPending -gt 0

# --- XProtect Data Freshness ---
try {
    $xpPath = '/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Resources/XProtect.meta.plist'
    if (Test-Path $xpPath) {
        $xpMeta = _Run 'plutil' @('-convert','xml1','-o','-',$xpPath) 5
        if ($xpMeta -match '<key>LastModification</key>') {
            $data.XProtectAge = 'Present (modified)'
        } else {
            $data.XProtectAge = 'Present'
        }
    } else {
        $data.XProtectAge = 'Not found'
    }
} catch { $errors.Add("XProtect: $($_.Exception.Message)") }

# --- GateKeeper / MRT Config Data ---
try {
    $gkConfig = _Run 'defaults' @('read','/private/var/db/gkopaque.bundle/Contents/Resources/gkopaque.meta.plist') 5
    $data.GateKeeperDataAge = if ($gkConfig -match 'LastModification') { 'Present' } else { 'Not found' }
} catch { $data.GateKeeperDataAge = 'Not found' }

$summary = "Pending: $($data.TotalPending) (Recommended: $($data.RecommendedUpdates.Count), macOS upgrades: $($data.MacOSUpgrades.Count))"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Test-MacUpdateStatus' -Status $(if ($data.RecommendedUpdates.Count -eq 0 -and $data.MacOSUpgrades.Count -eq 0) {'Success'} elseif ($data.RecommendedUpdates.Count -gt 0) {'Warning'} else {'Warning'}) `
        -Summary $summary -Data $data -Errors $errors.ToArray() `
        -Metrics @{ TotalPending=$data.TotalPending; Recommended=$data.RecommendedUpdates.Count; MacOSUpgrades=$data.MacOSUpgrades.Count }
} else {
    [pscustomobject]@{ Tool='Test-MacUpdateStatus'; Status=$(if ($data.RecommendedUpdates.Count -eq 0 -and $data.MacOSUpgrades.Count -eq 0) {'Success'} elseif ($data.RecommendedUpdates.Count -gt 0) {'Warning'} else {'Warning'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
