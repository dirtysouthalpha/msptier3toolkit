<#
.SYNOPSIS
    MSP Toolkit - RMM Bi-Directional Integration Module.
.DESCRIPTION
    Deep integration with NinjaOne, ConnectWise Manage, Datto RMM,
    and Autotask. Device sync, custom fields, automated ticketing,
    configuration mapping, and webhook-driven automation.
#>
Set-StrictMode -Version Latest

# =======================================================================
#  NinjaOne Integration
# =======================================================================

function Sync-MSPNinjaOneDevice {
    <#.SYNOPSIS Push MSP Toolkit diagnostics to NinjaOne custom fields.#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ApiEndpoint,
        [Parameter(Mandatory)][securestring]$ApiKey,
        [int]$DeviceId,
        [hashtable]$CustomFields = @{}
    )
    $headers = @{ 'Authorization' = "Bearer $([System.Net.NetworkCredential]::new('',$ApiKey).Password)"; 'Content-Type' = 'application/json' }
    $body = @{ deviceId = $DeviceId; fields = $CustomFields } | ConvertTo-Json -Compress
    try {
        $r = Invoke-RestMethod -Uri "$ApiEndpoint/v2/device/$DeviceId/custom-fields" -Method Put -Headers $headers -Body $body -ErrorAction Stop
        Write-Output "NinjaOne sync OK: $DeviceId"
        return [pscustomobject]@{ Platform='NinjaOne'; DeviceId=$DeviceId; Status='Synced' }
    } catch { throw "NinjaOne sync failed: $($_.Exception.Message)" }
}

function New-MSPNinjaOneTicket {
    <#.SYNOPSIS Create a ticket in NinjaOne from MSP diagnostic results.#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ApiEndpoint,
        [Parameter(Mandatory)][securestring]$ApiKey,
        [Parameter(Mandatory)][string]$Subject,
        [string]$Description,
        [ValidateSet('Critical','High','Medium','Low')][string]$Priority = 'Medium',
        [int]$DeviceId
    )
    $headers = @{ 'Authorization' = "Bearer $([System.Net.NetworkCredential]::new('',$ApiKey).Password)"; 'Content-Type' = 'application/json' }
    $body = @{ subject=$Subject; description=$Description; priority=$Priority; deviceId=$DeviceId } | ConvertTo-Json -Compress
    try {
        $r = Invoke-RestMethod -Uri "$ApiEndpoint/v2/ticketing/ticket" -Method Post -Headers $headers -Body $body -ErrorAction Stop
        return [pscustomobject]@{ Platform='NinjaOne'; TicketId=(if($r.id){$r.id}else{'unknown'}); Status='Created' }
    } catch { throw "NinjaOne ticket creation failed: $($_.Exception.Message)" }
}

# =======================================================================
#  ConnectWise Manage Integration
# =======================================================================

function Sync-MSPConnectWiseConfig {
    <#.SYNOPSIS Sync device configuration to ConnectWise Manage.#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ApiEndpoint,
        [Parameter(Mandatory)][string]$CompanyId,
        [Parameter(Mandatory)][securestring]$ApiKey,
        [string]$ConfigName,
        [hashtable]$Configuration = @{}
    )
    $cred = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$CompanyId+$([System.Net.NetworkCredential]::new('',$ApiKey).Password)"))
    $headers = @{ 'Authorization' = "Basic $cred"; 'Content-Type' = 'application/json' }
    $body = @{ name=$ConfigName; type='Configuration'; company={id=[int]$CompanyId}} + $Configuration | ConvertTo-Json -Depth 5 -Compress
    try {
        $r = Invoke-RestMethod -Uri "$ApiEndpoint/v4_6_release/apis/3.0/company/configurations" -Method Post -Headers $headers -Body $body -ErrorAction Stop
        return [pscustomobject]@{ Platform='ConnectWise'; ConfigId=$r.id; Status='Synced' }
    } catch { throw "ConnectWise sync failed: $($_.Exception.Message)" }
}

function New-MSPConnectWiseTicket {
    <#.SYNOPSIS Create a service ticket in ConnectWise Manage.#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ApiEndpoint,
        [Parameter(Mandatory)][string]$CompanyId,
        [Parameter(Mandatory)][securestring]$ApiKey,
        [Parameter(Mandatory)][string]$Summary,
        [string]$Detail,
        [string]$BoardName = 'Service Board',
        [ValidateSet('Low','Medium','High','Critical')][string]$Priority = 'Medium'
    )
    $cred = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$CompanyId+$([System.Net.NetworkCredential]::new('',$ApiKey).Password)"))
    $headers = @{ 'Authorization' = "Basic $cred"; 'Content-Type' = 'application/json' }
    $body = @{ summary=$Summary; initialDescription=$Detail; priority={name=$Priority}; board={name=$BoardName}; company={id=[int]$CompanyId}; status={name='New'} } | ConvertTo-Json -Depth 5 -Compress
    try {
        $r = Invoke-RestMethod -Uri "$ApiEndpoint/v4_6_release/apis/3.0/service/tickets" -Method Post -Headers $headers -Body $body -ErrorAction Stop
        return [pscustomobject]@{ Platform='ConnectWise'; TicketId=$r.id; Status='Created' }
    } catch { throw "ConnectWise ticket failed: $($_.Exception.Message)" }
}

# =======================================================================
#  Datto RMM Integration
# =======================================================================

