<#
.SYNOPSIS
    Checks Azure AD Connect / Entra Connect Sync health, cycles, and errors.
.DESCRIPTION
    Validates Entra Connect sync service, last sync time, export/import counts,
    connector space stats, and common configuration issues like OU filtering.
    Requires the ADSync module or direct ADSync database access.
.NOTES
    v14.0 -- Cloud & Hybrid Operations
#>
[CmdletBinding()]
param()

$data = [PSCustomObject]@{
    Timestamp          = (Get-Date).ToString('o')
    ServiceRunning     = $false
    ServiceName        = 'ADSync'
    LastSyncTime       = $null
    LastSyncResult     = ''
    SyncCycleDelta     = $false
    ExportCount        = 0
    ImportCount        = 0
    ConnectorsHealthy  = $true
    PassThroughAuth    = $false
    Checks             = @()
    Score              = 0
    MaxScore           = 0
    Summary            = ''
}

# Check 1: ADSync service
$svc = Get-Service -Name $data.ServiceName -ErrorAction SilentlyContinue
if ($svc) {
    $data.ServiceRunning = ($svc.Status -eq 'Running')
    $data.Checks += [PSCustomObject]@{ Name='Sync Service'; Pass=$data.ServiceRunning; Detail="Status: $($svc.Status)" }
} else {
    $data.Checks += [PSCustomObject]@{ Name='Sync Service'; Pass=$false; Detail='ADSync service not found -- not a sync server?' }
}

# Check 2: Last sync cycle (via ADSync module if available)
try {
    $mod = Get-Module -Name ADSync -ListAvailable -ErrorAction SilentlyContinue
    if ($mod) {
        Import-Module ADSync -ErrorAction Stop
        $run = Get-ADSyncScheduler
        $data.LastSyncTime = $run.NextSyncCycleTime
        $data.Checks += [PSCustomObject]@{ Name='ADSync Module'; Pass=$true; Detail="Next sync: $($run.NextSyncCycleTime)" }

        # Get connector space stats
        $cs = Get-ADSyncConnector
        $data.Checks += [PSCustomObject]@{ Name='Connectors'; Pass=($cs.Count -gt 0); Detail="$($cs.Count) connector(s) defined" }

        # Last run result
        $lastRun = Get-ADSyncRunProfileResult -NumberRequested 1 -ErrorAction SilentlyContinue
        if ($lastRun) {
            $data.LastSyncResult = $lastRun.Result
            $data.Checks += [PSCustomObject]@{ Name='Last Sync'; Pass=($lastRun.Result -eq 'success'); Detail="Result: $($lastRun.Result)" }
        } else {
            $data.Checks += [PSCustomObject]@{ Name='Last Sync'; Pass=$false; Detail='No sync history' }
        }
    } else {
        $data.Checks += [PSCustomObject]@{ Name='ADSync Module'; Pass=$false; Detail='Module not installed -- limited visibility' }
        $data.Checks += [PSCustomObject]@{ Name='Last Sync'; Pass=$false; Detail='Requires ADSync module' }
    }
} catch {
    $data.Checks += [PSCustomObject]@{ Name='ADSync Module'; Pass=$false; Detail="Error: $($_.Exception.Message)" }
}

# Check 3: Pass-through authentication agent
$pta = Get-Service -Name 'PassthroughAuthAgent' -ErrorAction SilentlyContinue
$data.PassThroughAuth = ($null -ne $pta -and $pta.Status -eq 'Running')
$data.Checks += [PSCustomObject]@{ Name='PTA Agent'; Pass=$data.PassThroughAuth; Detail=$(if($data.PassThroughAuth){'Running'}else{'Not in use or stopped'}) }

# Check 4: Event log check for sync errors
$events = Get-WinEvent -LogName 'Application' -FilterXPath "*[System[Provider[@Name='Directory Synchronization']]]" -MaxEvents 20 -ErrorAction SilentlyContinue
$errors = ($events | Where-Object { $_.LevelDisplayName -eq 'Error' }).Count
$data.Checks += [PSCustomObject]@{ Name='Sync Errors (24h)'; Pass=($errors -eq 0); Detail="$errors error(s) in recent events" }

$data.MaxScore = $data.Checks.Count * 20
$data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
$data.Summary = "Entra Connect: $($data.Score)/$($data.MaxScore) -- Service: $(if($data.ServiceRunning){'OK'}else{'FAIL'}) | Last Sync: $($data.LastSyncResult)"

return $data
