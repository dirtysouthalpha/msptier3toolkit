<#
.SYNOPSIS
    MSP Toolkit - Professional Installation Script
.DESCRIPTION
    One-click installation and setup for the MSP Tier 3 Toolkit
.NOTES
    Run as Administrator for full functionality
#>

[CmdletBinding()]
param(
    [switch]$SkipModuleInstall,
    [switch]$SkipScheduledTasks,
    [switch]$SkipShortcuts,
    [switch]$Uninstall
)

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

# Banner
function Show-InstallBanner {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║                                                              ║" -ForegroundColor Cyan
    Write-Host "  ║          MSP TOOLKIT INSTALLATION WIZARD                     ║" -ForegroundColor Cyan
    Write-Host "  ║                                                              ║" -ForegroundColor Cyan
    Write-Host "  ║          Automated Setup & Configuration                     ║" -ForegroundColor Cyan
    Write-Host "  ║                                                              ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param(
        [string]$Message,
        [string]$Status = "INFO"
    )

    $icon = switch ($Status) {
        "SUCCESS" { "✓" }
        "ERROR" { "✗" }
        "WARNING" { "⚠" }
        default { "➤" }
    }

    $color = switch ($Status) {
        "SUCCESS" { "Green" }
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        default { "Cyan" }
    }

    Write-Host "  $icon " -NoNewline -ForegroundColor $color
    Write-Host $Message -ForegroundColor White
}

