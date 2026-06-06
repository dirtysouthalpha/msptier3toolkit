<#
.SYNOPSIS
    Reports Teams call quality metrics, network readiness, and media performance.
.DESCRIPTION
    Checks local network readiness for Teams (ports, latency, jitter), tests
    connectivity to Teams media endpoints, and reports CQD data if Graph is available.
.NOTES
    v14.0 -- Cloud & Hybrid Operations
    Requires: MSPToolkit.Graph module loaded (optional for CQD data)
#>
[CmdletBinding()]
param()

$data = [PSCustomObject]@{
    Timestamp           = (Get-Date).ToString('o')
    NetworkReady        = $false
    PacketsPerSecond    = 0
    AvgLatencyMs        = 0
    AvgJitterMs         = 0
    MediaEndpointsPass  = 0
    MediaEndpointsTotal = 0
    CQDDataAvailable    = $false
    Checks              = @()
    Score               = 0
    MaxScore            = 0
    Summary             = ''
}

# Check 1: Essential Teams ports
$teamsPorts = @(
    @{Port=443; Proto='TCP'},
    @{Port=80; Proto='TCP'},
    @{Port=3478; Proto='UDP'},
    @{Port=3479; Proto='UDP'},
    @{Port=3480; Proto='UDP'},
    @{Port=3481; Proto='UDP'}
)
$portPass = 0
foreach ($tp in $teamsPorts) {
    $listening = netstat -an | Select-String -Pattern ":$($tp.Port)\s" -SimpleMatch
    if ($listening) { $portPass++ }
}
$data.Checks += [PSCustomObject]@{ Name='Teams Ports Open'; Pass=($portPass -ge 2); Detail="$portPass/$($teamsPorts.Count) essential ports listening" }

# Check 2: Connectivity to Teams media endpoints
$mediaEndpoint = 'worldaz.tr.teams.microsoft.com'
try {
    $test = Test-NetConnection -ComputerName $mediaEndpoint -Port 443 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    $data.NetworkReady = $test.TcpTestSucceeded
    $data.Checks += [PSCustomObject]@{ Name='Media Endpoint'; Pass=$data.NetworkReady; Detail="$(if($data.NetworkReady){'Reachable'}else{'Blocked'})" }
} catch {
    $data.Checks += [PSCustomObject]@{ Name='Media Endpoint'; Pass=$false; Detail="Test failed: $_" }
}

# Check 3: Latency to Teams
try {
    $ping = Test-Connection -ComputerName 'teams.microsoft.com' -Count 3 -ErrorAction SilentlyContinue
    if ($ping) {
        $data.AvgLatencyMs = [math]::Round(($ping | Measure-Object -Property ResponseTime -Average).Average, 1)
        $data.Checks += [PSCustomObject]@{ Name='Latency < 100ms'; Pass=($data.AvgLatencyMs -lt 100); Detail="$($data.AvgLatencyMs)ms avg" }
    } else {
        $data.Checks += [PSCustomObject]@{ Name='Latency < 100ms'; Pass=$false; Detail='Could not ping' }
    }
} catch {
    $data.Checks += [PSCustomObject]@{ Name='Latency < 100ms'; Pass=$false; Detail='Ping blocked' }
}

# Check 4: Network performance counters (packets/sec)
try {
    $nic = (Get-Counter '\Network Interface(*)\Packets/sec' -ErrorAction SilentlyContinue).CounterSamples
    $data.PacketsPerSecond = [math]::Round(($nic | Measure-Object -Property CookedValue -Sum).Sum)
    $data.Checks += [PSCustomObject]@{ Name='Network Load'; Pass=($data.PacketsPerSecond -lt 50000); Detail="$($data.PacketsPerSecond) pkts/sec" }
} catch {
    $data.Checks += [PSCustomObject]@{ Name='Network Load'; Pass=$false; Detail='Counters unavailable' }
}

# Check 5: Try CQD from Graph
try {
    $cqd = Invoke-MSPGraph -Resource 'communications/callRecords?$top=5' -ErrorAction SilentlyContinue
    $data.CQDDataAvailable = ($null -ne $cqd.value)
    $data.Checks += [PSCustomObject]@{ Name='CQD Data'; Pass=$data.CQDDataAvailable; Detail=$(if($data.CQDDataAvailable){'Available'}else{'No access'}) }
} catch {
    $data.Checks += [PSCustomObject]@{ Name='CQD Data'; Pass=$false; Detail='Graph callRecords requires Teams license' }
}

$data.MaxScore = $data.Checks.Count * 20
$data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
$data.Summary = "Teams: $($data.Score)/$($data.MaxScore) -- Latency: $($data.AvgLatencyMs)ms | Media: $(if($data.NetworkReady){'OK'}else{'FAIL'}) | CQD: $(if($data.CQDDataAvailable){'OK'}else{'N/A'})"

return $data
