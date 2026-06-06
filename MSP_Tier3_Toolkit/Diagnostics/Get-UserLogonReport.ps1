<#
.SYNOPSIS
    Report interactive logons / lockouts / failed sign-ins from the
    Security event log.
.DESCRIPTION
    Pulls 4624 (logon), 4625 (failed), 4634 (logoff), 4740 (lockout) from
    the Security log over the past N days, groups by account, and surfaces
    suspicious patterns (lockouts, repeated failures from a single workstation).

    Requires Admin to read Security log.
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [ValidateRange(1, 90)]
    [int]$Days = 7,
    [switch]$AsJson
)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$since   = (Get-Date).AddDays(-$Days)
$errors  = New-Object System.Collections.Generic.List[string]
$events  = @()

try {
    $events = Get-WinEvent -FilterHashtable @{
        LogName   = 'Security'
        Id        = 4624,4625,4740
        StartTime = $since
    } -MaxEvents 10000 -ErrorAction Stop
}
catch { $errors.Add($_.Exception.Message) }

$logonTypes = @{
    2  = 'Interactive'
    3  = 'Network'
    4  = 'Batch'
    5  = 'Service'
    7  = 'Unlock'
    8  = 'NetworkCleartext'
    10 = 'RemoteInteractive'
    11 = 'CachedInteractive'
}

$rows = foreach ($e in $events) {
    $xml = [xml]$e.ToXml()
    $data = @{}
    foreach ($d in $xml.Event.EventData.Data) { $data[$d.Name] = $d.'#text' }
    [pscustomobject]@{
        Time       = $e.TimeCreated
        Id         = $e.Id
        EventType  = switch ($e.Id) { 4624{'Logon'} 4625{'Failed'} 4740{'Lockout'} }
        User       = $data.TargetUserName
        Domain     = $data.TargetDomainName
        LogonType  = if ($data.LogonType) { "$($data.LogonType) ($($logonTypes[[int]$data.LogonType]))" } else { '' }
        Workstation= $data.WorkstationName
        SourceIP   = $data.IpAddress
        FailReason = $data.FailureReason
    }
}

$failedByUser = $rows | Where-Object EventType -eq 'Failed' |
                Group-Object User | Sort-Object Count -Descending |
                Select-Object -First 10 Name, Count
$lockouts = @($rows | Where-Object EventType -eq 'Lockout')

$status = if ($lockouts.Count) { 'Warning' } else { 'Success' }
$result = New-MSPResult `
    -Tool 'Get-UserLogonReport' `
    -Status $status `
    -Summary "Logons: $(($rows | Where-Object EventType -eq 'Logon').Count); Failed: $(($rows | Where-Object EventType -eq 'Failed').Count); Lockouts: $($lockouts.Count)" `
    -Data @{
        WindowDays   = $Days
        TopFailures  = $failedByUser
        Lockouts     = $lockouts
        AllEvents    = $rows | Select-Object -First 200
    } `
    -Errors $errors.ToArray() `
    -Metrics @{ LogonCount = ($rows | Where-Object EventType -eq 'Logon').Count;
                FailedCount = ($rows | Where-Object EventType -eq 'Failed').Count;
                LockoutCount = $lockouts.Count }

[void](Save-MSPResult -Result $result -Subfolder 'Diagnostics')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