function Install-Toolkit {
    Show-InstallBanner

    Write-Host "  This wizard will:" -ForegroundColor Yellow
    Write-Host "    • Create required directories" -ForegroundColor Gray
    Write-Host "    • Install PowerShell modules" -ForegroundColor Gray
    Write-Host "    • Set up scheduled tasks for monitoring" -ForegroundColor Gray
    Write-Host "    • Create desktop shortcuts" -ForegroundColor Gray
    Write-Host "    • Add toolkit to PATH" -ForegroundColor Gray
    Write-Host "    • Initialize configuration" -ForegroundColor Gray
    Write-Host ""

    Write-Host "  Continue with installation? (Y/N): " -NoNewline -ForegroundColor Yellow
    $confirm = Read-Host

    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Host ""
        Write-Step "Installation cancelled by user" "WARNING"
        return
    }

    Write-Host ""
    Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
    Write-Host ""

    # Get installation path
    $installPath = $PSScriptRoot

    # Step 1: Create directories
    Write-Step "Creating directory structure..." "INFO"

    $directories = @(
        "C:\MSPToolkit\Logs",
        "C:\MSPToolkit\Reports",
        "C:\MSPToolkit\Cache",
        "C:\MSPToolkit\Templates",
        "C:\MSPToolkit\KnowledgeBase",
        "C:\MSPToolkit\Backups"
    )

    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    Write-Step "Directories created successfully" "SUCCESS"

    # Step 2: Install required PowerShell modules
    if (-not $SkipModuleInstall) {
        Write-Step "Checking PowerShell modules..." "INFO"

        $requiredModules = @('ActiveDirectory', 'MSOnline')

        foreach ($module in $requiredModules) {
            try {
                if (-not (Get-Module -ListAvailable -Name $module)) {
                    Write-Step "  Installing $module module..." "INFO"
                    Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser -ErrorAction SilentlyContinue
                    Write-Step "  $module installed" "SUCCESS"
                } else {
                    Write-Step "  $module already installed" "SUCCESS"
                }
            }
            catch {
                Write-Step "  Failed to install $module (may require manual installation)" "WARNING"
            }
        }
    }

    # Step 3: Add to PATH
    Write-Step "Adding toolkit to system PATH..." "INFO"

    $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($currentPath -notlike "*$installPath*") {
        [Environment]::SetEnvironmentVariable("Path", "$currentPath;$installPath", "Machine")
        Write-Step "Added to PATH" "SUCCESS"
    } else {
        Write-Step "Already in PATH" "SUCCESS"
    }

    # Step 4: Create desktop shortcuts
    if (-not $SkipShortcuts) {
        Write-Step "Creating desktop shortcuts..." "INFO"

        $WshShell = New-Object -ComObject WScript.Shell

        # Main launcher shortcut
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $shortcutPath = Join-Path $desktopPath "MSP Toolkit.lnk"
        $shortcut = $WshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "powershell.exe"
        $shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$installPath\Start-MSPToolkit.ps1`""
        $shortcut.WorkingDirectory = $installPath
        $shortcut.Description = "MSP Tier 3 Automation Toolkit"
        $shortcut.IconLocation = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe,0"
        $shortcut.Save()

        Write-Step "Desktop shortcut created" "SUCCESS"
    }

    # Step 5: Create scheduled tasks for monitoring
    if (-not $SkipScheduledTasks) {
        Write-Step "Setting up scheduled tasks..." "INFO"

        # Self-healing task
        try {
            $action = New-ScheduledTaskAction -Execute "powershell.exe" `
                -Argument "-ExecutionPolicy Bypass -File `"$installPath\Tools\Start-SelfHealing.ps1`" -RunOnce"

            $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration ([TimeSpan]::MaxValue)

            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

            Register-ScheduledTask -TaskName "MSPToolkit-SelfHealing" `
                -Action $action `
                -Trigger $trigger `
                -Principal $principal `
                -Settings $settings `
                -Description "MSP Toolkit Self-Healing Automation" `
                -Force | Out-Null

            Write-Step "  Self-healing task created" "SUCCESS"
        }
        catch {
            Write-Step "  Failed to create self-healing task: $_" "WARNING"
        }

        # Daily cleanup task
        try {
            $action = New-ScheduledTaskAction -Execute "powershell.exe" `
                -Argument "-ExecutionPolicy Bypass -File `"$installPath\Cleanup Script\Cleanup-Auto.ps1`""

            $trigger = New-ScheduledTaskTrigger -Daily -At "2:00AM"

            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

            Register-ScheduledTask -TaskName "MSPToolkit-DailyCleanup" `
                -Action $action `
                -Trigger $trigger `
                -Principal $principal `
                -Description "MSP Toolkit Daily System Cleanup" `
                -Force | Out-Null

            Write-Step "  Daily cleanup task created" "SUCCESS"
        }
        catch {
            Write-Step "  Failed to create cleanup task: $_" "WARNING"
        }
    }

    # Step 6: Initialize configuration
    Write-Step "Initializing configuration..." "INFO"

    $configPath = Join-Path $installPath "config.json"
    if (Test-Path $configPath) {
        $config = Get-Content $configPath | ConvertFrom-Json

        # Set company name
        Write-Host ""
        Write-Host "  Enter your company name (or press Enter to skip): " -NoNewline -ForegroundColor Yellow
        $companyName = Read-Host

        if (-not [string]::IsNullOrWhiteSpace($companyName)) {
            $config.company.name = $companyName
        }

        # Save updated config
        $config | ConvertTo-Json -Depth 10 | Set-Content $configPath
        Write-Step "Configuration initialized" "SUCCESS"
    }

    # Step 7: Test installation
    Write-Step "Testing installation..." "INFO"

    $testsPassed = $true

    # Test if launcher exists
    $launcherPath = Join-Path $installPath "Start-MSPToolkit.ps1"
    if (-not (Test-Path $launcherPath)) {
        Write-Step "  Launcher not found" "ERROR"
        $testsPassed = $false
    }

    # Test if config exists
    if (-not (Test-Path $configPath)) {
        Write-Step "  Configuration not found" "ERROR"
        $testsPassed = $false
    }

    # Test if directories exist
    $missingDirs = $directories | Where-Object { -not (Test-Path $_) }
    if ($missingDirs) {
        Write-Step "  Some directories missing" "ERROR"
        $testsPassed = $false
    }

    if ($testsPassed) {
        Write-Step "All tests passed" "SUCCESS"
    }

    # Installation complete
    Write-Host ""
    Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║                                                              ║" -ForegroundColor Green
    Write-Host "  ║          ✓ INSTALLATION COMPLETE ✓                          ║" -ForegroundColor Green
    Write-Host "  ║                                                              ║" -ForegroundColor Green
    Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Quick Start:" -ForegroundColor Cyan
    Write-Host "    • Double-click 'MSP Toolkit' shortcut on your desktop" -ForegroundColor Gray
    Write-Host "    • Or run: " -NoNewline -ForegroundColor Gray
    Write-Host ".\Start-MSPToolkit.ps1" -ForegroundColor Yellow
    Write-Host "    • For web interface: " -NoNewline -ForegroundColor Gray
    Write-Host ".\Tools\Start-WebInterface.ps1" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Configuration:" -ForegroundColor Cyan
    Write-Host "    • Edit config.json to customize settings" -ForegroundColor Gray
    Write-Host "    • View documentation: README.md" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Next Steps:" -ForegroundColor Cyan
    Write-Host "    • Configure your company settings in config.json" -ForegroundColor Gray
    Write-Host "    • Set up email notifications (optional)" -ForegroundColor Gray
    Write-Host "    • Configure RMM integration (optional)" -ForegroundColor Gray
    Write-Host "    • Create custom templates in the Templates folder" -ForegroundColor Gray
    Write-Host ""

    # Offer to launch toolkit
    Write-Host "  Launch MSP Toolkit now? (Y/N): " -NoNewline -ForegroundColor Yellow
    $launch = Read-Host

    if ($launch -eq 'Y' -or $launch -eq 'y') {
        & $launcherPath
    }
}

