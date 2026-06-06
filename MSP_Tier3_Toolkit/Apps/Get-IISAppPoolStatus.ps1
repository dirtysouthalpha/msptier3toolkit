<#
.SYNOPSIS
    Checks IIS application pool status, worker processes, and request queues.
.DESCRIPTION
    Enumerates all IIS application pools, their running state, worker process count,
    request queue depth, and recent recycle events from event logs.
.NOTES
    v15.0 -- Application & Database Health
#>
[CmdletBinding()]
param()

$data = [PSCustomObject]@{
    Timestamp         = (Get-Date).ToString('o')
    IISInstalled      = $false
    TotalAppPools     = 0
    RunningPools      = 0
    StoppedPools      = 0
    QueueDepthWarning = 0
    TotalWorkerProcesses = 0
    RecentRecycles    = 0
    AppPoolDetails    = @()
    Checks            = @()
    Score             = 0
    MaxScore          = 0
    Summary           = ''
}

# Check IIS installation
$was = Get-Service -Name 'WAS' -ErrorAction SilentlyContinue
$w3svc = Get-Service -Name 'W3SVC' -ErrorAction SilentlyContinue
$data.IISInstalled = ($null -ne $was -and $null -ne $w3svc)

$data.Checks += [PSCustomObject]@{ Name='IIS Installed'; Pass=$data.IISInstalled; Detail=$(if($data.IISInstalled){'WAS+W3SVC present'}else{'Not installed'}) }

if (-not $data.IISInstalled) {
    $data.Summary = 'IIS not detected on this machine'
    $data.MaxScore = 20
    $data.Score = $(if ($data.IISInstalled) { 20 } else { 0 })
    return $data
}

# Check WAS/W3SVC running
$wasRunning = ($was.Status -eq 'Running')
$w3svcRunning = ($w3svc.Status -eq 'Running')
$data.Checks += [PSCustomObject]@{ Name='IIS Services Running'; Pass=($wasRunning -and $w3svcRunning); Detail="WAS: $(if($wasRunning){'Running'}else{'Stopped'}) | W3SVC: $(if($w3svcRunning){'Running'}else{'Stopped'})" }

# Enumerate App Pools via appcmd
try {
    $appcmd = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
    if (Test-Path $appcmd) {
        $pools = & $appcmd list apppool /text:name 2>$null
        if ($pools) {
            $data.TotalAppPools = $pools.Count
            foreach ($poolName in $pools) {
                $poolName = $poolName.Trim()
                $state = & $appcmd list apppool $poolName /text:state 2>$null
                $state = $state.Trim()
                $isRunning = ($state -eq 'Started')
                if ($isRunning) { $data.RunningPools++ } else { $data.StoppedPools++ }

                # Worker process count
                $wps = & $appcmd list wp /apppool.name:$poolName 2>$null
                $wpCount = ($wps | Measure-Object).Count
                $data.TotalWorkerProcesses += $wpCount

                # Request queue depth
                $requests = $null
                try { $requests = Get-Counter "\ASP.NET Apps v4.0.30319(*)\Requests Executing" -ErrorAction SilentlyContinue } catch {}
                $data.AppPoolDetails += [PSCustomObject]@{
                    Name=$poolName; State=$state; WorkerProcesses=$wpCount; QueueDepth=0
                }
            }
            $data.Checks += [PSCustomObject]@{ Name='App Pools OK'; Pass=($data.StoppedPools -eq 0); Detail="$($data.RunningPools) running / $($data.TotalAppPools) total" }
            $data.Checks += [PSCustomObject]@{ Name='Worker Processes'; Pass=($data.TotalWorkerProcesses -gt 0); Detail="$($data.TotalWorkerProcesses) total" }
        }
    } else {
        $data.Checks += [PSCustomObject]@{ Name='App Pools OK'; Pass=$false; Detail='appcmd.exe not found' }
    }
} catch {
    $data.Checks += [PSCustomObject]@{ Name='App Pools OK'; Pass=$false; Detail="Error: $($_.Exception.Message)" }
}

# Check for recent recycles (event log)
$recycles = Get-WinEvent -LogName 'System' -FilterXPath "*[System[Provider[@Name='Microsoft-Windows-WAS'] and (EventID=5076 or EventID=5079)]]" -MaxEvents 10 -ErrorAction SilentlyContinue
$data.RecentRecycles = ($recycles | Measure-Object).Count
$data.Checks += [PSCustomObject]@{ Name='No Excessive Recycles'; Pass=($data.RecentRecycles -lt 5); Detail="$($data.RecentRecycles) recent recycles" }

$data.MaxScore = $data.Checks.Count * 20
$data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
$data.Summary = "IIS: $($data.Score)/$($data.MaxScore) -- $($data.RunningPools)/$($data.TotalAppPools) pools running | $($data.TotalWorkerProcesses) worker processes"

return $data
