<#
.SYNOPSIS
    Reachability matrix for the official Microsoft 365 endpoint list.
.DESCRIPTION
    Pulls Microsoft's published endpoint catalog
    (endpoints.office.com/endpoints/Worldwide) and probes each required
    URL/IP for TCP reachability + TLS handshake. The classic
    "Outlook/Teams isn't connecting" diagnostic.

    Endpoints are bucketed by service area: Exchange / SharePoint /
    Skype / Common. Status per-bucket so you immediately see "Teams
    can't reach UDP 3478-3481" instead of a wall of failures.

    Network usage: one outbound HTTPS to endpoints.office.com plus one
    TCP connect per required URL (~80 endpoints typical).
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Instance = 'Worldwide',
    [switch]$AsJson
)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$clientReq = [guid]::NewGuid().ToString()
$uri = "https://endpoints.office.com/endpoints/$Instance`?clientrequestid=$clientReq"
$endpoints = try { Invoke-RestMethod -Uri $uri -TimeoutSec 10 }
             catch { throw "Failed to fetch endpoint list: $($_.Exception.Message)" }

$required = $endpoints | Where-Object { $_.required -eq $true -and $_.urls }
$rows = New-Object System.Collections.Generic.List[pscustomobject]
foreach ($e in $required) {
    foreach ($u in $e.urls) {
        $host = $u -replace '^\*\.','www.' -replace '^https?://',''
        $host = ($host -split '/')[0]
        $port = if ($e.tcpPorts) { ($e.tcpPorts -split ',')[0] -as [int] } else { 443 }
        $row = [pscustomobject]@{
            ServiceArea = $e.serviceArea
            Url         = $u
            Host        = $host
            Port        = $port
            Tcp         = $false
            Tls         = $false
            Ms          = $null
        }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $iar = $tcp.BeginConnect($host, $port, $null, $null)
            if ($iar.AsyncWaitHandle.WaitOne(2000)) {
                $tcp.EndConnect($iar)
                $row.Tcp = $tcp.Connected
                if ($port -eq 443 -and $row.Tcp) {
                    try {
                        $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, {$true})
                        $ssl.AuthenticateAsClient($host)
                        $row.Tls = $ssl.IsAuthenticated
                        $ssl.Close()
                    } catch { }
                }
            }
            $tcp.Close()
        } catch { }
        $row.Ms = $sw.ElapsedMilliseconds
        $rows.Add($row)
    }
}

$byArea = $rows | Group-Object ServiceArea | ForEach-Object {
    $bad = ($_.Group | Where-Object { -not $_.Tcp }).Count
    [pscustomobject]@{
        ServiceArea = $_.Name
        Total       = $_.Count
        Unreachable = $bad
        PctOk       = [math]::Round((($_.Count - $bad) / [math]::Max(1,$_.Count)) * 100,1)
    }
}

$totalBad = ($byArea | Measure-Object Unreachable -Sum).Sum
$status = if ($totalBad -eq 0) { 'Success' }
          elseif ($totalBad -lt $rows.Count / 4) { 'Warning' }
          else { 'Failure' }

$result = New-MSPResult `
    -Tool 'Test-M365Endpoints' `
    -Status $status `
    -Summary "$($rows.Count) endpoints probed; $totalBad unreachable; per-area: $(($byArea | ForEach-Object { "$($_.ServiceArea)=$($_.PctOk)%" }) -join ' ')" `
    -Data @{
        Instance       = $Instance
        ByServiceArea  = $byArea
        Failures       = ($rows | Where-Object { -not $_.Tcp })
        AllRows        = $rows.ToArray()
    } `
    -Metrics @{ Probed = $rows.Count; Unreachable = $totalBad }

[void](Save-MSPResult -Result $result -Subfolder 'Network')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
