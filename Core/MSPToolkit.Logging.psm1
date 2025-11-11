<#
.SYNOPSIS
    MSP Toolkit - Unified Logging Module
.DESCRIPTION
    Beautiful, standardized logging system with color support, log rotation, and multiple outputs
#>

$Script:Config = $null
$Script:LogPath = $null
$Script:SessionId = (New-Guid).ToString().Substring(0,8)

# Color definitions
$Script:Colors = @{
    'SUCCESS' = 'Green'
    'INFO' = 'Cyan'
    'WARNING' = 'Yellow'
    'ERROR' = 'Red'
    'DEBUG' = 'Magenta'
    'HEADER' = 'White'
    'EMPHASIS' = 'Yellow'
}

function Initialize-MSPLogging {
    <#
    .SYNOPSIS
        Initialize the logging system
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigPath = "$PSScriptRoot\..\config.json",
        [string]$ScriptName = "MSPToolkit"
    )

    try {
        # Load configuration
        if (Test-Path $ConfigPath) {
            $Script:Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        } else {
            Write-Warning "Config file not found at $ConfigPath. Using defaults."
            $Script:Config = @{ logging = @{ enabled = $true; logToFile = $true; logToConsole = $true } }
        }

        # Create log directory
        $logDir = $Script:Config.paths.logs
        if (-not $logDir) { $logDir = "C:\MSPToolkit\Logs" }

        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }

        # Set log file path
        $timestamp = Get-Date -Format "yyyyMMdd"
        $Script:LogPath = Join-Path $logDir "$ScriptName`_$timestamp`_$Script:SessionId.log"

        # Clean old logs if needed
        if ($Script:Config.logging.retentionDays) {
            $cutoffDate = (Get-Date).AddDays(-$Script:Config.logging.retentionDays)
            Get-ChildItem -Path $logDir -Filter "*.log" |
                Where-Object { $_.LastWriteTime -lt $cutoffDate } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }

        return $true
    }
    catch {
        Write-Warning "Failed to initialize logging: $_"
        return $false
    }
}

function Write-MSPLog {
    <#
    .SYNOPSIS
        Write a log entry with beautiful formatting
    .PARAMETER Message
        The message to log
    .PARAMETER Level
        Log level: INFO, SUCCESS, WARNING, ERROR, DEBUG
    .PARAMETER NoConsole
        Skip console output
    .PARAMETER NoFile
        Skip file output
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Message,

        [Parameter(Position=1)]
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR', 'DEBUG', 'HEADER')]
        [string]$Level = 'INFO',

        [switch]$NoConsole,
        [switch]$NoFile
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    # Console output with colors
    if (-not $NoConsole -and $Script:Config.logging.logToConsole) {
        $color = $Script:Colors[$Level]

        switch ($Level) {
            'SUCCESS' {
                Write-Host "[+] " -ForegroundColor Green -NoNewline
                Write-Host $Message -ForegroundColor $color
            }
            'ERROR' {
                Write-Host "[X] " -ForegroundColor Red -NoNewline
                Write-Host $Message -ForegroundColor $color
            }
            'WARNING' {
                Write-Host "[!] " -ForegroundColor Yellow -NoNewline
                Write-Host $Message -ForegroundColor $color
            }
            'INFO' {
                Write-Host "[i] " -ForegroundColor Cyan -NoNewline
                Write-Host $Message -ForegroundColor $color
            }
            'DEBUG' {
                Write-Host "[D] " -NoNewline
                Write-Host $Message -ForegroundColor $color
            }
            'HEADER' {
                Write-Host ""
                Write-Host ("═" * 80) -ForegroundColor $color
                Write-Host " $Message" -ForegroundColor $color
                Write-Host ("═" * 80) -ForegroundColor $color
                Write-Host ""
            }
        }
    }

    # File output
    if (-not $NoFile -and $Script:Config.logging.logToFile -and $Script:LogPath) {
        try {
            Add-Content -Path $Script:LogPath -Value $logEntry -ErrorAction SilentlyContinue
        }
        catch {
            # Silently fail to prevent logging errors from breaking scripts
        }
    }
}

function Write-MSPProgress {
    <#
    .SYNOPSIS
        Display a beautiful progress bar
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Activity,

        [Parameter(Mandatory=$true)]
        [string]$Status,

        [Parameter(Mandatory=$true)]
        [int]$PercentComplete,

        [int]$Id = 1
    )

    Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete -Id $Id
}

