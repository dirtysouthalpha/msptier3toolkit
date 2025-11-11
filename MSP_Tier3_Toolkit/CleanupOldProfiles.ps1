<#
.SYNOPSIS
    Safely removes old user profiles from Windows systems
.DESCRIPTION
    Removes user profiles that haven't been used in a specified number of days
    Uses SID-based filtering to protect system accounts and critical profiles
    Creates detailed logs of all operations
.PARAMETER DaysOld
    Remove profiles not used in this many days (default: 30)
.PARAMETER WhatIf
    Show what would be deleted without actually deleting
.PARAMETER ExcludeUsers
    Array of usernames to exclude from cleanup
.NOTES
    Author: MSP Toolkit Team
    Version: 2.0
    Requires: Administrator privileges
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Position=0)]
    [ValidateRange(1, 365)]
    [int]$DaysOld = 30,

    [Parameter()]
    [string[]]$ExcludeUsers = @(),

    [switch]$WhatIf,
    [switch]$Force
)

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

# Initialize logging
$logPath = "$env:TEMP\CleanupOldProfiles_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$deletedCount = 0
$failedCount = 0
$skippedCount = 0

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

function Test-ProtectedSID {
    <#
    .SYNOPSIS
        Determines if a SID belongs to a protected system account
    #>
    param([string]$SID)

    # Protected SID patterns
    $protectedSIDPatterns = @(
        'S-1-5-18',  # Local System
        'S-1-5-19',  # Local Service
        'S-1-5-20',  # Network Service
        'S-1-5-21-*-500',  # Built-in Administrator (ends in 500)
        'S-1-5-21-*-501',  # Built-in Guest (ends in 501)
        'S-1-5-21-*-503'   # Default Account (ends in 503)
    )

    foreach ($pattern in $protectedSIDPatterns) {
        if ($SID -like $pattern) {
            return $true
        }
    }

    return $false
}

function Test-ProfileInUse {
    <#
    .SYNOPSIS
        Checks if a profile is currently loaded/in use
    #>
    param([string]$ProfilePath)

    # Check if NTUSER.DAT is locked (profile is loaded)
    $ntUserPath = Join-Path $ProfilePath "NTUSER.DAT"

    if (Test-Path $ntUserPath) {
        try {
            $file = [System.IO.File]::Open($ntUserPath, 'Open', 'Read', 'None')
            $file.Close()
            return $false  # Not in use
        }
        catch {
            return $true  # File is locked, profile is in use
        }
    }

    return $false
}

function Get-ProfileUsername {
    <#
    .SYNOPSIS
        Extracts username from profile path
    #>
    param([string]$LocalPath)

    if ($LocalPath -match '\\Users\\(.+)$') {
        return $Matches[1]
    }

    return "Unknown"
}

# Main execution
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host " Old User Profile Cleanup Tool" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

Write-Log "Starting profile cleanup process..." -Level INFO
Write-Log "Log file: $logPath" -Level INFO
Write-Log "Parameters:" -Level INFO
Write-Log "  Days old threshold: $DaysOld days" -Level INFO
Write-Log "  WhatIf mode: $WhatIf" -Level INFO

if ($ExcludeUsers.Count -gt 0) {
    Write-Log "  Excluded users: $($ExcludeUsers -join ', ')" -Level INFO
}

Write-Host ""

# Get cutoff date
$cutoffDate = (Get-Date).AddDays(-$DaysOld)
Write-Log "Cutoff date: $($cutoffDate.ToString('yyyy-MM-dd HH:mm:ss'))" -Level INFO
Write-Log "Profiles not used since this date will be considered for removal" -Level INFO

Write-Host ""
Write-Log "Scanning user profiles..." -Level INFO
Write-Host ""

