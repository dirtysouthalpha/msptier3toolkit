<#
.SYNOPSIS
    Professional Software Uninstaller Tool
.DESCRIPTION
    Safely uninstalls software using registry-based approach (much faster and safer than Win32_Product)
    Supports both MSI and EXE uninstallers with proper error handling and logging
.PARAMETER AppName
    Name of the application to uninstall (supports wildcards)
.PARAMETER Publisher
    Filter by publisher name
.PARAMETER GUID
    Uninstall by specific product GUID
.PARAMETER WhatIf
    Show what would be uninstalled without actually uninstalling
.PARAMETER Force
    Skip confirmation prompts
.PARAMETER Silent
    Run uninstaller in silent mode
.NOTES
    Author: MSP Toolkit Team
    Version: 2.0
    Requires: Administrator privileges
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Position=0, Mandatory=$true, ParameterSetName='ByName')]
    [string]$AppName,

    [Parameter(ParameterSetName='ByName')]
    [string]$Publisher,

    [Parameter(Mandatory=$true, ParameterSetName='ByGUID')]
    [string]$GUID,

    [switch]$WhatIf,
    [switch]$Force,
    [switch]$Silent = $true
)

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

# Initialize logging
$logPath = "$env:TEMP\RemoteUninstall_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$uninstalledCount = 0
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

function Get-InstalledSoftware {
    <#
    .SYNOPSIS
        Gets installed software from registry (FAST and SAFE method)
    #>
    param(
        [string]$Name,
        [string]$Publisher,
        [string]$GUID
    )

    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $software = @()

    foreach ($path in $registryPaths) {
        try {
            $items = Get-ItemProperty $path -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName } |
                Select-Object DisplayName, DisplayVersion, Publisher, UninstallString,
                              QuietUninstallString, PSPath,
                              @{Name='ProductGUID'; Expression={$_.PSChildName}}

            $software += $items
        }
        catch {
            # Silently continue if registry path doesn't exist
        }
    }

    # Filter results
    if ($GUID) {
        $software = $software | Where-Object { $_.ProductGUID -eq $GUID }
    }
    elseif ($Name) {
        $software = $software | Where-Object { $_.DisplayName -like "*$Name*" }
    }

    if ($Publisher) {
        $software = $software | Where-Object { $_.Publisher -like "*$Publisher*" }
    }

    return $software
}

