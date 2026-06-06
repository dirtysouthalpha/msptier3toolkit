<#
.SYNOPSIS
    MSP Toolkit - Firewall Risk Audit.
.DESCRIPTION
    Audits Windows Firewall rules for high-risk configurations:
    wide-open rules (Any/Any), rules with no scope restriction,
    inbound rules allowing all traffic, and rules with unknown programs.
    Risk-scores each rule and produces a summary.
#>
#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ Rules=@(); HighRisk=@(); MediumRisk=@(); LowRisk=@(); Summary=@{} }

try {
    $rules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq $true -and $_.Direction -eq 'Inbound' }
    $totalInbound = $rules.Count
    $highRisk = 0; $medRisk = 0; $lowRisk = 0

    foreach ($rule in $rules) {
        $riskScore = 0
        $riskReasons = @()

        # Get address filter (ports and addresses)
        $addrFilter = Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue
        $portFilter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue
        $appFilter = Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue

        # Risk: Any local address
        if ($addrFilter.LocalAddress -eq 'Any' -or -not $addrFilter.LocalAddress) {
            $riskScore += 3; $riskReasons += 'LocalAddress=Any'
        }
        # Risk: Any remote address
        if ($addrFilter.RemoteAddress -eq 'Any' -or -not $addrFilter.RemoteAddress) {
            $riskScore += 3; $riskReasons += 'RemoteAddress=Any'
        }
        # Risk: Any program
        if (-not $appFilter -or $appFilter.Program -eq 'Any' -or -not $appFilter.Program) {
            $riskScore += 2; $riskReasons += 'App=Any'
        }
        # Risk: Broad port range
        if ($portFilter.LocalPort -eq 'Any' -or -not $portFilter.LocalPort -or $portFilter.LocalPort -contains 'Any') {
            $riskScore += 4; $riskReasons += 'LocalPort=Any'
        } elseif ($portFilter.LocalPort) {
            $ports = $portFilter.LocalPort -join ','
            if ($ports -match '.*\-.*' -and $ports -ne '') { $riskScore += 1; $riskReasons += 'PortRange' }
        }
        # Risk: Edge traversal allowed
        if ($rule.EdgeTraversalPolicy -eq 'Allow') {
            $riskScore += 2; $riskReasons += 'EdgeTraversal=Allow'
        }

        $riskLevel = if ($riskScore -ge 8) { 'High' } elseif ($riskScore -ge 5) { 'Medium' } else { 'Low' }

        $riskObj = [pscustomobject]@{
            DisplayName    = $rule.DisplayName
            Direction      = $rule.Direction
            Action         = $rule.Action
            Protocol       = $portFilter.Protocol
            LocalPort      = $portFilter.LocalPort -join ','
            RemoteAddress  = $addrFilter.RemoteAddress -join ','
            Program        = if ($appFilter.AppPath) { $appFilter.AppPath } else { 'Any' }
            Profile        = $rule.Profile
            RiskScore      = $riskScore
            RiskLevel      = $riskLevel
            RiskReasons    = $riskReasons -join '; '
        }

        $data.Rules += $riskObj
        switch ($riskLevel) {
            'High' { $highRisk++; $data.HighRisk += $riskObj }
            'Medium' { $medRisk++; $data.MediumRisk += $riskObj }
            default { $lowRisk++ }
        }
    }

    $data.Summary = @{
        TotalInboundRules = $totalInbound
        HighRisk          = $highRisk
        MediumRisk        = $medRisk
        LowRisk           = $lowRisk
        Profiles          = @{
            Domain  = ($rules | Where-Object { $_.Profile -like '*Domain*' }).Count
            Private = ($rules | Where-Object { $_.Profile -like '*Private*' }).Count
            Public  = ($rules | Where-Object { $_.Profile -like '*Public*' }).Count
        }
    }
} catch { $errors.Add("Firewall audit: $($_.Exception.Message)") }

$summary = "Firewall: $($data.Summary.TotalInboundRules) inbound rules | High risk: $($data.Summary.HighRisk) | Medium: $($data.Summary.MediumRisk)"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Get-FirewallRiskAudit' -Status $(if ($data.Summary.HighRisk -gt 0) {'Warning'} else {'Success'}) `
        -Summary $summary -Data $data -Errors $errors.ToArray() `
        -Metrics @{ Total=$data.Summary.TotalInboundRules; HighRisk=$data.Summary.HighRisk; MediumRisk=$data.Summary.MediumRisk }
} else {
    [pscustomobject]@{ Tool='Get-FirewallRiskAudit'; Status=$(if ($data.Summary.HighRisk -gt 0) {'Warning'} else {'Success'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
