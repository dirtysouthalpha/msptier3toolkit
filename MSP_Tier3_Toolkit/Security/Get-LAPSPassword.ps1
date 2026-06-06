<#
.SYNOPSIS
    Retrieve LAPS-managed local admin password from Active Directory.
.DESCRIPTION
    Reads the ms-Mcs-AdmPwd attribute (legacy LAPS) or msLAPS-Password (Windows Server 2016+ LAPS)
    from the computer object in AD. Requires read permission on the attribute (typically delegated
    to helpdesk/admin groups). Outputs standard MSP result with password and expiration.
.PARAMETER ComputerName
    Target computer name (default: local computer).
.PARAMETER DomainController
    Specific DC to query (optional).
.PARAMETER AsJson
    Emit raw JSON to stdout.
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ComputerName = $env:COMPUTERNAME,
    [string]$DomainController,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$errors  = New-Object System.Collections.Generic.List[string]
$data    = @{ ComputerName=$ComputerName; LegacyLAPS=$false; NewLAPS=$false; Password=''; Expiration=''; Source='' }

try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    $errors.Add('ActiveDirectory module not available. Install RSAT or run on a Domain Controller.')
    $result = New-MSPResult -Tool 'Get-LAPSPassword' -Status 'Failure' -Summary 'ActiveDirectory module missing' -Data $data -Errors $errors.ToArray()
    if ($AsJson) { $result | ConvertTo-Json -Depth 5 } else { $result }
    return
}

$dcParams = @{}
if ($DomainController) { $dcParams.Server = $DomainController }

try {
    $computer = Get-ADComputer -Identity $ComputerName -Properties 'ms-Mcs-AdmPwd','ms-Mcs-AdmPwdExpirationTime','msLAPS-Password','msLAPS-PasswordExpirationTime' @dcParams -ErrorAction Stop

    # Legacy LAPS (ms-Mcs-AdmPwd)
    if ($computer.'ms-Mcs-AdmPwd') {
        $data.LegacyLAPS = $true
        $data.Password = $computer.'ms-Mcs-AdmPwd'
        $data.Source = 'ms-Mcs-AdmPwd (Legacy LAPS)'
        if ($computer.'ms-Mcs-AdmPwdExpirationTime') {
            $exp = [DateTime]::FromFileTime($computer.'ms-Mcs-AdmPwdExpirationTime')
            $data.Expiration = $exp.ToString('o')
        }
    }

    # New LAPS (Windows Server 2016+)
    if ($computer.'msLAPS-Password') {
        $data.NewLAPS = $true
        $data.Password = $computer.'msLAPS-Password'
        $data.Source = 'msLAPS-Password (Windows LAPS)'
        if ($computer.'msLAPS-PasswordExpirationTime') {
            $exp = [DateTime]::FromFileTime($computer.'msLAPS-PasswordExpirationTime')
            $data.Expiration = $exp.ToString('o')
        }
    }

    if (-not $data.LegacyLAPS -and -not $data.NewLAPS) {
        $errors.Add("No LAPS password found for $ComputerName. LAPS may not be deployed or permissions insufficient.")
    }

} catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
    $errors.Add("Computer '$ComputerName' not found in AD.")
} catch {
    $errors.Add("AD query failed: $($_.Exception.Message)")
}

$hasPassword = $data.LegacyLAPS -or $data.NewLAPS
$status = if ($errors.Count -and -not $hasPassword) { 'Failure' } elseif ($hasPassword) { 'Success' } else { 'Warning' }
$summary = if ($hasPassword) { "LAPS password retrieved via $($data.Source)" } else { 'No LAPS password found' }

$result = New-MSPResult -Tool 'Get-LAPSPassword' -Status $status -Summary $summary -Data $data -Errors $errors.ToArray() `
    -Metrics @{ HasPassword=$hasPassword; Legacy=$data.LegacyLAPS; NewLAPS=$data.NewLAPS }

[void](Save-MSPResult -Result $result -Subfolder 'Security')
if ($AsJson) { $result | ConvertTo-Json -Depth 5 } else { $result }