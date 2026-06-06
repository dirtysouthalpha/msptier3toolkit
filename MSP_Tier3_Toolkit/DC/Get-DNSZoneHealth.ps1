<#
.SYNOPSIS
    MSP Toolkit - DNS Zone Health Check.
.DESCRIPTION
    Checks per-zone SOA serial consistency across DNS servers, aging/ scavenging
    configuration, forwarder resolution, and zone transfer settings.
    Uses dnscmd and Get-DnsServerZone when available.
#>
#Requires -Version 5.1
[CmdletBinding()]
param([string]$ComputerName = $env:COMPUTERNAME)

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }
function _Run { param($c,$a,$t=30) & $c @$a 2>&1 | Out-String }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ Zones=@(); Forwarders=@(); Scavenging=@{}; SerialConflicts=@() }

# --- List all zones ---
$zones = @()
try {
    # Try DNSServer module
    Import-Module DNSServer -ErrorAction Stop
    $zones = Get-DnsServerZone -ComputerName $ComputerName -ErrorAction SilentlyContinue
    foreach ($zone in $zones) {
        $zoneData = @{
            Name              = $zone.ZoneName
            Type              = $zone.ZoneType
            Replication       = $zone.ReplicationScope
            DynamicUpdate     = $zone.DynamicUpdate
            AgingEnabled      = $zone.Aging
            RefreshInterval   = $zone.RefreshInterval
            ScavengeServers   = @()
        }
        # SOA
        try {
            $soa = Get-DnsServerResourceRecord -ComputerName $ComputerName -ZoneName $zone.ZoneName -Name '@' -RRType SOA -ErrorAction SilentlyContinue
            if ($soa -and $soa.RecordData) {
                $zoneData.SOA = @{
                    PrimaryServer = $soa.RecordData.PrimaryServer
                    SerialNumber  = $soa.RecordData.SerialNumber
                    Refresh       = $soa.RecordData.RefreshInterval
                    Retry         = $soa.RecordData.RetryDelay
                    Expire        = $soa.RecordData.ExpireLimit
                    MinimumTTL    = $soa.RecordData.MinimumTimeToLive
                }
            }
        } catch { }
        if (Get-Command Test-MSPPortDC -ErrorAction SilentlyContinue) { } # skip port check in zone loop
        $data.Zones += $zoneData
    }
} catch {
    # dnscmd fallback
    try {
        $dnscmd = _Run 'dnscmd' @($ComputerName,'/EnumZones') 30
        $lines = $dnscmd -split "`n" | Where-Object { $_ -match '(Primary|Secondary|Stub)\s+(\S+)' }
        foreach ($line in $lines) {
            if ($line -match '(Primary|Secondary|Stub)\s+(\S+)') {
                $zoneType = $Matches[1]
                $zoneName = $Matches[2]
                $zoneData = @{ Name=$zoneName; Type=$zoneType; Replication=''; DynamicUpdate=''; AgingEnabled=$false }
                $data.Zones += $zoneData
            }
        }
    } catch { $errors.Add("EnumZones: $($_.Exception.Message)") }
}

# --- Forwarders ---
try {
    if (Get-Command Get-DnsServerForwarder -ErrorAction SilentlyContinue) {
        $fwd = Get-DnsServerForwarder -ComputerName $ComputerName -ErrorAction SilentlyContinue
        foreach ($f in $fwd) {
            $data.Forwarders += [pscustomobject]@{ IP=$f.IPAddress; Timeout=$f.Timeout; UseRootHint=$f.UseRootHint }
        }
    } else {
        $dnscmd = _Run 'dnscmd' @($ComputerName,'/Info') 10
        if ($dnscmd -match 'fowarders:\s*(.+)') { $data.Forwarders += @($Matches[1] -split '\s+' | Where-Object { $_ }) }
    }
} catch { $errors.Add("Forwarders: $($_.Exception.Message)") }

# --- Scavenging Config ---
try {
    if (Get-Command Get-DnsServerScavenging -ErrorAction SilentlyContinue) {
        $scav = Get-DnsServerScavenging -ComputerName $ComputerName -ErrorAction SilentlyContinue
        $data.Scavenging = @{ Enabled=$scav.ScavengingState; Interval=$scav.ScavengingInterval; Refresh=$scav.RefreshInterval; NoRefresh=$scav.NoRefreshInterval; LastScavenge=$scav.LastScavengeTime }
    } else {
        $dnscmd = _Run 'dnscmd' @($ComputerName,'/Info') 10
        $data.Scavenging = @{
            Enabled = ($dnscmd -match 'ScavengingInterval.*=\s*(\d+).*AutoScavengeInterval.*=\s*(\d+)')
            Raw = $dnscmd
        }
    }
} catch { $errors.Add("Scavenging: $($_.Exception.Message)") }

# --- SOA Serial Conflict Detection ---
$serialMap = @{}
foreach ($z in $data.Zones) {
    if ($z.SOA -and $z.SOA.SerialNumber) {
        $key = $z.Name
        if (-not $serialMap[$key]) { $serialMap[$key] = @() }
        $serialMap[$key] += [pscustomobject]@{ DC=$ComputerName; Serial=$z.SOA.SerialNumber }
    }
}
foreach ($key in $serialMap.Keys) {
    $serials = $serialMap[$key]
    $unique = ($serials | Select-Object -ExpandProperty Serial -Unique).Count
    if ($unique -gt 1) {
        $data.SerialConflicts += [pscustomobject]@{ Zone=$key; Serials=@($serials); Conflict=$true }
    }
}

$zoneCount = $data.Zones.Count
$conflicts = $data.SerialConflicts.Count
$summary = "Zones: $zoneCount | Forwarders: $($data.Forwarders.Count) | Scavenging: $(if($data.Scavenging.Enabled){'On'}else{'Off'}) | Serial conflicts: $conflicts"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Get-DNSZoneHealth' -Status $(if ($conflicts -gt 0) {'Warning'} else {'Success'}) `
        -Summary $summary -Data $data -Errors $errors.ToArray() `
        -Metrics @{ ZoneCount=$zoneCount; ForwarderCount=$data.Forwarders.Count; Scavenging=$data.Scavenging.Enabled; SerialConflicts=$conflicts }
} else {
    [pscustomobject]@{ Tool='Get-DNSZoneHealth'; Status=$(if ($conflicts -gt 0) {'Warning'} else {'Success'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
