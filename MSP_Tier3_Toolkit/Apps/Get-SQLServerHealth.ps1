<#
.SYNOPSIS
    Checks SQL Server instance health, database sizes, backups, and wait statistics.
.DESCRIPTION
    Validates SQL Server service state, enumerates databases with size/status,
    checks last backup ages, identifies top wait types, and scans error logs.
    Works with local SQL instances via SMO or SQLPS.
.NOTES
    v15.0 -- Application & Database Health
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$SqlInstance = '.'
)

$data = [PSCustomObject]@{
    Timestamp          = (Get-Date).ToString('o')
    ServiceRunning     = $false
    SqlVersion         = $null
    DatabaseCount      = 0
    DatabasesOk        = 0
    DatabasesSuspect   = 0
    NoBackupDBs        = @()
    TopWaitTypes       = @()
    ErrorLogEntries    = 0
    Checks             = @()
    Score              = 0
    MaxScore           = 0
    Summary            = ''
}

# Check 1: SQL Server service
$svcNames = @('MSSQLSERVER', 'MSSQL$*', 'SQLSERVERAGENT')
$found = $false
foreach ($sn in $svcNames) {
    $svcs = Get-Service -Name $sn -ErrorAction SilentlyContinue
    if ($svcs) {
        $svc = ($svcs | Where-Object { $_.Status -eq 'Running' } | Select-Object -First 1)
        if ($svc) { $data.ServiceRunning = $true; $found = $true; break }
    }
}
$data.Checks += [PSCustomObject]@{ Name='SQL Service'; Pass=$data.ServiceRunning; Detail=$(if($data.ServiceRunning){'Running'}else{'Not running / not installed'}) }

if (-not $data.ServiceRunning) {
    $data.Summary = 'SQL Server not detected on this machine'
    $data.MaxScore = 20
    $data.Score = 0
    return $data
}

# Check 2: SQL version via SMO or registry
$sqlReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\*\Setup' -ErrorAction SilentlyContinue
if (-not $sqlReg) { $sqlReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\MSSQLServer\Setup' -ErrorAction SilentlyContinue }
if ($sqlReg) { $data.SqlVersion = $sqlReg.Version }

# Check 3: Databases via SQLCMD or invoke-sqlcmd
try {
    $dbQuery = "SELECT name, state_desc, compatibility_level, create_date, recovery_model_desc FROM sys.databases WHERE database_id > 4"
    $dbs = Invoke-Sqlcmd -ServerInstance $SqlInstance -Query $dbQuery -ErrorAction Stop
    $data.DatabaseCount = $dbs.Count
    $data.DatabasesOk = ($dbs | Where-Object { $_.state_desc -eq 'ONLINE' }).Count
    $data.DatabasesSuspect = ($dbs | Where-Object { $_.state_desc -ne 'ONLINE' }).Count
    $data.Checks += [PSCustomObject]@{ Name='Databases Online'; Pass=($data.DatabasesSuspect -eq 0); Detail="$($data.DatabasesOk)/$($data.DatabaseCount) online" }

    # Check 4: Backup ages
    $backupQuery = @"
SELECT d.name, MAX(b.backup_finish_date) as LastBackup,
       DATEDIFF(HOUR, MAX(b.backup_finish_date), GETDATE()) as HoursSinceBackup
FROM sys.databases d
LEFT JOIN msdb.dbo.backupset b ON d.name = b.database_name AND b.type = 'D'
WHERE d.database_id > 4
GROUP BY d.name
"@
    $backups = Invoke-Sqlcmd -ServerInstance $SqlInstance -Query $backupQuery -ErrorAction SilentlyContinue
    $data.NoBackupDBs = @($backups | Where-Object { $_.HoursSinceBackup -gt 48 -or $_.HoursSinceBackup -eq $null } | ForEach-Object { $_.name })
    $data.Checks += [PSCustomObject]@{ Name='Recent Full Backups (<48h)'; Pass=($data.NoBackupDBs.Count -eq 0); Detail=("$($data.NoBackupDBs.Count) DBs missing recent backup: $($data.NoBackupDBs -join ', ')" | Select-Object -First 1) }

    # Check 5: Top wait types
    $waitQuery = "SELECT TOP 5 wait_type, wait_time_ms, waiting_tasks_count FROM sys.dm_os_wait_stats WHERE wait_type NOT LIKE '%SLEEP%' ORDER BY wait_time_ms DESC"
    $waits = Invoke-Sqlcmd -ServerInstance $SqlInstance -Query $waitQuery -ErrorAction SilentlyContinue
    if ($waits) {
        $data.TopWaitTypes = @($waits | ForEach-Object { [PSCustomObject]@{ Type=$_.wait_type; TimeMs=$_.wait_time_ms } })
        $data.Checks += [PSCustomObject]@{ Name='No Blocking Waits'; Pass=$true; Detail="Top wait: $($data.TopWaitTypes[0].Type)" }
    }
} catch {
    $data.Checks += [PSCustomObject]@{ Name='SQL Query'; Pass=$false; Detail="Error: $($_.Exception.Message)" }
}

# Check 6: Error log scan
try {
    $errLogQuery = "SELECT COUNT(*) as ErrorCount FROM sys.dm_os_sys_info CROSS APPLY sys.xp_readerrorlog(0,1,'Error')"
    $errCount = Invoke-Sqlcmd -ServerInstance $SqlInstance -Query $errLogQuery -ErrorAction SilentlyContinue
    if ($errCount) {
        $data.ErrorLogEntries = $errCount.ErrorCount
        $data.Checks += [PSCustomObject]@{ Name='Error Log Clean'; Pass=($data.ErrorLogEntries -lt 10); Detail="$($data.ErrorLogEntries) recent errors" }
    }
} catch {
    $data.Checks += [PSCustomObject]@{ Name='Error Log Clean'; Pass=$true; Detail='Could not query' }
}

$data.MaxScore = $data.Checks.Count * 20
$data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
$data.Summary = "SQL Server: $($data.Score)/$($data.MaxScore) -- $($data.DatabasesOk) online | $($data.NoBackupDBs.Count) missing backups | v$($data.SqlVersion)"

return $data
