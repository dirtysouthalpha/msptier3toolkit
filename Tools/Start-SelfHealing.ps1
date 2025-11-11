<#
.SYNOPSIS
    MSP Toolkit - Self-Healing Automation Engine
.DESCRIPTION
    Monitors system health and automatically remediates common issues
.NOTES
    Designed to run as a scheduled task or background service
#>

[CmdletBinding()]
param(
    [int]$IntervalMinutes = 5,
    [switch]$RunOnce,
    [switch]$EnableNotifications
)

# Import modules
$CorePath = "$PSScriptRoot\..\Core"
Import-Module "$CorePath\MSPToolkit.Config.psm1" -Force
Import-Module "$CorePath\MSPToolkit.Logging.psm1" -Force

Initialize-MSPLogging -ScriptName "SelfHealing"
$config = Get-MSPConfig

# Check if auto-healing is enabled
if (-not $config.monitoring.autoHealEnabled) {
    Write-MSPLog "Self-healing is disabled in configuration" -Level WARNING
    Write-MSPLog "Enable it by setting monitoring.autoHealEnabled = true in config.json" -Level INFO
    return
}

Write-MSPLog "═══ Self-Healing Automation Engine Started ═══" -Level HEADER
Write-MSPLog "Monitoring interval: $IntervalMinutes minutes" -Level INFO

# Healing actions tracking
$Script:HealingLog = Join-Path $config.paths.logs "SelfHealing_$(Get-Date -Format 'yyyyMMdd').log"
$Script:ActionsToday = 0

function Send-MSPNotification {
    param(
        [string]$Title,
        [string]$Message,
        [string]$Severity = "Info"
    )

    if (-not $EnableNotifications) { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $notification = @"
[$timestamp] [$Severity] $Title
$Message
"@

    Add-Content -Path $Script:HealingLog -Value $notification

    # Teams webhook if configured
    if ($config.notifications.teamsWebhookUrl) {
        try {
            $body = @{
                title = "🤖 MSP Toolkit Self-Healing"
                text = "**$Title**`n`n$Message"
                themeColor = switch ($Severity) {
                    "Success" { "00FF00" }
                    "Warning" { "FFA500" }
                    "Error" { "FF0000" }
                    default { "0078D4" }
                }
            } | ConvertTo-Json

            Invoke-RestMethod -Uri $config.notifications.teamsWebhookUrl -Method Post -Body $body -ContentType 'application/json' | Out-Null
        }
        catch {
            Write-MSPLog "Failed to send Teams notification: $_" -Level WARNING
        }
    }
}

function Test-PrintSpooler {
    Write-MSPLog "Checking Print Spooler service..." -Level INFO

    try {
        $spooler = Get-Service -Name Spooler

        if ($spooler.Status -ne 'Running') {
            Write-MSPLog "Print Spooler is stopped! Attempting to start..." -Level WARNING

            # Clear stuck jobs
            Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "C:\Windows\System32\spool\PRINTERS\*" -Force -ErrorAction SilentlyContinue
            Start-Service -Name Spooler

            $Script:ActionsToday++
            Write-MSPLog "✓ Print Spooler restarted successfully" -Level SUCCESS

            Send-MSPNotification -Title "Print Spooler Fixed" -Message "The Print Spooler service was stopped and has been restarted." -Severity "Success"

            return $true
        } else {
            Write-MSPLog "Print Spooler is running normally" -Level INFO
            return $false
        }
    }
    catch {
        Write-MSPLog "Failed to check/fix Print Spooler: $_" -Level ERROR
        return $false
    }
}

function Test-DiskSpace {
    Write-MSPLog "Checking disk space..." -Level INFO

    try {
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3"

        foreach ($disk in $disks) {
            $freePercent = [Math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)
            $threshold = $config.monitoring.diskSpaceThresholdPercent

            if ($freePercent -lt $threshold) {
                Write-MSPLog "⚠ Low disk space on $($disk.DeviceID): $freePercent% free" -Level WARNING

                # Auto cleanup
                Write-MSPLog "Initiating automatic cleanup..." -Level INFO

                # Clear temp files
                $tempPaths = @(
                    "$env:TEMP\*",
                    "C:\Windows\Temp\*",
                    "C:\Windows\SoftwareDistribution\Download\*"
                )

                $freedSpace = 0
                foreach ($path in $tempPaths) {
                    try {
                        $items = Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
                            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) }

                        foreach ($item in $items) {
                            $size = if ($item.PSIsContainer) { 0 } else { $item.Length }
                            Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
                            $freedSpace += $size
                        }
                    }
                    catch {
                        # Continue on error
                    }
                }

                $freedMB = [Math]::Round($freedSpace / 1MB, 2)

                $Script:ActionsToday++
                Write-MSPLog "✓ Freed $freedMB MB of disk space" -Level SUCCESS

                Send-MSPNotification -Title "Disk Cleanup Performed" -Message "Low disk space detected on $($disk.DeviceID). Automatic cleanup freed $freedMB MB." -Severity "Warning"

                return $true
            } else {
                Write-MSPLog "Disk space OK on $($disk.DeviceID): $freePercent% free" -Level INFO
            }
        }

        return $false
    }
    catch {
        Write-MSPLog "Failed to check disk space: $_" -Level ERROR
        return $false
    }
}