function Uninstall-Toolkit {
    Show-InstallBanner

    Write-Host "  This will:" -ForegroundColor Yellow
    Write-Host "    • Remove scheduled tasks" -ForegroundColor Gray
    Write-Host "    • Remove desktop shortcuts" -ForegroundColor Gray
    Write-Host "    • Remove from PATH" -ForegroundColor Gray
    Write-Host "    • Optionally delete data directories" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  WARNING: This cannot be undone!" -ForegroundColor Red
    Write-Host ""

    Write-Host "  Continue with uninstall? (Y/N): " -NoNewline -ForegroundColor Yellow
    $confirm = Read-Host

    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Step "Uninstall cancelled" "WARNING"
        return
    }

    Write-Host ""

    # Remove scheduled tasks
    Write-Step "Removing scheduled tasks..." "INFO"
    Unregister-ScheduledTask -TaskName "MSPToolkit-SelfHealing" -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "MSPToolkit-DailyCleanup" -Confirm:$false -ErrorAction SilentlyContinue
    Write-Step "Scheduled tasks removed" "SUCCESS"

    # Remove shortcuts
    Write-Step "Removing shortcuts..." "INFO"
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    Remove-Item -Path (Join-Path $desktopPath "MSP Toolkit.lnk") -Force -ErrorAction SilentlyContinue
    Write-Step "Shortcuts removed" "SUCCESS"

    # Remove from PATH
    Write-Step "Removing from PATH..." "INFO"
    $installPath = $PSScriptRoot
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $newPath = $currentPath -replace [regex]::Escape(";$installPath"), ""
    [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
    Write-Step "Removed from PATH" "SUCCESS"

    # Ask about data directories
    Write-Host ""
    Write-Host "  Delete data directories (logs, reports, cache)? (Y/N): " -NoNewline -ForegroundColor Yellow
    $deleteData = Read-Host

    if ($deleteData -eq 'Y' -or $deleteData -eq 'y') {
        Write-Step "Deleting data directories..." "INFO"
        Remove-Item -Path "C:\MSPToolkit" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Step "Data directories deleted" "SUCCESS"
    }

    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "  ║                                                              ║" -ForegroundColor Yellow
    Write-Host "  ║          UNINSTALL COMPLETE                                  ║" -ForegroundColor Yellow
    Write-Host "  ║                                                              ║" -ForegroundColor Yellow
    Write-Host "  ║          Thank you for using MSP Toolkit!                    ║" -ForegroundColor Yellow
    Write-Host "  ║                                                              ║" -ForegroundColor Yellow
    Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
}

# Main execution
if ($Uninstall) {
    Uninstall-Toolkit
} else {
    Install-Toolkit
}
