<#
.SYNOPSIS
    Boot Time Performance Analyzer
.DESCRIPTION
    Comprehensive boot time analysis tool that:
    - Analyzes recent boot and shutdown events
    - Calculates boot duration and performance trends
    - Identifies slow startup services
    - Tracks system uptime statistics
    - Provides performance recommendations
.PARAMETER BootCount
    Number of recent boot events to analyze (default: 10)
.PARAMETER ShowServices
    Display slow-starting services
.NOTES
    Author: MSP Toolkit Team
    Version: 2.0
    Requires: Standard user (Event log access)
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateRange(1, 50)]
    [int]$BootCount = 10,

    [switch]$ShowServices,
    [switch]$ExportReport
)

$ErrorActionPreference = 'Continue'

# Initialize logging
$logPath = "$env:TEMP\BootTimeAnalyzer_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"

    $color = switch ($Level) {
        'SUCCESS' { 'Green' }
        'ERROR'   { 'Red' }
        'WARNING' { 'Yellow' }
        default   { 'White' }
    }

    $icon = switch ($Level) {
        'SUCCESS' { '[+]' }
        'ERROR'   { '[X]' }
        'WARNING' { '[!]' }
        default   { '[i]' }
    }

    Write-Host "$icon " -NoNewline -ForegroundColor $color
    Write-Host $Message

    Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
}

