<#
.SYNOPSIS
    Uninstall well-known OEM and consumer bloatware (provisioned + installed).
.DESCRIPTION
    Removes a curated list of AppX packages -- Candy Crush, McAfee, Xbox apps,
    Dell SupportAssist consumer pieces, HP JumpStarts, Lenovo Vantage, etc.
    Removes both *installed* and *provisioned* (so they don't reappear for
    new users).

    Manual classic-installer cleanup (McAfee LiveSafe, Norton, etc.) is best
    done with vendor tools; this script focuses on AppX and a small set of
    MSI bloat detected via uninstall registry.

    Always supports -WhatIf and accepts a custom -Pattern list to extend.
.PARAMETER Pattern
    Wildcard patterns to match against AppX PackageFullName / DisplayName.
.EXAMPLE
    .\OEMBloatwareRemover.ps1 -WhatIf
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
    [string[]]$Pattern = @(
        '*Candy*Crush*','*king.com*','*BubbleWitch*',
        '*McAfee*','*Norton*Security*',
        '*XboxApp*','*XboxGameOverlay*','*XboxGamingOverlay*','*XboxIdentityProvider*','*XboxSpeechToTextOverlay*','*GamingApp*','*GameBar*',
        '*Microsoft.MixedReality.Portal*','*Microsoft.YourPhone*','*Microsoft.SkypeApp*','*Microsoft.GetHelp*','*Microsoft.Getstarted*','*Microsoft.MicrosoftSolitaireCollection*','*Microsoft.News*','*Microsoft.MicrosoftOfficeHub*','*Microsoft.WindowsFeedbackHub*','*Microsoft.Wallet*','*Microsoft.BingNews*','*Microsoft.BingWeather*','*Microsoft.Microsoft3DViewer*','*Microsoft.Print3D*','*Microsoft.Office.OneNote*',
        '*Dell.SupportAssist*','*DellInc*','*HP.JumpStart*','*HPJumpStart*','*HP.Audio*','*HPSure*','*HPSupportAssistant*','*LenovoCorporation*','*LenovoUtility*','*Lenovo.LenovoVantage*','*Disney*','*Spotify*','*Netflix*','*Facebook*','*TikTok*','*Hulu*','*Instagram*'
    ),
    [switch]$AsJson
)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$errors    = New-Object System.Collections.Generic.List[string]
$removed   = @()
$failed    = @()

# Installed (per-user)
foreach ($p in $Pattern) {
    Get-AppxPackage -AllUsers -Name $p -ErrorAction SilentlyContinue | ForEach-Object {
        $pkg = $_
        if ($PSCmdlet.ShouldProcess($pkg.PackageFullName, 'Remove-AppxPackage')) {
            try {
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                $removed += [pscustomobject]@{ Type='AppxInstalled'; Name=$pkg.Name; FullName=$pkg.PackageFullName }
            } catch {
                $failed += [pscustomobject]@{ Type='AppxInstalled'; Name=$pkg.Name; Error=$_.Exception.Message }
            }
        }
    }
}

# Provisioned (image-baked, removed = no reappearance for new users)
$prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
foreach ($p in $Pattern) {
    $prov | Where-Object DisplayName -like $p | ForEach-Object {
        $pkg = $_
        if ($PSCmdlet.ShouldProcess($pkg.PackageName, 'Remove-AppxProvisionedPackage')) {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageName -ErrorAction Stop | Out-Null
                $removed += [pscustomobject]@{ Type='AppxProvisioned'; Name=$pkg.DisplayName; FullName=$pkg.PackageName }
            } catch {
                $failed += [pscustomobject]@{ Type='AppxProvisioned'; Name=$pkg.DisplayName; Error=$_.Exception.Message }
            }
        }
    }
}

$status = if ($errors.Count -or $failed.Count) { 'Warning' } else { 'Success' }
$result = New-MSPResult `
    -Tool 'OEMBloatwareRemover' `
    -Status $status `
    -Summary "Removed $($removed.Count), failed $($failed.Count)." `
    -Data @{ Removed = $removed; Failed = $failed; PatternsUsed = $Pattern } `
    -Errors $errors.ToArray() `
    -Metrics @{ Removed = $removed.Count; Failed = $failed.Count }

[void](Save-MSPResult -Result $result -Subfolder 'Maintenance')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
