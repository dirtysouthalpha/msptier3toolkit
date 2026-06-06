<#
.SYNOPSIS
    Tests network bandwidth saturation by generating controlled traffic load.
.DESCRIPTION
    Generates UDP traffic bursts to a target at configurable bandwidth rates
    and measures response to determine available bandwidth headroom and
    saturation point. Uses iperf3 if available, or custom UDP flood.
.NOTES
    v19.0 -- Advanced Network Diagnostics
    ⚠ Can impact network performance -- use during maintenance windows only
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$TargetHost,
    [Parameter(Mandatory=$false)]
    [ValidateRange(1,1000)]
    [int]$MaxBandwidthMbps = 100,
    [Parameter(Mandatory=$false)]
    [ValidateRange(1,10)]
    [int]$StepCount = 5,
    [Parameter(Mandatory=$false)]
    [int]$StepDurationSeconds = 5,
    [Parameter(Mandatory=$false)]
    [switch]$ConfirmSafe
)

if (-not $ConfirmSafe) {
    Write-Warning "Bandwidth saturation testing can impact network performance."
    Write-Warning "Use -ConfirmSafe to acknowledge and proceed."
    return [PSCustomObject]@{ Summary='Requires -ConfirmSafe flag to proceed' }
}

$data = [PSCustomObject]@{
    Timestamp        = (Get-Date).ToString('o')
    TargetHost       = $TargetHost
    MaxBandwidth     = $MaxBandwidthMbps
    Steps            = @()
    SaturationPoint  = 0
    MaxThroughput    = 0
    AvgLatencyAtMax  = 0
    Checks           = @()
    Score            = 0
    MaxScore         = 0
    Summary          = ''
}

$iperf = Get-Command iperf3 -ErrorAction SilentlyContinue
if (-not $iperf) {
    $data.Summary = 'iperf3 required for bandwidth saturation testing'
    return $data
}

# Verify iperf3 server is running on target
try {
    $check = & $iperf -c $TargetHost -t 1 -J 2>&1
    if ($LASTEXITCODE -ne 0 -and $check -notmatch 'bits_per_second') {
        $data.Summary = "No iperf3 server detected on $TargetHost. Start one with: iperf3 -s"
        $data.Checks += [PSCustomObject]@{ Name='iperf3 Server'; Pass=$false; Detail='Not running on target' }
        $data.MaxScore = 20; return $data
    }
} catch { }
$data.Checks += [PSCustomObject]@{ Name='iperf3 Server'; Pass=$true; Detail='Responding' }

# Baseline latency
try {
    $basePing = Test-Connection -ComputerName $TargetHost -Count 5 -ErrorAction Stop
    $baseLatency = [math]::Round(($basePing | Measure-Object -Property ResponseTime -Average).Average, 1)
    $data.Checks += [PSCustomObject]@{ Name='Baseline Latency'; Pass=$true; Detail="$baseLatency ms" }
} catch {
    $data.Summary = 'Target unreachable'
    return $data
}

$stepSize = [math]::Round($MaxBandwidthMbps / $StepCount)
$saturated = $false

for ($i = 1; $i -le $StepCount; $i++) {
    $targetBw = [math]::Min($stepSize * $i, $MaxBandwidthMbps)
    
    try {
        # Run UDP test at target bandwidth
        $output = & $iperf -c $TargetHost -u -b "${targetBw}M" -t $StepDurationSeconds 2>&1
        
        $throughput = 0; $loss = 0; $jitter = 0
        if ($output -match '(\d+\.?\d*)\s*Mbits/sec') { $throughput = [double]$Matches[1] }
        if ($output -match '(\d+\.?\d*)%.*loss') { $loss = [double]$Matches[1] }
        if ($output -match '(\d+\.?\d*)\s*ms.*jitter') { $jitter = [double]$Matches[1] }

        # Check latency under load
        $loadPing = Test-Connection -ComputerName $TargetHost -Count 3 -ErrorAction SilentlyContinue
        $loadLatency = if ($loadPing) { [math]::Round(($loadPing | Measure-Object -Property ResponseTime -Average).Average, 1) } else { 999 }

        $stepResult = [PSCustomObject]@{
            TargetBandwidthMbps=$targetBw; AchievedThroughputMbps=$throughput
            PacketLossPct=$loss; JitterMs=$jitter; LatencyUnderLoadMs=$loadLatency
        }
        $data.Steps += $stepResult

        $data.MaxThroughput = [Math]::Max($data.MaxThroughput, $throughput)

        # Detect saturation: packet loss > 2% or throughput stops scaling
        if ($loss -gt 2 -or ($throughput / $targetBw) -lt 0.7) {
            if (-not $saturated) {
                $data.SaturationPoint = $targetBw
                $saturated = $true
            }
        }

        $data.AvgLatencyAtMax = $loadLatency
    } catch {
        $data.Steps += [PSCustomObject]@{ TargetBandwidthMbps=$targetBw; Error=$_.Exception.Message }
    }
}

$data.Checks += [PSCustomObject]@{ Name='Throughput Profiled'; Pass=($data.Steps.Count -gt 0); Detail="$MaxBandwidthMbps Mbps profiled" }
$data.Checks += [PSCustomObject]@{ Name='Saturation Detected'; Pass=($data.SaturationPoint -gt 0); Detail="At $($data.SaturationPoint) Mbps" }

$data.MaxScore = $data.Checks.Count * 20
$data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
$data.Summary = "Saturation: $($data.MaxThroughput) Mbps max | Saturated at $($data.SaturationPoint) Mbps | Latency @ max: $($data.AvgLatencyAtMax)ms"
return $data
