<#
.SYNOPSIS
    Checks NinjaOne RMM agent health, connectivity, and last check-in status.
.DESCRIPTION
    Validates the NinjaOne agent service, tray app, registry configuration,
    endpoint connectivity to the NinjaOne platform, and recent activity.
    Produces a scored health report (0-100).
.NOTES
    v13.0 -- RMM Deep Integration
#>
[CmdletBinding()]
param()

$data = [PSCustomObject]@{
    Timestamp          = (Get-Date).ToString('o')
    ServiceRunning     = $false
    ServiceName        = 'NinjaRMMAgent'
    TrayAppRunning     = $false
    RegistryConfigured = $false
    InstallationId     = $null
    LastCheckIn        = $null
    EndpointConnectivity = $false
    Version            = $null
    Checks             = @()
    Score              = 0
    MaxScore           = 0
    Summary            = ''
}

# Check 1: Service status
$svc = Get-Service -Name $data.ServiceName -ErrorAction SilentlyContinue
if ($svc) {
    $data.ServiceRunning = ($svc.Status -eq 'Running')
    $data.Checks += [PSCustomObject]@{ Name='Service Running'; Pass=$data.ServiceRunning; Detail="Status: $($svc.Status)" }
} else {
    $data.Checks += [PSCustomObject]@{ Name='Service Running'; Pass=$false; Detail='Service not found' }
}

# Check 2: Tray application
$tray = Get-Process -Name 'NinjaRMMAgent' -ErrorAction SilentlyContinue
$data.TrayAppRunning = ($null -ne $tray)
$data.Checks += [PSCustomObject]@{ Name='Tray App Running'; Pass=$data.TrayAppRunning; Detail=$(if($tray){'Running'}else{'Not running'}) }

# Check 3: Registry configuration
$regPaths = @(
    'HKLM:\SOFTWARE\NinjaRMM',
    'HKLM:\SOFTWARE\NinjaOne'
)
foreach ($rp in $regPaths) {
    try {
        $reg = Get-ItemProperty -Path $rp -ErrorAction Stop
        $data.RegistryConfigured = $true
        $data.InstallationId = $reg.InstallationId
        $data.Version = $reg.Version
        break
    } catch { continue }
}
$data.Checks += [PSCustomObject]@{ Name='Registry Configured'; Pass=$data.RegistryConfigured; Detail=$(if($data.RegistryConfigured){"ID: $($data.InstallationId)"}else{'No config found'}) }

# Check 4: Endpoint connectivity
$endpoints = @('app.ninjarmm.com', 'api.ninjarmm.com')
$connected = $false
foreach ($ep in $endpoints) {
    try {
        $test = Test-NetConnection -ComputerName $ep -Port 443 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if ($test.TcpTestSucceeded) { $connected = $true; break }
    } catch { }
}
$data.EndpointConnectivity = $connected
$data.Checks += [PSCustomObject]@{ Name='Endpoint Connectivity'; Pass=$connected; Detail=$(if($connected){'NinjaOne reachable'}else{'No connectivity'}) }

# Check 5: Last check-in (from local logs)
$logDir = "$env:ProgramData\NinjaRMMAgent\logs"
if (Test-Path $logDir) {
    $latestLog = Get-ChildItem $logDir -Filter '*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestLog) {
        $data.LastCheckIn = $latestLog.LastWriteTime
        $hoursAgo = [math]::Round(((Get-Date) - $latestLog.LastWriteTime).TotalHours, 1)
        $data.Checks += [PSCustomObject]@{ Name='Recent Activity'; Pass=($hoursAgo -lt 2); Detail="Last log: ${hoursAgo}h ago" }
    } else {
        $data.Checks += [PSCustomObject]@{ Name='Recent Activity'; Pass=$false; Detail='No log files found' }
    }
} else {
    $data.Checks += [PSCustomObject]@{ Name='Recent Activity'; Pass=$false; Detail='Log directory missing' }
}

# Calculate score
$data.MaxScore = $data.Checks.Count * 20
$data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
$data.Summary = "NinjaOne: $($data.Score)/$($data.MaxScore) -- Service: $(if($data.ServiceRunning){'OK'}else{'DOWN'}) | Connection: $(if($data.EndpointConnectivity){'OK'}else{'FAIL'}) | Version: $($data.Version)"

return $data
