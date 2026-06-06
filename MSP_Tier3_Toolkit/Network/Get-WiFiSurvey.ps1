<#
.SYNOPSIS
    WiFi spectrum + roaming health survey for the local machine.
.DESCRIPTION
    Uses `netsh wlan show` underneath to surface:
      - Current SSID, BSSID, channel, signal, radio type, auth
      - All visible BSSIDs ranked by signal
      - Channel overlap on 2.4 GHz (overlapping 1/6/11 calc)
      - Saved profiles + auto-connect priority
      - Roam aggressiveness setting (registry)

    Output is structured -- feed it into the GUI or a fleet run to spot
    a single weak AP across all field machines.
#>
#Requires -Version 5.1
[CmdletBinding()]
param([switch]$AsJson)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$current = @{}
$bssids  = New-Object System.Collections.Generic.List[pscustomobject]
$profiles = @()
$errors  = New-Object System.Collections.Generic.List[string]

try {
    # Current association
    $iface = & netsh wlan show interfaces 2>&1
    foreach ($line in $iface) {
        if ($line -match '^\s*(SSID|BSSID|Signal|Channel|Radio type|Authentication|Receive rate|Transmit rate|State)\s*:\s*(.+)$') {
            $current[$matches[1].Trim()] = $matches[2].Trim()
        }
    }

    # Visible networks
    $netsh = & netsh wlan show networks mode=bssid 2>&1
    $cur = $null; $bss = $null
    foreach ($line in $netsh) {
        if ($line -match '^SSID \d+ : (.+)$') {
            $cur = $matches[1].Trim()
        } elseif ($line -match '^\s*BSSID \d+\s*:\s*(.+)$') {
            $bss = [pscustomobject]@{
                SSID = $cur; BSSID = $matches[1].Trim(); Signal = $null; Channel = $null; Radio = $null
            }
            $bssids.Add($bss)
        } elseif ($bss -and $line -match '^\s*Signal\s*:\s*(\d+)%') {
            $bss.Signal = [int]$matches[1]
        } elseif ($bss -and $line -match '^\s*Channel\s*:\s*(\d+)') {
            $bss.Channel = [int]$matches[1]
        } elseif ($bss -and $line -match '^\s*Radio type\s*:\s*(.+)$') {
            $bss.Radio = $matches[1].Trim()
        }
    }

    # Saved profiles
    $rawProfs = & netsh wlan show profiles 2>&1 | Select-String 'All User Profile\s*:\s*(.+)$'
    $profiles = $rawProfs | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }

    # Roam aggressiveness (registry -- driver-specific, location varies)
    $roam = $null
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue | ForEach-Object {
        $val = (Get-ItemProperty $_.PSPath -Name RoamingAggressiveness -ErrorAction SilentlyContinue).RoamingAggressiveness
        if ($val) { $roam = $val }
    }
}
catch { $errors.Add($_.Exception.Message) }

# 2.4 GHz channel overlap analysis
$twoFour = $bssids | Where-Object { $_.Channel -ge 1 -and $_.Channel -le 14 }
$overlapBuckets = @{}
foreach ($b in $twoFour) {
    $bucket = if ($b.Channel -le 4) {1} elseif ($b.Channel -le 9) {6} else {11}
    $overlapBuckets[$bucket] = (1 + ($overlapBuckets[$bucket]))
}

$weakSignal = $current['Signal'] -replace '%' -as [int]
$problems = New-Object System.Collections.Generic.List[string]
if ($weakSignal -and $weakSignal -lt 50) { $problems.Add("Weak signal: $($current['Signal'])") }
$badRoam = $roam -ne $null -and $roam -lt 2
if ($badRoam) { $problems.Add("Low roam aggressiveness: $roam") }
$crowded = $overlapBuckets.Values | Where-Object { $_ -gt 5 }
if ($crowded) { $problems.Add("Crowded 2.4 GHz channels") }

$status = if ($errors.Count) { 'Failure' } elseif ($problems.Count) { 'Warning' } else { 'Success' }

$result = New-MSPResult `
    -Tool 'Get-WiFiSurvey' `
    -Status $status `
    -Summary "Connected to '$($current['SSID'])' on ch $($current['Channel']) @ $($current['Signal']); $($bssids.Count) BSSIDs visible." `
    -Data @{
        Current           = $current
        VisibleBSSIDs     = $bssids.ToArray() | Sort-Object Signal -Descending
        SavedProfiles     = $profiles
        RoamAggressiveness= $roam
        ChannelOverlap    = $overlapBuckets
        Problems          = $problems.ToArray()
    } `
    -Errors $errors.ToArray() `
    -Metrics @{ VisibleAPs = $bssids.Count; SignalPct = $weakSignal }

[void](Save-MSPResult -Result $result -Subfolder 'Network')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
