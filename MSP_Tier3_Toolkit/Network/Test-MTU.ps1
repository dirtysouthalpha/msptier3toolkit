<#
.SYNOPSIS
    Path-MTU discovery via DF-bit ping binary search.
.DESCRIPTION
    Finds the largest packet that survives end-to-end without fragmentation.
    The classic fix for "VPN works for some sites, drops connection for
    others" -- almost always a PMTU black hole somewhere upstream.

    Binary search between 576 (legacy floor) and 1500 (ethernet MTU).
    Returns the discovered MTU plus the configured interface MTU so you
    can spot mismatches.
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Target = '1.1.1.1',
    [int]$Min = 576,
    [int]$Max = 1500,
    [switch]$AsJson
)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

function Test-Mtu([int]$Size, [string]$T) {
    # 28 bytes overhead (20 IP + 8 ICMP)
    $payload = $Size - 28
    if ($payload -lt 1) { return $false }
    $r = & ping.exe -n 1 -f -l $payload -w 1000 $T
    return ($r -match 'Reply from') -and ($r -notmatch 'fragmented')
}

# Sanity: confirm Max DOESN'T pass and Min DOES
if (Test-Mtu $Max $Target) {
    $discovered = $Max
} elseif (-not (Test-Mtu $Min $Target)) {
    $discovered = 0
} else {
    $lo = $Min; $hi = $Max
    while ($hi - $lo -gt 2) {
        $mid = [int](($lo + $hi) / 2)
        if (Test-Mtu $mid $Target) { $lo = $mid } else { $hi = $mid }
    }
    $discovered = $lo
}

# Configured per-interface MTU
$configured = Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
              Where-Object ConnectionState -eq 'Connected' |
              Select-Object InterfaceAlias, NlMtu

$mismatch = $false
foreach ($iface in $configured) {
    if ($discovered -and $iface.NlMtu -gt $discovered) { $mismatch = $true }
}

$status = if ($discovered -eq 0) { 'Failure' }
          elseif ($mismatch) { 'Warning' }
          elseif ($discovered -lt 1400) { 'Warning' }
          else { 'Success' }

$summary = if ($discovered) { "Path MTU to ${Target}: $discovered bytes (configured min: $($configured.NlMtu | Sort-Object | Select-Object -First 1))" }
           else { "Could not establish path MTU -- target unreachable or all sizes fail." }

$result = New-MSPResult `
    -Tool 'Test-MTU' `
    -Status $status `
    -Summary $summary `
    -Data @{
        Target            = $Target
        DiscoveredMTU     = $discovered
        InterfaceMTUs     = $configured
        InterfaceMismatch = $mismatch
    } `
    -Metrics @{ DiscoveredMTU = $discovered }

[void](Save-MSPResult -Result $result -Subfolder 'Network')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
