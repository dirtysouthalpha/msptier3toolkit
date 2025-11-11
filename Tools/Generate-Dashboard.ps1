<#
.SYNOPSIS
    MSP Toolkit - Dashboard Generator
.DESCRIPTION
    Generates stunning HTML dashboard with charts, analytics, and system health overview
#>

[CmdletBinding()]
param(
    [switch]$OpenInBrowser,
    [string]$OutputPath
)

# Import modules
$CorePath = "$PSScriptRoot\..\Core"
Import-Module "$CorePath\MSPToolkit.Config.psm1" -Force
Import-Module "$CorePath\MSPToolkit.Logging.psm1" -Force

Initialize-MSPLogging -ScriptName "Dashboard"
$config = Get-MSPConfig

if (-not $OutputPath) {
    $OutputPath = Join-Path $config.paths.reports "Dashboard_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
}

Write-MSPLog "Generating dashboard..." -Level INFO

# Collect statistics
$stats = @{}

# Tool usage stats
$recentFile = Join-Path $config.paths.cache "recents.json"
if (Test-Path $recentFile) {
    $recents = Get-Content $recentFile | ConvertFrom-Json
    $stats.RecentToolsCount = $recents.Count
} else {
    $stats.RecentToolsCount = 0
}

# Log statistics
$logDir = $config.paths.logs
$stats.LogFiles = 0
$stats.LogSizeMB = 0
$stats.TodayExecutions = 0
$stats.ErrorsToday = 0

if (Test-Path $logDir) {
    $logs = Get-ChildItem -Path $logDir -Filter "*.log"
    $stats.LogFiles = $logs.Count
    $stats.LogSizeMB = [Math]::Round(($logs | Measure-Object -Property Length -Sum).Sum / 1MB, 2)

    # Parse today's logs
    $today = Get-Date -Format "yyyyMMdd"
    $todayLogs = $logs | Where-Object { $_.Name -like "*$today*" }

    foreach ($log in $todayLogs) {
        $content = Get-Content $log.FullName -ErrorAction SilentlyContinue
        $stats.TodayExecutions += ($content | Select-String "\[INFO\]" | Measure-Object).Count
        $stats.ErrorsToday += ($content | Select-String "\[ERROR\]" | Measure-Object).Count
    }
}

# System info
$sysInfo = Get-MSPSystemInfo
$disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" | Select-Object -First 1
$diskFreePercent = [Math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)

$os = Get-CimInstance -ClassName Win32_OperatingSystem
$memoryUsedPercent = [Math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 1)

