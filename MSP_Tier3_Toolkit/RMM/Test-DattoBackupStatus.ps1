<#
.SYNOPSIS
    Checks Datto backup appliance connectivity, agent status, and backup health.
.DESCRIPTION
    Validates the Datto Windows Agent service, VSS integration, network connectivity
    to the Datto appliance, and last backup job status from local logs.
.NOTES
    v13.0 -- RMM Deep Integration
#>
[CmdletBinding()]
param()

$data = [PSCustomObject]@{
    Timestamp           = (Get-Date).ToString('o')
    AgentInstalled      = $false
    AgentServiceRunning = $false
    AgentVersion        = $null
    ApplianceReachable  = $false
    ApplianceIP         = $null
    VSSHealthy          = $false
    LastBackupDate      = $null
    LastBackupSuccess   = $false
    ProtectedVolumes    = @()
    Checks              = @()
    Score               = 0
    MaxScore            = 0
    Summary             = ''
}

# Check 1: Agent service
$agentSvcs = @('DattoBackupAgent', 'DattoWindowsAgent', 'DWA', 'BackupAgent')
foreach ($sn in $agentSvcs) {
    $svc = Get-Service -Name $sn -ErrorAction SilentlyContinue
    if ($svc) {
        $data.AgentInstalled = $true
        $data.AgentServiceRunning = ($svc.Status -eq 'Running')
        break
    }
}
$data.Checks += [PSCustomObject]@{ Name='Agent Service'; Pass=$data.AgentServiceRunning; Detail=$(if($data.AgentInstalled){"Status: $(if($data.AgentServiceRunning){'Running'}else{'Stopped'})"}else{'Not installed'}) }

# Check 2: Agent version from registry
$dReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Datto\Windows Agent' -ErrorAction SilentlyContinue
if (-not $dReg) { $dReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Datto\Backup Agent' -ErrorAction SilentlyContinue }
if ($dReg) {
    $data.AgentVersion = $dReg.Version
    $data.ApplianceIP = $dReg.ApplianceAddress
}
$data.Checks += [PSCustomObject]@{ Name='Registry Config'; Pass=($null -ne $dReg); Detail=$(if($dReg){"v$($data.AgentVersion) -> $($data.ApplianceIP)"}else{'No config'}) }

# Check 3: Appliance connectivity
if ($data.ApplianceIP) {
    try {
        $ping = Test-Connection -ComputerName $data.ApplianceIP -Count 1 -Quiet -ErrorAction Stop
        $data.ApplianceReachable = $ping
    } catch { $data.ApplianceReachable = $false }
}
$data.Checks += [PSCustomObject]@{ Name='Appliance Reachable'; Pass=$data.ApplianceReachable; Detail=$(if($data.ApplianceReachable){'Ping OK'}else{'Unreachable'}) }

# Check 4: VSS health (critical for Datto)
try {
    $vssWriters = vssadmin list writers 2>$null
    $vssFailed = ($vssWriters | Select-String -Pattern 'State: \[[^1]' -SimpleMatch).Count
    $data.VSSHealthy = ($vssFailed -eq 0 -and $vssWriters.Count -gt 0)
} catch { $data.VSSHealthy = $false }
$data.Checks += [PSCustomObject]@{ Name='VSS Writers Healthy'; Pass=$data.VSSHealthy; Detail=$(if($data.VSSHealthy){'All writers stable'}else{"$vssFailed writer(s) in non-stable state"}) }

# Check 5: Protected volumes
$vols = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 'Fixed' -and $_.FileSystemLabel -ne 'Recovery' }
$data.ProtectedVolumes = @($vols | ForEach-Object { [PSCustomObject]@{ DriveLetter=$_.DriveLetter; SizeGB=[math]::Round($_.Size/1GB,1); FileSystem=$_.FileSystem } })

# Check 6: Last backup (Datto logs)
$logPath = "$env:ProgramData\Datto\Windows Agent\logs"
if (-not (Test-Path $logPath)) { $logPath = "$env:ProgramData\Datto\Backup Agent\logs" }
if (Test-Path $logPath) {
    $latest = Get-ChildItem $logPath -Filter '*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) {
        $content = Get-Content $latest.FullName -Tail 50 -ErrorAction SilentlyContinue
        $success = ($content | Select-String -Pattern 'backup.*(?:complete|success|finished)' -SimpleMatch).Count
        $data.LastBackupDate = $latest.LastWriteTime
        $data.LastBackupSuccess = ($success -gt 0)
        $daysAgo = [math]::Round(((Get-Date) - $latest.LastWriteTime).TotalDays, 1)
        $data.Checks += [PSCustomObject]@{ Name='Recent Backup'; Pass=($daysAgo -lt 2); Detail="Last: ${daysAgo}d ago -- $(if($data.LastBackupSuccess){'Success'}else{'Check logs'})" }
    } else {
        $data.Checks += [PSCustomObject]@{ Name='Recent Backup'; Pass=$false; Detail='No logs found' }
    }
} else {
    $data.Checks += [PSCustomObject]@{ Name='Recent Backup'; Pass=$false; Detail='Log directory missing' }
}

$data.MaxScore = $data.Checks.Count * 20
$data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
$data.Summary = "Datto: $($data.Score)/$($data.MaxScore) -- Agent: $(if($data.AgentServiceRunning){'OK'}else{'FAIL'}) | Appliance: $(if($data.ApplianceReachable){'OK'}else{'N/A'}) | Backup: $(if($data.LastBackupSuccess){'OK'}else{'CHECK'})"

return $data
