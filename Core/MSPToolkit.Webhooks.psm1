<#
.SYNOPSIS
    MSPToolkit Webhooks & Plugin Marketplace -- Extensibility framework for
    community plugins, custom tool builder, OpenAPI spec, and webhook integrations.
.DESCRIPTION
    Provides a plugin marketplace for community-contributed tools, a custom tool
    builder that generates compliant scripts from JSON templates, OpenAPI 3.0
    spec generation for the REST API, and webhook dispatch for event-driven automation.
    Exported functions:
      Register-MSPPlugin          -- Install a community plugin
      Get-MSPPluginCatalog        -- List available/installed plugins
      New-MSPCustomTool           -- Generate a toolkit-compliant script from template
      Publish-MSPPlugin           -- Package and publish a plugin
      New-MSPOpenApiSpec          -- Generate OpenAPI 3.0 spec for the REST API
      Register-MSPWebhook         -- Register a webhook endpoint
      Invoke-MSPWebhook           -- Dispatch events to registered webhooks
      Get-MSPWebhookHistory       -- View webhook delivery log
.NOTES
    v18.0 -- Community & Extensibility
#>
#Requires -Version 5.1

$script:Plugins = @{}
$script:Webhooks = @{}
$script:WebhookHistory = @()
$script:PersistPath = "$env:APPDATA\MSPToolkit"
$script:WebhookFile = "$script:PersistPath\webhooks.json"
$script:PluginFile = "$script:PersistPath\plugins.json"

function Save-MSPWebhookState {
    [CmdletBinding()]
    param()
    try {
        $state = [PSCustomObject]@{
            SavedAt = (Get-Date).ToString('o')
            Webhooks = @($script:Webhooks.Values)
            History = @($script:WebhookHistory | Select-Object -Last 200)
        }
        if (-not (Test-Path $script:PersistPath)) { New-Item -ItemType Directory -Force -Path $script:PersistPath | Out-Null }
        $state | ConvertTo-Json -Depth 10 | Set-Content $script:WebhookFile -Encoding UTF8
    } catch { Write-Warning "Failed to save webhook state: $($_.Exception.Message)" }
}

function Restore-MSPWebhookState {
    [CmdletBinding()]
    param()
    try {
        if (Test-Path $script:WebhookFile) {
            $s = Get-Content $script:WebhookFile -Raw | ConvertFrom-Json
            $script:Webhooks = @{}
            foreach ($w in $s.Webhooks) { $script:Webhooks[$w.Name] = $w }
            $script:WebhookHistory = @($s.History)
        }
        if (Test-Path $script:PluginFile) {
            $p = Get-Content $script:PluginFile -Raw | ConvertFrom-Json
            $script:Plugins = @{}
            foreach ($pl in $p.Plugins) { $script:Plugins[$pl.Name] = $pl }
        }
    } catch { Write-Warning "Webhook state restore: $($_.Exception.Message)" }
}

function Save-MSPPluginState {
    param()
    $state = [PSCustomObject]@{
        SavedAt = (Get-Date).ToString('o')
        Plugins = @($script:Plugins.Values)
    }
    if (-not (Test-Path $script:PersistPath)) { New-Item -ItemType Directory -Force -Path $script:PersistPath | Out-Null }
    $state | ConvertTo-Json -Depth 10 | Set-Content $script:PluginFile -Encoding UTF8
}

Restore-MSPWebhookState

