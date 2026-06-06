<#
.SYNOPSIS
    One-page client-friendly HTML triage report -- the report you hand to
    the user or attach to the ticket within 60 seconds of touching the box.
.DESCRIPTION
    Rolls up the existing diagnostic scripts into a single HTML page:

      - Hardware summary
      - Uptime + pending-reboot
      - Disk free % per drive (red bar if <15%)
      - Memory utilisation
      - Top 5 processes by CPU + RAM
      - BitLocker per-volume status
      - Defender + signature freshness
      - Pending Windows Updates count
      - Last 24h critical Event Log groups
      - Network: IPs, gateway, DNS
      - Local admins

    Output: self-contained .html with embedded CSS, no external assets --
    can be emailed to the client.
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputPath,
    [switch]$Open,
    [switch]$AsJson
)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$paths = Get-MSPPaths
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$facts = Get-MSPOSFacts -Refresh
$reboot = Test-MSPPendingReboot

# Quick metrics
$topCpu  = Get-Process | Sort-Object CPU -Descending          | Select-Object -First 5 Name,Id,@{n='CPUs';e={[math]::Round($_.CPU,1)}},@{n='MB';e={[math]::Round($_.WorkingSet64/1MB)}}
$topMem  = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 Name,Id,@{n='MB';e={[math]::Round($_.WorkingSet64/1MB)}},@{n='CPUs';e={[math]::Round($_.CPU,1)}}

$av = $null
if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
    try { $av = Get-MpComputerStatus } catch { }
}

$bl = @()
if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
    try { $bl = Get-BitLockerVolume | Select-Object MountPoint,@{n='Protection';e={"$($_.ProtectionStatus)"}},EncryptionPercentage } catch { }
}

$pendingUpdates = 0
try {
    $session = New-Object -ComObject Microsoft.Update.Session
    $pendingUpdates = $session.CreateUpdateSearcher().Search("IsInstalled=0").Updates.Count
} catch { }

$critEvents = @()
try {
    $critEvents = Get-WinEvent -FilterHashtable @{
        LogName='System','Application'; Level=1,2; StartTime=(Get-Date).AddHours(-24)
    } -MaxEvents 200 -ErrorAction SilentlyContinue |
        Group-Object ProviderName,Id | Sort-Object Count -Desc | Select-Object -First 5 Name,Count
} catch { }

$admins = @()
if (Get-Command Get-LocalGroupMember -ErrorAction SilentlyContinue) {
    try { $admins = Get-LocalGroupMember -Group Administrators | Select-Object -ExpandProperty Name } catch { }
}

function Bar([double]$Pct, [string]$GoodIfHigh = 'low') {
    $color = if ($GoodIfHigh -eq 'high') {
        if ($Pct -ge 50) { '#21c186' } elseif ($Pct -ge 20) { '#e8a93b' } else { '#e8505b' }
    } else {
        if ($Pct -le 70) { '#21c186' } elseif ($Pct -le 90) { '#e8a93b' } else { '#e8505b' }
    }
    "<div style='background:#e2e6ef;border-radius:6px;overflow:hidden;height:14px'><div style='width:$([math]::Min(100,[math]::Max(0,$Pct)))%;height:100%;background:$color'></div></div>"
}

$diskRows = $facts.Disks | ForEach-Object {
    $usedPct = if ($_.SizeGB) { 100 - (($_.FreeGB / $_.SizeGB) * 100) } else { 0 }
    @"
<tr><td><b>$($_.Drive)</b></td><td>$($_.SizeGB) GB</td><td>$($_.FreeGB) GB</td>
<td>$([math]::Round($usedPct,1))%</td><td>$(Bar -Pct $usedPct -GoodIfHigh 'low')</td></tr>
"@
} -join ''

