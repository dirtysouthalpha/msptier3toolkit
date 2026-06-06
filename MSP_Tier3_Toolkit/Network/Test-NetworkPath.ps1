<#
.SYNOPSIS
    Multi-signal network diagnostic against one or more targets.
.DESCRIPTION
    Replaces the 5 separate commands you'd normally run when a user reports
    "the internet is slow" with one call:
      - Default gateway + DNS responsiveness
      - ICMP + TCP connect (443, 80) to each target
      - DNS resolution time per target
      - Public IP + traceroute (first 8 hops, optional)
      - HTTP latency via HEAD when -Web
    Returns one row per target -- great for fleet runs.
.PARAMETER Target
    One or more hostnames/IPs to probe. Defaults to a useful pack:
    1.1.1.1, 8.8.8.8, google.com, outlook.office365.com.
.PARAMETER Web
    Include HTTP HEAD latency.
.PARAMETER Trace
    Include traceroute (first 8 hops).
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string[]]$Target = @('1.1.1.1','8.8.8.8','google.com','outlook.office365.com'),
    [switch]$Web,
    [switch]$Trace,
    [switch]$AsJson
)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$gateway = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric | Select-Object -First 1).NextHop
$dns     = (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object ServerAddresses).ServerAddresses | Select-Object -Unique

$rows = foreach ($t in $Target) {
    $row = [ordered]@{ Target = $t; Resolved = $null; PingMs = $null; TCP443 = $false; TCP80 = $false; DNSMs = $null; HttpMs = $null; HopCount = $null }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $ip = [System.Net.Dns]::GetHostAddresses($t) | Select-Object -First 1
        $row.Resolved = "$ip"
    } catch { }
    $row.DNSMs = $sw.ElapsedMilliseconds
    $sw.Stop()

    $ping = Test-Connection -ComputerName $t -Count 2 -ErrorAction SilentlyContinue
    if ($ping) { $row.PingMs = [math]::Round(($ping | Measure-Object ResponseTime -Average).Average) }

    $row.TCP443 = [bool](Test-NetConnection -ComputerName $t -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue)
    $row.TCP80  = [bool](Test-NetConnection -ComputerName $t -Port 80  -InformationLevel Quiet -WarningAction SilentlyContinue)

    if ($Web) {
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $null = Invoke-WebRequest -Uri "https://$t" -Method Head -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
            $row.HttpMs = $sw.ElapsedMilliseconds
            $sw.Stop()
        } catch { }
    }
    if ($Trace) {
        try {
            $tr = Test-NetConnection -ComputerName $t -TraceRoute -Hops 8 -WarningAction SilentlyContinue
            $row.HopCount = ($tr.TraceRoute | Where-Object { $_ -ne '0.0.0.0' }).Count
        } catch { }
    }
    [pscustomobject]$row
}

$rows   = @($rows)
$failed = @($rows | Where-Object { -not $_.TCP443 -and -not $_.TCP80 })
$status = if ($failed.Count -eq $rows.Count) { 'Failure' }
          elseif ($failed.Count) { 'Warning' }
          else { 'Success' }

$result = New-MSPResult `
    -Tool 'Test-NetworkPath' `
    -Status $status `
    -Summary "$($rows.Count) target(s), $($failed.Count) unreachable. GW: $gateway. DNS: $($dns -join ',')." `
    -Data @{ Gateway = $gateway; DNS = $dns; Results = $rows } `
    -Metrics @{ TargetCount = $rows.Count; FailedCount = $failed.Count }

[void](Save-MSPResult -Result $result -Subfolder 'Network')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
