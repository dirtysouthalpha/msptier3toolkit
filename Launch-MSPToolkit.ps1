<#
.SYNOPSIS
    MSP Toolkit - Standalone Launcher (No Dependencies!)
.DESCRIPTION
    Interactive menu system for the MSP Tier 3 Toolkit - Works out of the box!
.NOTES
    Author: MSP Toolkit Team
    Version: 2.0.0
    Requirements: PowerShell 5.1+ (Built into Windows 10/11)
#>

[CmdletBinding()]
param(
    [switch]$SkipBanner
)

# Core functions - No external dependencies!
function Show-Banner {
    $banner = @"

    ███╗   ███╗███████╗██████╗     ████████╗ ██████╗  ██████╗ ██╗     ██╗  ██╗██╗████████╗
    ████╗ ████║██╔════╝██╔══██╗    ╚══██╔══╝██╔═══██╗██╔═══██╗██║     ██║ ██╔╝██║╚══██╔══╝
    ██╔████╔██║███████╗██████╔╝       ██║   ██║   ██║██║   ██║██║     █████╔╝ ██║   ██║
    ██║╚██╔╝██║╚════██║██╔═══╝        ██║   ██║   ██║██║   ██║██║     ██╔═██╗ ██║   ██║
    ██║ ╚═╝ ██║███████║██║            ██║   ╚██████╔╝╚██████╔╝███████╗██║  ██╗██║   ██║
    ╚═╝     ╚═╝╚══════╝╚═╝            ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝   ╚═╝

              ╔════════════════════════════════════════════════════════════╗
              ║        TIER 3 SUPPORT AUTOMATION PLATFORM v2.0             ║
              ║              Dazzle. Automate. Dominate.                  ║
              ╚════════════════════════════════════════════════════════════╝

"@
    Write-Host $banner -ForegroundColor Cyan
    Write-Host "  Computer: " -NoNewline -ForegroundColor Gray
    Write-Host $env:COMPUTERNAME -NoNewline -ForegroundColor White
    Write-Host " | User: " -NoNewline -ForegroundColor Gray
    Write-Host $env:USERNAME -NoNewline -ForegroundColor White
    Write-Host " | " -NoNewline -ForegroundColor Gray
    Write-Host (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -ForegroundColor Yellow
    Write-Host ""
}

function Test-AdminRights {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-ColorMessage {
    param(
        [string]$Message,
        [string]$Type = "INFO"
    )

    $icon = switch ($Type) {
        "SUCCESS" { "✓"; $color = "Green" }
        "ERROR" { "✗"; $color = "Red" }
        "WARNING" { "⚠"; $color = "Yellow" }
        "INFO" { "ℹ"; $color = "Cyan" }
        default { "•"; $color = "White" }
    }

    Write-Host "$icon " -NoNewline -ForegroundColor $color
    Write-Host $Message -ForegroundColor White
}

function Show-SuccessBox {
    param([string]$Message)
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║                     ✓ SUCCESS ✓                          ║" -ForegroundColor Green
    Write-Host "  ╠═══════════════════════════════════════════════════════════╣" -ForegroundColor Green
    $padded = $Message.PadRight(55).Substring(0, 55)
    Write-Host "  ║  $padded  ║" -ForegroundColor Green
    Write-Host "  ╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
}

function Show-ErrorBox {
    param([string]$Message, [string]$Details = "")
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "  ║                      ✗ ERROR ✗                           ║" -ForegroundColor Red
    Write-Host "  ╠═══════════════════════════════════════════════════════════╣" -ForegroundColor Red
    $padded = $Message.PadRight(55).Substring(0, 55)
    Write-Host "  ║  $padded  ║" -ForegroundColor Red
    if ($Details) {
        Write-Host "  ║                                                           ║" -ForegroundColor Red
        $detailPadded = ("Details: " + $Details).PadRight(55).Substring(0, 55)
        Write-Host "  ║  $detailPadded  ║" -ForegroundColor Red
    }
    Write-Host "  ╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
}

# Script catalog
$Script:ToolCatalog = @(
    @{
        ID = 1
        Name = "System Health Report"
        Description = "Generate comprehensive system health report"
        Category = "Diagnostics"
        Path = "MSP_Tier3_Toolkit\SystemHealthReport.ps1"
        Icon = "📊"
        RequiresAdmin = $false
    },
    @{
        ID = 2
        Name = "Boot Time Analyzer"
        Description = "Analyze boot and shutdown times from Event Logs"
        Category = "Diagnostics"
        Path = "MSP_Tier3_Toolkit\BootTimeAnalyzer.ps1"
        Icon = "⏱️"
        RequiresAdmin = $false
    },
    @{
        ID = 3
        Name = "Client System Summary"
        Description = "Generate HTML system summary for clients"
        Category = "Diagnostics"
        Path = "MSP_Tier3_Toolkit\ClientSystemSummary.ps1"
        Icon = "📄"
        RequiresAdmin = $false
    },
    @{
        ID = 4
        Name = "Check AD User Status"
        Description = "Check user lockout and password status"
        Category = "Active Directory"
        Path = "MSP_Tier3_Toolkit\CheckADUserStatus.ps1"
        Icon = "👤"
        RequiresAdmin = $false
    },
    @{
        ID = 5
        Name = "M365 User Provisioning"
        Description = "Provision Office 365 licenses for users"
        Category = "Microsoft 365"
        Path = "MSP_Tier3_Toolkit\M365UserProvisioning.ps1"
        Icon = "☁️"
        RequiresAdmin = $false
    },
    @{
        ID = 6
        Name = "Cleanup Old Profiles"
        Description = "Remove user profiles older than 30 days"
        Category = "Maintenance"
        Path = "MSP_Tier3_Toolkit\CleanupOldProfiles.ps1"
        Icon = "🧹"
        RequiresAdmin = $true
    },
    @{
        ID = 7
        Name = "Comprehensive Cleanup"
        Description = "Full system cleanup with logging"
        Category = "Maintenance"
        Path = "Cleanup Script\Cleanup-Auto.ps1"
        Icon = "🗑️"
        RequiresAdmin = $true
    },
    @{
        ID = 8
        Name = "Printer Spooler Fix"
        Description = "Fix stuck print jobs and restart spooler"
        Category = "Print Management"
        Path = "MSP_Tier3_Toolkit\PrinterSpoolerFix.ps1"
        Icon = "🖨️"
        RequiresAdmin = $true
    },
    @{
        ID = 9
        Name = "Spooler Monitor Setup"
        Description = "Deploy automatic spooler monitoring"
        Category = "Print Management"
        Path = "Auto-Check and Start Printer Spooler\CheckAndStart-Spooler.ps1"
        Icon = "👁️"
        RequiresAdmin = $true
    },
    @{
        ID = 10
        Name = "Fix Mapped Drives"
        Description = "Test and repair network drive mappings"
        Category = "Network"
        Path = "MSP_Tier3_Toolkit\FixMappedDrives.ps1"
        Icon = "🔌"
        RequiresAdmin = $false
    },
    @{
        ID = 11
        Name = "Remote Software Uninstall"
        Description = "Uninstall software silently"
        Category = "Software"
        Path = "MSP_Tier3_Toolkit\RemoteUninstall.ps1"
        Icon = "📦"
        RequiresAdmin = $true
    },
    @{
        ID = 12
        Name = "Windows Update Fix"
        Description = "Reset Windows Update components"
        Category = "Windows Update"
        Path = "MSP_Tier3_Toolkit\WindowsUpdateFix.ps1"
        Icon = "🔄"
        RequiresAdmin = $true
    }
)

# Recently used tracking (simple file in TEMP)
$Script:RecentsFile = Join-Path $env:TEMP "msp-toolkit-recents.json"
$Script:Recents = @()
if (Test-Path $Script:RecentsFile) {
    try {
        $content = Get-Content $Script:RecentsFile -Raw -ErrorAction SilentlyContinue
        if ($content) {
            $Script:Recents = $content | ConvertFrom-Json
        }
    } catch {
        $Script:Recents = @()
    }
}

function Add-ToRecents {
    param([int]$ToolID)

    # Remove if exists
    $Script:Recents = @($Script:Recents | Where-Object { $_ -ne $ToolID })

    # Add to front
    $Script:Recents = @($ToolID) + $Script:Recents

    # Keep only 10
    if ($Script:Recents.Count -gt 10) {
        $Script:Recents = $Script:Recents[0..9]
    }

    # Save
    try {
        $Script:Recents | ConvertTo-Json | Set-Content $Script:RecentsFile -ErrorAction SilentlyContinue
    } catch {
        # Ignore save errors
    }
}

function Show-MainMenu {
    Clear-Host

    if (-not $SkipBanner) {
        Show-Banner
    }

    # System info bar
    $isAdmin = Test-AdminRights
    $adminStatus = if ($isAdmin) { "✓ Admin" } else { "User" }
    $adminColor = if ($isAdmin) { "Green" } else { "Yellow" }

    Write-Host "  ┌─────────────────────────────────────────────────────────────────────────────┐" -ForegroundColor DarkGray
    Write-Host "  │ Status: " -NoNewline -ForegroundColor DarkGray
    Write-Host $adminStatus -NoNewline -ForegroundColor $adminColor
    Write-Host " | Computer: " -NoNewline -ForegroundColor DarkGray
    Write-Host $env:COMPUTERNAME -NoNewline -ForegroundColor White
    Write-Host " | User: " -NoNewline -ForegroundColor DarkGray
    Write-Host $env:USERNAME -NoNewline -ForegroundColor White

    # Calculate padding
    $textLength = $adminStatus.Length + $env:COMPUTERNAME.Length + $env:USERNAME.Length + 32
    $padding = 79 - $textLength
    if ($padding -gt 0) {
        Write-Host (" " * $padding) -NoNewline
    }
    Write-Host "│" -ForegroundColor DarkGray
    Write-Host "  └─────────────────────────────────────────────────────────────────────────────┘" -ForegroundColor DarkGray
    Write-Host ""

    # Show scripts by category
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
    Write-Host "    [H]  " -NoNewline -ForegroundColor White
    Write-Host "❓ Help & About" -ForegroundColor Cyan
    Write-Host "    [Q]  " -NoNewline -ForegroundColor White
    Write-Host "❌ Quit" -ForegroundColor Cyan
    Write-Host ""

    # Show recently used
    if ($Script:Recents.Count -gt 0) {
        Write-Host "  ╔═══ " -NoNewline -ForegroundColor Yellow
        Write-Host "RECENTLY USED" -NoNewline -ForegroundColor Yellow
        Write-Host " ═══╗" -ForegroundColor Yellow
        Write-Host ""
        $recentCount = [Math]::Min(5, $Script:Recents.Count)
        for ($i = 0; $i -lt $recentCount; $i++) {
            $recentTool = $Script:ToolCatalog | Where-Object { $_.ID -eq $Script:Recents[$i] }
            if ($recentTool) {
                Write-Host "    ⭐ " -NoNewline
                Write-Host "$($recentTool.Icon) $($recentTool.Name)" -ForegroundColor Gray
            }
        }
        Write-Host ""
    }

    Write-Host "  ════════════════════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
    Write-Host ""
}

function Invoke-Tool {
    param([int]$ToolID)

    $tool = $Script:ToolCatalog | Where-Object { $_.ID -eq $ToolID }

    if (-not $tool) {
        Show-ErrorBox -Message "Invalid tool ID: $ToolID"
        Start-Sleep -Seconds 2
        return
    }

    # Check admin requirements
    if ($tool.RequiresAdmin -and -not (Test-AdminRights)) {
        Show-ErrorBox -Message "Admin Rights Required!" -Details "Restart PowerShell as Administrator"
        Read-Host "`n  Press Enter to continue"
        return
    }

    # Build path
    $scriptPath = Join-Path $PSScriptRoot $tool.Path

    if (-not (Test-Path $scriptPath)) {
        Show-ErrorBox -Message "Script not found!" -Details $tool.Path
        Read-Host "`n  Press Enter to continue"
        return
    }

    # Add to recents
    Add-ToRecents -ToolID $ToolID

    # Execute
    Clear-Host
    Write-Host ""
    Write-Host ("═" * 80) -ForegroundColor Cyan
    Write-Host " Executing: $($tool.Name)" -ForegroundColor Cyan
    Write-Host ("═" * 80) -ForegroundColor Cyan
    Write-Host ""

    try {
        & $scriptPath
        Write-Host ""
        Show-SuccessBox -Message "Script completed!"
    }
    catch {
        Write-Host ""
        Show-ErrorBox -Message "Script failed!" -Details $_.Exception.Message
    }

    Write-Host ""
    Read-Host "Press Enter to return to menu"
}

function Show-Help {
    Clear-Host
    Write-Host ""
    Write-Host ("═" * 80) -ForegroundColor Cyan
    Write-Host " MSP Toolkit - Help & About" -ForegroundColor Cyan
    Write-Host ("═" * 80) -ForegroundColor Cyan
    Write-Host ""

    Write-Host "  📖 HOW TO USE" -ForegroundColor Yellow
    Write-Host "  ─────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  • Enter a number (1-12) to run a script" -ForegroundColor Gray
    Write-Host "  • Scripts marked [ADMIN] require administrator rights" -ForegroundColor Gray
    Write-Host "  • To run as admin: Right-click PowerShell → Run as Administrator" -ForegroundColor Gray
    Write-Host ""

    Write-Host "  🎯 QUICK TIPS" -ForegroundColor Yellow
    Write-Host "  ────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  • All scripts are standalone and safe to run" -ForegroundColor Gray
    Write-Host "  • Scripts are located in: MSP_Tier3_Toolkit folder" -ForegroundColor Gray
    Write-Host "  • Your recently used scripts appear at the bottom" -ForegroundColor Gray
    Write-Host "  • No installation or setup required!" -ForegroundColor Gray
    Write-Host ""

    Write-Host "  📝 ABOUT" -ForegroundColor Yellow
    Write-Host "  ───────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  MSP Tier 3 Toolkit v2.0" -ForegroundColor White
    Write-Host "  A collection of PowerShell automation scripts" -ForegroundColor Gray
    Write-Host "  for MSP technicians and system administrators" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  GitHub: github.com/dirtysouthalpha/msptier3toolkit" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "  💡 COMMON SCRIPTS" -ForegroundColor Yellow
    Write-Host "  ────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [1] System Health - Quick system diagnostics" -ForegroundColor Gray
    Write-Host "  [7] Cleanup - Free up disk space" -ForegroundColor Gray
    Write-Host "  [8] Fix Printer - Restart print spooler" -ForegroundColor Gray
    Write-Host "  [12] Windows Update - Fix update issues" -ForegroundColor Gray
    Write-Host ""

    Read-Host "Press Enter to return to menu"
}

# Main loop
Write-Host ""
Write-Host "  Loading MSP Toolkit..." -ForegroundColor Cyan

# Check if scripts exist
$scriptDir = Join-Path $PSScriptRoot "MSP_Tier3_Toolkit"
if (-not (Test-Path $scriptDir)) {
    Write-Host ""
    Show-ErrorBox -Message "Scripts folder not found!" -Details "Expected: MSP_Tier3_Toolkit"
    Write-Host "  Please run this from the toolkit root directory." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit
}

# Main menu loop
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
                Show-ErrorBox -Message "Invalid selection: $choice"
                Start-Sleep -Seconds 2
            }
        }
        '^[Hh]$' {
            Show-Help
        }
        '^[Qq]$' {
            Clear-Host
            Write-Host ""
            Write-Host "  ╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
            Write-Host "  ║                                                        ║" -ForegroundColor Cyan
            Write-Host "  ║        Thanks for using MSP Toolkit! 🚀               ║" -ForegroundColor Cyan
            Write-Host "  ║                                                        ║" -ForegroundColor Cyan
            Write-Host "  ╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
            Write-Host ""
            exit
        }
        default {
            Show-ErrorBox -Message "Invalid selection: $choice"
            Start-Sleep -Seconds 2
        }
    }
} while ($true)
