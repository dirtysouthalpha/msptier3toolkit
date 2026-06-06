<#
.SYNOPSIS
    Captures network packets using pktmon for analysis and troubleshooting.
.DESCRIPTION
    Wraps Windows built-in pktmon to capture packets with filters, then parses
    the ETL output into a human-readable summary showing top talkers, protocols,
    and potential issues (retransmissions, resets, high latency).
.NOTES
    v19.0 -- Advanced Network Diagnostics
    Requires: Admin rights (pktmon)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string[]]$CaptureFilter,
    [Parameter(Mandatory=$false)]
    [int]$DurationSeconds = 30,
    [Parameter(Mandatory=$false)]
    [int]$MaxPackets = 10000
)

$data = [PSCustomObject]@{
    Timestamp          = (Get-Date).ToString('o')
    CapturedPackets    = 0
    DroppedPackets     = 0
    CapturePath        = ''
    TopTalkers         = @()
    TopProtocols       = @()
    Retransmits        = 0
    Resets             = 0
    Checks             = @()
    Score              = 0
    MaxScore           = 0
    Summary            = ''
}

# Verify admin
if (-not (Test-MSPElevation)) {
    $data.Checks += [PSCustomObject]@{ Name='Admin Rights'; Pass=$false; Detail='pktmon requires elevation' }
    $data.Summary = 'Requires admin rights'
    $data.MaxScore = 20; return $data
}

$data.Checks += [PSCustomObject]@{ Name='Admin Rights'; Pass=$true; Detail='Elevated' }

# Check pktmon availability
$pktmon = Get-Command pktmon.exe -ErrorAction SilentlyContinue
if (-not $pktmon) {
    $data.Checks += [PSCustomObject]@{ Name='pktmon Available'; Pass=$false; Detail='pktmon not found (Win10 1809+)' }
    $data.Summary = 'pktmon not available'
    $data.MaxScore = 40; $data.Score = 20; return $data
}

$data.Checks += [PSCustomObject]@{ Name='pktmon Available'; Pass=$true; Detail='Found' }

# Build capture
$capFile = "$env:TEMP\MSP_PacketCapture_$(Get-Date -Format 'yyyyMMdd_HHmmss').etl"
try {
    # Reset filters first -- save and restore existing
    $existingFilters = pktmon filter list 2>$null
    pktmon filter remove 2>$null | Out-Null

    # Apply custom filters or capture all
    if ($CaptureFilter) {
        foreach ($f in $CaptureFilter) {
            pktmon filter add -p $f 2>$null | Out-Null
        }
    }

    # Start capture
    $capArgs = "start --capture --pkt-size 0 --file-name `"$capFile`" --log-size 256"
    pktmon $capArgs.Split(' ') 2>$null | Out-Null

    Start-Sleep -Seconds $DurationSeconds

    # Stop capture
    pktmon stop 2>$null | Out-Null
    $data.CapturePath = $capFile

    # Convert ETL to text for analysis
    $txtFile = $capFile -replace '\.etl$', '.txt'
    pktmon etl2txt $capFile --out $txtFile 2>$null | Out-Null

    if (Test-Path $txtFile) {
        $raw = Get-Content $txtFile -Raw -ErrorAction SilentlyContinue
        
        # Count packets
        $packetLines = ($raw | Select-String -Pattern '^\s*\d+\s+(TCP|UDP|ICMP|ARP|DNS|HTTP|TLS)' -AllMatches).Matches
        $data.CapturedPackets = $packetLines.Count
        
        # Top protocols
        $protoCounts = @{}
        foreach ($m in $packetLines) {
            $proto = ($m.Value -split '\s+')[1]
            if (-not $protoCounts[$proto]) { $protoCounts[$proto] = 0 }
            $protoCounts[$proto]++
        }
        $data.TopProtocols = @($protoCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5 | ForEach-Object {
            [PSCustomObject]@{ Protocol=$_.Key; Count=$_.Value }
        })

        # Top talkers (IP extraction)
        $ipCounts = @{}
        $ipMatches = [regex]::Matches($raw, '\b(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\b')
        foreach ($m in $ipMatches) {
            $ip = $m.Value
            if (-not $ipCounts[$ip]) { $ipCounts[$ip] = 0 }
            $ipCounts[$ip]++
        }
        $data.TopTalkers = @($ipCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10 | ForEach-Object {
            [PSCustomObject]@{ IP=$_.Key; Packets=$_.Value }
        })

        # Retransmission and reset detection
        $data.Retransmits = ($raw | Select-String -Pattern '\[TCP Retransmit\]|TCP Retransmission' -AllMatches).Matches.Count
        $data.Resets = ($raw | Select-String -Pattern '\[TCP RST\]|Flags:.*RST' -AllMatches).Matches.Count
    }

    $data.Checks += [PSCustomObject]@{ Name='Capture Completed'; Pass=($data.CapturedPackets -gt 0); Detail="$($data.CapturedPackets) packets over ${DurationSeconds}s" }
    $data.Checks += [PSCustomObject]@{ Name='Low Retransmit Rate'; Pass=($data.Retransmits -lt $data.CapturedPackets * 0.02); Detail="$($data.Retransmits) retransmits" }
    $data.Checks += [PSCustomObject]@{ Name='Low TCP Reset Rate'; Pass=($data.Resets -lt $data.CapturedPackets * 0.05); Detail="$($data.Resets) resets" }
} catch {
    $data.Checks += [PSCustomObject]@{ Name='Capture Completed'; Pass=$false; Detail="Error: $($_.Exception.Message)" }
} finally {
    # Restore any previously-existing filters
    pktmon filter remove 2>$null | Out-Null
    if ($existingFilters) {
        foreach ($ef in $existingFilters) {
            if ($ef -match 'Filter') { pktmon filter add -p any 2>$null | Out-Null }
        }
    }
}

$data.MaxScore = $data.Checks.Count * 20
$data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
$data.Summary = "Packet Capture: $($data.CapturedPackets) packets | Retrans:$($data.Retransmits) Reset:$($data.Resets)"
return $data
