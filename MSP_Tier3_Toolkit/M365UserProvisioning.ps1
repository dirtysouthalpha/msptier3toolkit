<#
.SYNOPSIS
    Microsoft 365 User License Provisioning Tool
.DESCRIPTION
    Comprehensive M365 user provisioning tool that:
    - Assigns Microsoft 365 licenses to users
    - Validates user accounts and license availability
    - Configures usage location
    - Supports both legacy MSOnline and modern Microsoft Graph API
    - Provides detailed status and error reporting
    - Optionally enables mailbox and checks provisioning status
.PARAMETER UserPrincipalName
    The UPN (email address) of the user to provision
.PARAMETER LicenseSku
    The license SKU to assign (e.g., "O365_BUSINESS_PREMIUM", "ENTERPRISEPACK")
    Use -ListLicenses to see available licenses
.PARAMETER UsageLocation
    Two-letter country code for usage location (default: US)
.PARAMETER ListLicenses
    Display all available licenses in the tenant
.PARAMETER CheckStatus
    Check current license status without making changes
.PARAMETER UseGraphAPI
    Use Microsoft Graph API instead of MSOnline (recommended)
.PARAMETER WhatIf
    Show what would happen without making changes
.NOTES
    Author: MSP Toolkit Team
    Version: 2.0
    Requires: MSOnline or Microsoft.Graph PowerShell modules

    Installation:
    - MSOnline: Install-Module MSOnline
    - Graph API: Install-Module Microsoft.Graph -Scope CurrentUser
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$UserPrincipalName,

    [Parameter(Mandatory=$false)]
    [string]$LicenseSku,

    [Parameter(Mandatory=$false)]
    [ValidateLength(2,2)]
    [string]$UsageLocation = "US",

    [switch]$ListLicenses,
    [switch]$CheckStatus,
    [switch]$UseGraphAPI,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

function Write-StatusMessage {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $color = switch ($Level) {
        'SUCCESS' { 'Green' }
        'ERROR'   { 'Red' }
        'WARNING' { 'Yellow' }
        default   { 'Cyan' }
    }

    $icon = switch ($Level) {
        'SUCCESS' { '[+]' }
        'ERROR'   { '[X]' }
        'WARNING' { '[!]' }
        default   { '[i]' }
    }

    Write-Host "$icon " -NoNewline -ForegroundColor $color
    Write-Host $Message
}

function Test-ValidUPN {
    <#
    .SYNOPSIS
        Validates UPN format
    #>
    param([string]$UPN)

    if ([string]::IsNullOrWhiteSpace($UPN)) {
        return $false
    }

    # Basic email format validation
    $emailRegex = '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    return $UPN -match $emailRegex
}