function Test-WindowsUpdate {
    Write-MSPLog "Checking Windows Update service..." -Level INFO

    try {
        $wuauserv = Get-Service -Name wuauserv

        if ($wuauserv.Status -ne 'Running') {
            Write-MSPLog "Windows Update service is stopped! Attempting to start..." -Level WARNING

            Start-Service -Name wuauserv

            $Script:ActionsToday++
            Write-MSPLog "✓ Windows Update service started" -Level SUCCESS

            Send-MSPNotification -Title "Windows Update Service Fixed" -Message "The Windows Update service was stopped and has been restarted." -Severity "Success"

            return $true
        } else {
            Write-MSPLog "Windows Update service is running normally" -Level INFO
            return $false
        }
    }
    catch {
        Write-MSPLog "Failed to check Windows Update service: $_" -Level ERROR
        return $false
    }
}

function Test-MemoryUsage {
    Write-MSPLog "Checking memory usage..." -Level INFO

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $usedPercent = [Math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 1)
        $threshold = $config.monitoring.memoryThresholdPercent

        if ($usedPercent -gt $threshold) {
            Write-MSPLog "⚠ High memory usage: $usedPercent%" -Level WARNING

            # Find memory hogs
            $topProcesses = Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 5

            $processList = $topProcesses | ForEach-Object {
                "$($_.Name) ($(([Math]::Round($_.WorkingSet / 1MB, 0))) MB)"
            }

            Send-MSPNotification -Title "High Memory Usage Alert" -Message "Memory usage is at $usedPercent%. Top processes: $($processList -join ', ')" -Severity "Warning"

            Write-MSPLog "Top memory consumers: $($processList -join ', ')" -Level INFO

            return $false
        } else {
            Write-MSPLog "Memory usage OK: $usedPercent%" -Level INFO
            return $false
        }
    }
    catch {
        Write-MSPLog "Failed to check memory usage: $_" -Level ERROR
        return $false
    }
}

function Test-NetworkDrives {
    Write-MSPLog "Checking network drives..." -Level INFO

    try {
        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.DisplayRoot -like "\\*" }

        $reconnected = 0
        foreach ($drive in $drives) {
            if (-not (Test-Path "$($drive.Name):")) {
                Write-MSPLog "⚠ Network drive $($drive.Name): is disconnected" -Level WARNING

                # Try to reconnect
                try {
                    Remove-PSDrive -Name $drive.Name -Force -ErrorAction SilentlyContinue
                    New-PSDrive -Name $drive.Name -PSProvider FileSystem -Root $drive.DisplayRoot -Persist -ErrorAction Stop | Out-Null

                    $reconnected++
                    Write-MSPLog "✓ Reconnected drive $($drive.Name):" -Level SUCCESS
                }
                catch {
                    Write-MSPLog "Failed to reconnect drive $($drive.Name): $_" -Level ERROR
                }
            }
        }

        if ($reconnected -gt 0) {
            $Script:ActionsToday++
            Send-MSPNotification -Title "Network Drives Reconnected" -Message "Reconnected $reconnected network drive(s)." -Severity "Success"
            return $true
        } else {
            Write-MSPLog "All network drives connected" -Level INFO
            return $false
        }
    }
    catch {
        Write-MSPLog "Failed to check network drives: $_" -Level ERROR
        return $false
    }
}

function Invoke-HealthCheck {
    Write-MSPLog "═══ Running Health Checks ═══" -Level HEADER

    $checks = @(
        @{ Name = "Print Spooler"; Function = { Test-PrintSpooler } },
        @{ Name = "Disk Space"; Function = { Test-DiskSpace } },
        @{ Name = "Windows Update"; Function = { Test-WindowsUpdate } },
        @{ Name = "Memory Usage"; Function = { Test-MemoryUsage } },
        @{ Name = "Network Drives"; Function = { Test-NetworkDrives } }
    )

    $actionsTaken = 0

    foreach ($check in $checks) {
        Write-Host ""
        $result = & $check.Function

        if ($result) {
            $actionsTaken++
        }
    }

    Write-Host ""
    Write-MSPLog "Health check completed. Actions taken: $actionsTaken" -Level INFO

    if ($actionsTaken -gt 0) {
        Write-MSPLog "Total healing actions today: $Script:ActionsToday" -Level INFO
    }
}

# Main monitoring loop
do {
    try {
        Invoke-HealthCheck

        if ($RunOnce) {
            Write-MSPLog "Single run completed. Exiting..." -Level INFO
            break
        }

        Write-MSPLog "Next check in $IntervalMinutes minutes..." -Level INFO
        Start-Sleep -Seconds ($IntervalMinutes * 60)
    }
    catch {
        Write-MSPLog "Error in monitoring loop: $_" -Level ERROR

        if ($RunOnce) {
            break
        }

        Start-Sleep -Seconds 60
    }
} while ($true)

Write-MSPLog "═══ Self-Healing Engine Stopped ═══" -Level HEADER
