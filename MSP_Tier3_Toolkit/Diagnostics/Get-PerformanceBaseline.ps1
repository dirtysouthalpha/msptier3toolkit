<#
.SYNOPSIS
    Sample CPU / memory / disk / network counters over N seconds for a
    "before/after" baseline.
.DESCRIPTION
    Uses Get-Counter to take a SampleCount-long snapshot then summarises
    averages, peaks, and top-N processes by CPU and working set. Useful
    when a user says "the box is slow" and you want concrete numbers.
.PARAMETER Seconds
    Total duration (default 30).
.PARAMETER Interval
    Sample interval seconds (default 2).
.PARAMETER TopProcesses
    Number of heavy hitters to list per metric (default 5).
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateRange(5,600)]
    [int]$Seconds = 30,
    [ValidateRange(1,10)]
    [int]$Interval = 2,
    [ValidateRange(1,25)]
    [int]$TopProcesses = 5,
    [switch]$AsJson
)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$samples = [math]::Ceiling($Seconds / $Interval)

$counters = @(
    '\Processor(_Total)\% Processor Time',
    '\Memory\Available MBytes',
    '\Memory\Committed Bytes',
    '\PhysicalDisk(_Total)\Avg. Disk sec/Read',
    '\PhysicalDisk(_Total)\Avg. Disk sec/Write',
    '\PhysicalDisk(_Total)\Disk Bytes/sec',
    '\Network Interface(*)\Bytes Total/sec'
)

$data = Get-Counter -Counter $counters -SampleInterval $Interval -MaxSamples $samples -ErrorAction SilentlyContinue
$avg = @{}
foreach ($c in $counters) {
    $vals = @()
    foreach ($s in $data) {
        $vals += ($s.CounterSamples | Where-Object Path -like "*$($c.Split('\')[-1])*").CookedValue
    }
    if ($vals) {
        $avg[$c] = [pscustomobject]@{
            Avg = [math]::Round(($vals | Measure-Object -Average).Average, 2)
            Max = [math]::Round(($vals | Measure-Object -Maximum).Maximum, 2)
            Min = [math]::Round(($vals | Measure-Object -Minimum).Minimum, 2)
        }
    }
}

$procsByCPU = Get-Process | Sort-Object CPU -Descending | Select-Object -First $TopProcesses |
              Select-Object Name, Id, @{n='CPU(s)';e={[math]::Round($_.CPU,1)}}, @{n='WS(MB)';e={[math]::Round($_.WorkingSet64/1MB)}}
$procsByRAM = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First $TopProcesses |
              Select-Object Name, Id, @{n='WS(MB)';e={[math]::Round($_.WorkingSet64/1MB)}}, @{n='CPU(s)';e={[math]::Round($_.CPU,1)}}

$cpuAvg = $avg['\Processor(_Total)\% Processor Time'].Avg
$memAvail = $avg['\Memory\Available MBytes'].Avg
$status = if ($cpuAvg -gt 85 -or $memAvail -lt 512) { 'Warning' } else { 'Success' }

$result = New-MSPResult `
    -Tool 'Get-PerformanceBaseline' `
    -Status $status `
    -Summary "CPU avg ${cpuAvg}%, mem avail ${memAvail} MB over ${Seconds}s." `
    -Data @{
        DurationSec      = $Seconds
        Interval         = $Interval
        Counters         = $avg
        TopByCPU         = $procsByCPU
        TopByMemory      = $procsByRAM
    } `
    -Metrics @{ CPUAvg = $cpuAvg; MemAvailMB = $memAvail }

[void](Save-MSPResult -Result $result -Subfolder 'Diagnostics')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
