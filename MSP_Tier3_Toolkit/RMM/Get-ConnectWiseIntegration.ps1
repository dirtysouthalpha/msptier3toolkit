<#
.SYNOPSIS
    Validates ConnectWise Manage (PSA) integration configuration and connectivity.
.DESCRIPTION
    Checks ConnectWise Manage REST API endpoint reachability, credentials,
    company/member info, and recent ticket activity from the local agent.
.NOTES
    v13.0 -- RMM Deep Integration
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ApiBaseUrl,
    [Parameter(Mandatory=$false)]
    [string]$CompanyId,
    [Parameter(Mandatory=$false)]
    [string]$PublicKey,
    [Parameter(Mandatory=$false)]
    [string]$PrivateKey
)

$data = [PSCustomObject]@{
    Timestamp       = (Get-Date).ToString('o')
    ApiConfigured   = $false
    ApiReachable    = $false
    CompanyFound    = $false
    MemberCount     = 0
    RecentTickets   = 0
    IntegrationType = 'ConnectWise Manage'
    Checks          = @()
    Score           = 0
    MaxScore        = 0
    Summary         = ''
}

# Attempt to load from environment or registry if not provided
if (-not $ApiBaseUrl) {
    $cwReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\ConnectWise' -ErrorAction SilentlyContinue
    if ($cwReg) {
        $ApiBaseUrl = $cwReg.ApiUrl
        $CompanyId = $cwReg.CompanyId
        $PublicKey = $cwReg.PublicKey
    }
}

$data.ApiConfigured = ($ApiBaseUrl -and $CompanyId -and $PublicKey -and $PrivateKey)
$data.Checks += [PSCustomObject]@{ Name='Credentials Configured'; Pass=$data.ApiConfigured; Detail=$(if($data.ApiConfigured){'All 4 required values present'}else{'Missing: check API URL, CompanyId, keys'}) }

# Check API reachability
if ($data.ApiConfigured) {
    try {
        $baseUrl = $ApiBaseUrl.TrimEnd('/')
        $authString = "${CompanyId}+${PublicKey}:${PrivateKey}"
        $authBytes = [Text.Encoding]::ASCII.GetBytes($authString)
        $authB64 = [Convert]::ToBase64String($authBytes)
        $headers = @{ Authorization = "Basic $authB64"; 'ClientId' = (New-Guid).ToString() }

        $response = Invoke-RestMethod -Uri "$baseUrl/system/members" -Headers $headers -Method Get -ErrorAction Stop
        $data.ApiReachable = $true
        $data.MemberCount = ($response | Measure-Object).Count
        $data.CompanyFound = $true
        $data.Checks += [PSCustomObject]@{ Name='API Reachable'; Pass=$true; Detail="$($data.MemberCount) members returned" }

        # Check recent tickets
        $tickets = Invoke-RestMethod -Uri "$baseUrl/service/tickets`?pageSize=5" -Headers $headers -Method Get -ErrorAction SilentlyContinue
        $data.RecentTickets = ($tickets | Measure-Object).Count
        $data.Checks += [PSCustomObject]@{ Name='Tickets Accessible'; Pass=($data.RecentTickets -gt 0); Detail="$($data.RecentTickets) recent tickets" }
    } catch {
        $data.Checks += [PSCustomObject]@{ Name='API Reachable'; Pass=$false; Detail="Error: $($_.Exception.Message)" }
        $data.Checks += [PSCustomObject]@{ Name='Tickets Accessible'; Pass=$false; Detail='API connection failed' }
    }
} else {
    $data.Checks += [PSCustomObject]@{ Name='API Reachable'; Pass=$false; Detail='Credentials not configured' }
    $data.Checks += [PSCustomObject]@{ Name='Tickets Accessible'; Pass=$false; Detail='Skipped' }
}

# Check local agent (CW Automate / ScreenConnect)
$agentSvcs = @('SCClient', 'ScreenConnect Client', 'ConnectWiseControl')
$agentFound = $false
foreach ($s in $agentSvcs) {
    $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
    if ($svc) { $agentFound = $true; break }
}
$data.Checks += [PSCustomObject]@{ Name='Local Agent'; Pass=$agentFound; Detail=$(if($agentFound){'Found'}else{'No ConnectWise agent detected'}) }

$data.MaxScore = $data.Checks.Count * 20
$data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
$data.Summary = "ConnectWise: $($data.Score)/$($data.MaxScore) -- API: $(if($data.ApiReachable){'OK'}else{'FAIL'}) | Agent: $(if($agentFound){'OK'}else{'N/A'})"

return $data
