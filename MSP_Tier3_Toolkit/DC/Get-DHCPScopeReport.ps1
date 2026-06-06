<#
.SYNOPSIS
    MSP Toolkit - DHCP Scope Report.
.DESCRIPTION
    Analyzes DHCP scopes: utilization %, exclusions, reservations,
    lease distribution, BAD_ADDRESS count. Uses Get-DhcpServerv4Scope
    when available, falls back to netsh.
#>
#Requires -Version 5.1
[CmdletBinding()]
param([string]$ComputerName = $env:COMPUTERNAME)

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }
function _Run { param($c,$a,$t=30) & $c @$a 2>&1 | Out-String }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ Scopes=@(); Summary=@{}; Warnings=@() }

# --- Enumerate Scopes ---
try {
    Import-Module DhcpServer -ErrorAction Stop
    $scopes = Get-DhcpServerv4Scope -ComputerName $ComputerName -ErrorAction SilentlyContinue
    foreach ($scope in $scopes) {
        $scopeData = @{
            Name          = $scope.Name
            ScopeID       = $scope.ScopeId.IPAddressToString
            SubnetMask    = $scope.SubnetMask.IPAddressToString
            State         = $scope.State
            StartRange    = $scope.StartRange.IPAddressToString
            EndRange      = $scope.EndRange.IPAddressToString
            LeaseDuration = $scope.LeaseDuration
            Utilization   = 0
            InUse         = 0
            Free          = 0
            Reserved       = 0
            Exclusions     = @()
            BAD_ADDRESS    = 0
        }

        # Leases
        try {
            $leases = Get-DhcpServerv4Lease -ComputerName $ComputerName -ScopeId $scope.ScopeId -ErrorAction SilentlyContinue
            $scopeData.InUse = ($leases | Where-Object AddressState -eq 'Active').Count
            $scopeData.Free = ($leases | Where-Object AddressState -eq 'Inactive').Count
            $scopeData.BAD_ADDRESS = ($leases | Where-Object AddressState -like '*BAD*').Count
            $total = $scopeData.InUse + $scopeData.Free
            if ($total -gt 0) { $scopeData.Utilization = [math]::Round(($scopeData.InUse / $total) * 100, 1) }
        } catch { }

        # Reservations
        try {
            $reservations = Get-DhcpServerv4Reservation -ComputerName $ComputerName -ScopeId $scope.ScopeId -ErrorAction SilentlyContinue
            $scopeData.Reserved = $reservations.Count
        } catch { }

        # Exclusions
        try {
            $exclusions = Get-DhcpServerv4ExclusionRange -ComputerName $ComputerName -ScopeId $scope.ScopeId -ErrorAction SilentlyContinue
            foreach ($ex in $exclusions) {
                $scopeData.Exclusions += "$($ex.StartRange.IPAddressToString)-$($ex.EndRange.IPAddressToString)"
            }
        } catch { }

        # Warnings
        if ($scopeData.Utilization -gt 90) { $data.Warnings += "$($scopeData.ScopeID) at $($scopeData.Utilization)% utilization" }
        if ($scopeData.BAD_ADDRESS -gt 10) { $data.Warnings += "$($scopeData.ScopeID) has $($scopeData.BAD_ADDRESS) BAD_ADDRESS entries" }
        if ($scopeData.State -eq 'Inactive') { $data.Warnings += "$($scopeData.ScopeID) is inactive" }

        $data.Scopes += [pscustomobject]$scopeData
    }
} catch {
    # netsh fallback
    try {
        $netsh = _Run 'netsh' @('dhcp','server',$ComputerName,'show','scope') 30
        foreach ($line in ($netsh -split "`n")) {
            if ($line -match '(\d+\.\d+\.\d+\.\d+)\s*-\s*(\d+\.\d+\.\d+\.\d+)') {
                $data.Scopes += [pscustomobject]@{ ScopeID=$Matches[1]; State='Unknown'; Utilization=0; InUse=0; Free=0; Reserved=0; Exclusions=@(); BAD_ADDRESS=0 }
            }
        }
    } catch { $errors.Add("DHCP enumeration: $($_.Exception.Message)") }
}

# --- Summary ---
$totalScopes = $data.Scopes.Count
$overUtilized = @($data.Scopes | Where-Object { $_.Utilization -gt 90 }).Count
$data.Summary = @{ TotalScopes=$totalScopes; Active=($data.Scopes | Where-Object {$_.State -ne 'Inactive'}).Count; OverUtilized=$overUtilized; Warnings=$data.Warnings.Count }

$summary = "Scopes: $totalScopes | Over-90% utilization: $overUtilized | Warnings: $($data.Warnings.Count)"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Get-DHCPScopeReport' -Status $(if ($data.Warnings.Count -gt 0) {'Warning'} else {'Success'}) `
        -Summary $summary -Data $data -Errors $errors.ToArray() `
        -Metrics @{ TotalScopes=$totalScopes; OverUtilized=$overUtilized; Warnings=$data.Warnings.Count }
} else {
    [pscustomobject]@{ Tool='Get-DHCPScopeReport'; Status=$(if ($data.Warnings.Count -gt 0) {'Warning'} else {'Success'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
