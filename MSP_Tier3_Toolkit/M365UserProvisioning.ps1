<#
.SYNOPSIS
Assigns M365 license and enables mailbox.
#>

Connect-MsolService
$UPN = Read-Host "Enter UserPrincipalName"
Set-MsolUser -UserPrincipalName $UPN -UsageLocation US
Set-MsolUserLicense -UserPrincipalName $UPN -AddLicenses "tenantname:O365_BUSINESS_PREMIUM"
