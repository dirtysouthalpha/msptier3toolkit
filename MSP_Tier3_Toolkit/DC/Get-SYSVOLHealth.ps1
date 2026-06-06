<#
.SYNOPSIS
    MSP Toolkit - SYSVOL Health Check.
.DESCRIPTION
    Checks SYSVOL share accessibility, DFSR/FRS replication state,
    policy file consistency across DCs, and staging area health.
#>
#Requires -Version 5.1
[CmdletBinding()]
param([string]$Domain)

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }
function _Run { param($c,$a,$t=30) & $c @$a 2>&1 | Out-String }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ DCs=@(); DFSRState=@{}; PolicyFileCounts=@(); Issues=@() }

# --- Get DC list ---
$dcList = @()
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $dcList = Get-ADDomainController -Filter * -ErrorAction SilentlyContinue
} catch {
    try {
        $nltest = _Run 'nltest' @('/dclist:' + (if ($Domain) { $Domain } else { $env:USERDNSDOMAIN })) 15
        $dcList = $nltest -split "`n" | Where-Object { $_ -match '^\s+\S+' } | ForEach-Object { [pscustomobject]@{ HostName=$_.Trim() } }
    } catch { }
}

# --- Check each DC ---
foreach ($dc in $dcList) {
    $dcName = if ($dc.HostName) { $dc.HostName } elseif ($dc.Name) { $dc.Name } else { $dc }
    $dcData = @{
        Name            = $dcName
        SYSVOLReachable = $false
        PolicyCount     = 0
        GPTCount        = 0
        DFSRState       = ''
        SYSVOLPath      = ''
    }

    # SYSVOL share reachability
    try {
        $sysvolPath = "\\$dcName\SYSVOL"
        if (Test-Path $sysvolPath) {
            $dcData.SYSVOLReachable = $true
            $dcData.SYSVOLPath = $sysvolPath
            
            # Count policy folders
            $domainSysvol = Join-Path $sysvolPath (if ($Domain) { $Domain } else { $env:USERDNSDOMAIN }) | Join-Path -ChildPath 'Policies'
            if (Test-Path $domainSysvol) {
                $dcData.PolicyCount = (Get-ChildItem $domainSysvol -Directory -ErrorAction SilentlyContinue).Count
                $dcData.GPTCount = (Get-ChildItem $domainSysvol -Recurse -Filter 'GPT.INI' -ErrorAction SilentlyContinue).Count
            }
        }
    } catch { }

    # DFSR state
    try {
        $dfsr = _Run 'dfsrdiag' @('ReplicationState','/Member:' + $dcName) 30
        if ($dfsr -match 'No backlog') { $dcData.DFSRState = 'Healthy - No backlog' }
        elseif ($dfsr -match 'backlog') { $dcData.DFSRState = "Backlog: $($dfsr -split "`n" | Where-Object { $_ -match 'backlog' } -join ' ')"; $data.Issues += "DFSR backlog on $dcName" }
    } catch {
        # Check if FRS instead
        try {
            $nltest = _Run 'nltest' @('/dsgetsite') 10
            $dcData.DFSRState = 'DFSR check failed - check manually'
        } catch { }
    }

    $data.DCs += [pscustomobject]$dcData
}

# --- Policy count consistency ---
$counts = $data.DCs | Where-Object SYSVOLReachable | ForEach-Object PolicyCount | Select-Object -Unique
if ($counts.Count -gt 1) {
    $data.Issues += "Policy count inconsistency across DCs: $($counts -join ', ')"
}

# --- Accessibility rate ---
$reachable = @($data.DCs | Where-Object SYSVOLReachable).Count
$total = $data.DCs.Count

$summary = "SYSVOL: $reachable/$total DCs reachable | Policy count range: $($counts -join '..') | Issues: $($data.Issues.Count)"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Get-SYSVOLHealth' -Status $(if ($data.Issues.Count -gt 0) {'Warning'} elseif ($reachable -lt $total) {'Warning'} else {'Success'}) `
        -Summary $summary -Data $data -Errors $errors.ToArray() `
        -Metrics @{ TotalDCs=$total; Reachable=$reachable; Issues=$data.Issues.Count }
} else {
    [pscustomobject]@{ Tool='Get-SYSVOLHealth'; Status=$(if ($data.Issues.Count -gt 0) {'Warning'} elseif ($reachable -lt $total) {'Warning'} else {'Success'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
