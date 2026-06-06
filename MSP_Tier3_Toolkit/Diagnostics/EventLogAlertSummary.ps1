<#
.SYNOPSIS
    Surface noteworthy Event Log entries from System and Application logs.
.DESCRIPTION
    Pulls Critical, Error, and selected high-signal Warnings from the System
    and Application logs over the past N hours, groups by event ID + source,
    and ranks by frequency. Output is a structured MSP result; intended to
    feed daily/weekly health emails or ticket auto-creation.

.PARAMETER Hours
    Look-back window. Default 24.
.PARAMETER TopN
    Cap on number of grouped events returned. Default 25.
.EXAMPLE
    .\EventLogAlertSummary.ps1 -Hours 72
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateRange(1, 720)]
    [int]$Hours = 24,
    [ValidateRange(1, 200)]
    [int]$TopN = 25,
    [switch]$AsJson
)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$since   = (Get-Date).AddHours(-$Hours)
$errors  = New-Object System.Collections.Generic.List[string]
$grouped = @()

$filter = @{
    LogName   = 'System','Application'
    StartTime = $since
    Level     = 1,2,3   # Critical, Error, Warning
}

try {
    $events = Get-WinEvent -FilterHashtable $filter -MaxEvents 5000 -ErrorAction Stop

    # Warnings flood logs -- only keep ones MSPs actually care about.
    $signalSources = '^(disk|ntfs|volsnap|kernel-power|dhcp-client|service control manager|application error|.net runtime|wininit|w32time|Microsoft-Windows-WindowsUpdateClient|Microsoft-Windows-Hyper-V.*)$'

    $events = $events | Where-Object {
        $_.LevelDisplayName -ne 'Warning' -or $_.ProviderName -match $signalSources
    }

    $grouped = $events |
        Group-Object ProviderName, Id, LevelDisplayName |
        Sort-Object Count -Descending |
        Select-Object -First $TopN |
        ForEach-Object {
            $sample = $_.Group | Select-Object -First 1
            [pscustomobject]@{
                Source       = $sample.ProviderName
                Id           = $sample.Id
                Level        = $sample.LevelDisplayName
                Count        = $_.Count
                FirstSeen    = ($_.Group | Sort-Object TimeCreated | Select-Object -First 1).TimeCreated
                LastSeen     = ($_.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated
                SampleMessage = ($sample.Message -replace "`r?`n",' ').Substring(0,[math]::Min(180, $sample.Message.Length))
            }
        }
}
catch {
    $errors.Add($_.Exception.Message)
}

$critCount = @($grouped | Where-Object Level -in 'Critical','Error').Count
$status = if ($errors.Count) { 'Failure' } elseif ($critCount -gt 0) { 'Warning' } else { 'Success' }

$result = New-MSPResult `
    -Tool 'EventLogAlertSummary' `
    -Status $status `
    -Summary "Found $($grouped.Count) noteworthy event groups in last $Hours h." `
    -Data @{ WindowHours = $Hours; Groups = $grouped } `
    -Errors $errors.ToArray() `
    -Metrics @{ CriticalOrError = $critCount; TotalGroups = $grouped.Count }

[void](Save-MSPResult -Result $result -Subfolder 'Diagnostics')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
