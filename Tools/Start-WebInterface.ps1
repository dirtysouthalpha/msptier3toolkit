<#
.SYNOPSIS
    MSP Toolkit - Web Interface & REST API
.DESCRIPTION
    Launches a lightweight web server for toolkit access from browsers
#>

[CmdletBinding()]
param(
    [int]$Port = 8080,
    [switch]$OpenBrowser
)

# Import modules
$CorePath = "$PSScriptRoot\..\Core"
Import-Module "$CorePath\MSPToolkit.Config.psm1" -Force
Import-Module "$CorePath\MSPToolkit.Logging.psm1" -Force

Initialize-MSPLogging -ScriptName "WebInterface"
$config = Get-MSPConfig

# Check if enabled
if (-not $config.webInterface.enabled) {
    Write-MSPLog "Web interface is disabled in configuration" -Level WARNING
    Write-MSPLog "Enable it by setting webInterface.enabled = true in config.json" -Level INFO
    return
}

$Port = $config.webInterface.port
if (-not $Port) { $Port = 8080 }

Write-MSPLog "═══ Starting MSP Toolkit Web Interface ═══" -Level HEADER
Write-MSPLog "Port: $Port" -Level INFO

# Create HTTP listener
$listener = New-Object System.Net.HttpListener
$prefix = "http://localhost:$Port/"
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
    Write-MSPLog "✓ Web interface started successfully!" -Level SUCCESS
    Write-Host ""
    Write-Host "  ╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║        WEB INTERFACE ACTIVE                            ║" -ForegroundColor Green
    Write-Host "  ╠════════════════════════════════════════════════════════╣" -ForegroundColor Green
    Write-Host "  ║                                                        ║" -ForegroundColor Green
    Write-Host "  ║  URL: " -NoNewline -ForegroundColor Green
    Write-Host "http://localhost:$Port".PadRight(42) -NoNewline -ForegroundColor Yellow
    Write-Host "     ║" -ForegroundColor Green
    Write-Host "  ║                                                        ║" -ForegroundColor Green
    Write-Host "  ║  Press Ctrl+C to stop the server                      ║" -ForegroundColor Green
    Write-Host "  ║                                                        ║" -ForegroundColor Green
    Write-Host "  ╚════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""

    if ($OpenBrowser) {
        Start-Process "http://localhost:$Port"
    }

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
        .header p { opacity: 0.9; }
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
        }
        .card h3 { font-size: 24px; margin-bottom: 10px; }
        .card p { opacity: 0.8; line-height: 1.6; }
        .category { font-size: 12px; opacity: 0.7; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 10px; }
        .badge {
            display: inline-block;
            padding: 4px 10px;
            border-radius: 12px;
            font-size: 11px;
            margin-left: 5px;
            background: rgba(255,255,255,0.2);
        }
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
        }
        .btn:hover {
            transform: scale(1.05);
            box-shadow: 0 5px 20px rgba(0,0,0,0.3);
        }
        .output {
            background: rgba(0,0,0,0.3);
            border-radius: 10px;
            padding: 20px;
            margin-top: 20px;
            font-family: 'Courier New', monospace;
            max-height: 400px;
            overflow-y: auto;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>🚀 MSP TOOLKIT</h1>
        <p>Web-Based Automation Platform</p>
    </div>

    <div class="container">
        <h2>Available Tools</h2>
        <div class="grid">
            <div class="card" onclick="alert('This feature requires PowerShell backend integration')">
                <div class="category">Diagnostics</div>
                <h3>📊 System Health Report</h3>
                <p>Generate comprehensive system health report</p>
                <span class="badge">REMOTE</span>
            </div>

            <div class="card" onclick="alert('This feature requires PowerShell backend integration')">
                <div class="category">Maintenance</div>
                <h3>🗑️ Comprehensive Cleanup</h3>
                <p>Full system cleanup with logging</p>
                <span class="badge">ADMIN</span>
                <span class="badge">REMOTE</span>
            </div>

            <div class="card" onclick="alert('This feature requires PowerShell backend integration')">
                <div class="category">Print Management</div>
                <h3>🖨️ Printer Spooler Fix</h3>
                <p>Fix stuck print jobs and restart spooler</p>
                <span class="badge">ADMIN</span>
                <span class="badge">REMOTE</span>
            </div>

            <div class="card" onclick="alert('This feature requires PowerShell backend integration')">
                <div class="category">Windows Update</div>
                <h3>🔄 Windows Update Fix</h3>
                <p>Reset Windows Update components</p>
                <span class="badge">ADMIN</span>
                <span class="badge">REMOTE</span>
            </div>

            <div class="card" onclick="window.location.href='/dashboard'">
                <div class="category">Analytics</div>
                <h3>📈 Dashboard</h3>
                <p>View system statistics and reports</p>
            </div>

            <div class="card" onclick="window.location.href='/api/status'">
                <div class="category">System</div>
                <h3>⚙️ API Status</h3>
                <p>View REST API endpoints</p>
            </div>
        </div>

        <div class="card">
            <h3>💡 Quick Actions</h3>
            <button class="btn" onclick="alert('Feature: Generate System Report')">Generate Report</button>
            <button class="btn" onclick="alert('Feature: Run Cleanup')">Run Cleanup</button>
            <button class="btn" onclick="alert('Feature: Check Updates')">Check Updates</button>
            <button class="btn" onclick="window.location.href='/api/health'">Health Check</button>
        </div>

        <div class="output" id="output" style="display:none;">
            <strong>Output:</strong><br>
            <pre id="outputText"></pre>
        </div>
    </div>

    <script>
        console.log('MSP Toolkit Web Interface Loaded');
        console.log('API Base: /api/');
    </script>
</body>
</html>
"@

    # Request handler loop
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        $url = $request.Url.LocalPath
        Write-MSPLog "Request: $($request.HttpMethod) $url from $($request.RemoteEndPoint)" -Level INFO

        $responseString = ""
        $contentType = "text/html"

        switch -Regex ($url) {
            '^/$' {
                $responseString = $mainPage
            }
            '^/api/status$' {
                $contentType = "application/json"
                $status = @{
                    status = "online"
                    version = $config.version
                    timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    endpoints = @(
                        "/api/status",
                        "/api/health",
                        "/api/scripts",
                        "/dashboard"
                    )
                } | ConvertTo-Json
                $responseString = $status
            }
            '^/api/health$' {
                $contentType = "application/json"
                $os = Get-CimInstance -ClassName Win32_OperatingSystem
                $health = @{
                    status = "healthy"
                    computerName = $env:COMPUTERNAME
                    memoryUsagePercent = [Math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 1)
                    timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                } | ConvertTo-Json
                $responseString = $health
            }
            '^/api/scripts$' {
                $contentType = "application/json"
                $scripts = @(
                    @{ id = 1; name = "System Health Report"; category = "Diagnostics" },
                    @{ id = 7; name = "Comprehensive Cleanup"; category = "Maintenance" },
                    @{ id = 8; name = "Printer Spooler Fix"; category = "Print Management" },
                    @{ id = 12; name = "Windows Update Fix"; category = "Windows Update" }
                ) | ConvertTo-Json
                $responseString = $scripts
            }
            '^/dashboard$' {
                $responseString = @"
<!DOCTYPE html>
<html>
<head>
    <title>Dashboard</title>
    <style>
        body { font-family: Arial; margin: 20px; background: #f0f0f0; }
        h1 { color: #333; }
        .stat { background: white; padding: 20px; margin: 10px 0; border-radius: 8px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
    </style>
</head>
<body>
    <h1>Dashboard</h1>
    <div class="stat">
        <h3>System Status: Online</h3>
        <p>Version: $($config.version)</p>
        <p>Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    </div>
    <a href="/">← Back to Home</a>
</body>
</html>
"@
            }
            default {
                $response.StatusCode = 404
                $responseString = "<html><body><h1>404 - Not Found</h1><p>$url</p></body></html>"
            }
        }

        $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseString)
        $response.ContentLength64 = $buffer.Length
        $response.ContentType = $contentType
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.Close()
    }
}
catch {
    Write-MSPLog "Error starting web interface: $_" -Level ERROR
    Show-MSPError -Message "Failed to start web interface" -Details $_.Exception.Message
}
finally {
    if ($listener.IsListening) {
        $listener.Stop()
        $listener.Close()
    }
    Write-MSPLog "Web interface stopped" -Level INFO
}
