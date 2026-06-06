<#
.SYNOPSIS
    MSP Toolkit - Microsoft Graph thin client (app-only auth, no SDK required).
.DESCRIPTION
    The official Microsoft.Graph PS SDK is a 600 MB monster. For the 90%
    of MSP scenarios -- list users, check licenses, reset password, lock a
    sign-in, list mailboxes -- we just need a small client that:
      1. Acquires an app-only token via client_credentials
      2. Wraps Invoke-RestMethod with pagination + throttling retry
      3. Exposes a few high-value helpers

    Auth setup (one-time, per-tenant):
      - Register an Entra ID app
      - Grant application permissions (User.Read.All, UserAuthenticationMethod.ReadWrite.All,
        Group.Read.All, Directory.Read.All, Reports.Read.All)
      - Mint a client secret
      - Store via Set-MSPGraphCredential

    All secrets are stored DPAPI-encrypted (Export-Clixml) per-machine --
    they cannot be roamed or copied to another box. Encrypted file lives
    under <Cache>\Graph\<TenantId>.xml.
#>

Set-StrictMode -Version Latest

$Script:GraphToken = $null
$Script:GraphTokenExp = [datetime]::MinValue
$Script:GraphTenant = $null

function Set-MSPGraphCredential {
    <#
    .SYNOPSIS
        Store a Graph app credential securely (DPAPI per-machine).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$TenantId,
        [Parameter(Mandatory)] [string]$ClientId,
        [Parameter(Mandatory)] [securestring]$ClientSecret
    )

    $paths = Get-MSPPaths
    $dir = Join-Path $paths.Cache 'Graph'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $file = Join-Path $dir "$TenantId.xml"

    [pscustomobject]@{
        TenantId    = $TenantId
        ClientId    = $ClientId
        Secret      = $ClientSecret
        SavedAt     = (Get-Date).ToString('o')
    } | Export-Clixml -LiteralPath $file -Force

    Write-Verbose "Saved Graph credential to $file"
}

function Get-MSPGraphCredential {
    [CmdletBinding()]
    param([string]$TenantId)

    $paths = Get-MSPPaths
    $dir = Join-Path $paths.Cache 'Graph'
    if (-not $TenantId) {
        $first = Get-ChildItem -LiteralPath $dir -Filter '*.xml' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $first) { throw 'No Graph credentials saved. Use Set-MSPGraphCredential.' }
        return Import-Clixml -LiteralPath $first.FullName
    }
    $file = Join-Path $dir "$TenantId.xml"
    if (-not (Test-Path $file)) { throw "No Graph credential for tenant $TenantId." }
    return Import-Clixml -LiteralPath $file
}

