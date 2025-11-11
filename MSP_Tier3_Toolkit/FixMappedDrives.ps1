<#
.SYNOPSIS
    Network Mapped Drive Repair and Management Tool
.DESCRIPTION
    Diagnoses and repairs mapped network drives including:
    - Testing connectivity to network shares
    - Reconnecting disconnected drives
    - Repairing broken mappings
    - Adding new persistent drive mappings
    - Removing orphaned drive mappings
.PARAMETER AutoFix
    Automatically attempt to fix all disconnected drives
.PARAMETER RemoveOrphaned
    Remove orphaned/unavailable drive mappings
.PARAMETER DriveLetters
    Specific drive letters to check (e.g., "Z","Y")
.NOTES
    Author: MSP Toolkit Team
    Version: 2.0
    Requires: Standard user (Admin for persistent mapping changes)
#>

[CmdletBinding()]
param(
    [switch]$AutoFix,
    [switch]$RemoveOrphaned,
    [string[]]$DriveLetters
)

$ErrorActionPreference = 'Continue'

# Initialize logging
$logPath = "$env:TEMP\FixMappedDrives_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$fixedCount = 0
$failedCount = 0
$healthyCount = 0

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"

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

    Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
}

function Test-NetworkShare {
    <#
    .SYNOPSIS
        Tests if a network share is accessible
    #>
    param(
        [string]$UNCPath
    )

    try {
        if ([string]::IsNullOrWhiteSpace($UNCPath)) {
            return $false
        }

        # Try to access the share
        $testPath = Test-Path -Path $UNCPath -ErrorAction Stop
        return $testPath
    }
    catch {
        return $false
    }
}

function Get-MappedDriveInfo {
    <#
    .SYNOPSIS
        Gets comprehensive information about mapped drives
    #>

    $drives = @()

    # Get WMI mapped drives
    try {
        $wmiDrives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=4" -ErrorAction SilentlyContinue

        foreach ($drive in $wmiDrives) {
            $status = "Unknown"
            $accessible = Test-NetworkShare -UNCPath $drive.ProviderName

            if ($accessible) {
                $status = "Healthy"
            }
            elseif ($drive.ProviderName) {
                $status = "Disconnected"
            }
            else {
                $status = "Orphaned"
            }

            $drives += [PSCustomObject]@{
                DriveLetter = $drive.DeviceID
                UNCPath = $drive.ProviderName
                Status = $status
                Accessible = $accessible
                VolumeName = $drive.VolumeName
                FreeSpaceGB = if ($accessible) { [math]::Round($drive.FreeSpace / 1GB, 2) } else { $null }
                TotalSizeGB = if ($accessible) { [math]::Round($drive.Size / 1GB, 2) } else { $null }
            }
        }
    }
    catch {
        Write-Log "Error querying WMI drives: $($_.Exception.Message)" -Level ERROR
    }

    # Get PowerShell PSDrives
    try {
        $psDrives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayRoot -like "\\*" }

        foreach ($psDrive in $psDrives) {
            # Skip if already in collection
            if ($drives.DriveLetter -contains "$($psDrive.Name):") {
                continue
            }

            $accessible = Test-NetworkShare -UNCPath $psDrive.DisplayRoot
            $status = if ($accessible) { "Healthy" } else { "Disconnected" }

            $drives += [PSCustomObject]@{
                DriveLetter = "$($psDrive.Name):"
                UNCPath = $psDrive.DisplayRoot
                Status = $status
                Accessible = $accessible
                VolumeName = $psDrive.Description
                FreeSpaceGB = if ($accessible) { [math]::Round($psDrive.Free / 1GB, 2) } else { $null }
                TotalSizeGB = if ($accessible) { [math]::Round(($psDrive.Used + $psDrive.Free) / 1GB, 2) } else { $null }
            }
        }
    }
    catch {
        Write-Log "Error querying PSDrives: $($_.Exception.Message)" -Level ERROR
    }

    return $drives
}

