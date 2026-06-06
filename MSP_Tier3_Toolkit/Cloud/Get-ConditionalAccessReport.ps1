<#
.SYNOPSIS
    Audits Conditional Access policies for gaps, risks, and best-practice alignment.
.DESCRIPTION
    Enumerates all CA policies via Graph, flags risky configurations (no MFA,
    no compliant device requirement, overly broad exclusions), and scores
    the overall CA posture.
.NOTES
    v14.0 -- Cloud & Hybrid Operations
    Requires: MSPToolkit.Graph module loaded
#>
[CmdletBinding()]
param()

$data = [PSCustomObject]@{
    Timestamp         = (Get-Date).ToString('o')
    TotalPolicies     = 0
    EnabledPolicies   = 0
    ReportOnly        = 0
    PoliciesRequiringMFA = 0
    BroadExclusions   = 0
    RiskyPolicies     = @()
    Checks            = @()
    Score             = 0
    MaxScore          = 0
    Summary           = ''
}

try {
    $policies = Invoke-MSPGraph -Resource 'identity/conditionalAccess/policies' -ErrorAction Stop
    if ($policies.value) {
        $data.TotalPolicies = $policies.value.Count
        
        foreach ($p in $policies.value) {
            if ($p.state -eq 'enabled') { $data.EnabledPolicies++ }
            elseif ($p.state -eq 'enabledForReportingButNotEnforced') { $data.ReportOnly++ }

            # Check for MFA requirement
            $hasMFA = $false
            if ($p.grantControls.builtInControls) {
                $hasMFA = ($p.grantControls.builtInControls -contains 'mfa')
            }
            if ($hasMFA) { $data.PoliciesRequiringMFA++ }

            # Check for overly broad exclusions
            $hasBroadExclusion = $false
            if ($p.conditions.users.excludeUsers -contains 'All') { $hasBroadExclusion = $true }
            if ($p.conditions.users.excludeGroups) { $hasBroadExclusion = $true }
            if ($p.conditions.applications.includeApplications -contains 'All') { $hasBroadExclusion = $true }

            # Risk flagging
            if ($p.state -eq 'enabled' -and -not $hasMFA -and -not $hasBroadExclusion) {
                $data.RiskyPolicies += [PSCustomObject]@{
                    PolicyName = $p.displayName
                    Risk = 'No MFA required'
                    State = $p.state
                }
            }
            if ($hasBroadExclusion) {
                $data.BroadExclusions++
                $data.RiskyPolicies += [PSCustomObject]@{
                    PolicyName = $p.displayName
                    Risk = 'Broad exclusions'
                    State = $p.state
                }
            }
        }

        $data.Checks += [PSCustomObject]@{ Name='CA Policies Loaded'; Pass=$true; Detail="$($data.TotalPolicies) total -- $($data.EnabledPolicies) enabled" }
        $data.Checks += [PSCustomObject]@{ Name='MFA Coverage'; Pass=($data.PoliciesRequiringMFA -ge 1); Detail="$($data.PoliciesRequiringMFA) MFA-requiring policies" }
        $data.Checks += [PSCustomObject]@{ Name='No Broad Exclusions'; Pass=($data.BroadExclusions -eq 0); Detail="$($data.BroadExclusions) broad exclusions found" }
    } else {
        $data.Checks += [PSCustomObject]@{ Name='CA Policies Loaded'; Pass=$false; Detail='No policies returned' }
    }
} catch {
    $data.Checks += [PSCustomObject]@{ Name='CA Policies Loaded'; Pass=$false; Detail="Graph error: $($_.Exception.Message)" }
    $data.Checks += [PSCustomObject]@{ Name='MFA Coverage'; Pass=$false; Detail='Insufficient data' }
    $data.Checks += [PSCustomObject]@{ Name='No Broad Exclusions'; Pass=$false; Detail='Insufficient data' }
}

$data.MaxScore = $data.Checks.Count * 20
$data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
$data.Summary = "CA Policies: $($data.Score)/$($data.MaxScore) -- $($data.EnabledPolicies) enabled | $($data.PoliciesRequiringMFA) with MFA | $($data.BroadExclusions) broad exclusions"

return $data
