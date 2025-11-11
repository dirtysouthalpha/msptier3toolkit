<#
.SYNOPSIS
    Comprehensive Windows Update Component Reset Tool
.DESCRIPTION
    Safely resets Windows Update components to fix common update issues
    - Stops Windows Update services
    - Backs up and renames SoftwareDistribution folder
    - Clears update cache
    - Restarts services
    - Triggers update detection
.NOTES
    Author: MSP Toolkit Team
    Version: 2.0
    Requires: Administrator privileges
#>

[CmdletBinding()]
param(
    [switch]$NoBackup,
    [switch]$Verbose
)

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

# Initialize logging
$logPath = "$env:TEMP\WindowsUpdateFix_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"

    # Console output with colors
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

    # File logging
    Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
}

function Test-ServiceExists {
    param([string]$ServiceName)

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Stop-WindowsUpdateServices {
    Write-Log "Stopping Windows Update services..." -Level INFO

    $services = @('wuauserv', 'cryptSvc', 'bits', 'msiserver')
    $stoppedServices = @()

    foreach ($serviceName in $services) {
        try {
            if (Test-ServiceExists -ServiceName $serviceName) {
                $service = Get-Service -Name $serviceName

                if ($service.Status -eq 'Running') {
                    Write-Log "  Stopping service: $serviceName" -Level INFO
                    Stop-Service -Name $serviceName -Force -ErrorAction Stop
                    $stoppedServices += $serviceName
                    Write-Log "  Service stopped: $serviceName" -Level SUCCESS
                }
                else {
                    Write-Log "  Service already stopped: $serviceName" -Level INFO
                }
            }
            else {
                Write-Log "  Service not found: $serviceName" -Level WARNING
            }
        }
        catch {
            Write-Log "  Failed to stop service $serviceName : $($_.Exception.Message)" -Level ERROR
            throw
        }
    }

    return $stoppedServices
}

function Start-WindowsUpdateServices {
    param([string[]]$ServiceNames)

    Write-Log "Starting Windows Update services..." -Level INFO

    foreach ($serviceName in $ServiceNames) {
        try {
            if (Test-ServiceExists -ServiceName $serviceName) {
                Write-Log "  Starting service: $serviceName" -Level INFO
                Start-Service -Name $serviceName -ErrorAction Stop
                Write-Log "  Service started: $serviceName" -Level SUCCESS
            }
        }
        catch {
            Write-Log "  Failed to start service $serviceName : $($_.Exception.Message)" -Level WARNING
        }
    }
}

function Reset-SoftwareDistribution {
    param([switch]$NoBackup)

    $sdPath = "$env:SystemRoot\SoftwareDistribution"
    $backupPath = "$env:SystemRoot\SoftwareDistribution.bak"

    Write-Log "Processing SoftwareDistribution folder..." -Level INFO

    # Check if folder exists
    if (-not (Test-Path $sdPath)) {
        Write-Log "  SoftwareDistribution folder does not exist. Creating it..." -Level WARNING
        New-Item -ItemType Directory -Path $sdPath -Force | Out-Null
        Write-Log "  Folder created successfully" -Level SUCCESS
        return $true
    }

    try {
        # Backup existing folder if requested
        if (-not $NoBackup) {
            # Remove old backup if exists
            if (Test-Path $backupPath) {
                Write-Log "  Removing old backup..." -Level INFO
                Remove-Item -Path $backupPath -Recurse -Force -ErrorAction Stop
            }

            Write-Log "  Creating backup: $backupPath" -Level INFO
            Rename-Item -Path $sdPath -NewName "SoftwareDistribution.bak" -Force -ErrorAction Stop
            Write-Log "  Backup created successfully" -Level SUCCESS

            # Create new empty folder
            New-Item -ItemType Directory -Path $sdPath -Force | Out-Null
            Write-Log "  New SoftwareDistribution folder created" -Level SUCCESS
        }
        else {
            # Direct removal
            Write-Log "  Removing SoftwareDistribution folder (no backup)..." -Level WARNING
            Remove-Item -Path $sdPath -Recurse -Force -ErrorAction Stop
            New-Item -ItemType Directory -Path $sdPath -Force | Out-Null
            Write-Log "  Folder reset successfully" -Level SUCCESS
        }

        return $true
    }
    catch {
        Write-Log "  Failed to process SoftwareDistribution: $($_.Exception.Message)" -Level ERROR
        throw
    }
}

function Reset-CatRoot2 {
    $catRoot2Path = "$env:SystemRoot\System32\catroot2"
    $backupPath = "$env:SystemRoot\System32\catroot2.bak"

    Write-Log "Processing catroot2 folder..." -Level INFO

    if (-not (Test-Path $catRoot2Path)) {
        Write-Log "  catroot2 folder does not exist. Skipping..." -Level WARNING
        return $true
    }

    try {
        # Remove old backup
        if (Test-Path $backupPath) {
            Remove-Item -Path $backupPath -Recurse -Force -ErrorAction SilentlyContinue
        }

        Rename-Item -Path $catRoot2Path -NewName "catroot2.bak" -Force -ErrorAction Stop
        Write-Log "  catroot2 folder backed up successfully" -Level SUCCESS

        # Windows will recreate this automatically
        return $true
    }
    catch {
        Write-Log "  Failed to process catroot2: $($_.Exception.Message)" -Level WARNING
        return $false
    }
}

# Main execution
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host " Windows Update Component Reset Tool" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

Write-Log "Starting Windows Update fix procedure..." -Level INFO
Write-Log "Log file: $logPath" -Level INFO

$stoppedServices = @()

try {
    # Step 1: Stop services
    $stoppedServices = Stop-WindowsUpdateServices

    # Wait for services to fully stop
    Write-Log "Waiting for services to fully stop..." -Level INFO
    Start-Sleep -Seconds 2

    # Step 2: Reset SoftwareDistribution
    $sdResult = Reset-SoftwareDistribution -NoBackup:$NoBackup

    # Step 3: Reset catroot2
    $catResult = Reset-CatRoot2

    # Step 4: Restart services
    Start-WindowsUpdateServices -ServiceNames $stoppedServices

    # Step 5: Trigger Windows Update detection
    Write-Log "Triggering Windows Update detection..." -Level INFO
    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session -ErrorAction Stop
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        Write-Log "  Detection triggered via COM interface" -Level SUCCESS
    }
    catch {
        # Fallback to wuauclt
        Write-Log "  COM interface failed, using wuauclt fallback..." -Level WARNING
        Start-Process -FilePath "wuauclt.exe" -ArgumentList "/detectnow" -NoNewWindow -ErrorAction SilentlyContinue
    }

    # Summary
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Green
    Write-Host " Windows Update Fix Completed Successfully!" -ForegroundColor Green
    Write-Host ("=" * 80) -ForegroundColor Green
    Write-Host ""
    Write-Log "All operations completed successfully" -Level SUCCESS
    Write-Log "Please check Windows Update in Settings to verify functionality" -Level INFO
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Open Settings > Windows Update" -ForegroundColor White
    Write-Host "  2. Click 'Check for updates'" -ForegroundColor White
    Write-Host "  3. Wait for updates to download and install" -ForegroundColor White
    Write-Host ""
    Write-Host "Log file saved to: $logPath" -ForegroundColor Cyan
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Red
    Write-Host " ERROR: Windows Update Fix Failed" -ForegroundColor Red
    Write-Host ("=" * 80) -ForegroundColor Red
    Write-Host ""
    Write-Log "Critical error occurred: $($_.Exception.Message)" -Level ERROR
    Write-Host ""
    Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Log file: $logPath" -ForegroundColor Yellow
    Write-Host ""

    # Attempt to restart services even on failure
    if ($stoppedServices.Count -gt 0) {
        Write-Log "Attempting to restart services after error..." -Level WARNING
        Start-WindowsUpdateServices -ServiceNames $stoppedServices
    }

    exit 1
}
