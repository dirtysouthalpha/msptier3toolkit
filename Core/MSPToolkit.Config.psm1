<#
.SYNOPSIS
    MSP Toolkit - Configuration Management Module
.DESCRIPTION
    Centralized configuration loading and management
#>

$Script:ConfigCache = $null
$Script:ConfigPath = "$PSScriptRoot\..\config.json"

function Get-MSPConfig {
    <#
    .SYNOPSIS
        Load and return the MSP Toolkit configuration
    .PARAMETER Reload
        Force reload configuration from disk
    #>
    [CmdletBinding()]
    param(
        [switch]$Reload
    )

    if ($Script:ConfigCache -and -not $Reload) {
        return $Script:ConfigCache
    }

    try {
        if (Test-Path $Script:ConfigPath) {
            $Script:ConfigCache = Get-Content $Script:ConfigPath -Raw | ConvertFrom-Json
            return $Script:ConfigCache
        } else {
            Write-Warning "Configuration file not found at $Script:ConfigPath"
            return $null
        }
    }
    catch {
        Write-Error "Failed to load configuration: $_"
        return $null
    }
}

function Set-MSPConfigValue {
    <#
    .SYNOPSIS
        Update a configuration value
    .PARAMETER Path
        Dot-notation path to the setting (e.g., "logging.level")
    .PARAMETER Value
        New value to set
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,

        [Parameter(Mandatory=$true)]
        $Value
    )

    try {
        $config = Get-MSPConfig

        # Navigate to the setting
        $pathParts = $Path -split '\.'
        $current = $config

        for ($i = 0; $i -lt $pathParts.Count - 1; $i++) {
            $current = $current.($pathParts[$i])
        }

        # Set the value
        $current.($pathParts[-1]) = $Value

        # Save configuration
        $config | ConvertTo-Json -Depth 10 | Set-Content $Script:ConfigPath -Force

        # Reload cache
        $Script:ConfigCache = $config

        return $true
    }
    catch {
        Write-Error "Failed to set configuration value: $_"
        return $false
    }
}

function Initialize-MSPDirectories {
    <#
    .SYNOPSIS
        Create all required directories from configuration
    #>
    [CmdletBinding()]
    param()

    try {
        $config = Get-MSPConfig

        $directories = @(
            $config.paths.logs,
            $config.paths.reports,
            $config.paths.cache,
            $config.paths.templates,
            $config.paths.knowledgeBase,
            $config.paths.backups
        )

        foreach ($dir in $directories) {
            if ($dir -and -not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Write-Verbose "Created directory: $dir"
            }
        }

        return $true
    }
    catch {
        Write-Error "Failed to initialize directories: $_"
        return $false
    }
}

function Test-MSPAdminRights {
    <#
    .SYNOPSIS
        Check if running with administrator privileges
    #>
    [CmdletBinding()]
    param()

    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-MSPSystemInfo {
    <#
    .SYNOPSIS
        Get basic system information
    #>
    [CmdletBinding()]
    param()

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem
        $bios = Get-CimInstance -ClassName Win32_BIOS

        return [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            OSName = $os.Caption
            OSVersion = $os.Version
            OSBuild = $os.BuildNumber
            Manufacturer = $cs.Manufacturer
            Model = $cs.Model
            SerialNumber = $bios.SerialNumber
            TotalMemoryGB = [Math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
            Domain = $cs.Domain
            Username = $env:USERNAME
            IsAdmin = Test-MSPAdminRights
        }
    }
    catch {
        Write-Error "Failed to get system info: $_"
        return $null
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Get-MSPConfig',
    'Set-MSPConfigValue',
    'Initialize-MSPDirectories',
    'Test-MSPAdminRights',
    'Get-MSPSystemInfo'
)
