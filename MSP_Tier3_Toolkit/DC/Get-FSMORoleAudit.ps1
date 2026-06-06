<#
.SYNOPSIS
    MSP Toolkit - FSMO Role Auditor.
.DESCRIPTION
    Discovers all 5 FSMO role holders, checks connectivity, flags RODC
    holders, and reports best-practice placement concerns.
#>
#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }
function _Run { param($c,$a,$t=30) & $c @$a 2>&1 | Out-String }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ Roles=@(); Issues=@(); Score=0; MaxScore=5 }

# Use the DC module's function
try {
    if (Get-Command Get-MSPFSMOInventory -ErrorAction SilentlyContinue) {
        $roles = Get-MSPFSMOInventory
    } else {
        # Manual discovery via netdom
        $netdom = _Run 'netdom' @('query','fsmo') 30
        $roles = @()
        $roleMap = @('Schema Master','Domain Naming Master','PDC Emulator','RID Master','Infrastructure Master')
        foreach ($r in $roleMap) {
            $holder = ''
            $pat = [regex]::Escape($r) + '.*?(\S+)$'
            if ($netdom -match $pat) { $holder = $Matches[1] }
            $reachable = if ($holder) { Test-Connection -ComputerName $holder -Count 1 -Quiet -ErrorAction SilentlyContinue } else { $false }
            $roles += [pscustomobject]@{ Role=$r; Holder=if($holder){$holder}else{'Unknown'}; Reachable=$reachable }
        }
    }
} catch { $errors.Add("FSMO discovery: $($_.Exception.Message)") }

foreach ($r in $roles) {
    $data.Roles += $r
    if ($r.Reachable) { $data.Score++ }
    if (-not $r.Reachable -and $r.Holder -ne 'Unknown') { $data.Issues += "$($r.Role) on $($r.Holder) is NOT reachable" }
    if ($r.Holder -eq 'Unknown') { $data.Issues += "$($r.Role) holder unknown" }
    if ($r.Holder -match 'RODC') { $data.Issues += "$($r.Role) is on a Read-Only DC -- NOT recommended" }
}

# Best practice checks
$holders = $data.Roles | ForEach-Object Holder | Where-Object { $_ -and $_ -ne 'Unknown' } | Select-Object -Unique
if ($holders.Count -gt 3) { $data.Issues += 'Roles distributed across many DCs -- consider consolidating non-PDC roles' }

$summary = "FSMO roles: $($data.Score)/$($data.MaxScore) reachable | Issues: $($data.Issues.Count)"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Get-FSMORoleAudit' -Status $(if ($data.Score -eq 5) {'Success'} elseif ($data.Score -ge 3) {'Warning'} else {'Failure'}) `
        -Summary $summary -Data $data -Errors $errors.ToArray() `
        -Metrics @{ Score=$data.Score; MaxScore=$data.MaxScore; Reachable=$data.Score; Issues=$data.Issues.Count }
} else {
    [pscustomobject]@{ Tool='Get-FSMORoleAudit'; Status=$(if ($data.Score -eq 5) {'Success'} elseif ($data.Score -ge 3) {'Warning'} else {'Failure'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
