<#
.SYNOPSIS
    MSP Toolkit - Epic Main Launcher
.DESCRIPTION
    Interactive menu system for the MSP Tier 3 Toolkit with search, favorites, and remote execution
.NOTES
    Author: MSP Toolkit Team
    Version: 2.0.0
#>

[CmdletBinding()]
param(
    [switch]$SkipBanner,
    [switch]$DirectMode,
    [string]$Script
)

# Set error handling
$ErrorActionPreference = 'Continue'

# Import core modules with error handling
try {
    $CorePath = "$PSScriptRoot\Core"

    if (Test-Path "$CorePath\MSPToolkit.Config.psm1") {
        Import-Module "$CorePath\MSPToolkit.Config.ps1" -Force -ErrorAction Stop
    }

    if (Test-Path "$CorePath\MSPToolkit.Logging.psm1") {
        Import-Module "$CorePath\MSPToolkit.Logging.psm1" -Force -ErrorAction Stop
    }

    if (Test-Path "$CorePath\MSPToolkit.Remote.psm1") {
        Import-Module "$CorePath\MSPToolkit.Remote.psm1" -Force -ErrorAction Stop
    }

    # Initialize
    if (Get-Command Initialize-MSPLogging -ErrorAction SilentlyContinue) {
        Initialize-MSPLogging -ScriptName "Launcher" -ErrorAction SilentlyContinue
    }

    if (Get-Command Get-MSPConfig -ErrorAction SilentlyContinue) {
        $config = Get-MSPConfig
    }

    if (Get-Command Initialize-MSPDirectories -ErrorAction SilentlyContinue) {
        Initialize-MSPDirectories -ErrorAction SilentlyContinue
    }
}
catch {
    Write-Warning "Some modules failed to load. Basic functionality will be available."
    Write-Warning "Error: $_"
}

# Fallback functions if modules didn't load
if (-not (Get-Command Write-MSPLog -ErrorAction SilentlyContinue)) {
    function Write-MSPLog {
        param([string]$Message, [string]$Level = "INFO")

        $color = switch ($Level) {
            "SUCCESS" { "Green" }
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "HEADER" { "Cyan" }
            default { "White" }
        }

        $icon = switch ($Level) {
            "SUCCESS" { "✓" }
            "ERROR" { "✗" }
            "WARNING" { "⚠" }
            "INFO" { "ℹ" }
            "HEADER" { "" }
            default { "•" }
        }

        if ($Level -eq "HEADER") {
            Write-Host ""
            Write-Host ("═" * 80) -ForegroundColor $color
            Write-Host " $Message" -ForegroundColor $color
            Write-Host ("═" * 80) -ForegroundColor $color
            Write-Host ""
        } else {
            Write-Host "$icon " -NoNewline -ForegroundColor $color
            Write-Host $Message -ForegroundColor White
        }
    }
}

