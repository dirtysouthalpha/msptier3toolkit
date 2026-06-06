<#
.SYNOPSIS
    Nuke the Outlook OST cache and rebuild the profile (per-user).
.DESCRIPTION
    The "I deleted my email and it came back / Outlook won't open / cached
    credentials are stuck" ticket. Closes Outlook, removes the OST, clears
    the AutoComplete cache and stored Windows credentials for Office
    endpoints. Optionally drops the active mail profile (so Outlook
    recreates from scratch on next launch).

    Runs in the current interactive user context -- that's the user whose
    Outlook is broken.
.PARAMETER ResetProfile
    Also clear the Outlook profile -- forces re-add of the account on next
    launch. Required when cached credentials are wedged.
.PARAMETER KeepAutoComplete
    Preserve the suggested-recipients stream. Default removes it.
.EXAMPLE
    .\Reset-OutlookCache.ps1
.EXAMPLE
    .\Reset-OutlookCache.ps1 -ResetProfile
#>
#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$ResetProfile,
    [switch]$KeepAutoComplete,
    [switch]$AsJson
)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$errors  = New-Object System.Collections.Generic.List[string]
$removed = New-Object System.Collections.Generic.List[string]
$bytesFreed = [long]0

# 1. Close Outlook
$proc = Get-Process OUTLOOK -ErrorAction SilentlyContinue
if ($proc) {
    if ($PSCmdlet.ShouldProcess('OUTLOOK.EXE', 'Stop-Process')) {
        $proc | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $removed.Add('Process: OUTLOOK.EXE killed')
    }
}

# 2. Remove OST files
$ostRoots = @(
    "$env:LOCALAPPDATA\Microsoft\Outlook",
    "$env:LOCALAPPDATA\Microsoft\OneNote"
)
foreach ($root in $ostRoots) {
    if (-not (Test-Path $root)) { continue }
    Get-ChildItem -LiteralPath $root -Filter *.ost -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($PSCmdlet.ShouldProcess($_.FullName, 'Delete OST')) {
            try {
                $bytesFreed += $_.Length
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                $removed.Add("OST: $($_.Name)")
            } catch { $errors.Add("OST $($_.Name): $($_.Exception.Message)") }
        }
    }
}

# 3. AutoComplete (.dat under RoamCache)
if (-not $KeepAutoComplete) {
    $roam = "$env:LOCALAPPDATA\Microsoft\Outlook\RoamCache"
    if (Test-Path $roam) {
        Get-ChildItem -LiteralPath $roam -Filter 'Stream_Autocomplete*.dat' -Force -ErrorAction SilentlyContinue | ForEach-Object {
            if ($PSCmdlet.ShouldProcess($_.FullName, 'Delete')) {
                try {
                    $bytesFreed += $_.Length
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                    $removed.Add("AutoComplete: $($_.Name)")
                } catch { $errors.Add("AutoComplete: $($_.Exception.Message)") }
            }
        }
    }
}

# 4. Stored Windows credentials for Office endpoints
$creds = & cmdkey /list 2>&1 | Select-String 'Target:'
foreach ($line in $creds) {
    $name = ($line -replace '^.*?Target:\s*','').Trim()
    if ($name -match 'MicrosoftOffice|MS\.Outlook|outlook\.office\.com|login\.microsoftonline|msteams') {
        if ($PSCmdlet.ShouldProcess($name, 'cmdkey /delete')) {
            & cmdkey /delete:"$name" | Out-Null
            $removed.Add("Credential: $name")
        }
    }
}

# 5. Optional profile blow-away
if ($ResetProfile) {
    $profilesKey = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Profiles'
    if (Test-Path $profilesKey) {
        if ($PSCmdlet.ShouldProcess($profilesKey, 'Remove profiles')) {
            try {
                Remove-Item -LiteralPath $profilesKey -Recurse -Force -ErrorAction Stop
                $removed.Add('Profiles: HKCU Outlook profiles cleared')
            } catch { $errors.Add("Profiles: $($_.Exception.Message)") }
        }
    }
    # Default Profile pointer
    $defaultKey = 'HKCU:\Software\Microsoft\Office\16.0\Outlook'
    if (Test-Path $defaultKey) {
        Remove-ItemProperty -LiteralPath $defaultKey -Name 'DefaultProfile' -ErrorAction SilentlyContinue
        $removed.Add('DefaultProfile pointer cleared')
    }
}

$status = if ($errors.Count) { 'Warning' } else { 'Success' }
$result = New-MSPResult `
    -Tool 'Reset-OutlookCache' `
    -Status $status `
    -Summary "Cleared $($removed.Count) item(s); freed $(ConvertTo-MSPSize $bytesFreed). Re-launch Outlook to rebuild." `
    -Data @{ Removed = $removed.ToArray(); ResetProfile = $ResetProfile.IsPresent } `
    -Errors $errors.ToArray() `
    -Metrics @{ ItemsRemoved = $removed.Count; BytesFreed = $bytesFreed }

[void](Save-MSPResult -Result $result -Subfolder 'Workstation')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