function Invoke-Uninstaller {
    <#
    .SYNOPSIS
        Executes the uninstaller for a software package
    #>
    param(
        [Parameter(Mandatory=$true)]
        $Software,

        [bool]$Silent = $true
    )

    $uninstallString = $Software.QuietUninstallString
    if (-not $uninstallString) {
        $uninstallString = $Software.UninstallString
    }

    if (-not $uninstallString) {
        Write-Log "No uninstall string found for $($Software.DisplayName)" -Level ERROR
        return $false
    }

    Write-Log "Uninstall string: $uninstallString" -Level INFO

    # Parse the uninstall string
    $isMSI = $uninstallString -match 'msiexec'

    try {
        if ($isMSI) {
            # MSI uninstaller
            if ($uninstallString -match '({[A-F0-9-]+})') {
                $productCode = $Matches[1]

                $arguments = @(
                    '/x',
                    $productCode,
                    '/qn',  # Quiet mode, no UI
                    '/norestart',
                    "/L*v `"$env:TEMP\Uninstall_$($Software.DisplayName)_$(Get-Date -Format 'yyyyMMdd_HHmmss').log`""
                )

                Write-Log "Executing: msiexec.exe $($arguments -join ' ')" -Level INFO

                $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -Wait -PassThru -NoNewWindow

                if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
                    Write-Log "Uninstall successful (Exit code: $($process.ExitCode))" -Level SUCCESS
                    return $true
                }
                else {
                    Write-Log "Uninstall failed with exit code: $($process.ExitCode)" -Level ERROR
                    return $false
                }
            }
            else {
                Write-Log "Could not parse MSI product code from uninstall string" -Level ERROR
                return $false
            }
        }
        else {
            # EXE uninstaller
            # Try to parse executable and arguments
            if ($uninstallString -match '^"([^"]+)"(.*)$') {
                $executable = $Matches[1]
                $arguments = $Matches[2].Trim()
            }
            elseif ($uninstallString -match '^([^\s]+)(.*)$') {
                $executable = $Matches[1]
                $arguments = $Matches[2].Trim()
            }
            else {
                $executable = $uninstallString
                $arguments = ''
            }

            # Add silent flags if requested and not already present
            if ($Silent) {
                $silentFlags = @('/S', '/SILENT', '/VERYSILENT', '/quiet', '/q', '-s', '--silent')
                $hasSilentFlag = $false

                foreach ($flag in $silentFlags) {
                    if ($arguments -match [regex]::Escape($flag)) {
                        $hasSilentFlag = $true
                        break
                    }
                }

                if (-not $hasSilentFlag) {
                    # Try common silent switches
                    $arguments += ' /S /VERYSILENT'
                }
            }

            Write-Log "Executing: $executable $arguments" -Level INFO

            if (Test-Path $executable) {
                $process = Start-Process -FilePath $executable -ArgumentList $arguments -Wait -PassThru -NoNewWindow

                if ($process.ExitCode -eq 0) {
                    Write-Log "Uninstall successful" -Level SUCCESS
                    return $true
                }
                else {
                    Write-Log "Uninstall completed with exit code: $($process.ExitCode)" -Level WARNING
                    return $true  # Some uninstallers return non-zero even on success
                }
            }
            else {
                Write-Log "Uninstaller executable not found: $executable" -Level ERROR
                return $false
            }
        }
    }
    catch {
        Write-Log "Exception during uninstall: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

# Main execution
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host " Professional Software Uninstaller Tool" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

Write-Log "Starting software uninstall process..." -Level INFO
Write-Log "Log file: $logPath" -Level INFO
Write-Host ""

# Search for software
Write-Log "Searching for installed software..." -Level INFO

$foundSoftware = if ($GUID) {
    Get-InstalledSoftware -GUID $GUID
} else {
    Get-InstalledSoftware -Name $AppName -Publisher $Publisher
}

if (-not $foundSoftware -or $foundSoftware.Count -eq 0) {
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "  ║                      [NO MATCHES]                         ║" -ForegroundColor Yellow
    Write-Host "  ╠═══════════════════════════════════════════════════════════╣" -ForegroundColor Yellow
    Write-Host "  ║  No software found matching your search criteria          ║" -ForegroundColor Yellow
    Write-Host "  ╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""

    if ($AppName) {
        Write-Log "Search term: $AppName" -Level INFO
    }
    if ($Publisher) {
        Write-Log "Publisher filter: $Publisher" -Level INFO
    }
    if ($GUID) {
        Write-Log "GUID: $GUID" -Level INFO
    }

    Write-Host "  Tip: Try a broader search term or check spelling" -ForegroundColor Gray
    Write-Host ""
    exit 0
}

Write-Log "Found $($foundSoftware.Count) matching software package(s)" -Level SUCCESS
Write-Host ""

# Display found software
Write-Host "  Found Software:" -ForegroundColor Cyan
Write-Host "  " + ("=" * 78) -ForegroundColor DarkGray
foreach ($app in $foundSoftware) {
    Write-Host ""
    Write-Host "  Name:      " -NoNewline -ForegroundColor Gray
    Write-Host $app.DisplayName -ForegroundColor White
    Write-Host "  Version:   " -NoNewline -ForegroundColor Gray
    Write-Host $app.DisplayVersion -ForegroundColor White
    Write-Host "  Publisher: " -NoNewline -ForegroundColor Gray
    Write-Host $app.Publisher -ForegroundColor White
    Write-Host "  GUID:      " -NoNewline -ForegroundColor Gray
    Write-Host $app.ProductGUID -ForegroundColor DarkGray
}
Write-Host ""
Write-Host "  " + ("=" * 78) -ForegroundColor DarkGray
Write-Host ""

# WhatIf mode
if ($WhatIf) {
    Write-Host "  [WhatIf Mode - No software will actually be uninstalled]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Would uninstall $($foundSoftware.Count) package(s)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Log file: $logPath" -ForegroundColor Cyan
    Write-Host ""
    exit 0
}

# Confirmation prompt
if (-not $Force -and $foundSoftware.Count -gt 0) {
    Write-Host "  WARNING: You are about to uninstall $($foundSoftware.Count) software package(s)!" -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "  Continue with uninstall? (Y/N)"

    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Log "Operation cancelled by user" -Level INFO
        Write-Host ""
        Write-Host "  Operation cancelled" -ForegroundColor Yellow
        Write-Host ""
        exit 0
    }
    Write-Host ""
}

# Uninstall each package
try {
    foreach ($app in $foundSoftware) {
        Write-Host ""
        Write-Host "  " + ("─" * 78) -ForegroundColor DarkGray
        Write-Log "Processing: $($app.DisplayName)" -Level INFO

        $result = Invoke-Uninstaller -Software $app -Silent $Silent

        if ($result) {
            $uninstalledCount++
        }
        else {
            $failedCount++
        }
    }

    # Summary
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Green
    Write-Host " Uninstall Process Completed" -ForegroundColor Green
    Write-Host ("=" * 80) -ForegroundColor Green
    Write-Host ""

    Write-Host "  Successfully uninstalled: " -NoNewline -ForegroundColor Gray
    Write-Host $uninstalledCount -ForegroundColor Green

    if ($failedCount -gt 0) {
        Write-Host "  Failed to uninstall:      " -NoNewline -ForegroundColor Gray
        Write-Host $failedCount -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "  Log file: $logPath" -ForegroundColor Cyan
    Write-Host ""

    if ($uninstalledCount -gt 0) {
        Write-Host "  Note: A system restart may be required for changes to take effect" -ForegroundColor Yellow
        Write-Host ""
    }

    Write-Log "Uninstall process completed: $uninstalledCount succeeded, $failedCount failed" -Level SUCCESS
}
catch {
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Red
    Write-Host " ERROR: Uninstall Process Failed" -ForegroundColor Red
    Write-Host ("=" * 80) -ForegroundColor Red
    Write-Host ""
    Write-Log "Critical error: $($_.Exception.Message)" -Level ERROR
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Log file: $logPath" -ForegroundColor Yellow
    Write-Host ""

    exit 1
}
