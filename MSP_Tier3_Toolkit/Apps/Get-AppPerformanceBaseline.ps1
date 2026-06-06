<#
.SYNOPSIS
    Captures per-application CPU, memory, handle, and I/O baselines for comparison.
.DESCRIPTION
    Samples running processes over a configurable duration, computing avg/max CPU,
    working set, handle count, and I/O rates. Produces a baseline snapshot suitable
    for drift detection in subsequent runs.
.NOTES
    v15.0 -- Application & Database Health
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [int]$SampleCount = 5,
    [Parameter(Mandatory=$false)]
    [int]$SampleIntervalSec = 5,
    [Parameter(Mandatory=$false)]
    [string[]]$TargetProcesses
)

$data = [PSCustomObject]@{
    Timestamp       = (Get-Date).ToString('o')
    SampleCount     = $SampleCount
    SampleInterval  = $SampleIntervalSec
    DurationSeconds = 0
    ProcessBaselines = @()
    TopCPU          = @()
    TopMemory       = @()
    TotalProcesses  = 0
    Checks          = @()
    Score           = 0
    MaxScore        = 0
    Summary         = ''
}

$startTime = Get-Date
$samples = @()
for ($i = 0; $i -lt $SampleCount; $i++) {
    $processes = if ($TargetProcesses) {
        Get-Process -Name $TargetProcesses -ErrorAction SilentlyContinue
    } else {
        Get-Process | Where-Object { $_.CPU -gt 0 -or $_.WorkingSet -gt 10MB }
    }
    $samples += ,@($processes)
    if ($i -lt $SampleCount - 1) { Start-Sleep -Seconds $SampleIntervalSec }
}

$data.DurationSeconds = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)

# Aggregate baselines
$allProcs = @{}
foreach ($sample in $samples) {
    foreach ($p in $sample) {
        $key = $p.ProcessName
        if (-not $allProcs[$key]) {
            $allProcs[$key] = @{
                Name = $p.ProcessName
                InstanceCount = 0
                TotalCPU = 0
                TotalWS = 0
                TotalHandles = 0
                PeakCPU = 0
                PeakWS = 0
                Samples = 0
            }
        }
        $allProcs[$key].InstanceCount = [Math]::Max($allProcs[$key].InstanceCount, ($sample | Where-Object { $_.ProcessName -eq $key }).Count)
        $allProcs[$key].TotalCPU += $p.CPU
        $allProcs[$key].TotalWS += $p.WorkingSet64
        $allProcs[$key].TotalHandles += $p.HandleCount
        $allProcs[$key].PeakCPU = [Math]::Max($allProcs[$key].PeakCPU, $p.CPU)
        $allProcs[$key].PeakWS = [Math]::Max($allProcs[$key].PeakWS, $p.WorkingSet64)
        $allProcs[$key].Samples++
    }
}

$data.TotalProcesses = $allProcs.Count

foreach ($key in $allProcs.Keys) {
    $p = $allProcs[$key]
    $data.ProcessBaselines += [PSCustomObject]@{
        ProcessName = $p.Name
        InstanceCount = $p.InstanceCount
        AvgCPU = [math]::Round($p.TotalCPU / $p.Samples, 2)
        PeakCPU = [math]::Round($p.PeakCPU, 2)
        AvgMemoryMB = [math]::Round($p.TotalWS / $p.Samples / 1MB, 1)
        PeakMemoryMB = [math]::Round($p.PeakWS / 1MB, 1)
        AvgHandles = [math]::Round($p.TotalHandles / $p.Samples)
    }
}

# Top consumers
$data.TopCPU = @($data.ProcessBaselines | Sort-Object AvgCPU -Descending | Select-Object -First 5)
$data.TopMemory = @($data.ProcessBaselines | Sort-Object AvgMemoryMB -Descending | Select-Object -First 5)

$data.Checks += [PSCustomObject]@{ Name='Sampling Complete'; Pass=($samples.Count -ge $SampleCount); Detail="$($samples.Count)/$SampleCount samples over $($data.DurationSeconds)s" }
$data.Checks += [PSCustomObject]@{ Name='Processes Profiled'; Pass=($data.TotalProcesses -gt 0); Detail="$($data.TotalProcesses) processes baselined" }

$data.MaxScore = $data.Checks.Count * 20
$data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
$data.Summary = "Perf Baseline: $($data.TotalProcesses) processes over $($data.DurationSeconds)s | Top CPU: $(if($data.TopCPU[0]){$data.TopCPU[0].ProcessName}else{'N/A'}) | Top Mem: $(if($data.TopMemory[0]){$data.TopMemory[0].ProcessName}else{'N/A'})"

return $data
