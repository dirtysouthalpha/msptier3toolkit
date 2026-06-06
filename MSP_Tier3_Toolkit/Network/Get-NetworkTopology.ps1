<#
.SYNOPSIS
    Auto-discovers and maps the local network topology.
.DESCRIPTION
    Uses ARP cache, neighbor discovery, and traceroute to build a network
    topology map showing routers, switches, and connected devices with
    their relationships.
.NOTES
    v19.0 -- Advanced Network Diagnostics
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$GatewayIP,
    [Parameter(Mandatory=$false)]
    [int]$MaxHops = 15
)

$data = [PSCustomObject]@{
    Timestamp        = (Get-Date).ToString('o')
    LocalSubnet      = ''
    DefaultGateway   = ''
    DNSservers       = @()
    HopsToInternet   = @()
    ARPNeighbors     = 0
    Devices          = @()
    Checks           = @()
    Score            = 0
    MaxScore         = 0
    Summary          = ''
}

# Get local interface info
$net = Get-NetIPConfiguration -Detailed -ErrorAction SilentlyContinue | Select-Object -First 1
if ($net) {
    $data.LocalSubnet = "$($net.IPv4Address.IPAddress)/$($net.IPv4Address.PrefixLength)"
    $data.DefaultGateway = $net.IPv4DefaultGateway.NextHop
    $data.DNSservers = @($net.DNSServer.ServerAddresses)
}

# If gateway not provided, use default
if (-not $GatewayIP) { $GatewayIP = $data.DefaultGateway }

$data.Checks += [PSCustomObject]@{ Name='Network Config'; Pass=($null -ne $net); Detail="Subnet: $($data.LocalSubnet) | GW: $($data.DefaultGateway)" }

# Traceroute to internet
try {
    $trace = Test-NetConnection -ComputerName '8.8.8.8' -TraceRoute -ErrorAction SilentlyContinue
    if ($trace.TraceRoute) {
        $hopNum = 0
        foreach ($hop in $trace.TraceRoute) {
            $hopNum++
            if ($hopNum -gt $MaxHops) { break }
            $hopInfo = [PSCustomObject]@{ Hop=$hopNum; IP=$hop; Hostname=(''); LatencyMs=0 }
            try {
                $dns = [Net.Dns]::GetHostEntry($hop)
                $hopInfo.Hostname = $dns.HostName
            } catch { }
            try {
                $ping = Test-Connection -ComputerName $hop -Count 2 -ErrorAction SilentlyContinue
                if ($ping) { $hopInfo.LatencyMs = [math]::Round(($ping | Measure-Object -Property ResponseTime -Average).Average, 1) }
            } catch { }
            $data.HopsToInternet += $hopInfo
        }
    }
    $data.Checks += [PSCustomObject]@{ Name='Internet Path'; Pass=($data.HopsToInternet.Count -gt 0); Detail="$($data.HopsToInternet.Count) hops" }
} catch {
    $data.Checks += [PSCustomObject]@{ Name='Internet Path'; Pass=$false; Detail='Trace route failed' }
}

# ARP cache neighbors
$arp = arp -a 2>$null
if ($arp) {
    $arpLines = $arp -split "`n" | Where-Object { $_ -match '\d+\.\d+\.\d+\.\d+' }
    foreach ($line in $arpLines) {
        if ($line -match '(\d+\.\d+\.\d+\.\d+)\s+([\w-]+)') {
            $mac = $Matches[2]
            if ($mac -ne '---' -and $mac -notmatch 'ff-ff-ff-ff') {
                $data.ARPNeighbors++
                $data.Devices += [PSCustomObject]@{ IP=$Matches[1]; MAC=$mac; Source='ARP Cache' }
            }
        }
    }
}
$data.Checks += [PSCustomObject]@{ Name='ARP Neighbors'; Pass=($data.ARPNeighbors -gt 0); Detail="$($data.ARPNeighbors) devices in ARP cache" }

# Identify gateway/router device
if ($GatewayIP) {
    $gwDevice = $data.Devices | Where-Object { $_.IP -eq $GatewayIP }
    $data.Checks += [PSCustomObject]@{ Name='Gateway Identified'; Pass=($null -ne $gwDevice); Detail="GW at $GatewayIP" }
}

$data.MaxScore = $data.Checks.Count * 20
$data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
$data.Summary = "Topology: $($data.ARPNeighbors) neighbors | $($data.HopsToInternet.Count) hops to internet | GW: $GatewayIP"
return $data
