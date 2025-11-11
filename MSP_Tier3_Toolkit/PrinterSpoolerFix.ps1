<#
.SYNOPSIS
    Comprehensive Print Spooler Service Fix Tool
.DESCRIPTION
    Safely clears stuck print jobs and repairs the print spooler service
    - Stops the spooler service safely
    - Backs up existing print jobs (optional)
    - Clears the spool directory
    - Restarts the spooler service
    - Verifies service is running
.PARAMETER NoBackup
    Skip backing up spool files before deletion
.PARAMETER Force
    Force stop the spooler even if jobs are pending
.NOTES
    Author: MSP Toolkit Team
    Version: 2.0
    Requires: Administrator privileges
#>

[CmdletBinding()]
param(
    [switch]$NoBackup,
    [switch]$Force
)

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

# Initialize logging
$logPath = "$env:TEMP\PrinterSpoolerFix_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$spoolPath = "$env:SystemRoot\System32\spool\PRINTERS"
$backupPath = "$env:TEMP\SpoolerBackup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

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

function Get-SpoolerStatus {
    if (-not (Test-ServiceExists -ServiceName 'spooler')) {
        return $null
    }

    $service = Get-Service -Name 'spooler'
    $spoolFiles = @()

    if (Test-Path $spoolPath) {
        $spoolFiles = Get-ChildItem -Path $spoolPath -Filter *.* -ErrorAction SilentlyContinue
    }

    return [PSCustomObject]@{
        ServiceStatus = $service.Status
        ServiceStartType = $service.StartType
        SpoolFileCount = $spoolFiles.Count
        SpoolFiles = $spoolFiles
    }
}

function Stop-PrintSpooler {
    param([switch]$Force)

    Write-Log "Attempting to stop Print Spooler service..." -Level INFO

    if (-not (Test-ServiceExists -ServiceName 'spooler')) {
        Write-Log "Print Spooler service not found on this system!" -Level ERROR
        throw "Print Spooler service not found"
    }

    $service = Get-Service -Name 'spooler'

    if ($service.Status -eq 'Stopped') {
        Write-Log "Print Spooler service is already stopped" -Level INFO
        return $true
    }

    try {
        # Check for dependent services
        $dependentServices = Get-Service -Name 'spooler' | Select-Object -ExpandProperty DependentServices | Where-Object { $_.Status -eq 'Running' }

        if ($dependentServices) {
            Write-Log "Found $($dependentServices.Count) dependent service(s) running:" -Level WARNING
            foreach ($dep in $dependentServices) {
                Write-Log "  - $($dep.DisplayName) ($($dep.Name))" -Level WARNING
            }

            if (-not $Force) {
                Write-Host ""
                $confirm = Read-Host "  Stop dependent services? (Y/N)"
                if ($confirm -ne 'Y' -and $confirm -ne 'y') {
                    throw "User cancelled operation due to dependent services"
                }
            }
        }

        Write-Log "Stopping Print Spooler service..." -Level INFO
        Stop-Service -Name 'spooler' -Force -ErrorAction Stop

        # Wait for service to fully stop
        $timeout = 30
        $elapsed = 0
        while ((Get-Service -Name 'spooler').Status -ne 'Stopped' -and $elapsed -lt $timeout) {
            Start-Sleep -Seconds 1
            $elapsed++
        }

        if ((Get-Service -Name 'spooler').Status -eq 'Stopped') {
            Write-Log "Print Spooler service stopped successfully" -Level SUCCESS
            return $true
        }
        else {
            Write-Log "Print Spooler service did not stop within timeout period" -Level ERROR
            return $false
        }
    }
    catch {
        Write-Log "Failed to stop Print Spooler service: $($_.Exception.Message)" -Level ERROR
        throw
    }
}

function Start-PrintSpooler {
    Write-Log "Starting Print Spooler service..." -Level INFO

    try {
        Start-Service -Name 'spooler' -ErrorAction Stop

        # Wait for service to start
        $timeout = 30
        $elapsed = 0
        while ((Get-Service -Name 'spooler').Status -ne 'Running' -and $elapsed -lt $timeout) {
            Start-Sleep -Seconds 1
            $elapsed++
        }

        if ((Get-Service -Name 'spooler').Status -eq 'Running') {
            Write-Log "Print Spooler service started successfully" -Level SUCCESS
            return $true
        }
        else {
            Write-Log "Print Spooler service did not start within timeout period" -Level ERROR
            return $false
        }
    }
    catch {
        Write-Log "Failed to start Print Spooler service: $($_.Exception.Message)" -Level ERROR
        throw
    }
}