try {
    # Get all user profiles
    $allProfiles = Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop

    Write-Log "Found $($allProfiles.Count) total profiles on system" -Level INFO
    Write-Host ""

    foreach ($profile in $allProfiles) {
        $username = Get-ProfileUsername -LocalPath $profile.LocalPath
        $profileInfo = "Profile: $username ($($profile.LocalPath))"

        # Skip profiles with no last use time
        if (-not $profile.LastUseTime) {
            Write-Log "$profileInfo - SKIPPED (no last use time recorded)" -Level WARNING
            $skippedCount++
            continue
        }

        # Check if profile is too new
        if ($profile.LastUseTime -ge $cutoffDate) {
            Write-Log "$profileInfo - SKIPPED (last used: $($profile.LastUseTime.ToString('yyyy-MM-dd')))" -Level INFO
            $skippedCount++
            continue
        }

        # Check if SID is protected
        if (Test-ProtectedSID -SID $profile.SID) {
            Write-Log "$profileInfo - SKIPPED (protected system account)" -Level WARNING
            $skippedCount++
            continue
        }

        # Check if special profile
        if ($profile.Special) {
            Write-Log "$profileInfo - SKIPPED (special profile flag set)" -Level WARNING
            $skippedCount++
            continue
        }

        # Check if username is excluded
        if ($username -in $ExcludeUsers) {
            Write-Log "$profileInfo - SKIPPED (in exclusion list)" -Level WARNING
            $skippedCount++
            continue
        }

        # Check if profile is currently loaded
        if ($profile.Loaded) {
            Write-Log "$profileInfo - SKIPPED (profile is currently loaded)" -Level WARNING
            $skippedCount++
            continue
        }

        # Double-check if profile is in use by checking file lock
        if (Test-ProfileInUse -ProfilePath $profile.LocalPath) {
            Write-Log "$profileInfo - SKIPPED (profile appears to be in use)" -Level WARNING
            $skippedCount++
            continue
        }

        # This profile is a candidate for deletion
        $daysSinceUse = ((Get-Date) - $profile.LastUseTime).Days
        $profileSize = 0

        # Calculate profile size
        if (Test-Path $profile.LocalPath) {
            try {
                $profileSize = (Get-ChildItem -Path $profile.LocalPath -Recurse -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1MB
                $profileSize = [math]::Round($profileSize, 2)
            }
            catch {
                $profileSize = 0
            }
        }

        # Delete the profile
        if ($WhatIf) {
            Write-Log "$profileInfo - WOULD DELETE (last used $daysSinceUse days ago, size: $profileSize MB)" -Level WARNING
            $deletedCount++
        }
        else {
            try {
                if (-not $Force) {
                    Write-Host ""
                    Write-Host "  Profile: $username" -ForegroundColor Yellow
                    Write-Host "  Path: $($profile.LocalPath)" -ForegroundColor Gray
                    Write-Host "  Last used: $($profile.LastUseTime.ToString('yyyy-MM-dd')) ($daysSinceUse days ago)" -ForegroundColor Gray
                    Write-Host "  Size: $profileSize MB" -ForegroundColor Gray
                    Write-Host ""
                    $confirm = Read-Host "  Delete this profile? (Y/N)"

                    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
                        Write-Log "$profileInfo - SKIPPED (user declined deletion)" -Level INFO
                        $skippedCount++
                        continue
                    }
                }

                Write-Log "$profileInfo - DELETING (last used $daysSinceUse days ago, size: $profileSize MB)..." -Level INFO

                # Delete the profile
                $profile.Delete()

                Write-Log "$profileInfo - DELETED successfully (freed $profileSize MB)" -Level SUCCESS
                $deletedCount++
            }
            catch {
                Write-Log "$profileInfo - FAILED to delete: $($_.Exception.Message)" -Level ERROR
                $failedCount++
            }
        }
    }

    # Summary
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Green
    Write-Host " Profile Cleanup Summary" -ForegroundColor Green
    Write-Host ("=" * 80) -ForegroundColor Green
    Write-Host ""

    if ($WhatIf) {
        Write-Host "  [WhatIf Mode - No profiles were actually deleted]" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Profiles that would be deleted: " -NoNewline
        Write-Host $deletedCount -ForegroundColor Cyan
    }
    else {
        Write-Host "  Profiles deleted: " -NoNewline
        Write-Host $deletedCount -ForegroundColor Green
        Write-Host "  Profiles skipped: " -NoNewline
        Write-Host $skippedCount -ForegroundColor Yellow
        Write-Host "  Failed deletions: " -NoNewline
        Write-Host $failedCount -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "  Log file: $logPath" -ForegroundColor Cyan
    Write-Host ""

    Write-Log "Profile cleanup completed: $deletedCount deleted, $skippedCount skipped, $failedCount failed" -Level SUCCESS
}
catch {
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Red
    Write-Host " ERROR: Profile Cleanup Failed" -ForegroundColor Red
    Write-Host ("=" * 80) -ForegroundColor Red
    Write-Host ""
    Write-Log "Critical error: $($_.Exception.Message)" -Level ERROR
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Log file: $logPath" -ForegroundColor Yellow
    Write-Host ""

    exit 1
}
