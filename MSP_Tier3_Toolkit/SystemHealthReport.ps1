<#
.SYNOPSIS
    Comprehensive System Health Report Generator
.DESCRIPTION
    Generates a detailed health and inventory report including:
    - System hardware and OS information
    - Disk space analysis with warnings
    - Memory utilization
    - Network connectivity status
    - Windows Update status
    - Recent critical errors from event logs
    - Service health checks
    - Performance metrics
.PARAMETER OutputPath
    Custom path for the output file (default: Desktop)
.PARAMETER Format
    Report format: Text, HTML, or Both (default: Text)
.PARAMETER IncludeErrors
    Include recent system errors from event log
.PARAMETER DaysBack
    Number of days to analyze for errors (default: 7)
.PARAMETER OpenReport
    Automatically open the report after generation
.NOTES
    Author: MSP Toolkit Team
    Version: 2.0
    Requires: Standard user
#>

[CmdletBinding()]
param(
    [string]$OutputPath = "$env:USERPROFILE\Desktop\SystemHealthReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt",
    [ValidateSet('Text', 'HTML', 'Both')]
    [string]$Format = 'Text',
    [switch]$IncludeErrors,
    [int]$DaysBack = 7,
    [switch]$OpenReport
)

$ErrorActionPreference = 'Continue'

# Initialize
$script:WarningCount = 0
$script:ErrorCount = 0
$script:HealthScore = 100

function Write-StatusMessage {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $color = switch ($Level) {
        'SUCCESS' { 'Green' }
        'ERROR'   { 'Red' }
        'WARNING' { 'Yellow' }
        default   { 'Cyan' }
    }

    $icon = switch ($Level) {
        'SUCCESS' { '[+]' }
        'ERROR'   { '[X]' }
        'WARNING' { '[!]' }
        default   { '[i]' }
    }

    Write-Host "$icon " -NoNewline -ForegroundColor $color
    Write-Host $Message
}

