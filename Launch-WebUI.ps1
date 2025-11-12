<#
.SYNOPSIS
    MSP Toolkit - Simple Web UI Launcher
.DESCRIPTION
    Standalone launcher for the MSP Toolkit Web Interface - Works anywhere!
.NOTES
    Version: 2.0.0
    Cross-Platform Compatible
#>

[CmdletBinding()]
param(
    [int]$Port = 8080,
    [switch]$OpenBrowser
)

# Simple banner
function Show-Banner {
    Write-Host ""
    Write-Host "  ╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║                                                        ║" -ForegroundColor Cyan
    Write-Host "  ║           MSP TOOLKIT WEB INTERFACE                   ║" -ForegroundColor Cyan
    Write-Host "  ║                                                        ║" -ForegroundColor Cyan
    Write-Host "  ╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

Show-Banner

Write-Host "  [+] Starting web server on port $Port..." -ForegroundColor Green
Write-Host ""

# Create HTTP listener
$listener = New-Object System.Net.HttpListener
$prefix = "http://localhost:$Port/"
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()

    Write-Host "  ╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║                                                        ║" -ForegroundColor Green
    Write-Host "  ║        ✓ WEB INTERFACE IS RUNNING!                    ║" -ForegroundColor Green
    Write-Host "  ║                                                        ║" -ForegroundColor Green
    Write-Host "  ║  URL: " -NoNewline -ForegroundColor Green
    Write-Host "http://localhost:$Port" -NoNewline -ForegroundColor Yellow
    Write-Host "                       ║" -ForegroundColor Green
    Write-Host "  ║                                                        ║" -ForegroundColor Green
    Write-Host "  ║  Press Ctrl+C to stop the server                      ║" -ForegroundColor Green
    Write-Host "  ║                                                        ║" -ForegroundColor Green
    Write-Host "  ╚════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""

    if ($OpenBrowser) {
        if ($IsWindows -or $env:OS -match "Windows") {
            Start-Process "http://localhost:$Port"
        } else {
            Write-Host "  [i] Open your browser to: http://localhost:$Port" -ForegroundColor Cyan
        }
    } else {
        Write-Host "  [i] Open your browser to: http://localhost:$Port" -ForegroundColor Cyan
    }
    Write-Host ""

    # Main web page HTML
    $mainPage = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MSP Toolkit Web Interface</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #fff;
            min-height: 100vh;
        }
        .header {
            background: rgba(0,0,0,0.2);
            padding: 30px;
            text-align: center;
            border-bottom: 2px solid rgba(255,255,255,0.2);
        }
        .header h1 { font-size: 42px; margin-bottom: 10px; }
        .header p { opacity: 0.9; font-size: 18px; }
        .container { max-width: 1200px; margin: 30px auto; padding: 0 20px; }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin: 30px 0;
        }
        .card {
            background: rgba(255,255,255,0.1);
            backdrop-filter: blur(10px);
            border-radius: 15px;
            padding: 25px;
            border: 1px solid rgba(255,255,255,0.2);
            transition: transform 0.3s ease, box-shadow 0.3s ease;
            cursor: pointer;
        }
        .card:hover {
            transform: translateY(-5px);
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
            background: rgba(255,255,255,0.15);
        }
        .card h3 {
            font-size: 24px;
            margin-bottom: 10px;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .card p { opacity: 0.8; line-height: 1.6; font-size: 14px; }
        .category {
            font-size: 12px;
            opacity: 0.7;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 10px;
        }
        .badge {
            display: inline-block;
            padding: 4px 10px;
            border-radius: 12px;
            font-size: 11px;
            margin-left: 5px;
            background: rgba(255,255,255,0.2);
        }
        .badge.admin { background: rgba(255,87,87,0.3); }
        .badge.remote { background: rgba(87,255,87,0.3); }
        .btn {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 12px 30px;
            border-radius: 25px;
            font-size: 16px;
            cursor: pointer;
            margin: 10px 5px;
            transition: all 0.3s ease;
            font-weight: 600;
        }
        .btn:hover {
            transform: scale(1.05);
            box-shadow: 0 5px 20px rgba(0,0,0,0.3);
        }
        .status {
            display: inline-block;
            padding: 8px 16px;
            border-radius: 20px;
            font-size: 14px;
            font-weight: 600;
            background: rgba(87,255,87,0.2);
            margin: 10px 0;
        }
        .info-box {
            background: rgba(255,255,255,0.1);
            backdrop-filter: blur(10px);
            border-radius: 15px;
            padding: 20px;
            margin: 20px 0;
            border: 1px solid rgba(255,255,255,0.2);
        }
        .footer {
            text-align: center;
            padding: 30px;
            opacity: 0.7;
            font-size: 14px;
        }
        pre {
            background: rgba(0,0,0,0.3);
            padding: 15px;
            border-radius: 8px;
            overflow-x: auto;
            font-family: 'Courier New', monospace;
            font-size: 13px;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>🚀 MSP TOOLKIT</h1>
        <p>Web-Based Automation Platform v2.0</p>
        <div class="status">🟢 Server Running</div>
    </div>

    <div class="container">
        <h2 style="margin: 20px 0;">Available Tools</h2>

        <div class="grid">
            <!-- Diagnostics -->
            <div class="card" onclick="showInfo('System Health Report', 'Generates a comprehensive health check report including disk space, memory, services, and event logs.')">
                <div class="category">Diagnostics</div>
                <h3>📊 System Health Report</h3>
                <p>Generate comprehensive system health report with detailed diagnostics</p>
                <span class="badge remote">REMOTE</span>
            </div>

            <div class="card" onclick="showInfo('Boot Time Analyzer', 'Analyzes Windows Event Logs to show boot and shutdown times, helping identify performance issues.')">
                <div class="category">Diagnostics</div>
                <h3>⏱️ Boot Time Analyzer</h3>
                <p>Analyze boot and shutdown times from Event Logs</p>
                <span class="badge remote">REMOTE</span>
            </div>

            <div class="card" onclick="showInfo('Client System Summary', 'Creates a beautiful HTML report with system information perfect for sending to clients.')">
                <div class="category">Diagnostics</div>
                <h3>📄 Client System Summary</h3>
                <p>Generate HTML system summary for clients</p>
                <span class="badge remote">REMOTE</span>
            </div>

            <!-- Maintenance -->
            <div class="card" onclick="showInfo('Cleanup Old Profiles', 'Removes user profiles that have not been used in over 30 days to free up disk space.')">
                <div class="category">Maintenance</div>
                <h3>🗑️ Cleanup Old Profiles</h3>
                <p>Remove user profiles older than 30 days</p>
                <span class="badge admin">ADMIN</span>
                <span class="badge remote">REMOTE</span>
            </div>

            <div class="card" onclick="showInfo('Comprehensive Cleanup', 'Full system cleanup including temp files, downloads, recycle bin, Windows Update cache, and more.')">
                <div class="category">Maintenance</div>
                <h3>🧹 Comprehensive Cleanup</h3>
                <p>Full system cleanup with logging</p>
                <span class="badge admin">ADMIN</span>
                <span class="badge remote">REMOTE</span>
            </div>

            <!-- Print Management -->
            <div class="card" onclick="showInfo('Printer Spooler Fix', 'Clears stuck print jobs and restarts the print spooler service.')">
                <div class="category">Print Management</div>
                <h3>🖨️ Printer Spooler Fix</h3>
                <p>Fix stuck print jobs and restart spooler</p>
                <span class="badge admin">ADMIN</span>
                <span class="badge remote">REMOTE</span>
            </div>

            <div class="card" onclick="showInfo('Spooler Monitor', 'Deploys automatic monitoring that restarts the spooler when it fails.')">
                <div class="category">Print Management</div>
                <h3>👁️ Spooler Monitor Setup</h3>
                <p>Deploy automatic spooler monitoring</p>
                <span class="badge admin">ADMIN</span>
                <span class="badge remote">REMOTE</span>
            </div>

            <!-- Network & Software -->
            <div class="card" onclick="showInfo('Fix Mapped Drives', 'Tests and repairs network drive mappings that have failed.')">
                <div class="category">Network</div>
                <h3>🔗 Fix Mapped Drives</h3>
                <p>Test and repair network drive mappings</p>
                <span class="badge remote">REMOTE</span>
            </div>

            <div class="card" onclick="showInfo('Remote Uninstall', 'Silently uninstalls software from local or remote computers.')">
                <div class="category">Software</div>
                <h3>❌ Remote Software Uninstall</h3>
                <p>Uninstall software silently</p>
                <span class="badge admin">ADMIN</span>
                <span class="badge remote">REMOTE</span>
            </div>

            <!-- Windows Update -->
            <div class="card" onclick="showInfo('Windows Update Fix', 'Resets Windows Update components to fix common update issues.')">
                <div class="category">Windows Update</div>
                <h3>🔄 Windows Update Fix</h3>
                <p>Reset Windows Update components</p>
                <span class="badge admin">ADMIN</span>
                <span class="badge remote">REMOTE</span>
            </div>

            <!-- Active Directory -->
            <div class="card" onclick="showInfo('Check AD User Status', 'Checks Active Directory for user lockout status and password expiration.')">
                <div class="category">Active Directory</div>
                <h3>👤 Check AD User Status</h3>
                <p>Check user lockout and password status</p>
            </div>

            <!-- Microsoft 365 -->
            <div class="card" onclick="showInfo('M365 User Provisioning', 'Provisions Office 365 licenses for users in your tenant.')">
                <div class="category">Microsoft 365</div>
                <h3>☁️ M365 User Provisioning</h3>
                <p>Provision Office 365 licenses for users</p>
            </div>
        </div>

        <div class="info-box">
            <h3>💡 Quick Actions</h3>
            <button class="btn" onclick="window.location.href='/api/status'">📊 API Status</button>
            <button class="btn" onclick="window.location.href='/api/health'">❤️ Health Check</button>
            <button class="btn" onclick="window.location.href='/api/scripts'">📜 Scripts List</button>
            <button class="btn" onclick="window.location.href='/dashboard'">📈 Dashboard</button>
        </div>

        <div id="infoDisplay" class="info-box" style="display:none;">
            <h3 id="infoTitle">Tool Information</h3>
            <p id="infoDescription"></p>
            <button class="btn" onclick="document.getElementById('infoDisplay').style.display='none'">Close</button>
        </div>

        <div class="info-box">
            <h3>ℹ️ How to Use</h3>
            <p style="margin: 10px 0; line-height: 1.8;">
                <strong>1.</strong> To run a tool from PowerShell, use the main launcher:<br>
                <pre>.\Launch-MSPToolkit.ps1</pre><br>
                <strong>2.</strong> For a simplified launcher with no dependencies:<br>
                <pre>.\WORKING_LAUNCHER_USE_THIS.ps1</pre><br>
                <strong>3.</strong> Tools marked <span class="badge admin">ADMIN</span> require administrator privileges<br>
                <strong>4.</strong> Tools marked <span class="badge remote">REMOTE</span> support remote execution<br>
            </p>
        </div>
    </div>

    <div class="footer">
        <p>MSP Tier 3 Toolkit v2.0 | Dazzle. Automate. Dominate.</p>
        <p style="margin-top: 10px;">
            <a href="https://github.com/dirtysouthalpha/msptier3toolkit"
               style="color: white; text-decoration: none; opacity: 0.8;"
               target="_blank">
               📦 GitHub Repository
            </a>
        </p>
    </div>

    <script>
        console.log('MSP Toolkit Web Interface Loaded');

        function showInfo(title, description) {
            document.getElementById('infoTitle').textContent = title;
            document.getElementById('infoDescription').textContent = description;
            document.getElementById('infoDisplay').style.display = 'block';
            document.getElementById('infoDisplay').scrollIntoView({ behavior: 'smooth' });
        }

        // Add some interactivity
        document.addEventListener('DOMContentLoaded', function() {
            console.log('Page loaded successfully');

            // Add animation to cards
            const cards = document.querySelectorAll('.card');
            cards.forEach((card, index) => {
                card.style.opacity = '0';
                card.style.transform = 'translateY(20px)';
                setTimeout(() => {
                    card.style.transition = 'all 0.5s ease';
                    card.style.opacity = '1';
                    card.style.transform = 'translateY(0)';
                }, index * 50);
            });
        });
    </script>
</body>
</html>
"@

    # Dashboard page
    $dashboardPage = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dashboard - MSP Toolkit</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #fff;
            min-height: 100vh;
        }
        .header {
            background: rgba(0,0,0,0.2);
            padding: 30px;
            text-align: center;
            border-bottom: 2px solid rgba(255,255,255,0.2);
        }
        .container { max-width: 1200px; margin: 30px auto; padding: 0 20px; }
        .stat-box {
            background: rgba(255,255,255,0.1);
            backdrop-filter: blur(10px);
            border-radius: 15px;
            padding: 25px;
            margin: 15px 0;
            border: 1px solid rgba(255,255,255,0.2);
        }
        .stat-box h3 { margin-bottom: 10px; }
        .stat-value { font-size: 32px; font-weight: bold; margin: 10px 0; }
        .btn {
            background: rgba(255,255,255,0.2);
            color: white;
            border: none;
            padding: 12px 30px;
            border-radius: 25px;
            font-size: 16px;
            cursor: pointer;
            text-decoration: none;
            display: inline-block;
            margin: 10px 5px;
        }
        .btn:hover { background: rgba(255,255,255,0.3); }
    </style>
</head>
<body>
    <div class="header">
        <h1>📈 Dashboard</h1>
        <p>MSP Toolkit System Status</p>
    </div>
    <div class="container">
        <div class="stat-box">
            <h3>System Information</h3>
            <p><strong>Computer:</strong> $env:COMPUTERNAME</p>
            <p><strong>User:</strong> $env:USERNAME</p>
            <p><strong>PowerShell Version:</strong> $($PSVersionTable.PSVersion)</p>
            <p><strong>Time:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
        </div>
        <div class="stat-box">
            <h3>Web Interface Status</h3>
            <div class="stat-value">🟢 Online</div>
            <p>Port: $Port</p>
            <p>Version: 2.0.0</p>
        </div>
        <div class="stat-box">
            <h3>Available Tools</h3>
            <div class="stat-value">12</div>
            <p>All scripts ready for execution</p>
        </div>
        <a href="/" class="btn">← Back to Home</a>
    </div>
</body>
</html>
"@

    # Request handler loop
    while ($listener.IsListening) {
        try {
            $context = $listener.GetContext()
            $request = $context.Request
            $response = $context.Response

            $url = $request.Url.LocalPath
            $timestamp = Get-Date -Format "HH:mm:ss"
            Write-Host "  [$timestamp] $($request.HttpMethod) $url" -ForegroundColor Gray

            $responseString = ""
            $contentType = "text/html; charset=utf-8"

            switch -Regex ($url) {
                '^/$' {
                    $responseString = $mainPage
                }
                '^/api/status$' {
                    $contentType = "application/json"
                    $status = @{
                        status = "online"
                        version = "2.0.0"
                        timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                        endpoints = @(
                            "/api/status",
                            "/api/health",
                            "/api/scripts",
                            "/dashboard"
                        )
                    } | ConvertTo-Json -Compress
                    $responseString = $status
                }
                '^/api/health$' {
                    $contentType = "application/json"
                    $health = @{
                        status = "healthy"
                        computerName = $env:COMPUTERNAME
                        user = $env:USERNAME
                        powershellVersion = $PSVersionTable.PSVersion.ToString()
                        timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    } | ConvertTo-Json -Compress
                    $responseString = $health
                }
                '^/api/scripts$' {
                    $contentType = "application/json"
                    $scripts = @(
                        @{ id = 1; name = "System Health Report"; category = "Diagnostics"; requiresAdmin = $false },
                        @{ id = 2; name = "Boot Time Analyzer"; category = "Diagnostics"; requiresAdmin = $false },
                        @{ id = 3; name = "Client System Summary"; category = "Diagnostics"; requiresAdmin = $false },
                        @{ id = 4; name = "Check AD User Status"; category = "Active Directory"; requiresAdmin = $false },
                        @{ id = 5; name = "M365 User Provisioning"; category = "Microsoft 365"; requiresAdmin = $false },
                        @{ id = 6; name = "Cleanup Old Profiles"; category = "Maintenance"; requiresAdmin = $true },
                        @{ id = 7; name = "Comprehensive Cleanup"; category = "Maintenance"; requiresAdmin = $true },
                        @{ id = 8; name = "Printer Spooler Fix"; category = "Print Management"; requiresAdmin = $true },
                        @{ id = 9; name = "Spooler Monitor Setup"; category = "Print Management"; requiresAdmin = $true },
                        @{ id = 10; name = "Fix Mapped Drives"; category = "Network"; requiresAdmin = $false },
                        @{ id = 11; name = "Remote Software Uninstall"; category = "Software"; requiresAdmin = $true },
                        @{ id = 12; name = "Windows Update Fix"; category = "Windows Update"; requiresAdmin = $true }
                    ) | ConvertTo-Json -Compress
                    $responseString = $scripts
                }
                '^/dashboard$' {
                    $responseString = $ExecutionContext.InvokeCommand.ExpandString($dashboardPage)
                }
                default {
                    $response.StatusCode = 404
                    $responseString = @"
<!DOCTYPE html>
<html>
<head>
    <title>404 - Not Found</title>
    <style>
        body {
            font-family: Arial;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            display: flex;
            align-items: center;
            justify-content: center;
            height: 100vh;
            margin: 0;
        }
        .error-box {
            background: rgba(255,255,255,0.1);
            backdrop-filter: blur(10px);
            border-radius: 15px;
            padding: 40px;
            text-align: center;
            border: 1px solid rgba(255,255,255,0.2);
        }
        h1 { font-size: 72px; margin: 0; }
        a { color: white; text-decoration: none; padding: 10px 20px; background: rgba(255,255,255,0.2); border-radius: 20px; }
    </style>
</head>
<body>
    <div class="error-box">
        <h1>404</h1>
        <p>Page not found: $url</p>
        <br>
        <a href="/">← Back to Home</a>
    </div>
</body>
</html>
"@
                }
            }

            $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseString)
            $response.ContentLength64 = $buffer.Length
            $response.ContentType = $contentType
            $response.StatusCode = if ($response.StatusCode -eq 0) { 200 } else { $response.StatusCode }
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
        }
        catch {
            # Handle any request processing errors
            Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
catch {
    Write-Host ""
    Write-Host "  [X] Error starting web interface: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""

    if ($_.Exception.Message -match "access is denied") {
        Write-Host "  [!] Try running PowerShell as Administrator" -ForegroundColor Yellow
    }
    elseif ($_.Exception.Message -match "already in use") {
        Write-Host "  [!] Port $Port is already in use. Try a different port:" -ForegroundColor Yellow
        Write-Host "      .\Launch-WebUI.ps1 -Port 8081" -ForegroundColor Cyan
    }

    Read-Host "Press Enter to exit"
}
finally {
    if ($listener -and $listener.IsListening) {
        $listener.Stop()
        $listener.Close()
        Write-Host ""
        Write-Host "  [i] Web interface stopped" -ForegroundColor Cyan
        Write-Host ""
    }
}
