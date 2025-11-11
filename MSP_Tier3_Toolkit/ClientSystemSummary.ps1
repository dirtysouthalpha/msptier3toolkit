<#
.SYNOPSIS
    Professional Client-Facing System Summary Report Generator
.DESCRIPTION
    Generates a beautifully formatted HTML system summary report for clients
    including comprehensive hardware, software, and health information
.PARAMETER OutputPath
    Custom path for the output HTML file (default: Desktop)
.PARAMETER CompanyName
    Your company name for branding
.PARAMETER OpenInBrowser
    Automatically open the report in default browser
.NOTES
    Author: MSP Toolkit Team
    Version: 2.0
    Requires: Standard user
#>

[CmdletBinding()]
param(
    [string]$OutputPath = "$env:USERPROFILE\Desktop\SystemSummary_$(Get-Date -Format 'yyyyMMdd_HHmmss').html",
    [string]$CompanyName = "IT Support Services",
    [switch]$OpenInBrowser
)

$ErrorActionPreference = 'Continue'

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host " Client System Summary Report Generator" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

Write-Host "[i] Collecting system information..." -ForegroundColor Cyan

# Collect system information
try {
    $computerInfo = Get-ComputerInfo -ErrorAction SilentlyContinue
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    $bios = Get-CimInstance -ClassName Win32_BIOS
    $cpu = Get-CimInstance -ClassName Win32_Processor
    $disks = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
    $network = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }

    # Get installed software (top 20 by install date)
    $software = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate -First 20

    # Get recent errors from event log
    $recentErrors = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        Level = 2  # Error level
        StartTime = (Get-Date).AddDays(-7)
    } -MaxEvents 10 -ErrorAction SilentlyContinue

    $recentWarnings = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        Level = 3  # Warning level
        StartTime = (Get-Date).AddDays(-7)
    } -MaxEvents 5 -ErrorAction SilentlyContinue

} catch {
    Write-Host "[X] Error collecting system information: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "[+] Information collected successfully" -ForegroundColor Green
Write-Host "[i] Generating HTML report..." -ForegroundColor Cyan

# Build HTML report
$html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>System Summary Report - $($cs.Name)</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            color: #333;
        }

        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            overflow: hidden;
        }

        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px;
            text-align: center;
        }

        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
        }

        .header p {
            font-size: 1.2em;
            opacity: 0.9;
        }

        .content {
            padding: 40px;
        }

        .section {
            margin-bottom: 40px;
        }

        .section-title {
            font-size: 1.8em;
            color: #667eea;
            border-bottom: 3px solid #667eea;
            padding-bottom: 10px;
            margin-bottom: 20px;
        }

        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
        }

        .info-card {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            border-left: 4px solid #667eea;
        }

        .info-card h3 {
            color: #667eea;
            font-size: 0.9em;
            text-transform: uppercase;
            margin-bottom: 10px;
        }

        .info-card p {
            font-size: 1.2em;
            color: #333;
            font-weight: 600;
        }

        .disk-bar {
            background: #e0e0e0;
            height: 30px;
            border-radius: 15px;
            overflow: hidden;
            margin-top: 10px;
            position: relative;
        }

        .disk-bar-fill {
            height: 100%;
            background: linear-gradient(90deg, #667eea, #764ba2);
            transition: width 0.5s ease;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
        }

        .disk-bar-fill.warning {
            background: linear-gradient(90deg, #f093fb, #f5576c);
        }

        .disk-bar-fill.critical {
            background: linear-gradient(90deg, #fa709a, #fee140);
        }

        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
        }

        table th {
            background: #667eea;
            color: white;
            padding: 12px;
            text-align: left;
        }

        table td {
            padding: 12px;
            border-bottom: 1px solid #e0e0e0;
        }

        table tr:hover {
            background: #f8f9fa;
        }

        .status-good {
            color: #28a745;
            font-weight: bold;
        }

        .status-warning {
            color: #ffc107;
            font-weight: bold;
        }

        .status-error {
            color: #dc3545;
            font-weight: bold;
        }

        .footer {
            background: #f8f9fa;
            padding: 30px;
            text-align: center;
            color: #666;
        }

        .badge {
            display: inline-block;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: bold;
        }

        .badge-success {
            background: #d4edda;
            color: #155724;
        }

        .badge-warning {
            background: #fff3cd;
            color: #856404;
        }

        .badge-danger {
            background: #f8d7da;
            color: #721c24;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🖥️ System Summary Report</h1>
            <p>Generated by $CompanyName</p>
            <p style="font-size:0.9em; margin-top:10px;">$(Get-Date -Format 'MMMM dd, yyyy - HH:mm:ss')</p>
        </div>

        <div class="content">
            <!-- Computer Information -->
            <div class="section">
                <h2 class="section-title">Computer Information</h2>
                <div class="info-grid">
                    <div class="info-card">
                        <h3>Computer Name</h3>
                        <p>$($cs.Name)</p>
                    </div>
                    <div class="info-card">
                        <h3>Manufacturer</h3>
                        <p>$($cs.Manufacturer)</p>
                    </div>
                    <div class="info-card">
                        <h3>Model</h3>
                        <p>$($cs.Model)</p>
                    </div>
                    <div class="info-card">
                        <h3>Serial Number</h3>
                        <p>$($bios.SerialNumber)</p>
                    </div>
                </div>
            </div>

            <!-- Operating System -->
            <div class="section">
                <h2 class="section-title">Operating System</h2>
                <div class="info-grid">
                    <div class="info-card">
                        <h3>OS Name</h3>
                        <p>$($os.Caption)</p>
                    </div>
                    <div class="info-card">
                        <h3>Version</h3>
                        <p>$($os.Version)</p>
                    </div>
                    <div class="info-card">
                        <h3>Build Number</h3>
                        <p>$($os.BuildNumber)</p>
                    </div>
                    <div class="info-card">
                        <h3>Last Boot</h3>
                        <p>$($os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm'))</p>
                    </div>
                </div>
            </div>

            <!-- Hardware -->
            <div class="section">
                <h2 class="section-title">Hardware</h2>
                <div class="info-grid">
                    <div class="info-card">
                        <h3>Processor</h3>
                        <p>$($cpu.Name)</p>
                    </div>
                    <div class="info-card">
                        <h3>Cores</h3>
                        <p>$($cpu.NumberOfCores) cores / $($cpu.NumberOfLogicalProcessors) threads</p>
                    </div>
                    <div class="info-card">
                        <h3>Total RAM</h3>
                        <p>$([math]::Round($cs.TotalPhysicalMemory / 1GB, 2)) GB</p>
                    </div>
                    <div class="info-card">
                        <h3>Available RAM</h3>
                        <p>$([math]::Round($os.FreePhysicalMemory / 1MB, 2)) GB</p>
                    </div>
                </div>
            </div>

            <!-- Storage -->
            <div class="section">
                <h2 class="section-title">Storage</h2>
"@

foreach ($disk in $disks) {
    $usedPercent = [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 1)
    $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    $totalGB = [math]::Round($disk.Size / 1GB, 2)

    $barClass = if ($usedPercent -gt 90) { "critical" }
                elseif ($usedPercent -gt 75) { "warning" }
                else { "" }

    $html += @"
                <div class="info-card">
                    <h3>Drive $($disk.DeviceID) - $($disk.VolumeName)</h3>
                    <p>$freeGB GB free of $totalGB GB</p>
                    <div class="disk-bar">
                        <div class="disk-bar-fill $barClass" style="width: $usedPercent%">$usedPercent%</div>
                    </div>
                </div>
"@
}

$html += @"
            </div>

            <!-- Network -->
            <div class="section">
                <h2 class="section-title">Network Adapters</h2>
                <table>
                    <tr>
                        <th>Adapter Name</th>
                        <th>Status</th>
                        <th>Link Speed</th>
                    </tr>
"@

foreach ($adapter in $network) {
    $html += @"
                    <tr>
                        <td>$($adapter.Name)</td>
                        <td><span class="status-good">$($adapter.Status)</span></td>
                        <td>$($adapter.LinkSpeed)</td>
                    </tr>
"@
}

$html += @"
                </table>
            </div>

            <!-- Installed Software (Top 20) -->
            <div class="section">
                <h2 class="section-title">Recently Installed Software (Top 20)</h2>
                <table>
                    <tr>
                        <th>Application</th>
                        <th>Version</th>
                        <th>Publisher</th>
                    </tr>
"@

foreach ($app in $software) {
    $html += @"
                    <tr>
                        <td>$($app.DisplayName)</td>
                        <td>$($app.DisplayVersion)</td>
                        <td>$($app.Publisher)</td>
                    </tr>
"@
}

$html += @"
                </table>
            </div>

            <!-- Recent System Events -->
            <div class="section">
                <h2 class="section-title">Recent System Events (Last 7 Days)</h2>
"@

if ($recentErrors) {
    $html += @"
                <h3 style="color: #dc3545; margin-top: 20px;">Recent Errors ($($recentErrors.Count))</h3>
                <table>
                    <tr>
                        <th>Time</th>
                        <th>Source</th>
                        <th>Event ID</th>
                        <th>Message</th>
                    </tr>
"@
    foreach ($event in $recentErrors | Select-Object -First 10) {
        $html += @"
                    <tr>
                        <td>$($event.TimeCreated.ToString('yyyy-MM-dd HH:mm'))</td>
                        <td>$($event.ProviderName)</td>
                        <td>$($event.Id)</td>
                        <td>$($event.Message.Substring(0, [Math]::Min(100, $event.Message.Length)))...</td>
                    </tr>
"@
    }
    $html += "</table>"
} else {
    $html += "<p class='status-good'>✓ No critical errors in the last 7 days</p>"
}

$html += @"
            </div>
        </div>

        <div class="footer">
            <p><strong>$CompanyName</strong></p>
            <p>Report generated on $(Get-Date -Format 'MMMM dd, yyyy')</p>
            <p style="margin-top: 10px; font-size: 0.9em;">This report provides a comprehensive overview of your system's current status.</p>
        </div>
    </div>
</body>
</html>
"@

# Save the HTML file
try {
    $html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
    Write-Host "[+] Report generated successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Location: $OutputPath" -ForegroundColor Cyan
    Write-Host ""

    if ($OpenInBrowser) {
        Start-Process $OutputPath
        Write-Host "[i] Opening report in default browser..." -ForegroundColor Cyan
    }

    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Green
    Write-Host " Report Generation Complete" -ForegroundColor Green
    Write-Host ("=" * 80) -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "[X] Error saving report: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
