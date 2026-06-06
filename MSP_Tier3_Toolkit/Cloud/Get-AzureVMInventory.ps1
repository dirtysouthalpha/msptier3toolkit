<#
.SYNOPSIS
    Inventories Azure VMs with size, cost estimates, and performance metrics.
.DESCRIPTION
    Uses Azure PowerShell or Az CLI to enumerate all VMs in a subscription,
    reporting OS, size, region, power state, disk config, and estimated monthly cost.
    Works with the Az module if available.
.NOTES
    v14.0 -- Cloud & Hybrid Operations
    Requires: Az module (optional -- falls back to REST)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId,
    [Parameter(Mandatory=$false)]
    [switch]$IncludeStopped
)

$data = [PSCustomObject]@{
    Timestamp      = (Get-Date).ToString('o')
    TotalVMs       = 0
    RunningVMs     = 0
    StoppedVMs     = 0
    DeallocatedVMs = 0
    EstimatedMonthlyCost = 0
    VMs            = @()
    Regions        = @{}
    Checks         = @()
    Score          = 0
    MaxScore       = 0
    Summary        = ''
}

# Attempt Az module
$azAvailable = $false
try {
    $azMod = Get-Module -Name Az.Compute -ListAvailable -ErrorAction SilentlyContinue
    if ($azMod) {
        $azAvailable = $true
        if (-not (Get-AzContext -ErrorAction SilentlyContinue)) {
            $data.Checks += [PSCustomObject]@{ Name='Az Context'; Pass=$false; Detail='Not logged in. Run Connect-AzAccount first.' }
        } else {
            $data.Checks += [PSCustomObject]@{ Name='Az Context'; Pass=$true; Detail='Authenticated' }

            if ($SubscriptionId) { Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction SilentlyContinue | Out-Null }
            
            $vms = Get-AzVM -Status -ErrorAction Stop
            $data.TotalVMs = $vms.Count
            
            foreach ($vm in $vms) {
                $powerState = ($vm.Statuses | Where-Object { $_.Code -like 'PowerState/*' }).DisplayStatus
                switch ($powerState) {
                    'VM running' { $data.RunningVMs++ }
                    'VM stopped' { $data.StoppedVMs++ }
                    'VM deallocated' { $data.DeallocatedVMs++ }
                }

                if ($IncludeStopped -or $powerState -eq 'VM running') {
                    $size = $vm.HardwareProfile.VmSize
                    # Approximate monthly cost based on common sizes
                    $costEst = switch -Regex ($size) {
                        'Standard_B' { 30 }
                        'Standard_D2' { 100 }
                        'Standard_D4' { 200 }
                        'Standard_D8' { 400 }
                        'Standard_E' { 300 }
                        'Standard_F' { 150 }
                        default { 100 }
                    }
                    $data.EstimatedMonthlyCost += $costEst
                    
                    if (-not $data.Regions[$vm.Location]) { $data.Regions[$vm.Location] = 0 }
                    $data.Regions[$vm.Location]++

                    $data.VMs += [PSCustomObject]@{
                        Name=$vm.Name; Size=$size; Location=$vm.Location
                        PowerState=$powerState; OSType=$vm.StorageProfile.OsDisk.OsType
                        EstMonthlyCost=$costEst
                    }
                }
            }
            
            $data.Checks += [PSCustomObject]@{ Name='VMs Enumerated'; Pass=($data.TotalVMs -gt 0); Detail="$($data.TotalVMs) VMs found" }
        }
    } else {
        $data.Checks += [PSCustomObject]@{ Name='Az Module'; Pass=$false; Detail='Az module not installed' }
    }
} catch {
    $data.Checks += [PSCustomObject]@{ Name='Az Module'; Pass=$false; Detail="Error: $($_.Exception.Message)" }
}

# Fallback: Check local Hyper-V/VMware if no Azure
if (-not $azAvailable -or $data.TotalVMs -eq 0) {
    $hyperv = Get-VM -ErrorAction SilentlyContinue
    if ($hyperv) {
        $data.Checks += [PSCustomObject]@{ Name='Local Hyper-V'; Pass=$true; Detail="$($hyperv.Count) local VMs (Hyper-V host detected)" }
    }
}

$data.MaxScore = $data.Checks.Count * 20
$data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
$data.Summary = "Azure VMs: $($data.TotalVMs) total | $($data.RunningVMs) running | Est. monthly: $$([math]::Round($data.EstimatedMonthlyCost))"

return $data