$memPct = if ($facts.MemoryGB) {
    $os = Get-CimInstance Win32_OperatingSystem
    100 - (($os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100)
} else { 0 }

$summaryFlags = @()
if ($reboot.PendingReboot)        { $summaryFlags += "<span class='flag bad'>PENDING REBOOT</span>" }
if ($pendingUpdates -gt 5)        { $summaryFlags += "<span class='flag warn'>$pendingUpdates updates pending</span>" }
if ($av -and -not $av.RealTimeProtectionEnabled) { $summaryFlags += "<span class='flag bad'>AV REALTIME OFF</span>" }
if ($av -and $av.AntivirusSignatureAge -gt 7)    { $summaryFlags += "<span class='flag warn'>AV signatures $($av.AntivirusSignatureAge)d old</span>" }
$lowDisk = $facts.Disks | Where-Object PctFree -lt 15
if ($lowDisk) { $summaryFlags += "<span class='flag bad'>LOW DISK: $($lowDisk.Drive -join ', ')</span>" }
$memPctRound = [math]::Round($memPct, 1)
if ($memPctRound -gt 90) { $summaryFlags += "<span class='flag warn'>Memory ${memPctRound}%</span>" }
if (-not $summaryFlags) { $summaryFlags = @("<span class='flag ok'>No critical issues</span>") }

$html = @"
<!doctype html><html><head><meta charset='utf-8'>
<title>Quick Triage - $($facts.ComputerName)</title>
<style>
body{font-family:-apple-system,Segoe UI,Arial,sans-serif;background:#f4f6fb;color:#1f2740;margin:0;padding:24px;}
.wrap{max-width:1000px;margin:0 auto;background:#fff;padding:28px;border-radius:12px;box-shadow:0 2px 8px rgba(0,0,0,.05);}
h1{font-size:24px;margin-bottom:4px;}
h2{font-size:16px;margin:24px 0 8px;border-bottom:1px solid #e2e6ef;padding-bottom:4px;color:#27375f;}
.meta{color:#7a839c;font-size:12px;margin-bottom:14px;}
.flag{display:inline-block;padding:4px 10px;border-radius:12px;font-size:12px;font-weight:600;margin:3px 4px 3px 0;}
.flag.ok{background:#dff7ec;color:#0e7a4c;}.flag.warn{background:#fff2d9;color:#8a5a00;}.flag.bad{background:#ffe1e3;color:#a3232c;}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px;}
.cell{background:#f8f9fc;padding:12px;border-radius:8px;border:1px solid #e2e6ef;}
.cell .l{color:#7a839c;font-size:11px;text-transform:uppercase;letter-spacing:.6px;}
.cell .v{font-size:18px;font-weight:600;margin-top:2px;}
table{width:100%;border-collapse:collapse;font-size:13px;}
th{text-align:left;padding:6px 10px;background:#f0f3fa;color:#27375f;}
td{padding:6px 10px;border-bottom:1px solid #f0f3fa;}
</style></head><body><div class='wrap'>
<h1>Quick Triage - $($facts.ComputerName)</h1>
<div class='meta'>$($facts.OSName) · $($facts.Manufacturer) $($facts.Model) · generated $(Get-Date -Format 'yyyy-MM-dd HH:mm')</div>
<div>$($summaryFlags -join ' ')</div>

<h2>Snapshot</h2>
<div class='grid'>
  <div class='cell'><div class='l'>Uptime</div><div class='v'>$([math]::Round($facts.Uptime.TotalHours,1)) h</div></div>
  <div class='cell'><div class='l'>Memory</div><div class='v'>$memPctRound% used / $($facts.MemoryGB) GB</div></div>
  <div class='cell'><div class='l'>CPU</div><div class='v'>$($facts.CPU)</div></div>
  <div class='cell'><div class='l'>Serial</div><div class='v'>$($facts.Serial)</div></div>
  <div class='cell'><div class='l'>Pending updates</div><div class='v'>$pendingUpdates</div></div>
  <div class='cell'><div class='l'>Pending reboot</div><div class='v'>$($reboot.PendingReboot)</div></div>
</div>

<h2>Disks</h2>
<table><tr><th>Drive</th><th>Size</th><th>Free</th><th>Used %</th><th></th></tr>$diskRows</table>

<h2>Antivirus</h2>
$(if ($av) {
@"
<table>
<tr><th>RealTime</th><td>$($av.RealTimeProtectionEnabled)</td></tr>
<tr><th>Tamper Protection</th><td>$($av.IsTamperProtected)</td></tr>
<tr><th>Signatures last updated</th><td>$($av.AntivirusSignatureLastUpdated) ($($av.AntivirusSignatureAge) days)</td></tr>
<tr><th>Last quick scan</th><td>$($av.QuickScanAge) days ago</td></tr>
</table>
"@
} else { '<p>Defender status unavailable.</p>' })

$(if ($bl.Count) { "<h2>BitLocker</h2>$(($bl | ConvertTo-Html -Fragment) -join '')" })

<h2>Top processes by CPU</h2>
$(($topCpu | ConvertTo-Html -Fragment) -join '')

<h2>Top processes by memory</h2>
$(($topMem | ConvertTo-Html -Fragment) -join '')

<h2>Network</h2>
<table>
<tr><th>IPs</th><td>$($facts.IPAddresses -join ', ')</td></tr>
<tr><th>DNS servers</th><td>$($facts.DNSServers -join ', ')</td></tr>
<tr><th>Domain</th><td>$($facts.Domain)</td></tr>
</table>

$(if ($critEvents.Count) { "<h2>Critical events (24h)</h2>$(($critEvents | ConvertTo-Html -Fragment) -join '')" })

$(if ($admins.Count) { "<h2>Local administrators</h2><ul>$(($admins | ForEach-Object { "<li>$_</li>" }) -join '')</ul>" })

<div class='meta' style='margin-top:24px'>Generated by MSP Tier 3 Toolkit v4.0 · session $(Get-MSPSessionId)</div>
</div></body></html>
"@

if (-not $OutputPath) {
    $OutputPath = Join-Path $paths.Reports "Workstation\Triage_$($facts.ComputerName)_$stamp.html"
    New-Item -ItemType Directory -Path (Split-Path $OutputPath) -Force | Out-Null
}
$html | Set-Content -LiteralPath $OutputPath -Encoding UTF8

if ($Open) { Start-Process $OutputPath }

$result = New-MSPResult `
    -Tool 'Get-QuickTriageReport' `
    -Status 'Success' `
    -Summary "Triage report written to $OutputPath" `
    -Data @{ OutputPath = $OutputPath; Flags = $summaryFlags } `
    -Metrics @{ PendingUpdates = $pendingUpdates; UptimeHours = [math]::Round($facts.Uptime.TotalHours,1); MemPct = $memPctRound }

[void](Save-MSPResult -Result $result -Subfolder 'Workstation')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
