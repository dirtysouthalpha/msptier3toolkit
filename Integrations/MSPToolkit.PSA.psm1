<#
.SYNOPSIS
    MSP Toolkit - PSA / RMM ticket adapter.
.DESCRIPTION
    Vendor-neutral New-MSPTicket function that routes a ticket to whichever
    PSA is configured (Generic webhook, NinjaOne, ConnectWise Manage). Each
    backend is a small switch arm -- easy to extend for HaloPSA, Autotask,
    Atera, Syncro, Halo, etc.

    Config (config.json -> rmmIntegration):
      {
        "platform": "Generic" | "NinjaOne" | "ConnectWise" | "Webhook",
        "apiEndpoint": "https://...",
        "apiKey": "...",
        "extra": { ... }      # platform-specific fields
      }
#>

Set-StrictMode -Version Latest

function New-MSPTicket {
    <#
    .SYNOPSIS
        Create a PSA/RMM ticket. Pipe in an MSP result to auto-fill subject + body.
    .EXAMPLE
        $result | New-MSPTicket -Priority High
    .EXAMPLE
        New-MSPTicket -Subject 'Disk 95% full' -Body 'See report' -Company 'Acme Corp' -Priority Critical
    #>
    [CmdletBinding(DefaultParameterSetName='Manual')]
    param(
        [Parameter(ParameterSetName='Result', Mandatory, ValueFromPipeline)] $Result,
        [Parameter(ParameterSetName='Manual', Mandatory)] [string]$Subject,
        [Parameter(ParameterSetName='Manual')] [string]$Body,
        [string]$Company,
        [ValidateSet('Low','Normal','High','Critical')] [string]$Priority = 'Normal',
        [hashtable]$Extra = @{}
    )

    begin { $cfg = Get-MSPConfig }
    process {
        if ($PSCmdlet.ParameterSetName -eq 'Result') {
            $Subject = "[$($Result.computerName)] $($Result.tool): $($Result.summary)"
            $Body    = "Tool: $($Result.tool)`r`nStatus: $($Result.status)`r`nSummary: $($Result.summary)`r`n`r`nMetrics:`r`n$(($Result.metrics | ConvertTo-Json -Depth 4))"
            $Priority = switch ($Result.status) { 'Failure' { 'High' } 'Warning' { 'Normal' } default { 'Low' } }
        }
        if (-not $cfg.rmmIntegration.enabled) {
            Write-Warning 'RMM integration disabled in config.'; return
        }

        $platform = $cfg.rmmIntegration.platform
        $endpoint = $cfg.rmmIntegration.apiEndpoint
        $apiKey   = $cfg.rmmIntegration.apiKey

        switch ($platform) {
            'Generic' {
                $payload = @{
                    subject  = $Subject; body = $Body; company = $Company
                    priority = $Priority; computerName = $env:COMPUTERNAME; extra = $Extra
                    source   = 'MSPToolkit'; timestamp = (Get-Date).ToString('o')
                }
                Invoke-RestMethod -Uri $endpoint -Method Post -ContentType 'application/json' `
                    -Headers @{ 'X-Api-Key' = $apiKey } -Body ($payload | ConvertTo-Json -Depth 10)
            }
            'Webhook' {
                # Same as Generic but no X-Api-Key -- assumes endpoint has its own auth
                $payload = @{ subject = $Subject; body = $Body; priority = $Priority; computerName = $env:COMPUTERNAME }
                Invoke-RestMethod -Uri $endpoint -Method Post -ContentType 'application/json' `
                    -Body ($payload | ConvertTo-Json -Depth 10)
            }
            'NinjaOne' {
                # NinjaOne expects an OAuth2 client_credentials token first
                $tokenBody = @{
                    grant_type    = 'client_credentials'
                    client_id     = $cfg.rmmIntegration.extra.clientId
                    client_secret = $apiKey
                    scope         = 'monitoring management'
                }
                $tok = Invoke-RestMethod -Uri "$endpoint/oauth/token" -Method Post -Body $tokenBody
                $headers = @{ Authorization = "Bearer $($tok.access_token)" }

                $ninjaPri = @{
                    Critical = 'HIGH'; High = 'HIGH'; Normal = 'MEDIUM'; Low = 'LOW'
                }[$Priority]
                $payload = @{
                    subject     = $Subject
                    description = @{ public = $true; body = $Body; htmlBody = $Body }
                    priority    = $ninjaPri
                    ticketFormId = $cfg.rmmIntegration.extra.ticketFormId
                }
                Invoke-RestMethod -Uri "$endpoint/api/v2/ticketing/ticket" -Method Post `
                    -Headers $headers -ContentType 'application/json' `
                    -Body ($payload | ConvertTo-Json -Depth 10)
            }
            'ConnectWise' {
                # ConnectWise Manage REST -- public/private key auth
                $company    = $cfg.rmmIntegration.extra.company
                $pubKey     = $cfg.rmmIntegration.extra.publicKey
                $privKey    = $apiKey
                $clientId   = $cfg.rmmIntegration.extra.clientId
                $auth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$company+$pubKey`:$privKey"))
                $headers = @{
                    Authorization = "Basic $auth"
                    clientId      = $clientId
                }
                $payload = @{
                    summary    = $Subject.Substring(0, [math]::Min(100, $Subject.Length))
                    initialDescription = $Body
                    board      = @{ id = $cfg.rmmIntegration.extra.boardId }
                    company    = @{ identifier = $Company }
                    priority   = @{ name = $Priority }
                }
                Invoke-RestMethod -Uri "$endpoint/v4_6_release/apis/3.0/service/tickets" `
                    -Method Post -Headers $headers -ContentType 'application/json' `
                    -Body ($payload | ConvertTo-Json -Depth 10)
            }
            default { throw "Unsupported PSA platform: $platform" }
        }
    }
}

Export-ModuleMember -Function 'New-MSPTicket'