function New-MSPDattoComponent {
    <#.SYNOPSIS Deploy a monitoring component from toolkit script output.#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ApiEndpoint,
        [Parameter(Mandatory)][securestring]$ApiKey,
        [Parameter(Mandatory)][string]$ComponentName,
        [string]$ScriptBody,
        [ValidateSet('monitor','script','alert')][string]$Type = 'monitor'
    )
    $headers = @{ 'Authorization' = "Bearer $([System.Net.NetworkCredential]::new('',$ApiKey).Password)"; 'Content-Type' = 'application/json' }
    $body = @{ name=$ComponentName; type=$Type; scriptBody=$ScriptBody } | ConvertTo-Json -Compress
    try {
        $r = Invoke-RestMethod -Uri "$ApiEndpoint/api/v2/component" -Method Post -Headers $headers -Body $body -ErrorAction Stop
        return [pscustomobject]@{ Platform='Datto'; Component=$ComponentName; Status='Created' }
    } catch { throw "Datto component deployment failed: $($_.Exception.Message)" }
}

# =======================================================================
#  Autotask Integration
# =======================================================================

function New-MSPAutotaskTicket {
    <#.SYNOPSIS Create a ticket in Autotask PSA.#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ApiEndpoint,
        [Parameter(Mandatory)][string]$ApiUser,
        [Parameter(Mandatory)][securestring]$ApiPassword,
        [Parameter(Mandatory)][string]$Title,
        [string]$Description,
        [int]$CompanyID,
        [int]$QueueID,
        [ValidateSet('1','2','3','4')][string]$Priority = '3'
    )
    $xmlBody = @"
<ticket>
  <title>$Title</title>
  <description>$Description</description>
  <companyID>$CompanyID</companyID>
  <queueID>$QueueID</queueID>
  <priority>$Priority</priority>
  <status>1</status>
</ticket>
"@
    $cred = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${ApiUser}:$([System.Net.NetworkCredential]::new('',$ApiPassword).Password)"))
    $headers = @{ 'Authorization' = "Basic $cred"; 'Content-Type' = 'application/xml' }
    try {
        $r = Invoke-RestMethod -Uri "$ApiEndpoint/atservicesrest/v1.0/Tickets" -Method Post -Headers $headers -Body $xmlBody -ErrorAction Stop
        return [pscustomobject]@{ Platform='Autotask'; Status='Created' }
    } catch { throw "Autotask ticket failed: $($_.Exception.Message)" }
}

# =======================================================================
#  Orchestrated Diagnostics-to-Ticket Pipeline
# =======================================================================

function Invoke-MSPDiagnosticToTicket {
    <#.SYNOPSIS Run a diagnostic, then auto-create a ticket if status is Warning/Failure.#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$DiagnosticScript,
        [ValidateSet('NinjaOne','ConnectWise','Autotask','Generic')][string]$TargetPSA = 'Generic',
        [hashtable]$PSAConfig = @{},
        [switch]$TicketOnSuccess
    )
    $result = & $DiagnosticScript
    $shouldTicket = $TicketOnSuccess -or $result.Status -in @('Warning','Failure')
    if ($shouldTicket) {
        $summary = '{0}: {1} - {2}' -f $result.Tool, $result.Status, $result.Summary
        switch ($TargetPSA) {
            'NinjaOne' { New-MSPNinjaOneTicket @PSAConfig -Subject $summary -Description ($result | ConvertTo-Json -Depth 5) }
            'ConnectWise' { New-MSPConnectWiseTicket @PSAConfig -Summary $summary -Detail ($result | ConvertTo-Json -Depth 5) }
            'Autotask' { New-MSPAutotaskTicket @PSAConfig -Title $summary -Description ($result | ConvertTo-Json -Depth 5) }
            default { Write-Output "Generic ticket would be created: $summary" }
        }
    }
    return $result
}

# =======================================================================
#  Bulk RMM Device Sync
# =======================================================================

function Sync-MSPBulkDeviceDiagnostics {
    <#.SYNOPSIS Run posture score and push results to RMM custom fields.#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('NinjaOne','ConnectWise')][string]$Platform,
        [hashtable]$Config,
        [int[]]$DeviceIDs
    )
    $results = @()
    foreach ($id in $DeviceIDs) {
        $cfg = $Config.Clone(); $cfg.DeviceId = $id
        try {
            $score = & (Join-Path $PSScriptRoot '..\MSP_Tier3_Toolkit\Security\Get-SecurityPostureScore.ps1')
            $fields = @{ postureScore = $score.Score; lastScan = (Get-Date).ToString('o') }
            if ($Platform -eq 'NinjaOne') { $r = Sync-MSPNinjaOneDevice @cfg -CustomFields $fields }
            else { $r = Sync-MSPConnectWiseConfig @cfg -Configuration $fields }
            $results += [pscustomobject]@{ DeviceId=$id; Synced=$true; Score=$score.Score }
        } catch { $results += [pscustomobject]@{ DeviceId=$id; Synced=$false; Error=$_.Exception.Message } }
    }
    return $results
}

Export-ModuleMember -Function @(
    'Sync-MSPNinjaOneDevice','New-MSPNinjaOneTicket',
    'Sync-MSPConnectWiseConfig','New-MSPConnectWiseTicket',
    'New-MSPDattoComponent',
    'New-MSPAutotaskTicket',
    'Invoke-MSPDiagnosticToTicket',
    'Sync-MSPBulkDeviceDiagnostics'
)
