<#
.SYNOPSIS
    MSP Toolkit - Notification sinks (Teams, Slack, Discord, SMTP, generic webhook).
.DESCRIPTION
    Single Send-MSPNotification function that routes a message to whichever
    channels are configured. Designed so scripts can fire-and-forget without
    knowing where messages land.
#>

Set-StrictMode -Version Latest

function Send-MSPTeamsMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$WebhookUrl,
        [Parameter(Mandatory)] [string]$Title,
        [string]$Text,
        [ValidateSet('good','warning','attention','accent')] [string]$Theme = 'accent',
        [hashtable]$Facts = @{}
    )

    $color = switch ($Theme) {
        'good'      { '00C853' }
        'warning'   { 'FFB300' }
        'attention' { 'D32F2F' }
        default     { '5B6CFA' }
    }

    $sections = @(@{ activityTitle = $Title; markdown = $true })
    if ($Text)  { $sections[0].text = $Text }
    if ($Facts.Count) {
        $sections[0].facts = @($Facts.GetEnumerator() | ForEach-Object {
            @{ name = "$($_.Key)"; value = "$($_.Value)" }
        })
    }

    $body = @{
        '@type'      = 'MessageCard'
        '@context'   = 'https://schema.org/extensions'
        themeColor   = $color
        summary      = $Title
        sections     = $sections
    } | ConvertTo-Json -Depth 10

    Invoke-RestMethod -Uri $WebhookUrl -Method Post -ContentType 'application/json' -Body $body | Out-Null
}

function Send-MSPSlackMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$WebhookUrl,
        [Parameter(Mandatory)] [string]$Title,
        [string]$Text,
        [ValidateSet('good','warning','danger','info')] [string]$Theme = 'info'
    )

    $color = switch ($Theme) {
        'good'    { '#00C853' }
        'warning' { '#FFB300' }
        'danger'  { '#D32F2F' }
        default   { '#5B6CFA' }
    }

    $body = @{
        attachments = @(@{
            color   = $color
            title   = $Title
            text    = $Text
            ts      = [int][double]::Parse((Get-Date -UFormat %s))
            footer  = "MSP Toolkit on $env:COMPUTERNAME"
        })
    } | ConvertTo-Json -Depth 10

    Invoke-RestMethod -Uri $WebhookUrl -Method Post -ContentType 'application/json' -Body $body | Out-Null
}

function Send-MSPDiscordMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$WebhookUrl,
        [Parameter(Mandatory)] [string]$Title,
        [string]$Text,
        [ValidateSet('good','warning','danger','info')] [string]$Theme = 'info'
    )

    $color = switch ($Theme) {
        'good'    { 51400  }
        'warning' { 16753920 }
        'danger'  { 13841214 }
        default   { 5985018 }
    }

    $body = @{
        embeds = @(@{
            title       = $Title
            description = $Text
            color       = $color
            timestamp   = (Get-Date).ToString('o')
            footer      = @{ text = "MSP Toolkit on $env:COMPUTERNAME" }
        })
    } | ConvertTo-Json -Depth 10

    Invoke-RestMethod -Uri $WebhookUrl -Method Post -ContentType 'application/json' -Body $body | Out-Null
}

function Send-MSPEmail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Subject,
        [Parameter(Mandatory)] [string]$Body,
        [string]$From,
        [string[]]$To,
        [string]$SmtpServer,
        [int]$Port = 587,
        [PSCredential]$Credential,
        [switch]$UseSsl = $true,
        [switch]$BodyAsHtml = $true
    )

    if (-not $SmtpServer) {
        $cfg = Get-MSPConfig
        $SmtpServer = $cfg.notifications.smtpServer
        $Port       = $cfg.notifications.smtpPort
        $From       = $cfg.notifications.fromAddress
        if (-not $To) { $To = $cfg.notifications.toAddresses }
    }
    if (-not ($SmtpServer -and $From -and $To)) {
        throw 'SMTP not configured (notifications.smtpServer / fromAddress / toAddresses).'
    }

    # Send-MailMessage is deprecated; use System.Net.Mail directly
    $client = [System.Net.Mail.SmtpClient]::new($SmtpServer, $Port)
    $client.EnableSsl = $UseSsl.IsPresent
    if ($Credential) { $client.Credentials = $Credential.GetNetworkCredential() }

    $msg = [System.Net.Mail.MailMessage]::new()
    $msg.From = $From
    foreach ($t in $To) { $msg.To.Add($t) }
    $msg.Subject = $Subject
    $msg.Body = $Body
    $msg.IsBodyHtml = $BodyAsHtml.IsPresent
    $client.Send($msg)
    $msg.Dispose()
    $client.Dispose()
}

function Send-MSPNotification {
    <#
    .SYNOPSIS
        Fire-and-forget notification -- dispatches to whichever channels are
        configured in config.notifications. Pass an MSP result object and the
        title/theme will be inferred.
    .EXAMPLE
        $result | Send-MSPNotification
    .EXAMPLE
        Send-MSPNotification -Title 'Backup failed' -Text 'See logs.' -Theme danger
    #>
    [CmdletBinding(DefaultParameterSetName='Manual')]
    param(
        [Parameter(ParameterSetName='Result', Mandatory, ValueFromPipeline)]
        $Result,

        [Parameter(ParameterSetName='Manual', Mandatory)]
        [string]$Title,
        [Parameter(ParameterSetName='Manual')]
        [string]$Text,
        [Parameter(ParameterSetName='Manual')]
        [ValidateSet('good','warning','danger','info','accent','attention')]
        [string]$Theme = 'info',

        [hashtable]$ExtraFacts = @{}
    )

    begin { $cfg = Get-MSPConfig }
    process {
        if ($PSCmdlet.ParameterSetName -eq 'Result') {
            $Title = "[$($Result.computerName)] $($Result.tool): $($Result.status)"
            $Text  = $Result.summary
            $Theme = switch ($Result.status) {
                'Success' { 'good' }
                'Warning' { 'warning' }
                'Failure' { 'danger' }
                default   { 'info' }
            }
        }

        $teamsUrl = $cfg.notifications.teamsWebhookUrl
        $slackUrl = $cfg.notifications.slackWebhookUrl
        $discord  = $null
        if ($cfg.notifications.PSObject.Properties.Name -contains 'discordWebhookUrl') {
            $discord = $cfg.notifications.discordWebhookUrl
        }

        if ($teamsUrl) {
            try { Send-MSPTeamsMessage -WebhookUrl $teamsUrl -Title $Title -Text $Text -Theme ($Theme -replace 'danger','attention') -Facts $ExtraFacts } catch { Write-Warning "Teams: $_" }
        }
        if ($slackUrl) {
            try { Send-MSPSlackMessage -WebhookUrl $slackUrl -Title $Title -Text $Text -Theme $Theme } catch { Write-Warning "Slack: $_" }
        }
        if ($discord) {
            try { Send-MSPDiscordMessage -WebhookUrl $discord -Title $Title -Text $Text -Theme $Theme } catch { Write-Warning "Discord: $_" }
        }
        if ($cfg.notifications.emailEnabled) {
            try { Send-MSPEmail -Subject $Title -Body $Text } catch { Write-Warning "Email: $_" }
        }
    }
}

Export-ModuleMember -Function @(
    'Send-MSPTeamsMessage','Send-MSPSlackMessage','Send-MSPDiscordMessage',
    'Send-MSPEmail','Send-MSPNotification'
)