function Clear-SpoolDirectory {
    param([switch]$NoBackup)

    Write-Log "Processing spool directory: $spoolPath" -Level INFO

    # Verify spool directory exists
    if (-not (Test-Path $spoolPath)) {
        Write-Log "Spool directory does not exist. Creating it..." -Level WARNING
        New-Item -ItemType Directory -Path $spoolPath -Force | Out-Null
        Write-Log "Spool directory created" -Level SUCCESS
        return $true
    }

    # Get spool files
    $spoolFiles = Get-ChildItem -Path $spoolPath -Filter *.* -ErrorAction SilentlyContinue

    if ($spoolFiles.Count -eq 0) {
        Write-Log "No files found in spool directory" -Level INFO
        return $true
    }

    Write-Log "Found $($spoolFiles.Count) file(s) in spool directory" -Level INFO

    try {
        # Backup files if requested
        if (-not $NoBackup) {
            Write-Log "Creating backup of spool files..." -Level INFO
            New-Item -ItemType Directory -Path $backupPath -Force | Out-Null

            foreach ($file in $spoolFiles) {
                Copy-Item -Path $file.FullName -Destination $backupPath -Force -ErrorAction SilentlyContinue
            }

            Write-Log "Spool files backed up to: $backupPath" -Level SUCCESS
        }

        # Delete spool files
        Write-Log "Deleting spool files..." -Level INFO
        $deletedCount = 0
        $failedCount = 0

        foreach ($file in $spoolFiles) {
            try {
                Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                $deletedCount++
            }
            catch {
                Write-Log "  Failed to delete: $($file.Name) - $($_.Exception.Message)" -Level WARNING
                $failedCount++
            }
        }

        Write-Log "Deleted $deletedCount file(s), $failedCount failed" -Level SUCCESS

        if ($failedCount -gt 0) {
            Write-Log "Some files could not be deleted. They may be in use." -Level WARNING
        }

        return $true
    }
    catch {
        Write-Log "Failed to clear spool directory: $($_.Exception.Message)" -Level ERROR
        throw
    }
}

# Main execution
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host " Print Spooler Service Fix Tool" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

Write-Log "Starting print spooler fix procedure..." -Level INFO
Write-Log "Log file: $logPath" -Level INFO
Write-Host ""

# Get initial status
Write-Log "Checking current spooler status..." -Level INFO
$initialStatus = Get-SpoolerStatus

if (-not $initialStatus) {
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Red
    Write-Host " ERROR: Print Spooler Service Not Found" -ForegroundColor Red
    Write-Host ("=" * 80) -ForegroundColor Red
    Write-Host ""
    Write-Log "Print Spooler service is not available on this system" -Level ERROR
    exit 1
}

Write-Log "  Service status: $($initialStatus.ServiceStatus)" -Level INFO
Write-Log "  Start type: $($initialStatus.ServiceStartType)" -Level INFO
Write-Log "  Files in spool: $($initialStatus.SpoolFileCount)" -Level INFO
Write-Host ""

if ($initialStatus.SpoolFileCount -eq 0) {
    Write-Log "No stuck print jobs found. Checking if service needs restart..." -Level INFO

    if ($initialStatus.ServiceStatus -eq 'Running') {
        Write-Host ""
        Write-Host "  The Print Spooler appears to be healthy." -ForegroundColor Green
        Write-Host "  No stuck jobs found and service is running." -ForegroundColor Green
        Write-Host ""

        if (-not $Force) {
            $confirm = Read-Host "  Restart service anyway? (Y/N)"
            if ($confirm -ne 'Y' -and $confirm -ne 'y') {
                Write-Log "Operation cancelled by user" -Level INFO
                exit 0
            }
        }
    }
}

try {
    # Step 1: Stop the spooler
    $stopResult = Stop-PrintSpooler -Force:$Force

    # Step 2: Clear spool directory
    $clearResult = Clear-SpoolDirectory -NoBackup:$NoBackup

    # Step 3: Start the spooler
    $startResult = Start-PrintSpooler

    # Step 4: Verify final status
    Write-Log "Verifying spooler status..." -Level INFO
    Start-Sleep -Seconds 2

    $finalStatus = Get-SpoolerStatus

    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Green
    Write-Host " Print Spooler Fix Completed Successfully!" -ForegroundColor Green
    Write-Host ("=" * 80) -ForegroundColor Green
    Write-Host ""

    Write-Host "  Service status: " -NoNewline -ForegroundColor Gray
    Write-Host $finalStatus.ServiceStatus -ForegroundColor Green

    Write-Host "  Files in spool: " -NoNewline -ForegroundColor Gray
    Write-Host $finalStatus.SpoolFileCount -ForegroundColor Green

    if (-not $NoBackup -and $initialStatus.SpoolFileCount -gt 0) {
        Write-Host "  Backup location: " -NoNewline -ForegroundColor Gray
        Write-Host $backupPath -ForegroundColor Cyan
    }

    Write-Host ""
    Write-Log "All operations completed successfully" -Level SUCCESS
    Write-Host "  Log file: $logPath" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Try printing a test page" -ForegroundColor White
    Write-Host "  2. Check if printers are responding" -ForegroundColor White
    Write-Host "  3. Resubmit any critical print jobs" -ForegroundColor White
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Red
    Write-Host " ERROR: Print Spooler Fix Failed" -ForegroundColor Red
    Write-Host ("=" * 80) -ForegroundColor Red
    Write-Host ""
    Write-Log "Critical error occurred: $($_.Exception.Message)" -Level ERROR
    Write-Host ""
    Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""

    # Attempt to restart service even on failure
    Write-Log "Attempting to restart Print Spooler service..." -Level WARNING
    try {
        Start-Service -Name 'spooler' -ErrorAction SilentlyContinue
        Write-Log "Service restart attempted" -Level INFO
    }
    catch {
        Write-Log "Failed to restart service: $($_.Exception.Message)" -Level ERROR
    }

    Write-Host "Log file: $logPath" -ForegroundColor Yellow
    Write-Host ""

    exit 1
}
