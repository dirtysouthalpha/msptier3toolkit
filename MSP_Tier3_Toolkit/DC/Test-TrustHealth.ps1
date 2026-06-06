<#
.SYNOPSIS
    MSP Toolkit - Trust Health Validator.
.DESCRIPTION
    Validates inter-domain and inter-forest trusts using nltest,
    checking secure channel, SID filtering, name suffix routing,
    and trust type/direction/status.
#>
#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }
function _Run { param($c,$a,$t=30) & $c @$a 2>&1 | Out-String }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ Trusts=@(); Issues=@() }

# --- Enumerate trusts ---
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $trusts = Get-ADTrust -Filter * -ErrorAction SilentlyContinue
    foreach ($t in $trusts) {
        $trustData = @{
            Name              = $t.Name
            Direction          = $t.Direction
            TrustType          = $t.TrustType
            TrustAttributes    = $t.TrustAttributes
            Created            = $t.Created
            ForestTransitive   = $t.ForestTransitive
            SelectiveAuth      = $t.SelectiveAuthentication
            SIDFilteringForestAware = $false
            SecureChannelOk    = $false
            Reachable          = $false
        }

        # Test connectivity to trust target
        try {
            $reachable = Test-Connection -TargetName $t.Name -Count 1 -Quiet -TimeoutSeconds 3
            $trustData.Reachable = $reachable
        } catch { }

        # nltest secure channel
        try {
            $sc = _Run 'nltest' @('/sc_verify:' + $t.Name) 30
            $trustData.SecureChannelOk = ($sc -match 'trusted' -and $sc -notmatch 'FAILED')
        } catch { }

        # SID filtering check
        if ($t.TrustAttributes -match 'QuarantinedDomain|SIDFiltering') {
            $trustData.SIDFilteringForestAware = $true
        }

        if (-not $trustData.Reachable) { $data.Issues += "Trust '$($t.Name)' is NOT reachable" }
        if (-not $trustData.SecureChannelOk -and $trustData.Reachable) { $data.Issues += "Trust '$($t.Name)' secure channel verification FAILED" }

        $data.Trusts += [pscustomobject]$trustData
    }
} catch {
    # nltest fallback for domain trusts
    try {
        $nltest = _Run 'nltest' @('/domain_trusts') 30
        $lines = $nltest -split "`n" | Where-Object { $_ -match '^\s+\d+' }
        foreach ($line in $lines) {
            $parts = $line -split '\s+'
            if ($parts.Count -ge 5) {
                $data.Trusts += [pscustomobject]@{
                    Name=$parts[1]; Direction=$parts[2]; TrustType=$parts[3]; TrustAttributes=$parts[4]; Reachable=$false; SecureChannelOk=$false
                }
            }
        }
    } catch { $errors.Add("Trust enumeration: $($_.Exception.Message)") }
}

# --- Name Suffix Routing ---
try {
    $nsr = _Run 'nltest' @('/dsgetdc:' + ($data.Trusts | Select-Object -First 1 -ExpandProperty Name -ErrorAction SilentlyContinue)) 15
    if ($nsr) { $data.NameSuffixRouting = ($nsr -split "`n" | Where-Object { $_ -match '\S' }).Trim() }
} catch { }

$healthy = @($data.Trusts | Where-Object { $_.Reachable -and $_.SecureChannelOk }).Count
$total = $data.Trusts.Count
$summary = "Trusts: $healthy/$total healthy | Issues: $($data.Issues.Count)"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Test-TrustHealth' -Status $(if ($data.Issues.Count -gt 0) {'Warning'} elseif ($total -eq 0) {'Success'} else {'Success'}) `
        -Summary $summary -Data $data -Errors $errors.ToArray() `
        -Metrics @{ TotalTrusts=$total; Healthy=$healthy; Issues=$data.Issues.Count }
} else {
    [pscustomobject]@{ Tool='Test-TrustHealth'; Status=$(if ($data.Issues.Count -gt 0) {'Warning'} elseif ($total -eq 0) {'Success'} else {'Success'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
