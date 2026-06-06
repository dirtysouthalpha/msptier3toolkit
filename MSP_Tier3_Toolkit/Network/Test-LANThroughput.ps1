<#
.SYNOPSIS
    Tests LAN throughput between two endpoints using iperf or built-in tools.
.DESCRIPTION
    Measures TCP/UDP throughput, jitter, and packet loss between the local
    machine and a target server. Falls back to measuring file transfer speed
    if iperf is not available.
.NOTES
    v19.0 -- Advanced Network Diagnostics
    iperf3 is preferred but not required.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$TargetHost,
    [Parameter(Mandatory=$false)]
    [int]$Port = 5201,
    [Parameter(Mandatory=$false)]
    [int]$DurationSeconds = 10,
    [Parameter(Mandatory=$false)]
    [ValidateSet('TCP','UDP','Auto')]
    [string]$Protocol = 'Auto'
)

$data = [PSCustomObject]@{
    Timestamp         = (Get-Date).ToString('o')
    TargetHost        = $TargetHost
    IperfAvailable    = $false
    Protocol          = $Protocol
    TCPThroughputMbps = 0
    UDPThroughputMbps = 0
    JitterMs          = 0
    PacketLossPct     = 0
    LatencyMs         = 0
    Checks            = @()
    Score             = 0
    MaxScore          = 0
    Summary           = ''
}

# Check latency first
try {
    $ping = Test-Connection -ComputerName $TargetHost -Count 5 -ErrorAction Stop
    $data.LatencyMs = [math]::Round(($ping | Measure-Object -Property ResponseTime -Average).Average, 1)
    $data.Checks += [PSCustomObject]@{ Name='Target Reachable'; Pass=$true; Detail="$($data.LatencyMs)ms avg latency" }
} catch {
    $data.Checks += [PSCustomObject]@{ Name='Target Reachable'; Pass=$false; Detail='Unreachable' }
    $data.MaxScore = 20; $data.Score = 0
    $data.Summary = 'Target unreachable'
    return $data
}

# Check iperf3
$iperf = Get-Command iperf3 -ErrorAction SilentlyContinue
if (-not $iperf) { $iperf = Get-Command iperf -ErrorAction SilentlyContinue }
$data.IperfAvailable = ($null -ne $iperf)

$data.Checks += [PSCustomObject]@{ Name='iperf Available'; Pass=$data.IperfAvailable; Detail=$(if($data.IperfAvailable){'Found'}else{'Not installed -- using fallback'}) }

if ($data.IperfAvailable -and $Protocol -in @('TCP','Auto')) {
    try {
        $result = & $iperf -c $TargetHost -p $Port -t $DurationSeconds -J 2>$null
        if ($result) {
            $parsed = $result | ConvertFrom-Json
            $data.TCPThroughputMbps = [math]::Round($parsed.end.sum_received.bits_per_second / 1e6, 1)
            $data.Checks += [PSCustomObject]@{ Name='TCP Throughput'; Pass=($data.TCPThroughputMbps -gt 10); Detail="$($data.TCPThroughputMbps) Mbps" }
        }
    } catch {
        # Try text output parsing
        try {
            $text = & $iperf -c $TargetHost -p $Port -t $DurationSeconds 2>&1
            if ($text -match '(\d+\.?\d*)\s*Mbits/sec') {
                $data.TCPThroughputMbps = [double]$Matches[1]
                $data.Checks += [PSCustomObject]@{ Name='TCP Throughput'; Pass=($data.TCPThroughputMbps -gt 10); Detail="$($data.TCPThroughputMbps) Mbps" }
            }
        } catch { }
    }
}

# UDP test
if ($data.IperfAvailable -and $Protocol -in @('UDP','Auto')) {
    try {
        $text = & $iperf -c $TargetHost -p $Port -t $DurationSeconds -u -b 100M 2>&1
        if ($text -match '(\d+\.?\d*)\s*Mbits/sec') { $data.UDPThroughputMbps = [double]$Matches[1] }
        if ($text -match '(\d+\.?\d*)\s*ms.*jitter') { $data.JitterMs = [double]$Matches[1] }
        if ($text -match '(\d+\.?\d*)%.*loss') { $data.PacketLossPct = [double]$Matches[1] }
        $data.Checks += [PSCustomObject]@{ Name='Packet Loss < 1%'; Pass=($data.PacketLossPct -lt 1); Detail="$($data.PacketLossPct)% loss" }
    } catch { }
}

# Fallback: file transfer test
if (-not $data.IperfAvailable -or $data.TCPThroughputMbps -eq 0) {
    $testFile = "$env:TEMP\MSP_ThroughputTest.dat"
    try {
        $bytes = [byte[]]::new(50MB)
        (New-Object Random).NextBytes($bytes)
        [IO.File]::WriteAllBytes($testFile, $bytes)

        # Try SMB copy to target
        $targetPath = "\\$TargetHost\C$\TEMP\MSP_ThroughputTest.dat"
        $sw = [Diagnostics.Stopwatch]::StartNew()
        Copy-Item $testFile $targetPath -Force -ErrorAction Stop
        $sw.Stop()
        $fileMB = 50
        $data.TCPThroughputMbps = [math]::Round($fileMB * 8 / $sw.Elapsed.TotalSeconds, 1)
        Remove-Item $targetPath -ErrorAction SilentlyContinue
        $data.Checks += [PSCustomObject]@{ Name='TCP Throughput (SMB)'; Pass=($data.TCPThroughputMbps -gt 10); Detail="$($data.TCPThroughputMbps) Mbps (50MB file copy)" }
    } catch {
        $data.Checks += [PSCustomObject]@{ Name='TCP Throughput (SMB)'; Pass=$false; Detail="SMB fallback failed: $_" }
    } finally {
        Remove-Item $testFile -ErrorAction SilentlyContinue
    }
}

$data.MaxScore = $data.Checks.Count * 20
$data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
$data.Summary = "Throughput: TCP $($data.TCPThroughputMbps) Mbps | Latency: $($data.LatencyMs)ms | Loss: $($data.PacketLossPct)%"
return $data
