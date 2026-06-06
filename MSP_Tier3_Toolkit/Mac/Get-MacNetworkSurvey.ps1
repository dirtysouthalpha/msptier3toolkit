<#
.SYNOPSIS
    MSP Toolkit - macOS Network Survey.
.DESCRIPTION
    WiFi signal survey via airport/airportd, DNS config, interface
    metrics, proxy settings, and internet reachability test.
#>
#Requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }

function _Run { param($c,$a,$t=15) & $c @$a 2>&1 | Out-String }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{}

# --- WiFi Scan ---
$data.WiFi = @{ CurrentBSSID=''; SSID=''; Channel=''; RSSI=''; BSSIDs=@() }
try {
    $airportCheck = _Run 'which' @('airport') 3
    $airportPath = if ($airportCheck -match '/') { $airportCheck.Trim() } else { '/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport' }
    
    if (Test-Path $airportPath) {
        $scan = _Run $airportPath @('-s') 10
        $lines = $scan -split "`n" | Select-Object -Skip 1
        foreach ($line in $lines) {
            $parts = $line -split '\s+'
            if ($parts.Count -ge 3) {
                $data.WiFi.BSSIDs += @{ SSID=$parts[0]; BSSID=$parts[1]; RSSI=$parts[2]; Channel=$parts[3] }
            }
        }
        $info = _Run $airportPath @('-I') 5
        $data.WiFi.CurrentBSSID = if ($info -match 'BSSID:\s+(.+)') { $Matches[1].Trim() } else { '' }
        $data.WiFi.SSID         = if ($info -match '\s+SSID:\s+(.+)') { $Matches[1].Trim() } else { '' }
        $data.WiFi.Channel      = if ($info -match 'channel:\s+(.+)') { $Matches[1].Trim() } else { '' }
        $data.WiFi.RSSI         = if ($info -match 'agrCtlRSSI:\s+(.+)') { $Matches[1].Trim() } else { '' }
        $data.WiFi.TxRate       = if ($info -match 'lastTxRate:\s+(.+)') { $Matches[1].Trim() } else { '' }
    } else {
        $errors.Add("airport utility not found at $airportPath")
    }
} catch { $errors.Add("WiFi scan: $($_.Exception.Message)") }

# --- Interface Stats ---
$data.Interfaces = @()
try {
    $ifconfig = _Run 'ifconfig' @() 5
    $currentIface = $null
    foreach ($line in ($ifconfig -split "`n")) {
        if ($line -match '^([a-z0-9]+):\s') {
            if ($currentIface) { $data.Interfaces += $currentIface }
            $currentIface = @{ Name=$Matches[1]; Flags=''; IPv4=''; IPv6=''; MAC=''; Status='unknown' }
        }
        if (-not $currentIface) { continue }
        if ($line -match 'flags=\d+<([^>]+)>') { $currentIface.Flags = $Matches[1]; $currentIface.Status = if ($Matches[1] -match 'UP') {'Up'} else {'Down'} }
        if ($line -match 'inet\s+(\d+\.\d+\.\d+\.\d+)') { $currentIface.IPv4 = $Matches[1] }
        if ($line -match 'inet6\s+([a-f0-9:]+)') { $currentIface.IPv6 = $Matches[1] }
        if ($line -match 'ether\s+([a-f0-9:]+)') { $currentIface.MAC = $Matches[1] }
    }
    if ($currentIface) { $data.Interfaces += $currentIface }
} catch { $errors.Add("Interfaces: $($_.Exception.Message)") }

# --- DNS Configuration ---
try {
    $resolv = _Run 'scutil' @('--dns') 5
    $data.DNS = @{ Servers=@(); SearchDomains=@() }
    $inServer = $false; $inSearch = $false
    foreach ($line in ($resolv -split "`n")) {
        if ($line -match 'nameserver\[(\d+)\]\s+:\s+(\S+)') { $data.DNS.Servers += $Matches[2] }
        if ($line -match 'search domain\[(\d+)\]\s+:\s+(\S+)') { $data.DNS.SearchDomains += $Matches[2] }
    }
} catch { $errors.Add("DNS: $($_.Exception.Message)") }

# --- Internet Reachability ---
try {
    $reachable = Test-Connection -TargetName '8.8.8.8' -Count 1 -Quiet -TimeoutSeconds 3
    $data.InternetReachable = $reachable
    $dnsTest = try { Resolve-DnsName 'google.com' -QuickTimeout -ErrorAction SilentlyContinue; $true } catch { $false }
    $data.DNSWorking = $dnsTest
} catch { $errors.Add("Reachability: $($_.Exception.Message)") }

$signal = if ($data.WiFi.RSSI) { $data.WiFi.RSSI } else { 'N/A' }
$summary = "WiFi: $($data.WiFi.SSID) ($signal dBm) | BSSIDs: $($data.WiFi.BSSIDs.Count) | Internet: $(if($data.InternetReachable){'Yes'}else{'No'})"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Get-MacNetworkSurvey' -Status $(if ($data.InternetReachable) { 'Success' } else { 'Warning' }) `
        -Summary $summary -Data $data -Errors $errors.ToArray() `
        -Metrics @{ BSSIDCount=$data.WiFi.BSSIDs.Count; Interfaces=$data.Interfaces.Count; DNSServers=$data.DNS.Servers.Count }
} else {
    [pscustomobject]@{ Tool='Get-MacNetworkSurvey'; Status=$(if ($data.InternetReachable) { 'Success' } else { 'Warning' }); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
