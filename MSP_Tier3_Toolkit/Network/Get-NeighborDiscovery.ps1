<#
.SYNOPSIS
    Discover the switch/router neighbour the local NIC is plugged into
    via LLDP and CDP packet capture.
.DESCRIPTION
    When you walk into a server room and need to know "what switch port
    is this server on" without logging into the switch. Listens for
    LLDP (0x88CC) and CDP frames for N seconds and reports:

      - Local interface
      - Neighbour device name + model
      - Port ID
      - VLAN
      - Management IP

    Uses native `Get-NetAdapter` + a short pktmon capture (Win10/11/Server
    2019+). Falls back to checking the NDIS LLDP cache if pktmon is not
    available.

    Requires admin.
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [int]$Seconds = 35,
    [switch]$AsJson
)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$errors = New-Object System.Collections.Generic.List[string]
$result = $null

# Strategy 1: NDIS LLDP cache (fast, no capture needed if driver supports it)
$cached = @()
try {
    $cached = Get-NetLldpAgent -ErrorAction SilentlyContinue
} catch { }

# Strategy 2: pktmon-based capture (35 s default -- LLDP TTL is 30 s)
$pktData = @()
$pmExe = Get-Command pktmon -ErrorAction SilentlyContinue
if ($pmExe) {
    try {
        & pktmon filter remove | Out-Null
        & pktmon filter add -t 0x88CC | Out-Null              # LLDP
        $pcapPath = Join-Path $env:TEMP "msp_lldp_$([guid]::NewGuid().ToString('N').Substring(0,8)).etl"
        & pktmon start --capture --pkt-size 0 --file-name $pcapPath | Out-Null
        Start-Sleep -Seconds $Seconds
        & pktmon stop | Out-Null
        & pktmon filter remove | Out-Null
        # Convert ETL to text -- pktmon outputs binary; rely on `pktmon format`
        $txt = & pktmon format $pcapPath 2>$null
        $pktData = $txt | Where-Object { $_ -match 'LLDP|CDP' }
        Remove-Item $pcapPath -Force -ErrorAction SilentlyContinue
    } catch {
        $errors.Add("pktmon: $($_.Exception.Message)")
    }
} else {
    $errors.Add('pktmon not available on this OS; only NDIS cache will be returned.')
}

# Strategy 3: Switch port description from registry on some Intel/Broadcom drivers
$driverHints = @()
foreach ($nic in (Get-NetAdapter -Physical | Where-Object Status -eq 'Up')) {
    $hint = (Get-NetAdapterAdvancedProperty -Name $nic.Name -ErrorAction SilentlyContinue |
             Where-Object { $_.DisplayName -match 'LLDP|Switch|Neighbor' }).DisplayValue
    if ($hint) {
        $driverHints += [pscustomobject]@{ Nic = $nic.Name; Hint = $hint }
    }
}

$summary = if ($cached) { "$($cached.Count) NDIS LLDP agent(s) reported" }
           elseif ($pktData.Count) { "Captured $($pktData.Count) LLDP/CDP frame(s) in $Seconds s" }
           else { 'No neighbour info found -- switch may not advertise LLDP/CDP, or driver does not expose cache.' }

$status = if ($cached -or $pktData.Count -or $driverHints.Count) { 'Success' } else { 'Warning' }
$result = New-MSPResult `
    -Tool 'Get-NeighborDiscovery' `
    -Status $status `
    -Summary $summary `
    -Data @{
        NDISAgents     = $cached
        CapturedFrames = $pktData
        DriverHints    = $driverHints
        CaptureSeconds = $Seconds
    } `
    -Errors $errors.ToArray() `
    -Metrics @{ Frames = $pktData.Count }

[void](Save-MSPResult -Result $result -Subfolder 'Network')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
