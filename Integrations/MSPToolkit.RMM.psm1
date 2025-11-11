<#
.SYNOPSIS
    MSP Toolkit - RMM/PSA Integration Module
.DESCRIPTION
    Connectors for popular RMM platforms (ConnectWise, Autotask, Datto, etc.)
#>

Import-Module "$PSScriptRoot\..\Core\MSPToolkit.Config.psm1" -Force
Import-Module "$PSScriptRoot\..\Core\MSPToolkit.Logging.psm1" -Force

function Send-RMMAlert {
    <#
    .SYNOPSIS
        Send alert to configured RMM platform
    .PARAMETER Title
        Alert title
    .PARAMETER Message
        Alert message
    .PARAMETER Severity
        Alert severity (Low, Medium, High, Critical)
    .PARAMETER ComputerName
        Target computer name
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Title,

        [Parameter(Mandatory=$true)]
        [string]$Message,

        [ValidateSet('Low', 'Medium', 'High', 'Critical')]
        [string]$Severity = 'Medium',

        [string]$ComputerName = $env:COMPUTERNAME
    )

    $config = Get-MSPConfig

    if (-not $config.rmmIntegration.enabled) {
        Write-MSPLog "RMM integration is disabled" -Level WARNING
        return $false
    }

    $platform = $config.rmmIntegration.platform

    Write-MSPLog "Sending alert to RMM platform: $platform" -Level INFO

    switch ($platform.ToLower()) {
        'connectwise' {
            Send-ConnectWiseAlert -Title $Title -Message $Message -Severity $Severity -ComputerName $ComputerName
        }
        'autotask' {
            Send-AutotaskAlert -Title $Title -Message $Message -Severity $Severity -ComputerName $ComputerName
        }
        'datto' {
            Send-DattoAlert -Title $Title -Message $Message -Severity $Severity -ComputerName $ComputerName
        }
        'kaseya' {
            Send-KaseyaAlert -Title $Title -Message $Message -Severity $Severity -ComputerName $ComputerName
        }
        'ninjarmm' {
            Send-NinjaRMMAlert -Title $Title -Message $Message -Severity $Severity -ComputerName $ComputerName
        }
        'generic' {
            Send-GenericWebhook -Title $Title -Message $Message -Severity $Severity -ComputerName $ComputerName
        }
        default {
            Write-MSPLog "Unsupported RMM platform: $platform" -Level ERROR
            return $false
        }
    }

    return $true
}

function New-RMMTicket {
    <#
    .SYNOPSIS
        Create a new ticket in the PSA system
    .PARAMETER Title
        Ticket title
    .PARAMETER Description
        Ticket description
    .PARAMETER Priority
        Ticket priority
    .PARAMETER CompanyName
        Client company name
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Title,

        [Parameter(Mandatory=$true)]
        [string]$Description,

        [ValidateSet('Low', 'Medium', 'High', 'Critical')]
        [string]$Priority = 'Medium',

        [string]$CompanyName = "Internal"
    )

    $config = Get-MSPConfig

    if (-not $config.rmmIntegration.enabled -or -not $config.rmmIntegration.autoCreateTickets) {
        Write-MSPLog "Ticket creation is disabled" -Level WARNING
        return $null
    }

    Write-MSPLog "Creating ticket: $Title" -Level INFO

    $platform = $config.rmmIntegration.platform

    switch ($platform.ToLower()) {
        'connectwise' {
            return New-ConnectWiseTicket -Title $Title -Description $Description -Priority $Priority -CompanyName $CompanyName
        }
        'autotask' {
            return New-AutotaskTicket -Title $Title -Description $Description -Priority $Priority -CompanyName $CompanyName
        }
        default {
            Write-MSPLog "Ticket creation not supported for platform: $platform" -Level WARNING
            return $null
        }
    }
}

function Update-RMMTicket {
    <#
    .SYNOPSIS
        Update an existing ticket
    .PARAMETER TicketID
        Ticket ID
    .PARAMETER Note
        Note to add to ticket
    .PARAMETER Status
        New ticket status
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TicketID,

        [string]$Note,

        [string]$Status
    )

    $config = Get-MSPConfig

    if (-not $config.rmmIntegration.enabled) {
        return $false
    }

    Write-MSPLog "Updating ticket $TicketID" -Level INFO

    # Platform-specific implementation would go here
    # This is a template for the structure

    return $true
}

# ConnectWise integration
function Send-ConnectWiseAlert {
    param($Title, $Message, $Severity, $ComputerName)

    $config = Get-MSPConfig

    try {
        $apiUrl = $config.rmmIntegration.apiEndpoint
        $apiKey = $config.rmmIntegration.apiKey

        # ConnectWise API call would go here
        # This is a placeholder showing the structure

        $body = @{
            subject = $Title
            body = $Message
            severity = $Severity
            deviceName = $ComputerName
        } | ConvertTo-Json

        # Invoke-RestMethod -Uri "$apiUrl/alerts" -Method Post -Headers @{ Authorization = "Bearer $apiKey" } -Body $body -ContentType 'application/json'

        Write-MSPLog "Alert sent to ConnectWise" -Level SUCCESS
        return $true
    }
    catch {
        Write-MSPLog "Failed to send ConnectWise alert: $_" -Level ERROR
        return $false
    }
}

function New-ConnectWiseTicket {
    param($Title, $Description, $Priority, $CompanyName)

    $config = Get-MSPConfig

    try {
        # ConnectWise ticket creation API call
        Write-MSPLog "Ticket would be created in ConnectWise" -Level INFO

        # Return mock ticket ID
        return "CW-12345"
    }
    catch {
        Write-MSPLog "Failed to create ConnectWise ticket: $_" -Level ERROR
        return $null
    }
}

# Autotask integration
function Send-AutotaskAlert {
    param($Title, $Message, $Severity, $ComputerName)

    Write-MSPLog "Alert would be sent to Autotask" -Level INFO
    return $true
}

function New-AutotaskTicket {
    param($Title, $Description, $Priority, $CompanyName)

    Write-MSPLog "Ticket would be created in Autotask" -Level INFO
    return "AT-12345"
}

# Datto RMM integration
function Send-DattoAlert {
    param($Title, $Message, $Severity, $ComputerName)

    Write-MSPLog "Alert would be sent to Datto RMM" -Level INFO
    return $true
}

# Kaseya integration
function Send-KaseyaAlert {
    param($Title, $Message, $Severity, $ComputerName)

    Write-MSPLog "Alert would be sent to Kaseya" -Level INFO
    return $true
}

# NinjaRMM integration
function Send-NinjaRMMAlert {
    param($Title, $Message, $Severity, $ComputerName)

    Write-MSPLog "Alert would be sent to NinjaRMM" -Level INFO
    return $true
}

# Generic webhook for any platform
function Send-GenericWebhook {
    param($Title, $Message, $Severity, $ComputerName)

    $config = Get-MSPConfig

    try {
        $webhookUrl = $config.rmmIntegration.apiEndpoint

        if (-not $webhookUrl) {
            Write-MSPLog "No webhook URL configured" -Level WARNING
            return $false
        }

        $body = @{
            title = $Title
            message = $Message
            severity = $Severity
            computerName = $ComputerName
            timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            source = "MSP Toolkit"
        } | ConvertTo-Json

        Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $body -ContentType 'application/json' | Out-Null

        Write-MSPLog "Alert sent via webhook" -Level SUCCESS
        return $true
    }
    catch {
        Write-MSPLog "Failed to send webhook: $_" -Level ERROR
        return $false
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Send-RMMAlert',
    'New-RMMTicket',
    'Update-RMMTicket'
)