function Register-MSPPlugin {
    <#
    .SYNOPSIS
        Installs/registers a community plugin from a .ps1 script or URL.
    .PARAMETER Path
        Local path to the plugin .ps1 or .json manifest.
    .PARAMETER Url
        URL to download the plugin from.
    #>
    [CmdletBinding(DefaultParameterSetName='Local')]
    param(
        [Parameter(ParameterSetName='Local',Mandatory=$true)][string]$Path,
        [Parameter(ParameterSetName='Remote',Mandatory=$true)][string]$Url
    )

    $source = if ($Url) {
        $tempPath = "$env:TEMP\MSPPlugin_$(New-Guid).ps1"
        Invoke-WebRequest -Uri $Url -OutFile $tempPath -ErrorAction Stop
        $tempPath
    } else { $Path }

    if (-not (Test-Path $source)) { throw "Plugin source not found: $source" }

    $content = Get-Content $source -Raw
    $manifest = @{}

    if ($content -match '<#\s*@MSPPlugin\s*(.*?)\s*#>') {
        $manifestBlock = $Matches[1]
        $manifestBlock -split '\n' | ForEach-Object {
            if ($_ -match '^\s*\.(\w+)\s+(.*)') {
                $manifest[$Matches[1]] = $Matches[2].Trim()
            }
        }
    }

    if (-not $manifest['Name']) {
        $manifest = @{
            Name = [IO.Path]::GetFileNameWithoutExtension($source)
            Version = '1.0.0'
            Author = 'Unknown'
            Description = 'Community plugin'
        }
    }

    $pluginDir = "$env:APPDATA\MSPToolkit\Plugins\$($manifest['Name'])"
    New-Item -ItemType Directory -Force -Path $pluginDir | Out-Null
    Copy-Item -Path $source -Destination "$pluginDir\$($manifest['Name']).ps1" -Force

    $script:Plugins[$manifest['Name']] = [PSCustomObject]@{
        Name = $manifest['Name']
        Version = $manifest['Version']
        Author = $manifest['Author']
        Description = $manifest['Description']
        Path = "$pluginDir\$($manifest['Name']).ps1"
        InstalledAt = (Get-Date).ToString('o')
        Enabled = $true
    }
    Save-MSPPluginState
    Write-Host "Plugin '$($manifest['Name'])' v$($manifest['Version']) registered." -ForegroundColor Green
    return $script:Plugins[$manifest['Name']]
}

function Get-MSPPluginCatalog {
    [CmdletBinding()]
    param([switch]$IncludeCommunity)

    $installed = $script:Plugins.Values
    $catalog = [PSCustomObject]@{ Installed=$installed; Community=@() }

    if ($IncludeCommunity) {
        try {
            $communityUrl = 'https://raw.githubusercontent.com/dirtysouthalpha/msptier3toolkit/main/community/plugins.json'
            $response = Invoke-RestMethod -Uri $communityUrl -ErrorAction Stop
            $catalog.Community = $response.plugins
        } catch {
            Write-Warning "Community catalog unavailable: $($_.Exception.Message)"
        }
    }

    return $catalog
}

function Publish-MSPPlugin {
    <#
    .SYNOPSIS
        Packages a script as a shareable plugin with manifest and optional signature.
    .PARAMETER ScriptPath
        Path to the script to publish.
    .PARAMETER OutputPath
        Where to save the .msp-plugin package.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ScriptPath,
        [string]$OutputPath
    )

    if (-not $OutputPath) {
        $OutputPath = "$env:TEMP\$(Get-Item $ScriptPath | ForEach-Object { $_.BaseName }).msp-plugin.zip"
    }

    $tempDir = "$env:TEMP\MSPPluginPackage"
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    Copy-Item $ScriptPath "$tempDir\$(Get-Item $ScriptPath).Name" -Force

    $manifest = @{
        name = (Get-Item $ScriptPath).BaseName
        version = '1.0.0'
        author = $env:USERNAME
        description = 'Exported tool'
        exportedAt = (Get-Date).ToString('o')
    }
    $manifest | ConvertTo-Json | Set-Content "$tempDir\plugin.json"

    Compress-Archive -Path "$tempDir\*" -DestinationPath $OutputPath -Force
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue

    return [PSCustomObject]@{ Package=$OutputPath; SizeKB=[math]::Round((Get-Item $OutputPath).Length/1KB,1) }
}