function Repair-MappedDrive {
    <#
    .SYNOPSIS
        Attempts to repair a disconnected mapped drive
    #>
    param(
        [Parameter(Mandatory=$true)]
        $Drive
    )

    Write-Log "Attempting to repair $($Drive.DriveLetter) -> $($Drive.UNCPath)" -Level INFO

    try {
        # First, try to remove the existing mapping
        try {
            $null = Remove-PSDrive -Name $Drive.DriveLetter.TrimEnd(':') -ErrorAction SilentlyContinue -Force
            Start-Sleep -Milliseconds 500
        }
        catch {
            # Ignore errors
        }

        # Try to remap using New-PSDrive
        try {
            $newDrive = New-PSDrive -Name $Drive.DriveLetter.TrimEnd(':') `
                                    -PSProvider FileSystem `
                                    -Root $Drive.UNCPath `
                                    -Persist `
                                    -Scope Global `
                                    -ErrorAction Stop

            if ($newDrive) {
                # Verify it works
                $testResult = Test-NetworkShare -UNCPath $Drive.UNCPath

                if ($testResult) {
                    Write-Log "Successfully repaired $($Drive.DriveLetter)" -Level SUCCESS
                    return $true
                }
                else {
                    Write-Log "Drive mapped but not accessible: $($Drive.DriveLetter)" -Level WARNING
                    return $false
                }
            }
        }
        catch {
            Write-Log "PSDrive mapping failed: $($_.Exception.Message)" -Level WARNING

            # Try using net use as fallback
            try {
                $netUseCommand = "net use $($Drive.DriveLetter) `"$($Drive.UNCPath)`" /persistent:yes"
                $result = Invoke-Expression $netUseCommand 2>&1

                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Successfully repaired using net use: $($Drive.DriveLetter)" -Level SUCCESS
                    return $true
                }
                else {
                    Write-Log "net use failed: $result" -Level ERROR
                    return $false
                }
            }
            catch {
                Write-Log "net use command failed: $($_.Exception.Message)" -Level ERROR
                return $false
            }
        }

        return $false
    }
    catch {
        Write-Log "Failed to repair $($Drive.DriveLetter): $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Remove-OrphanedDrive {
    <#
    .SYNOPSIS
        Removes an orphaned drive mapping
    #>
    param(
        [Parameter(Mandatory=$true)]
        $Drive
    )

    Write-Log "Removing orphaned drive: $($Drive.DriveLetter)" -Level INFO

    try {
        # Try Remove-PSDrive
        try {
            Remove-PSDrive -Name $Drive.DriveLetter.TrimEnd(':') -ErrorAction Stop -Force
            Write-Log "Removed orphaned drive: $($Drive.DriveLetter)" -Level SUCCESS
            return $true
        }
        catch {
            # Try net use delete
            $result = Invoke-Expression "net use $($Drive.DriveLetter) /delete /yes" 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-Log "Removed orphaned drive using net use: $($Drive.DriveLetter)" -Level SUCCESS
                return $true
            }
            else {
                Write-Log "Failed to remove orphaned drive: $result" -Level ERROR
                return $false
            }
        }
    }
    catch {
        Write-Log "Error removing orphaned drive: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

# Main execution
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host " Network Mapped Drive Repair Tool" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

Write-Log "Starting mapped drive diagnostics..." -Level INFO
Write-Log "Log file: $logPath" -Level INFO
Write-Host ""

# Get all mapped drives
Write-Log "Scanning for mapped network drives..." -Level INFO
$allDrives = Get-MappedDriveInfo

if (-not $allDrives -or $allDrives.Count -eq 0) {
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "  ║                   [NO MAPPED DRIVES]                      ║" -ForegroundColor Yellow
    Write-Host "  ╠═══════════════════════════════════════════════════════════╣" -ForegroundColor Yellow
    Write-Host "  ║  No mapped network drives found on this system            ║" -ForegroundColor Yellow
    Write-Host "  ╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Log file: $logPath" -ForegroundColor Cyan
    Write-Host ""
    exit 0
}

# Filter by drive letters if specified
if ($DriveLetters) {
    $allDrives = $allDrives | Where-Object { $DriveLetters -contains $_.DriveLetter }
}

Write-Log "Found $($allDrives.Count) mapped network drive(s)" -Level SUCCESS
Write-Host ""

# Display drive status
Write-Host "  Drive Status:" -ForegroundColor Cyan
Write-Host "  " + ("=" * 78) -ForegroundColor DarkGray
Write-Host ""

foreach ($drive in $allDrives) {
    $statusColor = switch ($drive.Status) {
        "Healthy" { "Green" }
        "Disconnected" { "Yellow" }
        "Orphaned" { "Red" }
        default { "Gray" }
    }

    Write-Host "  Drive:  " -NoNewline -ForegroundColor Gray
    Write-Host "$($drive.DriveLetter)" -NoNewline -ForegroundColor White
    Write-Host "  Status: " -NoNewline -ForegroundColor Gray
    Write-Host $drive.Status -ForegroundColor $statusColor

    Write-Host "  Path:   " -NoNewline -ForegroundColor Gray
    Write-Host $drive.UNCPath -ForegroundColor DarkGray

    if ($drive.Accessible -and $drive.TotalSizeGB) {
        $usedGB = $drive.TotalSizeGB - $drive.FreeSpaceGB
        $usedPercent = [math]::Round(($usedGB / $drive.TotalSizeGB) * 100, 1)

        Write-Host "  Space:  " -NoNewline -ForegroundColor Gray
        Write-Host "$($drive.FreeSpaceGB) GB free of $($drive.TotalSizeGB) GB " -NoNewline -ForegroundColor White
        Write-Host "($usedPercent% used)" -ForegroundColor DarkGray
    }

    Write-Host ""

    # Track statistics
    switch ($drive.Status) {
        "Healthy" { $healthyCount++ }
    }
}

Write-Host "  " + ("=" * 78) -ForegroundColor DarkGray
Write-Host ""

# Summary of issues
$disconnectedDrives = $allDrives | Where-Object { $_.Status -eq "Disconnected" }
$orphanedDrives = $allDrives | Where-Object { $_.Status -eq "Orphaned" }

Write-Host "  Summary:" -ForegroundColor Cyan
Write-Host "  Healthy drives:      " -NoNewline -ForegroundColor Gray
Write-Host $healthyCount -ForegroundColor Green
Write-Host "  Disconnected drives: " -NoNewline -ForegroundColor Gray
Write-Host $disconnectedDrives.Count -ForegroundColor Yellow
Write-Host "  Orphaned drives:     " -NoNewline -ForegroundColor Gray
Write-Host $orphanedDrives.Count -ForegroundColor Red
Write-Host ""

# If all drives are healthy
if ($disconnectedDrives.Count -eq 0 -and $orphanedDrives.Count -eq 0) {
    Write-Host "  ╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║                   [ALL DRIVES HEALTHY]                    ║" -ForegroundColor Green
    Write-Host "  ╠═══════════════════════════════════════════════════════════╣" -ForegroundColor Green
    Write-Host "  ║  All mapped drives are accessible and functioning         ║" -ForegroundColor Green
    Write-Host "  ╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Log file: $logPath" -ForegroundColor Cyan
    Write-Host ""
    exit 0
}

# Repair disconnected drives
if ($disconnectedDrives.Count -gt 0) {
    Write-Host "  " + ("─" * 78) -ForegroundColor DarkCyan
    Write-Host ""

    if ($AutoFix) {
        Write-Log "Auto-fix mode enabled. Attempting repairs..." -Level INFO
        Write-Host ""

        foreach ($drive in $disconnectedDrives) {
            $result = Repair-MappedDrive -Drive $drive

            if ($result) {
                $fixedCount++
            }
            else {
                $failedCount++
            }
        }
    }
    else {
        Write-Host "  Found $($disconnectedDrives.Count) disconnected drive(s)" -ForegroundColor Yellow
        Write-Host ""
        $confirm = Read-Host "  Attempt to reconnect disconnected drives? (Y/N)"

        if ($confirm -eq 'Y' -or $confirm -eq 'y') {
            Write-Host ""

            foreach ($drive in $disconnectedDrives) {
                $result = Repair-MappedDrive -Drive $drive

                if ($result) {
                    $fixedCount++
                }
                else {
                    $failedCount++
                }
            }
        }
    }
}

# Remove orphaned drives
if ($orphanedDrives.Count -gt 0) {
    Write-Host ""
    Write-Host "  " + ("─" * 78) -ForegroundColor DarkCyan
    Write-Host ""

    if ($RemoveOrphaned) {
        Write-Log "Removing orphaned drives..." -Level INFO
        Write-Host ""

        foreach ($drive in $orphanedDrives) {
            $result = Remove-OrphanedDrive -Drive $drive

            if ($result) {
                $fixedCount++
            }
            else {
                $failedCount++
            }
        }
    }
    else {
        Write-Host "  Found $($orphanedDrives.Count) orphaned drive(s)" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Tip: Run with -RemoveOrphaned to clean up orphaned drives" -ForegroundColor Gray
        Write-Host ""
    }
}

# Final summary
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Green
Write-Host " Drive Repair Complete" -ForegroundColor Green
Write-Host ("=" * 80) -ForegroundColor Green
Write-Host ""

Write-Host "  Healthy drives:       " -NoNewline -ForegroundColor Gray
Write-Host $healthyCount -ForegroundColor Green

if ($fixedCount -gt 0) {
    Write-Host "  Repaired drives:      " -NoNewline -ForegroundColor Gray
    Write-Host $fixedCount -ForegroundColor Green
}

if ($failedCount -gt 0) {
    Write-Host "  Failed repairs:       " -NoNewline -ForegroundColor Gray
    Write-Host $failedCount -ForegroundColor Red
}

Write-Host ""
Write-Host "  Log file: $logPath" -ForegroundColor Cyan
Write-Host ""

if ($fixedCount -gt 0) {
    Write-Host "  Note: You may need to refresh Explorer to see changes" -ForegroundColor Yellow
    Write-Host ""
}

if ($failedCount -gt 0) {
    Write-Host "  Troubleshooting Tips:" -ForegroundColor Yellow
    Write-Host "  - Check network connectivity" -ForegroundColor Gray
    Write-Host "  - Verify share permissions" -ForegroundColor Gray
    Write-Host "  - Ensure server is online" -ForegroundColor Gray
    Write-Host "  - Check credentials are valid" -ForegroundColor Gray
    Write-Host ""
}

Write-Log "Drive repair completed: $fixedCount fixed, $failedCount failed" -Level SUCCESS
