# Script: CheckAndStart-Spooler.ps1
# Purpose: Ensure Print Spooler is running; restart if not

$serviceName = "Spooler"
$logFile = "C:\Logs\SpoolerMonitor.log"  # Optional logging

# Create log directory if it doesn't exist
if (!(Test-Path -Path (Split-Path $logFile))) {
    New-Item -Path (Split-Path $logFile) -ItemType Directory -Force
}

# Get spooler service status
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($null -eq $service) {
    Add-Content $logFile "$(Get-Date) - ERROR: Spooler service not found."
    exit 1
}

if ($service.Status -ne "Running") {
    try {
        Start-Service -Name $serviceName
        Add-Content $logFile "$(Get-Date) - Spooler was stopped. Service started successfully."
    } catch {
        Add-Content $logFile "$(Get-Date) - ERROR: Failed to start Spooler. $_"
        exit 2
    }
} else {
    Add-Content $logFile "$(Get-Date) - Spooler is already running."
}