function New-MSPCustomTool {
    <#
    .SYNOPSIS
        Generates a toolkit-compliant PowerShell script from a JSON template.
    .PARAMETER TemplatePath
        Path to JSON template file.
    .PARAMETER OutputPath
        Where to write the generated .ps1 file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$TemplatePath,
        [string]$OutputPath
    )

    $template = Get-Content $TemplatePath -Raw | ConvertFrom-Json

    if (-not $OutputPath) {
        $cat = if ($template.category) { $template.category } else { 'Custom' }
        $OutputPath = "$PSScriptRoot\..\MSP_Tier3_Toolkit\$cat\$($template.name).ps1"
    }

    $params = if ($template.parameters) {
        ($template.parameters | ForEach-Object {
            "        [Parameter(Mandatory=`$$($_.mandatory))]
        [$($_.type)]`$$($_.name)$(if($_.default){' = '+$_.default})"
        }) -join ",`n"
    } else { '' }

    $code = @"
<#
.SYNOPSIS
    $($template.synopsis)
.DESCRIPTION
    $($template.description)
.NOTES
    Generated by MSP Custom Tool Builder v18.0
    Category: $($template.category)
#>
[CmdletBinding()]
param(
$params
)

[PSCustomObject]@{
    Timestamp = (Get-Date).ToString('o')
    Checks = @()
    Score = 0
    MaxScore = 0
    Summary = ''
}

try {
    $($template.script)
    $data.Checks += [PSCustomObject]@{ Name='Completed'; Pass=$true; Detail='Execution succeeded' }
} catch {
    $data.Checks += [PSCustomObject]@{ Name='Completed'; Pass=$false; Detail=$_.Exception.Message }
}

[PSCustomObject]@{
    MaxScore = ($data.Checks | Measure-Object).Count * 20
    Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
    Summary = ('Custom tool: {0}/{1}' -f ($data.Checks | Where-Object { $_.Pass }).Count, ($data.Checks | Measure-Object).Count)
}
"@

    $parentDir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $parentDir)) { New-Item -ItemType Directory -Force -Path $parentDir | Out-Null }

    Set-Content -Path $OutputPath -Value $code -Encoding UTF8

    Write-Host "Custom tool generated: $OutputPath" -ForegroundColor Green
    return [PSCustomObject]@{ Name=$template.name; Path=$OutputPath; Category=$template.category }
}

function New-MSPOpenApiSpec {
    <#
    .SYNOPSIS
        Generates an OpenAPI 3.0 specification for the MSP REST API.
    .PARAMETER OutputPath
        Where to write the openapi.json file.
    #>
    [CmdletBinding()]
    param([string]$OutputPath = "$env:TEMP\MSP_OpenAPI.json")

    $spec = @{
        openapi = '3.0.3'
        info = @{
            title = 'MSP Tier 3 Toolkit API'
            version = '18.0.0'
            description = 'REST API for MSP Tier 3 Toolkit -- execute diagnostics, manage tenants, and retrieve reports.'
        }
        servers = @(
            @{ url='http://localhost:8080'; description='Local instance' }
        )
        paths = @{
            '/api/health' = @{
                get = @{
                    summary = 'System health'
                    description = 'Returns live CPU, memory, disk, uptime, and pending reboot status.'
                    responses = @{
                        '200' = @{ description='Health metrics'; content=@{ 'application/json'=@{ schema=@{ '$ref'='#/components/schemas/HealthResponse' } } } }
                    }
                }
            }
            '/api/scripts' = @{
                get = @{
                    summary = 'List available scripts'
                    description = 'Returns the full tool catalog with categories.'
                    parameters = @(
                        @{ name='q'; in='query'; schema=@{ type='string' }; description='Search query' }
                        @{ name='category'; in='query'; schema=@{ type='string' }; description='Filter by category' }
                    )
                    responses = @{
                        '200' = @{ description='Script catalog'; content=@{ 'application/json'=@{ schema=@{ type='array'; items=@{ '$ref'='#/components/schemas/ScriptItem' } } } } }
                    }
                }
            }
            '/api/scripts/run' = @{
                post = @{
                    summary = 'Execute a script'
                    description = 'Runs a toolkit script by name with optional parameters.'
                    requestBody = @{
                        required = $true
                        content = @{ 'application/json'=@{ schema=@{ type='object'; properties=@{ script=@{ type='string'; example='Get-QuickTriageReport' }; params=@{ type='object' } } } } }
                    }
                    responses = @{
                        '202' = @{ description='Job accepted'; content=@{ 'application/json'=@{ schema=@{ '$ref'='#/components/schemas/JobResponse' } } } }
                    }
                }
            }
            '/api/jobs/{id}' = @{
                get = @{
                    summary = 'Get job status'
                    parameters = @( @{ name='id'; in='path'; required=$true; schema=@{ type='string' } } )
                    responses = @{
                        '200' = @{ description='Job status'; content=@{ 'application/json'=@{ schema=@{ '$ref'='#/components/schemas/JobResponse' } } } }
                    }
                }
            }
        }
        components = @{
            schemas = @{
                HealthResponse = @{ type='object'; properties=@{ computerName=@{ type='string' }; cpuPercent=@{ type='number' }; memoryUsagePercent=@{ type='number' }; diskFreeGB=@{ type='number' }; uptimeHours=@{ type='number' }; pendingReboot=@{ type='boolean' }; platform=@{ type='string' } } }
                ScriptItem = @{ type='object'; properties=@{ name=@{ type='string' }; path=@{ type='string' }; category=@{ type='string' }; description=@{ type='string' }; requiresAdmin=@{ type='boolean' } } }
                JobResponse = @{ type='object'; properties=@{ id=@{ type='string' }; status=@{ type='string'; enum=@('running','completed','failed') }; result=@{ type='object' }; error=@{ type='string' } } }
            }
        }
    }

    $spec | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8
    return [PSCustomObject]@{ Path=$OutputPath; Endpoints=4 }
}