if (-not (Get-Command Show-MSPBanner -ErrorAction SilentlyContinue)) {
    function Show-MSPBanner {
        $banner = @"

    ███╗   ███╗███████╗██████╗     ████████╗ ██████╗  ██████╗ ██╗     ██╗  ██╗██╗████████╗
    ████╗ ████║██╔════╝██╔══██╗    ╚══██╔══╝██╔═══██╗██╔═══██╗██║     ██║ ██╔╝██║╚══██╔══╝
    ██╔████╔██║███████╗██████╔╝       ██║   ██║   ██║██║   ██║██║     █████╔╝ ██║   ██║
    ██║╚██╔╝██║╚════██║██╔═══╝        ██║   ██║   ██║██║   ██║██║     ██╔═██╗ ██║   ██║
    ██║ ╚═╝ ██║███████║██║            ██║   ╚██████╔╝╚██████╔╝███████╗██║  ██╗██║   ██║
    ╚═╝     ╚═╝╚══════╝╚═╝            ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝   ╚═╝

              ╔════════════════════════════════════════════════════════════╗
              ║        TIER 3 SUPPORT AUTOMATION PLATFORM v2.0.0           ║
              ║              Dazzle. Automate. Dominate.                  ║
              ╚════════════════════════════════════════════════════════════╝

"@
        Write-Host $banner -ForegroundColor Cyan
        Write-Host "  Timestamp:  " -NoNewline -ForegroundColor Gray
        Write-Host (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -ForegroundColor Yellow
        Write-Host ""
    }
}

if (-not (Get-Command Show-MSPError -ErrorAction SilentlyContinue)) {
    function Show-MSPError {
        param([string]$Message, [string]$Details = "")

        Write-Host ""
        Write-Host "  ╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Red
        Write-Host "  ║                      ✗ ERROR ✗                           ║" -ForegroundColor Red
        Write-Host "  ╠═══════════════════════════════════════════════════════════╣" -ForegroundColor Red
        $msgPadded = $Message.PadRight(55)
        if ($msgPadded.Length -gt 55) { $msgPadded = $msgPadded.Substring(0, 55) }
        Write-Host "  ║  $msgPadded  ║" -ForegroundColor Red
        if ($Details) {
            Write-Host "  ║                                                           ║" -ForegroundColor Red
            $detailsPadded = $Details.Substring(0, [Math]::Min(47, $Details.Length)).PadRight(47)
            Write-Host "  ║  Details: $detailsPadded  ║" -ForegroundColor Red
        }
        Write-Host "  ╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Red
        Write-Host ""
    }
}

if (-not (Get-Command Show-MSPSuccess -ErrorAction SilentlyContinue)) {
    function Show-MSPSuccess {
        param([string]$Message)

        Write-Host ""
        Write-Host "  ╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "  ║                     ✓ SUCCESS ✓                          ║" -ForegroundColor Green
        Write-Host "  ╠═══════════════════════════════════════════════════════════╣" -ForegroundColor Green
        $msgPadded = $Message.PadRight(55)
        if ($msgPadded.Length -gt 55) { $msgPadded = $msgPadded.Substring(0, 55) }
        Write-Host "  ║  $msgPadded  ║" -ForegroundColor Green
        Write-Host "  ╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Host ""
    }
}

if (-not (Get-Command Test-MSPAdminRights -ErrorAction SilentlyContinue)) {
    function Test-MSPAdminRights {
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
}

# Script catalog with categories
$Script:ToolCatalog = @(
    # Diagnostics & Reporting
    @{
        ID = 1
        Name = "System Health Report"
        Description = "Generate comprehensive system health report"
        Category = "Diagnostics"
        Path = "MSP_Tier3_Toolkit\SystemHealthReport.ps1"
        Icon = "📊"
        RequiresAdmin = $false
        SupportsRemote = $true
    },
    @{
        ID = 2
        Name = "Boot Time Analyzer"
        Description = "Analyze boot and shutdown times from Event Logs"
        Category = "Diagnostics"
        Path = "MSP_Tier3_Toolkit\BootTimeAnalyzer.ps1"
        Icon = "⏱️"
        RequiresAdmin = $false
        SupportsRemote = $true
    },
    @{
        ID = 3
        Name = "Client System Summary"
        Description = "Generate HTML system summary for clients"
        Category = "Diagnostics"
        Path = "MSP_Tier3_Toolkit\ClientSystemSummary.ps1"
        Icon = "📄"
        RequiresAdmin = $false
        SupportsRemote = $true
    },

    # Active Directory
    @{
        ID = 4
        Name = "Check AD User Status"
        Description = "Check user lockout and password status"
        Category = "Active Directory"
        Path = "MSP_Tier3_Toolkit\CheckADUserStatus.ps1"
        Icon = "👤"
        RequiresAdmin = $false
        SupportsRemote = $false
    },

    # Microsoft 365
    @{
        ID = 5
        Name = "M365 User Provisioning"
        Description = "Provision Office 365 licenses for users"
        Category = "Microsoft 365"
        Path = "MSP_Tier3_Toolkit\M365UserProvisioning.ps1"
        Icon = "☁️"
        RequiresAdmin = $false
        SupportsRemote = $false
    },

    # Maintenance & Cleanup
    @{
        ID = 6
        Name = "Cleanup Old Profiles"
        Description = "Remove user profiles older than 30 days"
        Category = "Maintenance"
        Path = "MSP_Tier3_Toolkit\CleanupOldProfiles.ps1"
        Icon = "🧹"
        RequiresAdmin = $true
        SupportsRemote = $true
    },
    @{
        ID = 7
        Name = "Comprehensive Cleanup"
        Description = "Full system cleanup with logging"
        Category = "Maintenance"
        Path = "Cleanup Script\Cleanup-Auto.ps1"
        Icon = "🗑️"
        RequiresAdmin = $true
        SupportsRemote = $true
    },

    # Print Spooler
    @{
        ID = 8
        Name = "Printer Spooler Fix"
        Description = "Fix stuck print jobs and restart spooler"
        Category = "Print Management"
        Path = "MSP_Tier3_Toolkit\PrinterSpoolerFix.ps1"
        Icon = "🖨️"
        RequiresAdmin = $true
        SupportsRemote = $true
    },
    @{
        ID = 9
        Name = "Spooler Monitor Setup"
        Description = "Deploy automatic spooler monitoring"
        Category = "Print Management"
        Path = "Auto-Check and Start Printer Spooler\CheckAndStart-Spooler.ps1"
        Icon = "👁️"
        RequiresAdmin = $true
        SupportsRemote = $true
    },

    # Network & Software
    @{
        ID = 10
        Name = "Fix Mapped Drives"
        Description = "Test and repair network drive mappings"
        Category = "Network"
        Path = "MSP_Tier3_Toolkit\FixMappedDrives.ps1"
        Icon = "🔌"
        RequiresAdmin = $false
        SupportsRemote = $true
    },
    @{
        ID = 11
        Name = "Remote Software Uninstall"
        Description = "Uninstall software silently"
        Category = "Software"
        Path = "MSP_Tier3_Toolkit\RemoteUninstall.ps1"
        Icon = "📦"
        RequiresAdmin = $true
        SupportsRemote = $true
    },

    # Windows Update
    @{
        ID = 12
        Name = "Windows Update Fix"
        Description = "Reset Windows Update components"
        Category = "Windows Update"
        Path = "MSP_Tier3_Toolkit\WindowsUpdateFix.ps1"
        Icon = "🔄"
        RequiresAdmin = $true
        SupportsRemote = $true
    }
)

# Recently used scripts tracking
$Script:RecentsFile = "$env:TEMP\msp-recents.json"
$Script:Recents = @()
if (Test-Path $Script:RecentsFile) {
    try {
        $Script:Recents = Get-Content $Script:RecentsFile -ErrorAction SilentlyContinue | ConvertFrom-Json
    } catch {
        $Script:Recents = @()
    }
}

function Show-MainMenu {
    Clear-Host

    if (-not $SkipBanner) {
        Show-MSPBanner
    }

    # System info bar
    $isAdmin = Test-MSPAdminRights

    Write-Host "  ┌─────────────────────────────────────────────────────────────────────────────┐" -ForegroundColor DarkGray
    Write-Host "  │ " -NoNewline -ForegroundColor DarkGray
    Write-Host "Computer: " -NoNewline -ForegroundColor Gray
    Write-Host "$env:COMPUTERNAME" -NoNewline -ForegroundColor White
    Write-Host " | " -NoNewline -ForegroundColor DarkGray
    Write-Host "User: " -NoNewline -ForegroundColor Gray
    Write-Host "$env:USERNAME" -NoNewline -ForegroundColor White
    Write-Host " | " -NoNewline -ForegroundColor DarkGray
    Write-Host "Admin: " -NoNewline -ForegroundColor Gray
    $adminStatus = if ($isAdmin) { "Yes" } else { "No" }
    $adminColor = if ($isAdmin) { "Green" } else { "Yellow" }
    Write-Host "$adminStatus" -NoNewline -ForegroundColor $adminColor

    $padding = 68 - $env:COMPUTERNAME.Length - $env:USERNAME.Length - $adminStatus.Length
    if ($padding -gt 0) {
        Write-Host (" " * $padding) -NoNewline
    }
    Write-Host "│" -ForegroundColor DarkGray
    Write-Host "  └─────────────────────────────────────────────────────────────────────────────┘" -ForegroundColor DarkGray
    Write-Host ""

    # Categories
    $categories = $Script:ToolCatalog | Group-Object Category | Sort-Object Name

    foreach ($category in $categories) {
        Write-Host "  ╔═══ " -NoNewline -ForegroundColor Cyan
        Write-Host $category.Name.ToUpper() -NoNewline -ForegroundColor Yellow
        Write-Host " ═══╗" -ForegroundColor Cyan
        Write-Host ""

        foreach ($tool in $category.Group | Sort-Object ID) {
            $idText = "[$($tool.ID.ToString().PadLeft(2))]"
            Write-Host "    $idText " -NoNewline -ForegroundColor White
            Write-Host "$($tool.Icon)  " -NoNewline
            Write-Host $tool.Name -NoNewline -ForegroundColor Cyan

            if ($tool.RequiresAdmin) {
                Write-Host " [ADMIN]" -NoNewline -ForegroundColor Red
            }
            if ($tool.SupportsRemote) {
                Write-Host " [REMOTE]" -NoNewline -ForegroundColor Green
            }

            Write-Host ""
            Write-Host "        $($tool.Description)" -ForegroundColor Gray
            Write-Host ""
        }
    }

    # Special options
    Write-Host "  ╔═══ " -NoNewline -ForegroundColor Magenta
    Write-Host "SPECIAL OPTIONS" -NoNewline -ForegroundColor Yellow
    Write-Host " ═══╗" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "    [D]  " -NoNewline -ForegroundColor White
    Write-Host "📈 Dashboard & Reports" -ForegroundColor Cyan
    Write-Host "    [U]  " -NoNewline -ForegroundColor White
    Write-Host "🔄 Check for Updates" -ForegroundColor Cyan
    Write-Host "    [S]  " -NoNewline -ForegroundColor White
    Write-Host "⚙️  Settings & Configuration" -ForegroundColor Cyan
    Write-Host "    [H]  " -NoNewline -ForegroundColor White
    Write-Host "❓ Help & Documentation" -ForegroundColor Cyan
    Write-Host "    [Q]  " -NoNewline -ForegroundColor White
    Write-Host "❌ Quit" -ForegroundColor Cyan
    Write-Host ""

    if ($Script:Recents.Count -gt 0) {
        Write-Host "  ╔═══ " -NoNewline -ForegroundColor Yellow
        Write-Host "RECENTLY USED" -NoNewline -ForegroundColor Yellow
        Write-Host " ═══╗" -ForegroundColor Yellow
        Write-Host ""
        $recentTools = $Script:ToolCatalog | Where-Object { $_.ID -in $Script:Recents[0..4] }
        foreach ($tool in $recentTools) {
            Write-Host "    ⭐ " -NoNewline
            Write-Host "$($tool.Icon) $($tool.Name)" -ForegroundColor Gray
        }
        Write-Host ""
    }

    Write-Host "  ════════════════════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
    Write-Host ""
}

function Add-ToRecents {
    param([int]$ToolID)

    # Remove if already in list
    $Script:Recents = @($Script:Recents | Where-Object { $_ -ne $ToolID })

    # Add to front
    $Script:Recents = @($ToolID) + $Script:Recents

    # Keep only last 10
    if ($Script:Recents.Count -gt 10) {
        $Script:Recents = $Script:Recents[0..9]
    }

    # Save
    $Script:Recents | ConvertTo-Json | Set-Content $Script:RecentsFile
}

function Invoke-Tool {
    param(
        [int]$ToolID,
        [string]$ComputerName = $null
    )

    $tool = $Script:ToolCatalog | Where-Object { $_.ID -eq $ToolID }

    if (-not $tool) {
        Show-MSPError -Message "Invalid tool ID: $ToolID"
        return
    }

    # Check admin requirements
    if ($tool.RequiresAdmin -and -not (Test-MSPAdminRights)) {
        Show-MSPError -Message "This tool requires administrator privileges!" -Details "Please restart the launcher as Administrator"
        Read-Host "Press Enter to continue"
        return
    }

    # Build full path
    $scriptPath = Join-Path $PSScriptRoot $tool.Path

    if (-not (Test-Path $scriptPath)) {
        Show-MSPError -Message "Script not found!" -Details $scriptPath
        Read-Host "Press Enter to continue"
        return
    }

    Add-ToRecents -ToolID $ToolID

    Clear-Host
    Write-MSPLog "═══ Executing: $($tool.Name) ═══" -Level HEADER

    try {
        if ($ComputerName -and $tool.SupportsRemote) {
            Write-MSPLog "Executing on remote computer: $ComputerName" -Level INFO
            Invoke-MSPRemoteScriptFile -ComputerName $ComputerName -ScriptPath $scriptPath
        } else {
            & $scriptPath
        }

        Write-Host ""
        Show-MSPSuccess -Message "Tool execution completed!"
    }
    catch {
        Write-MSPLog "Error executing tool: $_" -Level ERROR
        Show-MSPError -Message "Tool execution failed!" -Details $_.Exception.Message
    }

    Write-Host ""
    Read-Host "Press Enter to return to main menu"
}

function Show-Dashboard {
    Clear-Host
    Write-MSPLog "═══ MSP Toolkit Dashboard ═══" -Level HEADER

    Write-Host "  Loading dashboard..." -ForegroundColor Cyan
    Write-Host ""

    # Call dashboard script
    $dashboardScript = Join-Path $PSScriptRoot "Tools\Generate-Dashboard.ps1"
    if (Test-Path $dashboardScript) {
        & $dashboardScript
    } else {
        Write-MSPLog "Dashboard script not found. Generating basic statistics..." -Level WARNING
        Write-Host ""

        # Show basic stats
        Write-Host "  Total Tools Available: " -NoNewline -ForegroundColor Gray
        Write-Host $Script:ToolCatalog.Count -ForegroundColor Green
        Write-Host "  Recently Used: " -NoNewline -ForegroundColor Gray
        Write-Host $Script:Recents.Count -ForegroundColor Green

        $logDir = $config.paths.logs
        if (Test-Path $logDir) {
            $logCount = (Get-ChildItem -Path $logDir -Filter "*.log" | Measure-Object).Count
            Write-Host "  Log Files: " -NoNewline -ForegroundColor Gray
            Write-Host $logCount -ForegroundColor Green
        }
    }

    Write-Host ""
    Read-Host "Press Enter to return to main menu"
}

function Show-Settings {
    Clear-Host
    Write-MSPLog "═══ Settings & Configuration ═══" -Level HEADER

    Write-Host ""
    Write-Host "  Current Configuration:" -ForegroundColor Cyan
    Write-Host "  ─────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Company Name:     " -NoNewline -ForegroundColor Gray
    Write-Host $config.company.name -ForegroundColor White
    Write-Host "  Log Directory:    " -NoNewline -ForegroundColor Gray
    Write-Host $config.paths.logs -ForegroundColor White
    Write-Host "  Auto Updates:     " -NoNewline -ForegroundColor Gray
    Write-Host $config.updates.autoCheckForUpdates -ForegroundColor White
    Write-Host "  Auto Healing:     " -NoNewline -ForegroundColor Gray
    Write-Host $config.monitoring.autoHealEnabled -ForegroundColor White
    Write-Host "  Web Interface:    " -NoNewline -ForegroundColor Gray
    Write-Host $config.webInterface.enabled -ForegroundColor White
    Write-Host ""

    Write-Host "  To modify settings, edit: " -NoNewline -ForegroundColor Gray
    Write-Host "config.json" -ForegroundColor Yellow
    Write-Host ""

    Read-Host "Press Enter to return to main menu"
}

function Show-RemoteMode {
    Clear-Host
    Write-MSPLog "═══ Remote Execution Mode ═══" -Level HEADER

    Write-Host ""
    Write-Host "  Enter target computer name(s):" -ForegroundColor Cyan
    Write-Host "  (separate multiple with commas, or path to CSV file)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  > " -NoNewline -ForegroundColor Yellow

    $input = Read-Host

    if ([string]::IsNullOrWhiteSpace($input)) {
        return
    }

    $computers = @()

    # Check if CSV file
    if ($input.EndsWith('.csv') -and (Test-Path $input)) {
        $computers = Import-MSPComputerList -Path $input
    } else {
        $computers = $input -split ',' | ForEach-Object { $_.Trim() }
    }

    Write-Host ""
    Write-MSPLog "Testing connectivity to $($computers.Count) computer(s)..." -Level INFO

    $status = Get-MSPRemoteComputerStatus -ComputerName $computers

    Write-Host ""
    Write-MSPTable -Data $status -Title "Connection Status"

    $online = $status | Where-Object { $_.WSManAvailable }

    if ($online.Count -eq 0) {
        Show-MSPError -Message "No computers are available for remote execution"
        Read-Host "Press Enter to return to main menu"
        return
    }

    Write-Host ""
    Write-Host "  Select a tool to execute remotely (or Q to cancel): " -NoNewline -ForegroundColor Cyan
    $toolChoice = Read-Host

    if ($toolChoice -eq 'Q') {
        return
    }

    [int]$toolID = 0
    if ([int]::TryParse($toolChoice, [ref]$toolID)) {
        foreach ($comp in $online.ComputerName) {
            Invoke-Tool -ToolID $toolID -ComputerName $comp
        }
    }
}

function Start-UpdateCheck {
    Clear-Host
    Write-MSPLog "═══ Checking for Updates ═══" -Level HEADER

    Write-Host ""
    $updateScript = Join-Path $PSScriptRoot "Tools\Update-MSPToolkit.ps1"

    if (Test-Path $updateScript) {
        & $updateScript
    } else {
        Write-MSPLog "Update script not found at: $updateScript" -Level WARNING
        Write-MSPLog "Current version: $($config.version)" -Level INFO
    }

    Write-Host ""
    Read-Host "Press Enter to return to main menu"
}

function Show-KnowledgeBase {
    Clear-Host
    Write-MSPLog "═══ Team Knowledge Base ═══" -Level HEADER

    Write-Host ""
    $kbScript = Join-Path $PSScriptRoot "Tools\Show-KnowledgeBase.ps1"

    if (Test-Path $kbScript) {
        & $kbScript
    } else {
        Write-MSPLog "Knowledge Base not yet configured" -Level WARNING
        Write-Host "  The Knowledge Base allows your team to:" -ForegroundColor Gray
        Write-Host "  • Share tips and tricks for each tool" -ForegroundColor Gray
        Write-Host "  • Document edge cases and solutions" -ForegroundColor Gray
        Write-Host "  • Build institutional knowledge" -ForegroundColor Gray
    }

    Write-Host ""
    Read-Host "Press Enter to return to main menu"
}

function Start-WebInterface {
    Clear-Host
    Write-MSPLog "═══ Starting Web Interface ═══" -Level HEADER

    Write-Host ""
    $webScript = Join-Path $PSScriptRoot "Tools\Start-WebInterface.ps1"

    if (Test-Path $webScript) {
        & $webScript
    } else {
        Write-MSPLog "Web interface not yet configured" -Level WARNING
        Write-Host "  The web interface will allow you to:" -ForegroundColor Gray
        Write-Host "  • Access toolkit from any browser" -ForegroundColor Gray
        Write-Host "  • Execute scripts remotely" -ForegroundColor Gray
        Write-Host "  • View logs and reports" -ForegroundColor Gray
        Write-Host "  • Perfect for help desk teams" -ForegroundColor Gray
    }

    Write-Host ""
    Read-Host "Press Enter to return to main menu"
}

# Main loop
do {
    Show-MainMenu

    Write-Host "  Select an option: " -NoNewline -ForegroundColor Yellow
    $choice = Read-Host

    switch -Regex ($choice) {
        '^[0-9]+$' {
            [int]$toolID = [int]$choice
            if ($toolID -ge 1 -and $toolID -le $Script:ToolCatalog.Count) {
                Invoke-Tool -ToolID $toolID
            } else {
                Show-MSPError -Message "Invalid selection: $choice"
                Start-Sleep -Seconds 2
            }
        }
        '^[Dd]$' { Show-Dashboard }
        '^[Uu]$' { Start-UpdateCheck }
        '^[Ss]$' { Show-Settings }
        '^[Rr]$' { Show-RemoteMode }
        '^[Kk]$' { Show-KnowledgeBase }
        '^[Ww]$' { Start-WebInterface }
        '^[Qq]$' {
            Clear-Host
            Write-Host ""
            Write-Host "  ╔════════════════════════════════════════════════════╗" -ForegroundColor Cyan
            Write-Host "  ║                                                    ║" -ForegroundColor Cyan
            Write-Host "  ║        Thanks for using MSP Toolkit! 🚀           ║" -ForegroundColor Cyan
            Write-Host "  ║                                                    ║" -ForegroundColor Cyan
            Write-Host "  ╚════════════════════════════════════════════════════╝" -ForegroundColor Cyan
            Write-Host ""
            exit
        }
        default {
            Show-MSPError -Message "Invalid selection: $choice"
            Start-Sleep -Seconds 2
        }
    }
} while ($true)