function Connect-MSPGraph {
    <#
    .SYNOPSIS
        Acquire an app-only access token via client_credentials.
    #>
    [CmdletBinding()]
    param(
        [string]$TenantId,
        [string]$Scope = 'https://graph.microsoft.com/.default'
    )

    $cred = Get-MSPGraphCredential -TenantId $TenantId
    $TenantId = $cred.TenantId

    $secretPlain = [System.Net.NetworkCredential]::new('', $cred.Secret).Password

    $body = @{
        client_id     = $cred.ClientId
        scope         = $Scope
        client_secret = $secretPlain
        grant_type    = 'client_credentials'
    }
    $resp = Invoke-RestMethod `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -Method Post -Body $body

    $Script:GraphToken    = $resp.access_token
    $Script:GraphTokenExp = (Get-Date).AddSeconds($resp.expires_in - 60)
    $Script:GraphTenant   = $TenantId
    Write-Verbose "Got Graph token, expires $Script:GraphTokenExp"
}

function Invoke-MSPGraph {
    <#
    .SYNOPSIS
        Invoke-RestMethod for Graph: handles paging (@odata.nextLink),
        429/5xx retry with Retry-After header, and token refresh.
    .EXAMPLE
        Invoke-MSPGraph -Path 'users?$select=displayName,mail,accountEnabled'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [ValidateSet('GET','POST','PATCH','DELETE','PUT')]
        [string]$Method = 'GET',
        $Body,
        [string]$Version = 'v1.0',
        [int]$MaxPages = 50
    )

    if (-not $Script:GraphToken -or (Get-Date) -ge $Script:GraphTokenExp) {
        Connect-MSPGraph
    }

    $url = if ($Path -match '^https?://') { $Path } else { "https://graph.microsoft.com/$Version/$($Path.TrimStart('/'))" }
    $headers = @{ Authorization = "Bearer $Script:GraphToken" }
    $page = 0
    $all = @()

    while ($url -and $page -lt $MaxPages) {
        $page++
        $attempt = 0
        while ($true) {
            $attempt++
            try {
                $params = @{ Uri = $url; Headers = $headers; Method = $Method; ErrorAction = 'Stop' }
                if ($Body) {
                    $params.Body = ($Body | ConvertTo-Json -Depth 10)
                    $params.ContentType = 'application/json'
                }
                $resp = Invoke-RestMethod @params
                break
            } catch {
                $code = $_.Exception.Response.StatusCode.value__
                if ($code -in 429,500,502,503,504 -and $attempt -lt 5) {
                    $retry = 1 + ($attempt * 2)
                    $hdr = $_.Exception.Response.Headers['Retry-After']
                    if ($hdr) { $retry = [int]$hdr }
                    Start-Sleep -Seconds $retry
                    continue
                }
                throw
            }
        }

        if ($resp.PSObject.Properties.Name -contains 'value') {
            $all += $resp.value
            $url = $resp.'@odata.nextLink'
        } else {
            return $resp
        }
    }
    return $all
}

# -------------------------------------------------------------------------
#  High-value helpers
# -------------------------------------------------------------------------

function Get-MSPGraphUser {
    [CmdletBinding()]
    param([string]$UserPrincipalName)
    if ($UserPrincipalName) {
        Invoke-MSPGraph -Path "users/$UserPrincipalName"
    } else {
        Invoke-MSPGraph -Path 'users?$select=displayName,userPrincipalName,mail,accountEnabled,assignedLicenses,createdDateTime'
    }
}

function Get-MSPGraphLicenseSummary {
    [CmdletBinding()] param()
    $skus = Invoke-MSPGraph -Path 'subscribedSkus'
    $skus | Select-Object skuPartNumber, skuId,
        @{n='Enabled';e={$_.prepaidUnits.enabled}},
        @{n='Consumed';e={$_.consumedUnits}},
        @{n='Available';e={$_.prepaidUnits.enabled - $_.consumedUnits}}
}

function Reset-MSPGraphUserPassword {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)] [string]$UserPrincipalName,
        [Parameter(Mandatory)] [string]$NewPassword,
        [switch]$ForceChangeAtNextSignIn
    )
    if ($PSCmdlet.ShouldProcess($UserPrincipalName, 'Reset password')) {
        Invoke-MSPGraph -Path "users/$UserPrincipalName" -Method PATCH -Body @{
            passwordProfile = @{
                forceChangeNextSignIn = [bool]$ForceChangeAtNextSignIn
                password              = $NewPassword
            }
        }
    }
}

function Set-MSPGraphUserAccountState {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string]$UserPrincipalName,
        [Parameter(Mandatory)] [ValidateSet('Enable','Disable')] [string]$State
    )
    if ($PSCmdlet.ShouldProcess($UserPrincipalName, "$State sign-in")) {
        Invoke-MSPGraph -Path "users/$UserPrincipalName" -Method PATCH -Body @{
            accountEnabled = ($State -eq 'Enable')
        }
    }
}

function Get-MSPGraphSignInRisk {
    [CmdletBinding()]
    param([int]$Days = 7)
    $iso = (Get-Date).AddDays(-$Days).ToString('o')
    Invoke-MSPGraph -Path "auditLogs/signIns?`$filter=createdDateTime ge $iso and riskLevelDuringSignIn ne 'none'&`$top=200"
}

Export-ModuleMember -Function @(
    'Set-MSPGraphCredential','Get-MSPGraphCredential',
    'Connect-MSPGraph','Invoke-MSPGraph',
    'Get-MSPGraphUser','Get-MSPGraphLicenseSummary',
    'Reset-MSPGraphUserPassword','Set-MSPGraphUserAccountState','Get-MSPGraphSignInRisk'
)
