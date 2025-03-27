<#
.SYNOPSIS
  Automated cleanup script for disk space and print spooler issues.
.DESCRIPTION
  - Clears TEMP folders (user/system)
  - Attempts to clear print spooler queue
  - Runs Disk Cleanup silently
  - Logs all actions to C:\CleanupLogs
#>

# Create log folder
$logPath = "C:\CleanupLogs"
if (!(Test-Path $logPath)) {
    New-Item -Path $logPath -ItemType Directory | Out-Null
}
$logFile = "$logPath\cleanup-$(Get-Date -Format yyyy-MM-dd_HH-mm-ss).log"

function Write-Log {
    param([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File -FilePath $logFile -Append
}

Write-Log "==== Starting Cleanup Script ===="

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Log "⚠️ WARNING: Script is NOT running with administrative privileges. Some functions may be skipped."
} else {
    Write-Log "✅ Script is running with administrative privileges."
}

# Clear user TEMP folder
try {
    $userTemp = $env:TEMP
    Write-Log "Clearing user TEMP folder: $userTemp"
    Remove-Item "$userTemp\*" -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-Log "Error clearing user TEMP: $_"
}

# Clear system TEMP folder
try {
    Write-Log "Clearing system TEMP folder: C:\Windows\Temp"
    Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-Log "Error clearing system TEMP: $_"
}

# Try to clear Print Spooler queue (only if admin)
if ($isAdmin) {
    try {
        Write-Log "Stopping Print Spooler service"
        Stop-Service spooler -Force -ErrorAction Stop
        Write-Log "Clearing spooler files"
        Remove-Item "C:\Windows\System32\spool\PRINTERS\*" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Starting Print Spooler service"
        Start-Service spooler -ErrorAction Stop
    } catch {
        Write-Log "Error clearing Print Spooler: $_"
    }
} else {
    Write-Log "Skipping spooler cleanup — not running as admin"
}

# Run Disk Cleanup silently
try {
    Write-Log "Running Disk Cleanup silently (cleanmgr.exe /sagerun:1)"
    Start-Process cleanmgr.exe -ArgumentList "/sagerun:1" -NoNewWindow -Wait
} catch {
    Write-Log "Error running Disk Cleanup: $_"
}

# Log available free space on C:
try {
    $freeSpace = [math]::round((Get-PSDrive C).Free / 1GB, 2)
    Write-Log "Free disk space on C: drive: $freeSpace GB"
} catch {
    Write-Log "Unable to calculate free disk space: $_"
}

Write-Log "==== Cleanup Script Completed ===="
