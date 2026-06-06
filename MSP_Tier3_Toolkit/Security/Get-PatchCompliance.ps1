<#
.SYNOPSIS
    Patch-compliance report for the local machine: missing/critical updates,
    last successful install, days since last reboot, current build.
.DESCRIPTION
    Uses the Microsoft.Update.Session COM API (works without PSWindowsUpdate)
    to list pending updates and recent install history. Falls back gracefully
    on Server Core / no-WSUS scenarios.
#>
#Requires -Version 5.1
[CmdletBinding()]
param([switch]$AsJson)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$errors  = New-Object System.Collections.Generic.List[string]
$pending = @()
$history = @()
$lastOk  = $null

try {
    $session  = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $search   = $searcher.Search("IsInstalled=0 and IsHidden=0")
    foreach ($u in $search.Updates) {
        $pending += [pscustomobject]@{
            Title    = $u.Title
            KB       = ($u.KBArticleIDs -join ',')
            Severity = $u.MsrcSeverity
            Size     = $u.MaxDownloadSize
            IsMandatory = $u.IsMandatory
        }
    }

    $count = $searcher.GetTotalHistoryCount()
    if ($count -gt 0) {
        $hist = $searcher.QueryHistory(0, [math]::Min($count, 50))
        foreach ($h in $hist) {
            $history += [pscustomobject]@{
                Title  = $h.Title
                Date   = $h.Date
                Result = switch ($h.ResultCode) { 2 {'Succeeded'} 3 {'WithErrors'} 4 {'Failed'} 5 {'Aborted'} default {'Other'} }
                HResult = '0x{0:X}' -f $h.HResult
            }
        }
        $lastOk = ($history | Where-Object Result -eq 'Succeeded' | Select-Object -First 1).Date
    }
}
catch { $errors.Add($_.Exception.Message) }

$os = Get-CimInstance Win32_OperatingSystem
$uptimeDays = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 1)
$build      = $os.BuildNumber
$critPending = @($pending | Where-Object { $_.Severity -in 'Critical','Important' }).Count

$status = if ($errors.Count) { 'Failure' }
          elseif ($critPending -gt 0 -or $uptimeDays -gt 30) { 'Warning' }
          else { 'Success' }

$summary = "Pending: $($pending.Count) ($critPending critical/important); uptime: $uptimeDays d; last success: $lastOk."

$result = New-MSPResult `
    -Tool 'Get-PatchCompliance' `
    -Status $status `
    -Summary $summary `
    -Data @{
        Build           = $build
        UptimeDays      = $uptimeDays
        LastSuccessful  = $lastOk
        Pending         = $pending
        RecentHistory   = $history | Select-Object -First 15
    } `
    -Errors $errors.ToArray() `
    -Metrics @{ PendingCount = $pending.Count; CriticalPending = $critPending; UptimeDays = $uptimeDays }

[void](Save-MSPResult -Result $result -Subfolder 'Security')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
