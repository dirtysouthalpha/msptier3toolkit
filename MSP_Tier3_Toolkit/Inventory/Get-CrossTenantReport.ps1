<#
.SYNOPSIS
    Run an inventory or compliance script across every tenant and roll
    results into one cross-tenant report.
.DESCRIPTION
    The reason multi-tenant exists: "show me every Windows 10 box that
    still hasn't moved to 11 across every customer". Pipe in a
    scriptblock, get back a per-tenant matrix plus a flattened result.

    Out of the box, computes:
      - License utilization across all tenants
      - Risky sign-ins (Get-MSPGraphSignInRisk per tenant)
      - User counts + disabled users still holding licenses
.PARAMETER Report
    Pre-canned report: License, Risk, Users, or Custom.
.PARAMETER CustomScript
    Scriptblock to run inside each tenant context (only if -Report Custom).
.EXAMPLE
    .\Get-CrossTenantReport.ps1 -Report License
.EXAMPLE
    .\Get-CrossTenantReport.ps1 -Report Custom -CustomScript { Invoke-MSPGraph -Path 'devices?$select=displayName,operatingSystem,operatingSystemVersion' }
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('License','Risk','Users','Custom')]
    [string]$Report = 'License',
    [scriptblock]$CustomScript,
    [int]$RiskDays = 7,
    [switch]$AsJson
)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$body = switch ($Report) {
    'License' { { Get-MSPGraphLicenseSummary } }
    'Risk'    { { Get-MSPGraphSignInRisk -Days $using:RiskDays } }
    'Users'   { { Invoke-MSPGraph -Path "users?`$select=displayName,userPrincipalName,accountEnabled,assignedLicenses,signInActivity" } }
    'Custom'  { if (-not $CustomScript) { throw '-CustomScript required when -Report Custom.' } else { $CustomScript } }
}

$tenants = Get-MSPTenant
if (-not $tenants) { throw 'No tenants registered. Use Set-MSPTenant first.' }

$rows = Invoke-MSPAcross -ScriptBlock $body
$ok   = ($rows | Where-Object Ok).Count
$flat = foreach ($r in $rows) {
    if (-not $r.Ok) { continue }
    foreach ($item in @($r.Result)) {
        if ($null -eq $item) { continue }
        $obj = if ($item -is [pscustomobject]) { $item } else { [pscustomobject]@{ Value = $item } }
        $obj | Add-Member -NotePropertyName _Tenant     -NotePropertyValue $r.Tenant      -Force
        $obj | Add-Member -NotePropertyName _TenantName -NotePropertyValue $r.DisplayName -Force
        $obj
    }
}

$paths = Get-MSPPaths
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$csvPath = Join-Path $paths.Reports "CrossTenant\$Report`_$stamp.csv"
New-Item -ItemType Directory -Path (Split-Path $csvPath) -Force | Out-Null
$flat | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

$result = New-MSPResult `
    -Tool 'Get-CrossTenantReport' `
    -Status 'Success' `
    -Summary "Ran $Report across $($tenants.Count) tenants ($ok ok). CSV: $csvPath" `
    -Data @{ Report = $Report; TenantsRun = $tenants.Count; Successes = $ok; CsvPath = $csvPath; Rows = $flat } `
    -Metrics @{ TenantsRun = $tenants.Count; RowsEmitted = @($flat).Count }

[void](Save-MSPResult -Result $result -Subfolder 'CrossTenant')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
