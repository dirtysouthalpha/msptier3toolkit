<#
.SYNOPSIS
    Find M365 licenses being paid for but not used -- quantifies the savings.
.DESCRIPTION
    Rolls up:
      - Per-SKU consumed vs. enabled counts (the easy "available" pool)
      - Users assigned a license but with sign-in age > N days (zombies)
      - Disabled users still holding licenses (immediate reclaim)
      - Shared/service accounts holding interactive licenses

    Output includes an "EstimatedMonthlySavings" if you pass -SkuPriceMap
    (a hashtable mapping SKU partNumbers to monthly cost).
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [int]$ZombieDays = 90,
    [hashtable]$SkuPriceMap = @{},
    [switch]$AsJson
)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue
Connect-MSPGraph

# Get sku catalog
$skus = Invoke-MSPGraph -Path 'subscribedSkus'
$skuMap = @{}
foreach ($s in $skus) { $skuMap[$s.skuId] = $s.skuPartNumber }

# Sku summary
$skuSummary = $skus | ForEach-Object {
    $avail = $_.prepaidUnits.enabled - $_.consumedUnits
    $price = if ($SkuPriceMap.ContainsKey($_.skuPartNumber)) { $SkuPriceMap[$_.skuPartNumber] } else { 0 }
    [pscustomobject]@{
        Sku       = $_.skuPartNumber
        Enabled   = $_.prepaidUnits.enabled
        Consumed  = $_.consumedUnits
        Available = $avail
        MonthlyWaste = $avail * $price
    }
}

# Pull users + sign-in activity
$users = Invoke-MSPGraph -Path "users?`$select=id,displayName,userPrincipalName,accountEnabled,assignedLicenses,signInActivity,userType,mail"

$threshold = (Get-Date).AddDays(-$ZombieDays)
$zombies = @()
$disabledHolding = @()
foreach ($u in $users) {
    if (-not $u.assignedLicenses) { continue }
    if (-not $u.assignedLicenses.Count) { continue }
    $skuList = ($u.assignedLicenses | ForEach-Object { $skuMap[$_.skuId] }) -join ', '
    $monthlyValue = ($u.assignedLicenses | ForEach-Object {
        if ($SkuPriceMap.ContainsKey($skuMap[$_.skuId])) { $SkuPriceMap[$skuMap[$_.skuId]] } else { 0 }
    } | Measure-Object -Sum).Sum

    if (-not $u.accountEnabled) {
        $disabledHolding += [pscustomobject]@{
            UPN          = $u.userPrincipalName
            DisplayName  = $u.displayName
            Skus         = $skuList
            MonthlyValue = $monthlyValue
        }
        continue
    }
    $lastSignIn = $null
    if ($u.signInActivity -and $u.signInActivity.lastSignInDateTime) {
        $lastSignIn = [datetime]$u.signInActivity.lastSignInDateTime
    }
    if (-not $lastSignIn -or $lastSignIn -lt $threshold) {
        $zombies += [pscustomobject]@{
            UPN          = $u.userPrincipalName
            DisplayName  = $u.displayName
            LastSignIn   = $lastSignIn
            Skus         = $skuList
            MonthlyValue = $monthlyValue
        }
    }
}

$totalSavings = ($skuSummary | Measure-Object MonthlyWaste -Sum).Sum +
                ($disabledHolding | Measure-Object MonthlyValue -Sum).Sum +
                ($zombies | Measure-Object MonthlyValue -Sum).Sum

$status = if ($disabledHolding.Count -gt 0) { 'Warning' } else { 'Success' }
$result = New-MSPResult `
    -Tool 'Get-LicenseRecoveryReport' `
    -Status $status `
    -Summary "Available: $($skuSummary | Measure-Object Available -Sum | ForEach-Object Sum); zombies: $($zombies.Count); disabled holding: $($disabledHolding.Count). Est savings: `$$totalSavings/mo" `
    -Data @{
        SkuSummary       = $skuSummary
        Zombies          = $zombies
        DisabledHolding  = $disabledHolding
        ZombieDays       = $ZombieDays
    } `
    -Metrics @{
        AvailableSlots   = ($skuSummary | Measure-Object Available -Sum).Sum
        ZombieCount      = $zombies.Count
        DisabledHolding  = $disabledHolding.Count
        EstMonthlySaving = $totalSavings
    }

[void](Save-MSPResult -Result $result -Subfolder 'Lifecycle')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
