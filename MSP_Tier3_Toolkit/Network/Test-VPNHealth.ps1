<#
.SYNOPSIS
    VPN posture check -- detect installed VPN clients, current state,
    split-tunnel routing, DNS leak.
.DESCRIPTION
    Field tool for the "I'm connected to VPN but X doesn't work" call.
    Detects: AnyConnect, GlobalProtect, OpenVPN, WireGuard, Always-On
    Windows VPN. Reports active tunnel adapter, assigned IP, default
    gateway, routes, DNS pushed by VPN vs. interface DNS, and a quick
    DNS-leak test (resolves a probe via both default and a public DNS).
#>
#Requires -Version 5.1
[CmdletBinding()]
param([switch]$AsJson)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

# Installed VPN client products
$installed = @()
$known = @(
    'AnyConnect|Cisco Secure Client',
    'GlobalProtect',
    'OpenVPN',
    'WireGuard',
    'NordVPN','ExpressVPN','TunnelBear',
    'FortiClient','SonicWall NetExtender','Pulse Secure','ZScaler'
)
$keys = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
foreach ($k in $keys) {
    Get-ItemProperty $k -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and ($known -join '|') -and ($_.DisplayName -match ($known -join '|')) } |
        ForEach-Object { $installed += $_.DisplayName }
}
$installed = $installed | Sort-Object -Unique

# Tunnel-ish adapters
$tunnels = Get-NetAdapter -ErrorAction SilentlyContinue |
           Where-Object { $_.MediaType -eq 'IP' -or $_.InterfaceDescription -match 'VPN|WireGuard|TAP|Tunnel|GlobalProtect|AnyConnect' }
$tunnelInfo = foreach ($t in $tunnels) {
    $ip = Get-NetIPAddress -InterfaceIndex $t.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $dns = (Get-DnsClientServerAddress -InterfaceIndex $t.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
    [pscustomobject]@{
        Name        = $t.Name
        Description = $t.InterfaceDescription
        Status      = "$($t.Status)"
        IPv4        = ($ip.IPAddress -join ',')
        DNS         = $dns -join ','
    }
}

# Default-route changes (split-tunnel detection)
$defaults = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric |
            Select-Object DestinationPrefix, NextHop, RouteMetric, InterfaceAlias

# DNS leak quick test -- resolve a probe via the system + public 1.1.1.1
$probe = 'whoami.akamai.net'
$sysAns = try { (Resolve-DnsName $probe -DnsOnly -QuickTimeout -ErrorAction Stop)[0].IPAddress } catch { '' }
$pubAns = try { (Resolve-DnsName $probe -Server 1.1.1.1 -DnsOnly -QuickTimeout -ErrorAction Stop)[0].IPAddress } catch { '' }
$dnsLeak = ($sysAns -and $pubAns -and $sysAns -ne $pubAns)

$activeTunnel = $tunnelInfo | Where-Object { $_.Status -eq 'Up' -and $_.IPv4 } | Select-Object -First 1
$status = if (-not $activeTunnel) { 'Warning' }
          elseif ($dnsLeak) { 'Warning' }
          else { 'Success' }

$summary = if (-not $activeTunnel) { "No active VPN tunnel; installed: $($installed -join ', ')" }
           else { "Tunnel $($activeTunnel.Name) up @ $($activeTunnel.IPv4); DNS leak: $dnsLeak" }

$result = New-MSPResult `
    -Tool 'Test-VPNHealth' `
    -Status $status `
    -Summary $summary `
    -Data @{
        InstalledClients = $installed
        Tunnels          = $tunnelInfo
        DefaultRoutes    = $defaults
        DnsLeak          = $dnsLeak
        SystemAnswer     = $sysAns
        PublicAnswer     = $pubAns
    } `
    -Metrics @{ ActiveTunnels = ($tunnelInfo | Where-Object Status -eq 'Up').Count; DnsLeakDetected = [int]$dnsLeak }

[void](Save-MSPResult -Result $result -Subfolder 'Network')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
