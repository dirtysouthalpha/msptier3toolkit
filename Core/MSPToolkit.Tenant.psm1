<#
.SYNOPSIS
    MSP Toolkit - Multi-tenant credential vault + tenant selection.
.DESCRIPTION
    Lets the toolkit operate against many customers from one workstation
    without juggling files. Each tenant is a record with:

      - Id (slug)
      - DisplayName
      - Graph credentials (TenantId, ClientId, ClientSecret) -- DPAPI per machine
      - PSA endpoint + API key
      - SMTP overrides
      - Default OUs, license SKU, etc.
      - Custom tags

    Storage: <Cache>\Tenants\<id>.xml (Export-Clixml -- DPAPI-encrypted
    per machine + per user). Secrets never leave the box.

    Operations:
      Set-MSPTenant      / Get-MSPTenant     / Remove-MSPTenant
      Select-MSPTenant   -- sets the "current" tenant for the session
      Get-MSPCurrentTenant
      Invoke-MSPAcross   -- fan out a scriptblock against every tenant
#>

Set-StrictMode -Version Latest
$Script:CurrentTenant = $null

function _TenantDir {
    $paths = Get-MSPPaths
    $dir = Join-Path $paths.Cache 'Tenants'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Set-MSPTenant {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [string]$DisplayName,
        [string]$GraphTenantId,
        [string]$GraphClientId,
        [securestring]$GraphClientSecret,
        [string]$PsaEndpoint,
        [securestring]$PsaApiKey,
        [hashtable]$Custom = @{}
    )

    $file = Join-Path (_TenantDir) "$Id.xml"
    [pscustomobject]@{
        Id                = $Id
        DisplayName       = $DisplayName
        GraphTenantId     = $GraphTenantId
        GraphClientId     = $GraphClientId
        GraphClientSecret = $GraphClientSecret
        PsaEndpoint       = $PsaEndpoint
        PsaApiKey         = $PsaApiKey
        Custom            = $Custom
        SavedAt           = (Get-Date).ToString('o')
    } | Export-Clixml -LiteralPath $file -Force

    # Mirror Graph cred into the existing Graph vault so Connect-MSPGraph
    # picks it up when this tenant is selected.
    if ($GraphTenantId -and $GraphClientId -and $GraphClientSecret) {
        Set-MSPGraphCredential -TenantId $GraphTenantId -ClientId $GraphClientId -ClientSecret $GraphClientSecret
    }
}

function Get-MSPTenant {
    [CmdletBinding()]
    param([string]$Id)
    if ($Id) {
        $f = Join-Path (_TenantDir) "$Id.xml"
        if (-not (Test-Path $f)) { return $null }
        return Import-Clixml -LiteralPath $f
    }
    Get-ChildItem (_TenantDir) -Filter '*.xml' | ForEach-Object { Import-Clixml -LiteralPath $_.FullName }
}

function Remove-MSPTenant {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param([Parameter(Mandatory)] [string]$Id)
    $f = Join-Path (_TenantDir) "$Id.xml"
    if ((Test-Path $f) -and $PSCmdlet.ShouldProcess($Id, 'Remove tenant')) {
        Remove-Item -LiteralPath $f -Force
    }
}

function Select-MSPTenant {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Id)
    $t = Get-MSPTenant -Id $Id
    if (-not $t) { throw "Unknown tenant '$Id'." }
    $Script:CurrentTenant = $t

    # Activate this tenant's Graph credential
    if ($t.GraphTenantId) { Connect-MSPGraph -TenantId $t.GraphTenantId }
    # Write-MSPAudit will pick the current tenant from $Script:CurrentTenant
    Write-MSPLog "Selected tenant: $($t.DisplayName) ($($t.Id))" -Level INFO
    return $t
}

function Get-MSPCurrentTenant { return $Script:CurrentTenant }

function Invoke-MSPAcross {
    <#
    .SYNOPSIS
        Fan out a scriptblock across every tenant. Returns one result per
        tenant, each tagged with the tenant id.
    .EXAMPLE
        Invoke-MSPAcross -ScriptBlock { Get-MSPGraphLicenseSummary }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [scriptblock]$ScriptBlock,
        [string[]]$TenantIds
    )

    $list = if ($TenantIds) { $TenantIds | ForEach-Object { Get-MSPTenant -Id $_ } } else { Get-MSPTenant }
    foreach ($t in $list) {
        Write-Verbose "Running across $($t.Id)"
        try {
            Select-MSPTenant -Id $t.Id | Out-Null
            $out = & $ScriptBlock
            [pscustomobject]@{ Tenant=$t.Id; DisplayName=$t.DisplayName; Ok=$true; Result=$out; Error=$null }
        } catch {
            [pscustomobject]@{ Tenant=$t.Id; DisplayName=$t.DisplayName; Ok=$false; Result=$null; Error=$_.Exception.Message }
        }
    }
}

Export-ModuleMember -Function 'Set-MSPTenant','Get-MSPTenant','Remove-MSPTenant',
                              'Select-MSPTenant','Get-MSPCurrentTenant','Invoke-MSPAcross'
