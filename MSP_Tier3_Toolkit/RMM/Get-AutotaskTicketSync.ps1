<#
.SYNOPSIS
    Validates Autotask PSA integration, API connectivity, and ticket synchronization.
.DESCRIPTION
    Checks Autotask REST API endpoint reachability, credentials, resource/company info,
    and recent ticket activity. Also checks Datto RMM integration bridge if present.
.NOTES
    v13.0 -- RMM Deep Integration
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ApiUsername,
    [Parameter(Mandatory=$false)]
    [string]$ApiPassword,
    [Parameter(Mandatory=$false)]
    [string]$ApiIntegrationCode,
    [Parameter(Mandatory=$false)]
    [string]$ApiBaseUrl = 'https://webservices.autotask.net/atservicesrest/v1.0'
)

$data = [PSCustomObject]@{
    Timestamp           = (Get-Date).ToString('o')
    ApiConfigured       = $false
    ApiReachable        = $false
    ResourceCount       = 0
    RecentTicketCount   = 0
    DattoRmmBridgeFound = $false
    Checks              = @()
    Score               = 0
    MaxScore            = 0
    Summary             = ''
}

# Attempt to load from registry
if (-not $ApiUsername) {
    $atReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Autotask' -ErrorAction SilentlyContinue
    if ($atReg) {
        $ApiUsername = $atReg.ApiUsername
        $ApiPassword = $atReg.ApiPassword
        $ApiIntegrationCode = $atReg.IntegrationCode
    }
}

$data.ApiConfigured = ($ApiUsername -and $ApiPassword -and $ApiIntegrationCode)
$data.Checks += [PSCustomObject]@{ Name='Credentials Configured'; Pass=$data.ApiConfigured; Detail=$(if($data.ApiConfigured){'API credentials found'}else{'Missing credentials'}) }

# Check API reachability
if ($data.ApiConfigured) {
    try {
        $authValue = "$ApiUsername`:$ApiPassword"
        $authBytes = [Text.Encoding]::ASCII.GetBytes($authValue)
        $authB64 = [Convert]::ToBase64String($authBytes)
        $headers = @{
            Authorization = "Basic $authB64"
            ApiIntegrationCode = $ApiIntegrationCode
            'Content-Type' = 'application/json'
        }
        $response = Invoke-RestMethod -Uri "$ApiBaseUrl/Resources" -Headers $headers -Method Get -ErrorAction Stop
        if ($response.items) {
            $data.ApiReachable = $true
            $data.ResourceCount = $response.items.Count
            $data.Checks += [PSCustomObject]@{ Name='API Reachable'; Pass=$true; Detail="$($data.ResourceCount) resources found" }
        } else {
            $data.Checks += [PSCustomObject]@{ Name='API Reachable'; Pass=$false; Detail='No resources returned' }
        }

        # Recent tickets
        $tickets = Invoke-RestMethod -Uri "$ApiBaseUrl/Tickets`?MaxRecords=5" -Headers $headers -Method Get -ErrorAction SilentlyContinue
        if ($tickets.items) {
            $data.RecentTicketCount = $tickets.items.Count
            $data.Checks += [PSCustomObject]@{ Name='Tickets Accessible'; Pass=($data.RecentTicketCount -gt 0); Detail="$($data.RecentTicketCount) recent tickets" }
        } else {
            $data.Checks += [PSCustomObject]@{ Name='Tickets Accessible'; Pass=$false; Detail='No tickets returned' }
        }
    } catch {
        $data.Checks += [PSCustomObject]@{ Name='API Reachable'; Pass=$false; Detail="Error: $($_.Exception.Message)" }
        $data.Checks += [PSCustomObject]@{ Name='Tickets Accessible'; Pass=$false; Detail='API connection failed' }
    }
} else {
    $data.Checks += [PSCustomObject]@{ Name='API Reachable'; Pass=$false; Detail='Skipped' }
    $data.Checks += [PSCustomObject]@{ Name='Tickets Accessible'; Pass=$false; Detail='Skipped' }
}

# Check Datto RMM bridge (Datto acquired Autotask)
$dRmmReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\CentraStage' -ErrorAction SilentlyContinue
if (-not $dRmmReg) { $dRmmReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Datto\RMM' -ErrorAction SilentlyContinue }
$data.DattoRmmBridgeFound = ($null -ne $dRmmReg)
$data.Checks += [PSCustomObject]@{ Name='Datto RMM Bridge'; Pass=$data.DattoRmmBridgeFound; Detail=$(if($data.DattoRmmBridgeFound){'Found -- Datto RMM linked'}else{'No bridge detected'}) }

$data.MaxScore = $data.Checks.Count * 20
$data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
$data.Summary = "Autotask: $($data.Score)/$($data.MaxScore) -- API: $(if($data.ApiReachable){'OK'}else{'FAIL'}) | Resources: $($data.ResourceCount) | Tickets: $($data.RecentTicketCount)"

return $data
