<#
.SYNOPSIS
    Rebuild the Windows Search index when Start menu / Outlook search /
    File Explorer search returns no results.
.DESCRIPTION
    Standard remediation: stop WSearch, delete the Windows.edb database,
    start WSearch (it rebuilds automatically). Optionally also reset the
    indexer's known-folders list to defaults.

    Common trigger: profile migration, upgrade-in-place, corrupted
    Windows.edb. Reindex on a typical box takes 30 min - 4 hours
    depending on file count.
.PARAMETER ResetScope
    Also clear the user-added indexed locations so the indexer goes back
    to the OS defaults (Start menu, IE history, Users folder).
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$ResetScope,
    [switch]$AsJson
)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$errors = New-Object System.Collections.Generic.List[string]
$steps  = New-Object System.Collections.Generic.List[pscustomobject]
function StepRec($n,[scriptblock]$b){
    try { & $b; $steps.Add([pscustomobject]@{Step=$n;Ok=$true;Detail=''}) }
    catch { $errors.Add("$n : $($_.Exception.Message)"); $steps.Add([pscustomobject]@{Step=$n;Ok=$false;Detail=$_.Exception.Message}) }
}

StepRec 'Stop WSearch'   { Stop-Service WSearch -Force -ErrorAction Stop }

$edb = "$env:ProgramData\Microsoft\Search\Data\Applications\Windows\Windows.edb"
if (Test-Path $edb) {
    $size = (Get-Item $edb).Length
    StepRec "Delete Windows.edb ($(ConvertTo-MSPSize $size))" {
        Remove-Item -LiteralPath $edb -Force -ErrorAction Stop
    }
} else {
    $steps.Add([pscustomobject]@{Step='Delete Windows.edb';Ok=$true;Detail='Not present.'})
}

if ($ResetScope) {
    StepRec 'Reset indexed scope' {
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows Search\CrawlScopeManager\Windows\SystemIndex\WorkingSetRules'
        if (Test-Path $key) {
            Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction Stop
        }
    }
}

# Tell Search to rebuild via registry trigger (set SetupCompletedSuccessfully=0 forces rebuild)
StepRec 'Trigger rebuild' {
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Search' -Name 'SetupCompletedSuccessfully' -Value 0 -ErrorAction Stop
}

StepRec 'Start WSearch' { Start-Service WSearch -ErrorAction Stop }

$status = if ($errors.Count) { 'Warning' } else { 'Success' }
$result = New-MSPResult `
    -Tool 'Repair-WindowsSearch' `
    -Status $status `
    -Summary "WSearch rebuild triggered. Index repopulates in 30 min - 4 hours; let the box stay awake." `
    -Data @{ Steps = $steps.ToArray() } `
    -Errors $errors.ToArray() `
    -Metrics @{ StepsRun = $steps.Count; StepsFailed = $errors.Count }

[void](Save-MSPResult -Result $result -Subfolder 'Workstation')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