function Register-MSPWebhook {
    <#
    .SYNOPSIS
        Registers a webhook endpoint for event notifications.
    .PARAMETER Name
        Webhook identifier.
    .PARAMETER Url
        Target URL (HTTPS required).
    .PARAMETER Events
        Event types to subscribe to (JobCompleted, Alert, Audit, All).
    .PARAMETER Secret
        HMAC secret for payload signing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Url,
        [string[]]$Events = @('All'),
        [string]$Secret
    )

    $wh = [PSCustomObject]@{
        Id = [Guid]::NewGuid().ToString()
        Name = $Name
        Url = $Url
        Events = $Events
        Secret = $Secret
        CreatedAt = (Get-Date).ToString('o')
        Enabled = $true
        FailCount = 0
    }

    $script:Webhooks[$Name] = $wh
    Save-MSPWebhookState
    return $wh
}

function Invoke-MSPWebhook {
    <#
    .SYNOPSIS
        Dispatches an event to all registered webhooks subscribed to its type.
    .PARAMETER EventType
        Event category.
    .PARAMETER Payload
        JSON-serializable data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateSet('JobCompleted','Alert','Audit','Test')][string]$EventType,
        [Parameter(Mandatory=$true)]$Payload
    )

    $results = @()
    foreach ($wh in $script:Webhooks.Values | Where-Object { $_.Enabled -and ($_.Events -contains 'All' -or $_.Events -contains $EventType) }) {
        $body = @{
            eventType = $EventType
            timestamp = (Get-Date).ToString('o')
            source = $env:COMPUTERNAME
            payload = $Payload
        } | ConvertTo-Json -Depth 10

        $headers = @{ 'Content-Type' = 'application/json' }
        if ($wh.Secret) {
            $hmac = [System.Security.Cryptography.HMACSHA256]::new([Text.Encoding]::UTF8.GetBytes($wh.Secret))
            $sigBytes = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($body))
            $headers['X-MSP-Signature'] = [BitConverter]::ToString($sigBytes) -replace '-',''
        }

        try {
            Invoke-RestMethod -Uri $wh.Url -Method Post -Body $body -Headers $headers -ErrorAction Stop | Out-Null
            $result = [PSCustomObject]@{ Webhook=$wh.Name; Success=$true; StatusCode=200 }
        } catch {
            $wh.FailCount++
            $result = [PSCustomObject]@{ Webhook=$wh.Name; Success=$false; Error=$_.Exception.Message }
            if ($wh.FailCount -gt 10) { $wh.Enabled = $false }
        }

        $script:WebhookHistory += [PSCustomObject]@{
            Timestamp = (Get-Date).ToString('o')
            Webhook = $wh.Name
            EventType = $EventType
            Success = $result.Success
            Error = $result.Error
        }
        if ($script:WebhookHistory.Count -gt 500) { $script:WebhookHistory = $script:WebhookHistory[-500..-1] }

        $results += $result
    }
    if ($results | Where-Object { -not $_.Success }) { Save-MSPWebhookState }
    return $results
}

function Get-MSPWebhookHistory {
    <#
    .SYNOPSIS
        Retrieves webhook delivery history.
    .PARAMETER WebhookName
        Filter by webhook name.
    .PARAMETER MaxResults
        Limit results.
    #>
    [CmdletBinding()]
    param(
        [string]$WebhookName,
        [int]$MaxResults = 100
    )

    $history = $script:WebhookHistory
    if ($WebhookName) { $history = $history | Where-Object { $_.Webhook -eq $WebhookName } }
    return $history | Select-Object -Last $MaxResults | Sort-Object Timestamp -Descending
}

Export-ModuleMember -Function @(
    'Register-MSPPlugin',
    'Get-MSPPluginCatalog',
    'New-MSPCustomTool',
    'Publish-MSPPlugin',
    'New-MSPOpenApiSpec',
    'Register-MSPWebhook',
    'Invoke-MSPWebhook',
    'Get-MSPWebhookHistory',
    'Save-MSPWebhookState',
    'Restore-MSPWebhookState',
    'Save-MSPPluginState'
)