# Generate HTML
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MSP Toolkit Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            color: #ffffff;
            padding: 20px;
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
        }

        .header {
            text-align: center;
            padding: 30px 0;
            border-bottom: 2px solid rgba(255, 255, 255, 0.2);
            margin-bottom: 30px;
        }

        .header h1 {
            font-size: 48px;
            font-weight: bold;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.3);
        }

        .header .subtitle {
            font-size: 18px;
            opacity: 0.9;
        }

        .header .timestamp {
            font-size: 14px;
            opacity: 0.7;
            margin-top: 10px;
        }

        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }

        .stat-card {
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.2);
            border: 1px solid rgba(255, 255, 255, 0.18);
            transition: transform 0.3s ease, box-shadow 0.3s ease;
        }

        .stat-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 12px 40px rgba(0, 0, 0, 0.3);
        }

        .stat-card .icon {
            font-size: 48px;
            margin-bottom: 15px;
        }

        .stat-card .label {
            font-size: 14px;
            opacity: 0.8;
            margin-bottom: 8px;
            text-transform: uppercase;
            letter-spacing: 1px;
        }

        .stat-card .value {
            font-size: 36px;
            font-weight: bold;
            margin-bottom: 5px;
        }

        .stat-card .subvalue {
            font-size: 12px;
            opacity: 0.7;
        }

        .system-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(450px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }

        .system-card {
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.2);
            border: 1px solid rgba(255, 255, 255, 0.18);
        }

        .system-card h2 {
            font-size: 24px;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid rgba(255, 255, 255, 0.2);
        }

        .info-row {
            display: flex;
            justify-content: space-between;
            padding: 12px 0;
            border-bottom: 1px solid rgba(255, 255, 255, 0.1);
        }

        .info-row:last-child {
            border-bottom: none;
        }

        .info-label {
            opacity: 0.8;
        }

        .info-value {
            font-weight: bold;
        }

        .progress-bar {
            width: 100%;
            height: 25px;
            background: rgba(0, 0, 0, 0.3);
            border-radius: 12px;
            overflow: hidden;
            margin-top: 10px;
            box-shadow: inset 0 2px 4px rgba(0, 0, 0, 0.2);
        }

        .progress-fill {
            height: 100%;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 12px;
            font-weight: bold;
            transition: width 1s ease;
        }

        .progress-good {
            background: linear-gradient(90deg, #00b09b, #96c93d);
        }

        .progress-warning {
            background: linear-gradient(90deg, #f2994a, #f2c94c);
        }

        .progress-critical {
            background: linear-gradient(90deg, #eb3349, #f45c43);
        }

        .chart-container {
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 15px;
            padding: 25px;
            margin-bottom: 30px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.2);
            border: 1px solid rgba(255, 255, 255, 0.18);
        }

        .chart-container h2 {
            font-size: 24px;
            margin-bottom: 20px;
        }

        .footer {
            text-align: center;
            padding: 20px 0;
            opacity: 0.7;
            font-size: 14px;
            border-top: 2px solid rgba(255, 255, 255, 0.2);
            margin-top: 30px;
        }

        @keyframes fadeIn {
            from {
                opacity: 0;
                transform: translateY(20px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }

        .stat-card, .system-card, .chart-container {
            animation: fadeIn 0.6s ease;
        }

        .badge {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: bold;
            margin-left: 10px;
        }

        .badge-success {
            background: #00b09b;
        }

        .badge-warning {
            background: #f2994a;
        }

        .badge-error {
            background: #eb3349;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 MSP TOOLKIT DASHBOARD</h1>
            <div class="subtitle">Tier 3 Support Automation Platform</div>
            <div class="timestamp">Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>
        </div>

        <div class="stats-grid">
            <div class="stat-card">
                <div class="icon">📊</div>
                <div class="label">Executions Today</div>
                <div class="value">$($stats.TodayExecutions)</div>
                <div class="subvalue">Scripts run in last 24 hours</div>
            </div>

            <div class="stat-card">
                <div class="icon">📁</div>
                <div class="label">Log Files</div>
                <div class="value">$($stats.LogFiles)</div>
                <div class="subvalue">Total: $($stats.LogSizeMB) MB</div>
            </div>

            <div class="stat-card">
                <div class="icon">⭐</div>
                <div class="label">Recent Tools</div>
                <div class="value">$($stats.RecentToolsCount)</div>
                <div class="subvalue">Frequently accessed</div>
            </div>

            <div class="stat-card">
                <div class="icon">$(if ($stats.ErrorsToday -eq 0) { '✅' } else { '⚠️' })</div>
                <div class="label">Errors Today</div>
                <div class="value">$($stats.ErrorsToday)</div>
                <div class="subvalue">$(if ($stats.ErrorsToday -eq 0) { 'All systems nominal' } else { 'Requires attention' })</div>
            </div>
        </div>

        <div class="system-grid">
            <div class="system-card">
                <h2>💻 System Information</h2>
                <div class="info-row">
                    <span class="info-label">Computer Name:</span>
                    <span class="info-value">$($sysInfo.ComputerName)</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Operating System:</span>
                    <span class="info-value">$($sysInfo.OSName)</span>
                </div>
                <div class="info-row">
                    <span class="info-label">OS Version:</span>
                    <span class="info-value">$($sysInfo.OSVersion) (Build $($sysInfo.OSBuild))</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Domain:</span>
                    <span class="info-value">$($sysInfo.Domain)</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Total Memory:</span>
                    <span class="info-value">$($sysInfo.TotalMemoryGB) GB</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Current User:</span>
                    <span class="info-value">$($sysInfo.Username)$(if ($sysInfo.IsAdmin) { '<span class="badge badge-success">ADMIN</span>' } else { '<span class="badge badge-warning">USER</span>' })</span>
                </div>
            </div>

            <div class="system-card">
                <h2>📈 Resource Usage</h2>
                <div class="info-row">
                    <span class="info-label">Memory Usage:</span>
                    <span class="info-value">$memoryUsedPercent%</span>
                </div>
                <div class="progress-bar">
                    <div class="progress-fill $(if ($memoryUsedPercent -lt 70) { 'progress-good' } elseif ($memoryUsedPercent -lt 85) { 'progress-warning' } else { 'progress-critical' })" style="width: $memoryUsedPercent%">
                        $memoryUsedPercent%
                    </div>
                </div>

                <div class="info-row" style="margin-top: 20px;">
                    <span class="info-label">Disk Free Space:</span>
                    <span class="info-value">$diskFreePercent%</span>
                </div>
                <div class="progress-bar">
                    <div class="progress-fill $(if ($diskFreePercent -gt 30) { 'progress-good' } elseif ($diskFreePercent -gt 15) { 'progress-warning' } else { 'progress-critical' })" style="width: $diskFreePercent%">
                        $diskFreePercent%
                    </div>
                </div>
            </div>
        </div>

        <div class="chart-container">
            <h2>⚙️ Configuration Status</h2>
            <div class="system-grid">
                <div>
                    <div class="info-row">
                        <span class="info-label">Auto Updates:</span>
                        <span class="info-value">$(if ($config.updates.autoCheckForUpdates) { '✅ Enabled' } else { '❌ Disabled' })</span>
                    </div>
                    <div class="info-row">
                        <span class="info-label">Auto Healing:</span>
                        <span class="info-value">$(if ($config.monitoring.autoHealEnabled) { '✅ Enabled' } else { '❌ Disabled' })</span>
                    </div>
                    <div class="info-row">
                        <span class="info-label">Logging:</span>
                        <span class="info-value">$(if ($config.logging.enabled) { '✅ Enabled' } else { '❌ Disabled' })</span>
                    </div>
                </div>
                <div>
                    <div class="info-row">
                        <span class="info-label">Web Interface:</span>
                        <span class="info-value">$(if ($config.webInterface.enabled) { '✅ Enabled' } else { '❌ Disabled' })</span>
                    </div>
                    <div class="info-row">
                        <span class="info-label">RMM Integration:</span>
                        <span class="info-value">$(if ($config.rmmIntegration.enabled) { '✅ Enabled' } else { '❌ Disabled' })</span>
                    </div>
                    <div class="info-row">
                        <span class="info-label">Notifications:</span>
                        <span class="info-value">$(if ($config.notifications.emailEnabled) { '✅ Enabled' } else { '❌ Disabled' })</span>
                    </div>
                </div>
            </div>
        </div>

        <div class="footer">
            <p>MSP Toolkit v$($config.version) | Powered by PowerShell</p>
            <p>Dashboard auto-refreshes on each generation</p>
        </div>
    </div>

    <script>
        // Animate counters on load
        document.addEventListener('DOMContentLoaded', function() {
            const statValues = document.querySelectorAll('.stat-card .value');
            statValues.forEach(el => {
                const target = parseInt(el.textContent);
                let current = 0;
                const increment = target / 50;
                const timer = setInterval(() => {
                    current += increment;
                    if (current >= target) {
                        el.textContent = target;
                        clearInterval(timer);
                    } else {
                        el.textContent = Math.floor(current);
                    }
                }, 20);
            });
        });
    </script>
</body>
</html>
"@

# Save HTML file
$html | Out-File -FilePath $OutputPath -Encoding UTF8

Write-MSPLog "Dashboard generated: $OutputPath" -Level SUCCESS

if ($OpenInBrowser) {
    Start-Process $OutputPath
}

# Also display in console
Write-Host ""
Write-Host "  ╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║              DASHBOARD SUMMARY                             ║" -ForegroundColor Cyan
Write-Host "  ╠════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "  ║                                                            ║" -ForegroundColor Cyan
Write-Host "  ║  Executions Today:    " -NoNewline -ForegroundColor Cyan
Write-Host "$($stats.TodayExecutions.ToString().PadLeft(30))    ║" -ForegroundColor White
Write-Host "  ║  Errors Today:        " -NoNewline -ForegroundColor Cyan
Write-Host "$($stats.ErrorsToday.ToString().PadLeft(30))    ║" -ForegroundColor $(if ($stats.ErrorsToday -eq 0) { 'Green' } else { 'Red' })
Write-Host "  ║  Log Files:           " -NoNewline -ForegroundColor Cyan
Write-Host "$($stats.LogFiles.ToString().PadLeft(30))    ║" -ForegroundColor White
Write-Host "  ║  Memory Usage:        " -NoNewline -ForegroundColor Cyan
Write-Host "$("$memoryUsedPercent%".PadLeft(30))    ║" -ForegroundColor $(if ($memoryUsedPercent -lt 85) { 'Green' } else { 'Red' })
Write-Host "  ║  Disk Free:           " -NoNewline -ForegroundColor Cyan
Write-Host "$("$diskFreePercent%".PadLeft(30))    ║" -ForegroundColor $(if ($diskFreePercent -gt 15) { 'Green' } else { 'Red' })
Write-Host "  ║                                                            ║" -ForegroundColor Cyan
Write-Host "  ╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  HTML Dashboard saved to:" -ForegroundColor Gray
Write-Host "  $OutputPath" -ForegroundColor Yellow
Write-Host ""

return $OutputPath
