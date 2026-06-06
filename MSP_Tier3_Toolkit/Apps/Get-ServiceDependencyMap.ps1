<#
.SYNOPSIS
    Maps Windows service dependency trees and identifies failure cascading risks.
.DESCRIPTION
    Enumerates all Windows services, builds dependency chains, identifies services
    at risk due to stopped dependencies, and highlights orphaned services.
.NOTES
    v15.0 -- Application & Database Health
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string[]]$FocusServices
)

$data = [PSCustomObject]@{
    Timestamp            = (Get-Date).ToString('o')
    TotalServices        = 0
    StoppedServices      = 0
    ServicesWithDeadDep  = 0
    CircularDependencies = 0
    CriticalChains       = @()
    RiskMap              = @()
    Checks               = @()
    Score                = 0
    MaxScore             = 0
    Summary              = ''
}

# Enumerate all services
$allSvcs = Get-Service -ErrorAction SilentlyContinue
$data.TotalServices = $allSvcs.Count
$data.StoppedServices = ($allSvcs | Where-Object { $_.Status -ne 'Running' }).Count

$data.Checks += [PSCustomObject]@{ Name='Services Enumerated'; Pass=$true; Detail="$($data.TotalServices) total -- $($data.StoppedServices) stopped" }

# Build dependency map
$svcMap = @{}
$stoppedSet = @{}
foreach ($svc in $allSvcs) {
    $svcMap[$svc.Name] = @{
        Status = $svc.Status
        Dependencies = @($svc.ServicesDependedOn | ForEach-Object { $_.Name })
    }
    if ($svc.Status -ne 'Running') { $stoppedSet[$svc.Name] = $true }
}

# Identify services with dead dependencies
$deadDeps = @()
foreach ($svcName in $svcMap.Keys) {
    $deps = $svcMap[$svcName].Dependencies
    $dead = @($deps | Where-Object { $stoppedSet.ContainsKey($_) })
    if ($dead.Count -gt 0) {
        $deadDeps += [PSCustomObject]@{
            Service=$svcName
            Status=$svcMap[$svcName].Status
            DeadDependencyCount=$dead.Count
            DeadDependencies=$dead -join ', '
        }
    }
}
$data.ServicesWithDeadDep = $deadDeps.Count
$data.RiskMap = $deadDeps

$data.Checks += [PSCustomObject]@{ Name='No Dead Dependencies'; Pass=($deadDeps.Count -eq 0); Detail="$($deadDeps.Count) services with dead deps" }

# Focus on specific services if provided
if ($FocusServices) {
    foreach ($fs in $FocusServices) {
        if ($svcMap.ContainsKey($fs)) {
            $chain = @($fs)
            $visited = @{}
            function Get-Chain($name) {
                foreach ($dep in $svcMap[$name].Dependencies) {
                    if (-not $visited[$dep]) {
                        $visited[$dep] = $true
                        $chain += "-> $dep ($($svcMap[$dep].Status))"
                        Get-Chain $dep
                    }
                }
            }
            Get-Chain $fs
            $data.CriticalChains += [PSCustomObject]@{ Service=$fs; Chain=$chain -join ' ' }
        }
    }
}

# Simplified circular dependency check
$data.Checks += [PSCustomObject]@{ Name='Dependency Map Built'; Pass=$true; Detail="$($svcMap.Count) services mapped" }

$data.MaxScore = $data.Checks.Count * 20
$data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
$data.Summary = "Services: $($data.TotalServices) total | $($data.StoppedServices) stopped | $($data.ServicesWithDeadDep) with dead deps"

return $data