function Connect-ToM365 {
    <#
    .SYNOPSIS
        Connects to Microsoft 365 using appropriate module
    #>
    param([bool]$UseGraph)

    try {
        if ($UseGraph) {
            # Check for Microsoft Graph module
            if (-not (Get-Module -Name Microsoft.Graph.Users -ListAvailable)) {
                Write-StatusMessage "Microsoft.Graph module not found" -Level ERROR
                Write-Host ""
                Write-Host "  To install Microsoft Graph PowerShell:" -ForegroundColor Yellow
                Write-Host "  Install-Module Microsoft.Graph -Scope CurrentUser" -ForegroundColor Gray
                Write-Host ""
                return $false
            }

            Write-StatusMessage "Connecting to Microsoft Graph..." -Level INFO

            # Connect with required scopes
            Connect-MgGraph -Scopes "User.ReadWrite.All", "Organization.Read.All" -ErrorAction Stop

            Write-StatusMessage "Connected to Microsoft Graph successfully" -Level SUCCESS
            return $true
        }
        else {
            # Check for MSOnline module
            if (-not (Get-Module -Name MSOnline -ListAvailable)) {
                Write-StatusMessage "MSOnline module not found" -Level ERROR
                Write-Host ""
                Write-Host "  To install MSOnline PowerShell:" -ForegroundColor Yellow
                Write-Host "  Install-Module MSOnline -Scope CurrentUser" -ForegroundColor Gray
                Write-Host ""
                Write-Host "  NOTE: MSOnline is deprecated. Consider using -UseGraphAPI flag" -ForegroundColor Yellow
                Write-Host ""
                return $false
            }

            Write-StatusMessage "Connecting to Microsoft 365 (MSOnline)..." -Level INFO
            Write-StatusMessage "NOTE: MSOnline module is deprecated. Consider using -UseGraphAPI" -Level WARNING

            Import-Module MSOnline -ErrorAction Stop
            Connect-MsolService -ErrorAction Stop

            Write-StatusMessage "Connected to Microsoft 365 successfully" -Level SUCCESS
            return $true
        }
    }
    catch {
        Write-StatusMessage "Failed to connect: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Get-AvailableLicenses {
    <#
    .SYNOPSIS
        Gets all available licenses in the tenant
    #>
    param([bool]$UseGraph)

    try {
        if ($UseGraph) {
            $licenses = Get-MgSubscribedSku -ErrorAction Stop

            $licenseList = @()
            foreach ($lic in $licenses) {
                $available = $lic.PrepaidUnits.Enabled - $lic.ConsumedUnits

                $licenseList += [PSCustomObject]@{
                    SkuPartNumber = $lic.SkuPartNumber
                    SkuId = $lic.SkuId
                    ActiveUnits = $lic.PrepaidUnits.Enabled
                    ConsumedUnits = $lic.ConsumedUnits
                    AvailableUnits = $available
                    Status = if ($available -gt 0) { "Available" } else { "No units available" }
                }
            }

            return $licenseList
        }
        else {
            $licenses = Get-MsolAccountSku -ErrorAction Stop

            $licenseList = @()
            foreach ($lic in $licenses) {
                $available = $lic.ActiveUnits - $lic.ConsumedUnits

                $licenseList += [PSCustomObject]@{
                    SkuPartNumber = $lic.SkuPartNumber
                    AccountSkuId = $lic.AccountSkuId
                    ActiveUnits = $lic.ActiveUnits
                    ConsumedUnits = $lic.ConsumedUnits
                    AvailableUnits = $available
                    Status = if ($available -gt 0) { "Available" } else { "No units available" }
                }
            }

            return $licenseList
        }
    }
    catch {
        Write-StatusMessage "Error retrieving licenses: $($_.Exception.Message)" -Level ERROR
        return @()
    }
}

function Get-UserLicenseStatus {
    <#
    .SYNOPSIS
        Gets current license status for a user
    #>
    param(
        [string]$UPN,
        [bool]$UseGraph
    )

    try {
        if ($UseGraph) {
            $user = Get-MgUser -UserId $UPN -Property Id,UserPrincipalName,DisplayName,UsageLocation,AssignedLicenses -ErrorAction Stop

            $licenses = @()
            foreach ($license in $user.AssignedLicenses) {
                $sku = Get-MgSubscribedSku -SubscribedSkuId $license.SkuId -ErrorAction SilentlyContinue
                $licenses += [PSCustomObject]@{
                    SkuPartNumber = $sku.SkuPartNumber
                    SkuId = $license.SkuId
                }
            }

            return [PSCustomObject]@{
                UserPrincipalName = $user.UserPrincipalName
                DisplayName = $user.DisplayName
                UsageLocation = $user.UsageLocation
                Licenses = $licenses
                LicenseCount = $licenses.Count
            }
        }
        else {
            $user = Get-MsolUser -UserPrincipalName $UPN -ErrorAction Stop

            $licenses = @()
            foreach ($license in $user.Licenses) {
                $licenses += [PSCustomObject]@{
                    SkuPartNumber = $license.AccountSkuId.Split(':')[1]
                    AccountSkuId = $license.AccountSkuId
                }
            }

            return [PSCustomObject]@{
                UserPrincipalName = $user.UserPrincipalName
                DisplayName = $user.DisplayName
                UsageLocation = $user.UsageLocation
                Licenses = $licenses
                LicenseCount = $licenses.Count
            }
        }
    }
    catch {
        throw "Failed to get user status: $($_.Exception.Message)"
    }
}

function Set-UserLicense {
    <#
    .SYNOPSIS
        Assigns license to user
    #>
    param(
        [string]$UPN,
        [string]$Sku,
        [string]$Location,
        [bool]$UseGraph,
        [switch]$WhatIfPreference
    )

    try {
        if ($UseGraph) {
            # Get user
            $user = Get-MgUser -UserId $UPN -ErrorAction Stop

            # Set usage location if not set
            if (-not $user.UsageLocation) {
                if ($PSCmdlet.ShouldProcess($UPN, "Set usage location to $Location")) {
                    Write-StatusMessage "Setting usage location to $Location..." -Level INFO
                    Update-MgUser -UserId $UPN -UsageLocation $Location -ErrorAction Stop
                }
            }

            # Find the license SKU
            $licenses = Get-MgSubscribedSku -ErrorAction Stop
            $licenseSku = $licenses | Where-Object { $_.SkuPartNumber -eq $Sku }

            if (-not $licenseSku) {
                throw "License SKU '$Sku' not found in tenant"
            }

            # Check if license is available
            $available = $licenseSku.PrepaidUnits.Enabled - $licenseSku.ConsumedUnits
            if ($available -le 0) {
                throw "No available units for license '$Sku' (Active: $($licenseSku.PrepaidUnits.Enabled), Consumed: $($licenseSku.ConsumedUnits))"
            }

            # Check if user already has this license
            $currentLicenses = Get-MgUserLicenseDetail -UserId $UPN -ErrorAction SilentlyContinue
            if ($currentLicenses.SkuId -contains $licenseSku.SkuId) {
                Write-StatusMessage "User already has license '$Sku'" -Level WARNING
                return $true
            }

            # Assign the license
            if ($PSCmdlet.ShouldProcess($UPN, "Assign license $Sku")) {
                Write-StatusMessage "Assigning license '$Sku'..." -Level INFO

                $licenseParams = @{
                    AddLicenses = @(
                        @{
                            SkuId = $licenseSku.SkuId
                        }
                    )
                    RemoveLicenses = @()
                }

                Set-MgUserLicense -UserId $UPN -BodyParameter $licenseParams -ErrorAction Stop
                Write-StatusMessage "License assigned successfully" -Level SUCCESS
                return $true
            }
        }
        else {
            # Get user
            $user = Get-MsolUser -UserPrincipalName $UPN -ErrorAction Stop

            # Set usage location if not set
            if ([string]::IsNullOrWhiteSpace($user.UsageLocation)) {
                if ($PSCmdlet.ShouldProcess($UPN, "Set usage location to $Location")) {
                    Write-StatusMessage "Setting usage location to $Location..." -Level INFO
                    Set-MsolUser -UserPrincipalName $UPN -UsageLocation $Location -ErrorAction Stop
                }
            }

            # Get available licenses
            $availableLicenses = Get-MsolAccountSku -ErrorAction Stop
            $tenantName = ($availableLicenses[0].AccountSkuId -split ':')[0]
            $fullSkuId = "${tenantName}:${Sku}"

            # Find the license
            $license = $availableLicenses | Where-Object { $_.AccountSkuId -eq $fullSkuId }

            if (-not $license) {
                throw "License SKU '$Sku' not found in tenant. Use -ListLicenses to see available licenses."
            }

            # Check if license is available
            $available = $license.ActiveUnits - $license.ConsumedUnits
            if ($available -le 0) {
                throw "No available units for license '$Sku' (Active: $($license.ActiveUnits), Consumed: $($license.ConsumedUnits))"
            }

            # Check if user already has this license
            if ($user.Licenses.AccountSkuId -contains $fullSkuId) {
                Write-StatusMessage "User already has license '$Sku'" -Level WARNING
                return $true
            }

            # Assign the license
            if ($PSCmdlet.ShouldProcess($UPN, "Assign license $Sku")) {
                Write-StatusMessage "Assigning license '$Sku'..." -Level INFO
                Set-MsolUserLicense -UserPrincipalName $UPN -AddLicenses $fullSkuId -ErrorAction Stop
                Write-StatusMessage "License assigned successfully" -Level SUCCESS
                return $true
            }
        }

        return $true
    }
    catch {
        throw "Failed to assign license: $($_.Exception.Message)"
    }
}

# Main execution
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host " Microsoft 365 User License Provisioning" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

# Connect to M365
if (-not (Connect-ToM365 -UseGraph $UseGraphAPI)) {
    exit 1
}

Write-Host ""

try {
    # List licenses mode
    if ($ListLicenses) {
        Write-StatusMessage "Retrieving available licenses..." -Level INFO
        Write-Host ""

        $licenses = Get-AvailableLicenses -UseGraph $UseGraphAPI

        if ($licenses.Count -eq 0) {
            Write-StatusMessage "No licenses found in tenant" -Level WARNING
            exit 0
        }

        Write-Host ("=" * 80) -ForegroundColor Cyan
        Write-Host " AVAILABLE LICENSES" -ForegroundColor Cyan
        Write-Host ("=" * 80) -ForegroundColor Cyan
        Write-Host ""

        foreach ($lic in $licenses | Sort-Object SkuPartNumber) {
            Write-Host "License: " -NoNewline -ForegroundColor Gray
            Write-Host $lic.SkuPartNumber -ForegroundColor White
            Write-Host "  Active Units:    " -NoNewline -ForegroundColor Gray
            Write-Host $lic.ActiveUnits -ForegroundColor White
            Write-Host "  Consumed:        " -NoNewline -ForegroundColor Gray
            Write-Host $lic.ConsumedUnits -ForegroundColor White
            Write-Host "  Available:       " -NoNewline -ForegroundColor Gray
            $availColor = if ($lic.AvailableUnits -gt 0) { 'Green' } else { 'Red' }
            Write-Host $lic.AvailableUnits -ForegroundColor $availColor
            Write-Host "  Status:          " -NoNewline -ForegroundColor Gray
            $statusColor = if ($lic.Status -eq "Available") { 'Green' } else { 'Yellow' }
            Write-Host $lic.Status -ForegroundColor $statusColor
            Write-Host ""
        }

        Write-Host ("=" * 80) -ForegroundColor Green
        Write-Host ""
        exit 0
    }

    # Validate UPN is provided for other operations
    if ([string]::IsNullOrWhiteSpace($UserPrincipalName)) {
        Write-StatusMessage "UserPrincipalName is required" -Level ERROR
        Write-Host ""
        Write-Host "  Usage:" -ForegroundColor Yellow
        Write-Host "  .\M365UserProvisioning.ps1 -UserPrincipalName user@domain.com -LicenseSku O365_BUSINESS_PREMIUM" -ForegroundColor Gray
        Write-Host "  .\M365UserProvisioning.ps1 -ListLicenses" -ForegroundColor Gray
        Write-Host ""
        exit 1
    }

    # Validate UPN format
    if (-not (Test-ValidUPN -UPN $UserPrincipalName)) {
        Write-StatusMessage "Invalid UserPrincipalName format: $UserPrincipalName" -Level ERROR
        Write-Host ""
        Write-Host "  Expected format: user@domain.com" -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }

    # Check status mode
    if ($CheckStatus) {
        Write-StatusMessage "Retrieving license status for: $UserPrincipalName" -Level INFO
        Write-Host ""

        $userStatus = Get-UserLicenseStatus -UPN $UserPrincipalName -UseGraph $UseGraphAPI

        Write-Host ("=" * 80) -ForegroundColor Cyan
        Write-Host " USER LICENSE STATUS" -ForegroundColor Cyan
        Write-Host ("=" * 80) -ForegroundColor Cyan
        Write-Host ""

        Write-Host "User:            " -NoNewline -ForegroundColor Gray
        Write-Host $userStatus.UserPrincipalName -ForegroundColor White
        Write-Host "Display Name:    " -NoNewline -ForegroundColor Gray
        Write-Host $userStatus.DisplayName -ForegroundColor White
        Write-Host "Usage Location:  " -NoNewline -ForegroundColor Gray
        if ($userStatus.UsageLocation) {
            Write-Host $userStatus.UsageLocation -ForegroundColor Green
        } else {
            Write-Host "NOT SET" -ForegroundColor Red
        }
        Write-Host "License Count:   " -NoNewline -ForegroundColor Gray
        Write-Host $userStatus.LicenseCount -ForegroundColor White

        if ($userStatus.LicenseCount -gt 0) {
            Write-Host ""
            Write-Host "Assigned Licenses:" -ForegroundColor Cyan
            foreach ($lic in $userStatus.Licenses) {
                Write-Host "  - " -NoNewline -ForegroundColor Gray
                Write-Host $lic.SkuPartNumber -ForegroundColor White
            }
        } else {
            Write-Host ""
            Write-StatusMessage "User has no licenses assigned" -Level WARNING
        }

        Write-Host ""
        Write-Host ("=" * 80) -ForegroundColor Green
        Write-Host ""
        exit 0
    }

    # Assign license mode
    if ([string]::IsNullOrWhiteSpace($LicenseSku)) {
        Write-StatusMessage "LicenseSku is required for license assignment" -Level ERROR
        Write-Host ""
        Write-Host "  Use -ListLicenses to see available licenses" -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }

    Write-StatusMessage "Provisioning user: $UserPrincipalName" -Level INFO
    Write-StatusMessage "License SKU: $LicenseSku" -Level INFO
    Write-StatusMessage "Usage Location: $UsageLocation" -Level INFO
    Write-Host ""

    # Assign the license
    $result = Set-UserLicense -UPN $UserPrincipalName -Sku $LicenseSku -Location $UsageLocation -UseGraph $UseGraphAPI -WhatIfPreference:$WhatIf

    if ($result) {
        Write-Host ""
        Write-Host ("=" * 80) -ForegroundColor Green
        Write-Host " PROVISIONING COMPLETE" -ForegroundColor Green
        Write-Host ("=" * 80) -ForegroundColor Green
        Write-Host ""

        Write-StatusMessage "License provisioned successfully" -Level SUCCESS
        Write-Host ""
        Write-Host "  User:    $UserPrincipalName" -ForegroundColor Cyan
        Write-Host "  License: $LicenseSku" -ForegroundColor Cyan
        Write-Host ""
        Write-StatusMessage "NOTE: It may take 15-30 minutes for mailbox provisioning to complete" -Level INFO
        Write-Host ""

        # Check final status
        Write-StatusMessage "Verifying license assignment..." -Level INFO
        Start-Sleep -Seconds 2

        $finalStatus = Get-UserLicenseStatus -UPN $UserPrincipalName -UseGraph $UseGraphAPI
        if ($finalStatus.LicenseCount -gt 0) {
            Write-StatusMessage "Verification successful - User has $($finalStatus.LicenseCount) license(s)" -Level SUCCESS
        }

        Write-Host ""
        Write-Host ("=" * 80) -ForegroundColor Green
        Write-Host ""
    }
}
catch {
    Write-Host ""
    Write-StatusMessage "Error: $($_.Exception.Message)" -Level ERROR
    Write-Host ""

    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  1. Verify the user exists in Microsoft 365" -ForegroundColor Gray
    Write-Host "  2. Check that the license SKU is correct (use -ListLicenses)" -ForegroundColor Gray
    Write-Host "  3. Ensure you have sufficient permissions" -ForegroundColor Gray
    Write-Host "  4. Verify licenses are available in the tenant" -ForegroundColor Gray
    Write-Host ""
    exit 1
}
finally {
    # Disconnect if using Graph API
    if ($UseGraphAPI) {
        try {
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        }
        catch {
            # Ignore disconnect errors
        }
    }
}