function Get-SystemHealth {
    <#
    .SYNOPSIS
        Collects comprehensive system health information
    #>

    $health = @{}

    try {
        # Basic system info
        Write-StatusMessage "Collecting system information..." -Level INFO
        $health.ComputerName = $env:COMPUTERNAME
        $health.UserName = $env:USERNAME
        $health.OS = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $health.CS = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $health.CPU = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
        $health.BIOS = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue

        # Memory information
        $health.TotalRAM = [math]::Round($health.OS.TotalVisibleMemorySize / 1MB, 2)
        $health.FreeRAM = [math]::Round($health.OS.FreePhysicalMemory / 1MB, 2)
        $health.UsedRAMPercent = [math]::Round((($health.TotalRAM - $health.FreeRAM) / $health.TotalRAM) * 100, 1)

        # Disk information
        Write-StatusMessage "Analyzing disk space..." -Level INFO
        $health.Disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop | ForEach-Object {
            $freeGB = [math]::Round($_.FreeSpace / 1GB, 2)
            $totalGB = [math]::Round($_.Size / 1GB, 2)
            $usedPercent = if ($totalGB -gt 0) { [math]::Round((($totalGB - $freeGB) / $totalGB) * 100, 1) } else { 0 }

            $status = if ($usedPercent -gt 90) {
                $script:ErrorCount++
                $script:HealthScore -= 10
                'CRITICAL'
            } elseif ($usedPercent -gt 80) {
                $script:WarningCount++
                $script:HealthScore -= 5
                'WARNING'
            } else {
                'GOOD'
            }

            [PSCustomObject]@{
                Drive = $_.DeviceID
                Label = $_.VolumeName
                TotalGB = $totalGB
                FreeGB = $freeGB
                UsedPercent = $usedPercent
                Status = $status
            }
        }

        # Network adapters
        Write-StatusMessage "Checking network connectivity..." -Level INFO
        $health.NetworkAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                Status = $_.Status
                LinkSpeed = $_.LinkSpeed
                MacAddress = $_.MacAddress
            }
        }

        # Internet connectivity test
        $health.InternetConnected = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue
        if (-not $health.InternetConnected) {
            $script:WarningCount++
            $script:HealthScore -= 5
        }

        # Windows Update status
        Write-StatusMessage "Checking Windows Update status..." -Level INFO
        try {
            $updateSession = New-Object -ComObject Microsoft.Update.Session
            $updateSearcher = $updateSession.CreateUpdateSearcher()
            $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Software'")
            $health.PendingUpdates = $searchResult.Updates.Count

            if ($health.PendingUpdates -gt 10) {
                $script:WarningCount++
                $script:HealthScore -= 3
            }
        } catch {
            $health.PendingUpdates = "Unable to check"
            Write-StatusMessage "Could not check Windows Update status" -Level WARNING
        }

        # Critical services check
        Write-StatusMessage "Checking critical services..." -Level INFO
        $criticalServices = @('wuauserv', 'BITS', 'CryptSvc', 'TrustedInstaller', 'EventLog', 'Spooler')
        $health.Services = @()

        foreach ($serviceName in $criticalServices) {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service) {
                $status = if ($service.Status -eq 'Running' -or $service.StartType -eq 'Disabled') { 'OK' } else { 'ISSUE' }
                if ($status -eq 'ISSUE') {
                    $script:WarningCount++
                    $script:HealthScore -= 2
                }

                $health.Services += [PSCustomObject]@{
                    Name = $service.DisplayName
                    Status = $service.Status
                    StartType = $service.StartType
                    HealthStatus = $status
                }
            }
        }

        # Recent errors from event log
        if ($IncludeErrors) {
            Write-StatusMessage "Analyzing recent system errors..." -Level INFO
            try {
                $health.RecentErrors = Get-WinEvent -FilterHashtable @{
                    LogName = 'System'
                    Level = 2  # Error
                    StartTime = (Get-Date).AddDays(-$DaysBack)
                } -MaxEvents 10 -ErrorAction SilentlyContinue

                if ($health.RecentErrors.Count -gt 5) {
                    $script:WarningCount++
                    $script:HealthScore -= 5
                }
            } catch {
                $health.RecentErrors = @()
            }
        }

        # System uptime
        $uptime = (Get-Date) - $health.OS.LastBootUpTime
        $health.UptimeDays = [math]::Round($uptime.TotalDays, 2)

        if ($health.UptimeDays -gt 30) {
            $script:WarningCount++
            $script:HealthScore -= 3
        }

        # Final health score
        $health.HealthScore = [math]::Max(0, $script:HealthScore)
        $health.WarningCount = $script:WarningCount
        $health.ErrorCount = $script:ErrorCount

        Write-StatusMessage "System health analysis complete" -Level SUCCESS

        return $health
    }
    catch {
        Write-StatusMessage "Error collecting system information: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

function Format-TextReport {
    param([hashtable]$Health)

    $report = @"
================================================================================
                    SYSTEM HEALTH REPORT
================================================================================
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Computer: $($Health.ComputerName)
User: $($Health.UserName)

================================================================================
OVERALL HEALTH SCORE: $($Health.HealthScore)/100
================================================================================
Warnings: $($Health.WarningCount)
Errors: $($Health.ErrorCount)

Status: $(if ($Health.HealthScore -ge 90) { "EXCELLENT" }
         elseif ($Health.HealthScore -ge 75) { "GOOD" }
         elseif ($Health.HealthScore -ge 60) { "FAIR" }
         else { "POOR - ATTENTION REQUIRED" })

================================================================================
SYSTEM INFORMATION
================================================================================
Operating System: $($Health.OS.Caption) $($Health.OS.Version)
Build Number: $($Health.OS.BuildNumber)
Architecture: $($Health.OS.OSArchitecture)
Manufacturer: $($Health.CS.Manufacturer)
Model: $($Health.CS.Model)
$(if ($Health.BIOS) { "Serial Number: $($Health.BIOS.SerialNumber)" } else { "" })

Last Boot Time: $($Health.OS.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss'))
System Uptime: $($Health.UptimeDays) days$(if ($Health.UptimeDays -gt 30) { " [!] RECOMMEND REBOOT" } else { "" })

================================================================================
PROCESSOR
================================================================================
CPU: $($Health.CPU.Name)
Cores: $($Health.CPU.NumberOfCores) cores / $($Health.CPU.NumberOfLogicalProcessors) threads
Max Clock Speed: $($Health.CPU.MaxClockSpeed) MHz

================================================================================
MEMORY
================================================================================
Total RAM: $($Health.TotalRAM) GB
Free RAM: $($Health.FreeRAM) GB
Used: $($Health.UsedRAMPercent)%$(if ($Health.UsedRAMPercent -gt 90) { " [!] HIGH MEMORY USAGE" } else { "" })

================================================================================
DISK SPACE
================================================================================
"@

    foreach ($disk in $Health.Disks) {
        $statusIndicator = switch ($disk.Status) {
            'CRITICAL' { '[X] CRITICAL' }
            'WARNING'  { '[!] WARNING' }
            default    { '[+] GOOD' }
        }

        $report += @"

Drive $($disk.Drive) - $($disk.Label)
  Total: $($disk.TotalGB) GB
  Free: $($disk.FreeGB) GB
  Used: $($disk.UsedPercent)% $statusIndicator
"@
    }

    $report += @"


================================================================================
NETWORK
================================================================================
Internet Connectivity: $(if ($Health.InternetConnected) { "[+] Connected" } else { "[X] NOT CONNECTED" })

Active Network Adapters:
"@

    foreach ($adapter in $Health.NetworkAdapters) {
        $report += @"

  - $($adapter.Name)
    Status: $($adapter.Status)
    Speed: $($adapter.LinkSpeed)
    MAC: $($adapter.MacAddress)
"@
    }

    $report += @"


================================================================================
WINDOWS UPDATE
================================================================================
Pending Updates: $($Health.PendingUpdates)$(if ($Health.PendingUpdates -gt 10) { " [!] MANY UPDATES PENDING" } else { "" })

================================================================================
CRITICAL SERVICES
================================================================================
"@

    foreach ($service in $Health.Services) {
        $statusIndicator = if ($service.HealthStatus -eq 'OK') { '[+]' } else { '[!]' }
        $report += @"

$statusIndicator $($service.Name)
  Status: $($service.Status) ($($service.StartType))
"@
    }

    if ($Health.RecentErrors -and $Health.RecentErrors.Count -gt 0) {
        $report += @"


================================================================================
RECENT SYSTEM ERRORS (Last $DaysBack Days)
================================================================================
Total Errors: $($Health.RecentErrors.Count)

"@
        foreach ($error in $Health.RecentErrors | Select-Object -First 5) {
            $msgPreview = if ($error.Message.Length -gt 100) {
                $error.Message.Substring(0, 100) + "..."
            } else {
                $error.Message
            }

            $report += @"

[$($error.TimeCreated.ToString('yyyy-MM-dd HH:mm'))] Event ID: $($error.Id)
Source: $($error.ProviderName)
Message: $msgPreview

"@
        }
    }

    $report += @"


================================================================================
RECOMMENDATIONS
================================================================================
"@

    if ($Health.UptimeDays -gt 30) {
        $report += "`n[!] System uptime exceeds 30 days - Schedule a reboot to apply updates"
    }

    if ($Health.UsedRAMPercent -gt 90) {
        $report += "`n[!] High memory usage detected - Consider closing applications or adding RAM"
    }

    foreach ($disk in $Health.Disks) {
        if ($disk.Status -eq 'CRITICAL') {
            $report += "`n[X] CRITICAL: Drive $($disk.Drive) is critically low on space - Immediate cleanup required"
        } elseif ($disk.Status -eq 'WARNING') {
            $report += "`n[!] WARNING: Drive $($disk.Drive) is running low on space - Cleanup recommended"
        }
    }

    if (-not $Health.InternetConnected) {
        $report += "`n[X] No internet connectivity detected - Check network settings"
    }

    if ($Health.PendingUpdates -gt 10) {
        $report += "`n[!] Multiple Windows updates pending - Schedule installation"
    }

    if ($Health.HealthScore -lt 60) {
        $report += "`n[!] Overall system health is POOR - Address warnings and errors above"
    }

    $report += @"


================================================================================
END OF REPORT
================================================================================
"@

    return $report
}

# Main execution
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host " System Health Report Generator" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

# Collect health data
$healthData = Get-SystemHealth

if (-not $healthData) {
    Write-StatusMessage "Failed to collect system health data" -Level ERROR
    exit 1
}

Write-Host ""
Write-StatusMessage "Generating report..." -Level INFO

# Generate text report
$textReport = Format-TextReport -Health $healthData

try {
    # Save report
    $textReport | Out-File -FilePath $OutputPath -Encoding UTF8 -Force

    Write-Host ""
    Write-StatusMessage "Report generated successfully!" -Level SUCCESS
    Write-Host ""
    Write-Host "  Location: $OutputPath" -ForegroundColor Cyan
    Write-Host "  Health Score: $($healthData.HealthScore)/100" -ForegroundColor $(
        if ($healthData.HealthScore -ge 90) { 'Green' }
        elseif ($healthData.HealthScore -ge 75) { 'Yellow' }
        else { 'Red' }
    )
    Write-Host ""

    if ($OpenReport) {
        Start-Process notepad.exe -ArgumentList $OutputPath
        Write-StatusMessage "Opening report..." -Level INFO
    }

    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Green
    Write-Host " Report Generation Complete" -ForegroundColor Green
    Write-Host ("=" * 80) -ForegroundColor Green
    Write-Host ""

} catch {
    Write-StatusMessage "Error saving report: $($_.Exception.Message)" -Level ERROR
    exit 1
}