function Show-MSPBanner {
    <#
    .SYNOPSIS
        Display the epic MSP Toolkit banner
    #>
    [CmdletBinding()]
    param(
        [string]$Version = "2.0.0"
    )

    $banner = @"

    ███╗   ███╗███████╗██████╗     ████████╗ ██████╗  ██████╗ ██╗     ██╗  ██╗██╗████████╗
    ████╗ ████║██╔════╝██╔══██╗    ╚══██╔══╝██╔═══██╗██╔═══██╗██║     ██║ ██╔╝██║╚══██╔══╝
    ██╔████╔██║███████╗██████╔╝       ██║   ██║   ██║██║   ██║██║     █████╔╝ ██║   ██║
    ██║╚██╔╝██║╚════██║██╔═══╝        ██║   ██║   ██║██║   ██║██║     ██╔═██╗ ██║   ██║
    ██║ ╚═╝ ██║███████║██║            ██║   ╚██████╔╝╚██████╔╝███████╗██║  ██╗██║   ██║
    ╚═╝     ╚═╝╚══════╝╚═╝            ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝   ╚═╝

              ╔════════════════════════════════════════════════════════════╗
              ║        TIER 3 SUPPORT AUTOMATION PLATFORM v$Version         ║
              ║              Dazzle. Automate. Dominate.                  ║
              ╚════════════════════════════════════════════════════════════╝

"@

    Write-Host $banner -ForegroundColor Cyan
    Write-Host "  Session ID: " -NoNewline -ForegroundColor Gray
    Write-Host $Script:SessionId -ForegroundColor Yellow
    Write-Host "  Timestamp:  " -NoNewline -ForegroundColor Gray
    Write-Host (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -ForegroundColor Yellow
    Write-Host ""
}

function Show-MSPSuccess {
    <#
    .SYNOPSIS
        Display a success message with ASCII art
    #>
    [CmdletBinding()]
    param(
        [string]$Message = "Operation completed successfully!"
    )

    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║                     [SUCCESS]                             ║" -ForegroundColor Green
    Write-Host "  ╠═══════════════════════════════════════════════════════════╣" -ForegroundColor Green
    $msgPadded = if ($Message.Length -gt 55) { $Message.Substring(0, 55) } else { $Message.PadRight(55) }
    Write-Host "  ║  $msgPadded  ║" -ForegroundColor Green
    Write-Host "  ╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
}

function Show-MSPError {
    <#
    .SYNOPSIS
        Display an error message with ASCII art
    #>
    [CmdletBinding()]
    param(
        [string]$Message = "Operation failed!",
        [string]$Details = ""
    )

    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "  ║                      [ERROR]                              ║" -ForegroundColor Red
    Write-Host "  ╠═══════════════════════════════════════════════════════════╣" -ForegroundColor Red
    $msgPadded = if ($Message.Length -gt 55) { $Message.Substring(0, 55) } else { $Message.PadRight(55) }
    Write-Host "  ║  $msgPadded  ║" -ForegroundColor Red
    if ($Details) {
        Write-Host "  ║                                                           ║" -ForegroundColor Red
        $detailsText = "Details: $Details"
        $detailsPadded = if ($detailsText.Length -gt 55) { $detailsText.Substring(0, 55) } else { $detailsText.PadRight(55) }
        Write-Host "  ║  $detailsPadded  ║" -ForegroundColor Red
    }
    Write-Host "  ╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
}

function Show-MSPBox {
    <#
    .SYNOPSIS
        Display text in a beautiful box
    #>
    [CmdletBinding()]
    param(
        [string]$Title,
        [string[]]$Lines,
        [string]$Color = 'Cyan'
    )

    $maxLength = ($Lines | Measure-Object -Property Length -Maximum).Maximum
    $maxLength = [Math]::Max($maxLength, $Title.Length) + 4

    Write-Host ""
    Write-Host "  ╔$('═' * $maxLength)╗" -ForegroundColor $Color
    if ($Title) {
        Write-Host "  ║ $($Title.PadRight($maxLength - 1))║" -ForegroundColor $Color
        Write-Host "  ╠$('═' * $maxLength)╣" -ForegroundColor $Color
    }
    foreach ($line in $Lines) {
        Write-Host "  ║ $($line.PadRight($maxLength - 1))║" -ForegroundColor $Color
    }
    Write-Host "  ╚$('═' * $maxLength)╝" -ForegroundColor $Color
    Write-Host ""
}

function Write-MSPTable {
    <#
    .SYNOPSIS
        Display data in a beautiful table format
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object[]]$Data,

        [string[]]$Properties,

        [string]$Title
    )

    if (-not $Properties) {
        $Properties = $Data[0].PSObject.Properties.Name
    }

    Write-Host ""
    if ($Title) {
        Write-Host "  $Title" -ForegroundColor Cyan
        Write-Host "  $('═' * $Title.Length)" -ForegroundColor Cyan
        Write-Host ""
    }

    $Data | Format-Table -Property $Properties -AutoSize | Out-String | Write-Host -ForegroundColor White
}

# Export module members
Export-ModuleMember -Function @(
    'Initialize-MSPLogging',
    'Write-MSPLog',
    'Write-MSPProgress',
    'Show-MSPBanner',
    'Show-MSPSuccess',
    'Show-MSPError',
    'Show-MSPBox',
    'Write-MSPTable'
)