function Get-BootEvents {
    <#
    .SYNOPSIS
        Gets boot and shutdown events from the System event log
    #>
    param([int]$Count = 10)

    try {
        # Event ID 6005 = Event Log Started (boot)
        # Event ID 6006 = Event Log Stopped (shutdown)
        # Event ID 6009 = System boot (alternative)

        $bootEvents = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            ID = @(6005, 6009)
        } -MaxEvents $Count -ErrorAction Stop

        $shutdownEvents = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            ID = 6006
        } -MaxEvents $Count -ErrorAction SilentlyContinue

        return @{
            Boots = $bootEvents
            Shutdowns = $shutdownEvents
        }
    }
    catch {
        Write-Log "Error reading event log: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

function Get-BootDuration {
    <#
    .SYNOPSIS
        Calculates boot duration using performance counters
    #>

    try {
        $bootTime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
        $currentTime = Get-Date

        $uptime = $currentTime - $bootTime

        return @{
            BootTime = $bootTime
            Uptime = $uptime
            UptimeDays = [math]::Round($uptime.TotalDays, 2)
            UptimeHours = [math]::Round($uptime.TotalHours, 2)
        }
    }
    catch {
        Write-Log "Error calculating boot duration: $($_.Exception.Message)" -Level WARNING
        return $null
    }
}

function Get-SlowServices {
    <#
    .SYNOPSIS
        Identifies slow-starting services
    #>

    try {
        $services = Get-Service | Where-Object {
            $_.StartType -eq 'Automatic' -and $_.Status -eq 'Running'
        }

        $serviceInfo = @()

        foreach ($service in $services) {
            try {
                $process = Get-Process -Id (Get-CimInstance Win32_Service |
                    Where-Object { $_.Name -eq $service.Name }).ProcessId -ErrorAction SilentlyContinue

                if ($process) {
                    $startTime = $process.StartTime
                    $bootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime

                    if ($startTime) {
                        $startDelay = ($startTime - $bootTime).TotalSeconds

                        $serviceInfo += [PSCustomObject]@{
                            Name = $service.DisplayName
                            ServiceName = $service.Name
                            StartDelaySeconds = [math]::Round($startDelay, 2)
                            Status = $service.Status
                        }
                    }
                }
            }
            catch {
                # Skip services we can't query
            }
        }

        return $serviceInfo | Sort-Object StartDelaySeconds -Descending | Select-Object -First 10
    }
    catch {
        Write-Log "Error analyzing services: $($_.Exception.Message)" -Level WARNING
        return @()
    }
}

# Main execution
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host " Boot Time Performance Analyzer" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

Write-Log "Starting boot time analysis..." -Level INFO
Write-Host ""

# Get current system uptime
Write-Log "Analyzing current system uptime..." -Level INFO
$bootInfo = Get-BootDuration

if ($bootInfo) {
    Write-Host "  Current System Status:" -ForegroundColor Cyan
    Write-Host "  " + ("=" * 78) -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Last Boot:    " -NoNewline -ForegroundColor Gray
    Write-Host $bootInfo.BootTime.ToString('yyyy-MM-dd HH:mm:ss') -ForegroundColor White
    Write-Host "  Current Time: " -NoNewline -ForegroundColor Gray
    Write-Host (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -ForegroundColor White
    Write-Host "  Uptime:       " -NoNewline -ForegroundColor Gray

    $days = [math]::Floor($bootInfo.Uptime.TotalDays)
    $hours = $bootInfo.Uptime.Hours
    $minutes = $bootInfo.Uptime.Minutes

    $uptimeString = ""
    if ($days -gt 0) { $uptimeString += "$days days, " }
    if ($hours -gt 0 -or $days -gt 0) { $uptimeString += "$hours hours, " }
    $uptimeString += "$minutes minutes"

    $uptimeColor = if ($bootInfo.UptimeDays -gt 30) { "Red" }
                   elseif ($bootInfo.UptimeDays -gt 7) { "Yellow" }
                   else { "Green" }

    Write-Host $uptimeString -ForegroundColor $uptimeColor

    if ($bootInfo.UptimeDays -gt 30) {
        Write-Host ""
        Write-Host "  [!] " -NoNewline -ForegroundColor Red
        Write-Host "System has been running for over 30 days. Consider rebooting." -ForegroundColor Yellow
    }

    Write-Host ""
}

# Get boot history
Write-Log "Retrieving boot history..." -Level INFO
$events = Get-BootEvents -Count $BootCount

if ($events -and $events.Boots) {
    Write-Host "  Boot History (Last $($events.Boots.Count) boots):" -ForegroundColor Cyan
    Write-Host "  " + ("=" * 78) -ForegroundColor DarkGray
    Write-Host ""

    $bootHistory = @()

    for ($i = 0; $i -lt $events.Boots.Count; $i++) {
        $boot = $events.Boots[$i]
        $shutdown = $events.Shutdowns | Where-Object {
            $_.TimeCreated -lt $boot.TimeCreated
        } | Select-Object -First 1

        $downtime = if ($shutdown) {
            ($boot.TimeCreated - $shutdown.TimeCreated).TotalMinutes
        } else {
            $null
        }

        $uptimeDuration = if ($i -lt ($events.Boots.Count - 1)) {
            ($events.Boots[$i + 1].TimeCreated - $boot.TimeCreated).TotalHours
        } else {
            $null
        }

        $bootHistory += [PSCustomObject]@{
            BootNumber = $i + 1
            BootTime = $boot.TimeCreated
            ShutdownTime = if ($shutdown) { $shutdown.TimeCreated } else { "N/A" }
            DowntimeMinutes = if ($downtime) { [math]::Round($downtime, 1) } else { "N/A" }
            UptimeHours = if ($uptimeDuration) { [math]::Round($uptimeDuration, 1) } else { "Current" }
        }

        # Display
        Write-Host "  Boot #$($i + 1):" -ForegroundColor White
        Write-Host "    Time:     " -NoNewline -ForegroundColor Gray
        Write-Host $boot.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss') -ForegroundColor White

        if ($shutdown) {
            Write-Host "    Shutdown: " -NoNewline -ForegroundColor Gray
            Write-Host $shutdown.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss') -ForegroundColor White
            Write-Host "    Downtime: " -NoNewline -ForegroundColor Gray
            Write-Host "$([math]::Round($downtime, 1)) minutes" -ForegroundColor Cyan
        }

        if ($uptimeDuration) {
            Write-Host "    Uptime:   " -NoNewline -ForegroundColor Gray
            $uptimeColor = if ($uptimeDuration -gt 168) { "Red" }  # > 7 days
                          elseif ($uptimeDuration -gt 24) { "Yellow" }  # > 1 day
                          else { "Green" }
            Write-Host "$([math]::Round($uptimeDuration, 1)) hours" -ForegroundColor $uptimeColor
        }

        Write-Host ""
    }

    # Calculate statistics
    $validDowntimes = $bootHistory | Where-Object { $_.DowntimeMinutes -ne "N/A" }
    $validUptimes = $bootHistory | Where-Object { $_.UptimeHours -ne "Current" }

    if ($validDowntimes.Count -gt 0) {
        $avgDowntime = ($validDowntimes | Measure-Object -Property DowntimeMinutes -Average).Average
        $maxDowntime = ($validDowntimes | Measure-Object -Property DowntimeMinutes -Maximum).Maximum
        $minDowntime = ($validDowntimes | Measure-Object -Property DowntimeMinutes -Minimum).Minimum

        Write-Host "  Boot Statistics:" -ForegroundColor Cyan
        Write-Host "  " + ("─" * 78) -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Average Downtime: " -NoNewline -ForegroundColor Gray
        Write-Host "$([math]::Round($avgDowntime, 1)) minutes" -ForegroundColor White
        Write-Host "  Min Downtime:     " -NoNewline -ForegroundColor Gray
        Write-Host "$([math]::Round($minDowntime, 1)) minutes" -ForegroundColor Green
        Write-Host "  Max Downtime:     " -NoNewline -ForegroundColor Gray
        Write-Host "$([math]::Round($maxDowntime, 1)) minutes" -ForegroundColor Yellow

        if ($validUptimes.Count -gt 0) {
            $avgUptime = ($validUptimes | Measure-Object -Property UptimeHours -Average).Average
            Write-Host "  Average Uptime:   " -NoNewline -ForegroundColor Gray
            Write-Host "$([math]::Round($avgUptime, 1)) hours" -ForegroundColor White
        }

        Write-Host ""
    }
}
else {
    Write-Log "Could not retrieve boot history from event log" -Level WARNING
}

# Analyze slow services
if ($ShowServices) {
    Write-Host "  " + ("=" * 78) -ForegroundColor DarkGray
    Write-Host ""
    Write-Log "Analyzing service startup times..." -Level INFO
    $slowServices = Get-SlowServices

    if ($slowServices.Count -gt 0) {
        Write-Host "  Top 10 Slowest Starting Services:" -ForegroundColor Cyan
        Write-Host "  " + ("─" * 78) -ForegroundColor DarkGray
        Write-Host ""

        foreach ($service in $slowServices) {
            $delayColor = if ($service.StartDelaySeconds -gt 60) { "Red" }
                         elseif ($service.StartDelaySeconds -gt 30) { "Yellow" }
                         else { "Green" }

            Write-Host "  $($service.Name)" -ForegroundColor White
            Write-Host "    Delay: " -NoNewline -ForegroundColor Gray
            Write-Host "$($service.StartDelaySeconds) seconds after boot" -ForegroundColor $delayColor
        }

        Write-Host ""
    }
    else {
        Write-Log "No service timing data available" -Level INFO
    }
}

# Summary and recommendations
Write-Host ("=" * 80) -ForegroundColor Green
Write-Host " Analysis Complete" -ForegroundColor Green
Write-Host ("=" * 80) -ForegroundColor Green
Write-Host ""

Write-Host "  Recommendations:" -ForegroundColor Yellow
Write-Host ""

if ($bootInfo -and $bootInfo.UptimeDays -gt 30) {
    Write-Host "  [!] Reboot recommended - System has been running for $($bootInfo.UptimeDays) days" -ForegroundColor Red
}
elseif ($bootInfo -and $bootInfo.UptimeDays -gt 7) {
    Write-Host "  [!] Consider rebooting soon - System has been running for $($bootInfo.UptimeDays) days" -ForegroundColor Yellow
}
else {
    Write-Host "  [+] System uptime is healthy" -ForegroundColor Green
}

Write-Host ""
Write-Host "  Tip: Run with -ShowServices to see slow-starting services" -ForegroundColor Gray
Write-Host "  Log file: $logPath" -ForegroundColor Cyan
Write-Host ""

Write-Log "Boot time analysis completed" -Level SUCCESS
