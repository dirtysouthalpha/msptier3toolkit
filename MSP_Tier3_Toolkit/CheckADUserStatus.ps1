<#
.SYNOPSIS
    Comprehensive Active Directory User Status Checker
.DESCRIPTION
    Retrieves detailed user information from Active Directory including:
    - Account status and lockout information
    - Password status and expiration
    - Last logon and bad password attempt tracking
    - Group membership
    - Account properties (enabled/disabled, expiration)
    - Manager and department information
    - Ability to unlock accounts
.PARAMETER Username
    The SAM Account Name or UserPrincipalName of the user to check
.PARAMETER UnlockAccount
    Unlock the user account if it is locked
.PARAMETER ShowGroups
    Display group membership information
.PARAMETER ExportReport
    Export detailed report to CSV file
.NOTES
    Author: MSP Toolkit Team
    Version: 2.0
    Requires: ActiveDirectory module, standard user (unlock requires elevated permissions)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Username,

    [switch]$UnlockAccount,
    [switch]$ShowGroups,
    [switch]$ExportReport
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

function Test-ADModuleAvailable {
    <#
    .SYNOPSIS
        Checks if ActiveDirectory module is available
    #>
    try {
        if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
            Write-StatusMessage "ActiveDirectory module not found" -Level ERROR
            Write-Host ""
            Write-Host "  To install the ActiveDirectory module:" -ForegroundColor Yellow
            Write-Host "  1. Install RSAT (Remote Server Administration Tools)" -ForegroundColor Gray
            Write-Host "  2. Or run on a Domain Controller" -ForegroundColor Gray
            Write-Host ""
            return $false
        }

        Import-Module ActiveDirectory -ErrorAction Stop
        return $true
    }
    catch {
        Write-StatusMessage "Failed to load ActiveDirectory module: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Get-PasswordExpirationInfo {
    <#
    .SYNOPSIS
        Calculates password expiration information
    #>
    param(
        [Parameter(Mandatory=$true)]
        $User,
        [Parameter(Mandatory=$true)]
        $DomainPolicy
    )

    try {
        if ($User.PasswordNeverExpires) {
            return [PSCustomObject]@{
                Status = "Never Expires"
                DaysUntilExpiration = "N/A"
                ExpirationDate = "Never"
                NeedsChange = $false
            }
        }

        if (-not $User.PasswordLastSet) {
            return [PSCustomObject]@{
                Status = "Never Set"
                DaysUntilExpiration = "N/A"
                ExpirationDate = "N/A"
                NeedsChange = $true
            }
        }

        $maxPasswordAge = $DomainPolicy.MaxPasswordAge
        if ($maxPasswordAge.TotalDays -eq 0) {
            return [PSCustomObject]@{
                Status = "Never Expires (Domain Policy)"
                DaysUntilExpiration = "N/A"
                ExpirationDate = "Never"
                NeedsChange = $false
            }
        }

        $expirationDate = $User.PasswordLastSet.AddDays($maxPasswordAge.TotalDays)
        $daysUntilExpiration = ($expirationDate - (Get-Date)).Days

        $status = if ($daysUntilExpiration -lt 0) {
            "EXPIRED"
        } elseif ($daysUntilExpiration -le 7) {
            "EXPIRING SOON"
        } elseif ($daysUntilExpiration -le 14) {
            "WARNING"
        } else {
            "GOOD"
        }

        return [PSCustomObject]@{
            Status = $status
            DaysUntilExpiration = $daysUntilExpiration
            ExpirationDate = $expirationDate.ToString('yyyy-MM-dd')
            NeedsChange = ($daysUntilExpiration -le 0)
        }
    }
    catch {
        Write-StatusMessage "Error calculating password expiration: $($_.Exception.Message)" -Level WARNING
        return [PSCustomObject]@{
            Status = "Unknown"
            DaysUntilExpiration = "N/A"
            ExpirationDate = "N/A"
            NeedsChange = $false
        }
    }
}

function Get-LastLogonInfo {
    <#
    .SYNOPSIS
        Gets the most recent logon time across all domain controllers
    #>
    param([string]$Username)

    try {
        $dcs = Get-ADDomainController -Filter * -ErrorAction SilentlyContinue
        $lastLogon = $null

        foreach ($dc in $dcs) {
            try {
                $user = Get-ADUser -Identity $Username -Server $dc.HostName -Properties LastLogon -ErrorAction SilentlyContinue
                if ($user.LastLogon -and ($null -eq $lastLogon -or $user.LastLogon -gt $lastLogon)) {
                    $lastLogon = $user.LastLogon
                }
            }
            catch {
                # Skip DCs that are unreachable
            }
        }

        if ($lastLogon) {
            return [DateTime]::FromFileTime($lastLogon)
        }

        return $null
    }
    catch {
        return $null
    }
}

# Main execution
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host " Active Directory User Status Checker" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

# Check for AD module
if (-not (Test-ADModuleAvailable)) {
    exit 1
}

Write-StatusMessage "Querying Active Directory for user: $Username" -Level INFO
Write-Host ""

try {
    # Get user information with all required properties
    $user = Get-ADUser -Identity $Username -Properties `
        LockedOut, PasswordLastSet, BadLogonCount, LastBadPasswordAttempt, `
        Enabled, AccountExpirationDate, PasswordNeverExpires, PasswordExpired, `
        whenCreated, whenChanged, Description, EmailAddress, Manager, Department, `
        Title, telephoneNumber, MemberOf, LastLogonDate, DistinguishedName `
        -ErrorAction Stop

    # Get domain password policy
    $domainPolicy = Get-ADDefaultDomainPasswordPolicy -ErrorAction SilentlyContinue

    # Get password expiration info
    $passwordInfo = Get-PasswordExpirationInfo -User $user -DomainPolicy $domainPolicy

    # Get most recent logon across all DCs
    Write-StatusMessage "Checking logon history across domain controllers..." -Level INFO
    $actualLastLogon = Get-LastLogonInfo -Username $Username

    Write-Host ""
    Write-StatusMessage "User information retrieved successfully" -Level SUCCESS
    Write-Host ""

    # Display results
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host " USER ACCOUNT INFORMATION" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ""

    Write-Host "Username (SAM):     " -NoNewline -ForegroundColor Gray
    Write-Host $user.SamAccountName -ForegroundColor White

    Write-Host "Display Name:       " -NoNewline -ForegroundColor Gray
    Write-Host $user.Name -ForegroundColor White

    if ($user.EmailAddress) {
        Write-Host "Email:              " -NoNewline -ForegroundColor Gray
        Write-Host $user.EmailAddress -ForegroundColor White
    }

    Write-Host "Distinguished Name: " -NoNewline -ForegroundColor Gray
    Write-Host $user.DistinguishedName -ForegroundColor Cyan

    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host " ACCOUNT STATUS" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ""

    # Account enabled status
    Write-Host "Account Enabled:    " -NoNewline -ForegroundColor Gray
    if ($user.Enabled) {
        Write-Host "YES" -ForegroundColor Green
    } else {
        Write-Host "NO (DISABLED)" -ForegroundColor Red
    }

    # Account lockout status
    Write-Host "Account Locked:     " -NoNewline -ForegroundColor Gray
    if ($user.LockedOut) {
        Write-Host "YES (LOCKED)" -ForegroundColor Red
        if ($UnlockAccount) {
            try {
                Unlock-ADAccount -Identity $Username -ErrorAction Stop
                Write-Host ""
                Write-StatusMessage "Account unlocked successfully" -Level SUCCESS
            }
            catch {
                Write-Host ""
                Write-StatusMessage "Failed to unlock account: $($_.Exception.Message)" -Level ERROR
                Write-StatusMessage "Note: Unlock requires elevated permissions" -Level WARNING
            }
        }
    } else {
        Write-Host "No" -ForegroundColor Green
    }

    # Account expiration
    Write-Host "Account Expiration: " -NoNewline -ForegroundColor Gray
    if ($user.AccountExpirationDate) {
        $daysUntilExpiration = ($user.AccountExpirationDate - (Get-Date)).Days
        if ($daysUntilExpiration -lt 0) {
            Write-Host "EXPIRED on $($user.AccountExpirationDate.ToString('yyyy-MM-dd'))" -ForegroundColor Red
        } elseif ($daysUntilExpiration -le 7) {
            Write-Host "Expires in $daysUntilExpiration days ($($user.AccountExpirationDate.ToString('yyyy-MM-dd')))" -ForegroundColor Yellow
        } else {
            Write-Host "$($user.AccountExpirationDate.ToString('yyyy-MM-dd'))" -ForegroundColor White
        }
    } else {
        Write-Host "Never" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host " PASSWORD INFORMATION" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ""

    Write-Host "Password Last Set:  " -NoNewline -ForegroundColor Gray
    if ($user.PasswordLastSet) {
        Write-Host $user.PasswordLastSet.ToString('yyyy-MM-dd HH:mm:ss') -ForegroundColor White
        $passwordAge = ((Get-Date) - $user.PasswordLastSet).Days
        Write-Host "Password Age:       " -NoNewline -ForegroundColor Gray
        Write-Host "$passwordAge days" -ForegroundColor $(if ($passwordAge -gt 90) { 'Yellow' } else { 'White' })
    } else {
        Write-Host "Never" -ForegroundColor Yellow
    }

    Write-Host "Password Status:    " -NoNewline -ForegroundColor Gray
    $statusColor = switch ($passwordInfo.Status) {
        'GOOD' { 'Green' }
        'WARNING' { 'Yellow' }
        'EXPIRING SOON' { 'Yellow' }
        'EXPIRED' { 'Red' }
        default { 'White' }
    }
    Write-Host $passwordInfo.Status -ForegroundColor $statusColor

    if ($passwordInfo.DaysUntilExpiration -ne "N/A") {
        Write-Host "Days Until Expiry:  " -NoNewline -ForegroundColor Gray
        $expiryColor = if ($passwordInfo.DaysUntilExpiration -le 0) { 'Red' }
                       elseif ($passwordInfo.DaysUntilExpiration -le 7) { 'Yellow' }
                       else { 'White' }
        Write-Host $passwordInfo.DaysUntilExpiration -ForegroundColor $expiryColor

        Write-Host "Expiration Date:    " -NoNewline -ForegroundColor Gray
        Write-Host $passwordInfo.ExpirationDate -ForegroundColor $expiryColor
    }

    Write-Host "Password Expired:   " -NoNewline -ForegroundColor Gray
    Write-Host $(if ($user.PasswordExpired) { "YES" } else { "No" }) -ForegroundColor $(if ($user.PasswordExpired) { 'Red' } else { 'Green' })

    Write-Host "Never Expires:      " -NoNewline -ForegroundColor Gray
    Write-Host $(if ($user.PasswordNeverExpires) { "YES" } else { "No" }) -ForegroundColor $(if ($user.PasswordNeverExpires) { 'Yellow' } else { 'White' })

    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host " LOGON & SECURITY" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ""

    Write-Host "Last Logon:         " -NoNewline -ForegroundColor Gray
    if ($actualLastLogon) {
        $daysSinceLogon = ((Get-Date) - $actualLastLogon).Days
        Write-Host $actualLastLogon.ToString('yyyy-MM-dd HH:mm:ss') -ForegroundColor White
        Write-Host "Days Since Logon:   " -NoNewline -ForegroundColor Gray
        Write-Host "$daysSinceLogon days" -ForegroundColor $(if ($daysSinceLogon -gt 90) { 'Yellow' } else { 'White' })
    } elseif ($user.LastLogonDate) {
        Write-Host $user.LastLogonDate.ToString('yyyy-MM-dd HH:mm:ss') -ForegroundColor White
    } else {
        Write-Host "Never" -ForegroundColor Yellow
    }

    Write-Host "Bad Logon Count:    " -NoNewline -ForegroundColor Gray
    Write-Host $user.BadLogonCount -ForegroundColor $(if ($user.BadLogonCount -gt 0) { 'Yellow' } else { 'Green' })

    if ($user.LastBadPasswordAttempt) {
        Write-Host "Last Bad Attempt:   " -NoNewline -ForegroundColor Gray
        Write-Host $user.LastBadPasswordAttempt.ToString('yyyy-MM-dd HH:mm:ss') -ForegroundColor Yellow
    }

    # Organization info
    if ($user.Department -or $user.Title -or $user.Manager) {
        Write-Host ""
        Write-Host ("=" * 80) -ForegroundColor Cyan
        Write-Host " ORGANIZATION" -ForegroundColor Cyan
        Write-Host ("=" * 80) -ForegroundColor Cyan
        Write-Host ""

        if ($user.Department) {
            Write-Host "Department:         " -NoNewline -ForegroundColor Gray
            Write-Host $user.Department -ForegroundColor White
        }

        if ($user.Title) {
            Write-Host "Title:              " -NoNewline -ForegroundColor Gray
            Write-Host $user.Title -ForegroundColor White
        }

        if ($user.Manager) {
            try {
                $manager = Get-ADUser -Identity $user.Manager -Properties DisplayName -ErrorAction SilentlyContinue
                Write-Host "Manager:            " -NoNewline -ForegroundColor Gray
                Write-Host $manager.Name -ForegroundColor White
            }
            catch {
                Write-Host "Manager:            " -NoNewline -ForegroundColor Gray
                Write-Host $user.Manager -ForegroundColor White
            }
        }

        if ($user.telephoneNumber) {
            Write-Host "Phone:              " -NoNewline -ForegroundColor Gray
            Write-Host $user.telephoneNumber -ForegroundColor White
        }
    }

    # Group membership
    if ($ShowGroups -and $user.MemberOf) {
        Write-Host ""
        Write-Host ("=" * 80) -ForegroundColor Cyan
        Write-Host " GROUP MEMBERSHIP ($($user.MemberOf.Count) groups)" -ForegroundColor Cyan
        Write-Host ("=" * 80) -ForegroundColor Cyan
        Write-Host ""

        $groups = $user.MemberOf | ForEach-Object {
            try {
                $group = Get-ADGroup -Identity $_ -Properties Description -ErrorAction SilentlyContinue
                [PSCustomObject]@{
                    Name = $group.Name
                    Description = $group.Description
                }
            }
            catch {
                [PSCustomObject]@{
                    Name = ($_ -split ',')[0] -replace 'CN=', ''
                    Description = "Unable to retrieve"
                }
            }
        } | Sort-Object Name

        foreach ($group in $groups) {
            Write-Host "  - " -NoNewline -ForegroundColor Gray
            Write-Host $group.Name -ForegroundColor White
            if ($group.Description) {
                Write-Host "    $($group.Description)" -ForegroundColor DarkGray
            }
        }
    }

    # Additional info
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host " ADDITIONAL INFORMATION" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ""

    Write-Host "Created:            " -NoNewline -ForegroundColor Gray
    Write-Host $user.whenCreated.ToString('yyyy-MM-dd HH:mm:ss') -ForegroundColor White

    Write-Host "Last Modified:      " -NoNewline -ForegroundColor Gray
    Write-Host $user.whenChanged.ToString('yyyy-MM-dd HH:mm:ss') -ForegroundColor White

    if ($user.Description) {
        Write-Host "Description:        " -NoNewline -ForegroundColor Gray
        Write-Host $user.Description -ForegroundColor White
    }

    # Summary and recommendations
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Green
    Write-Host " SUMMARY" -ForegroundColor Green
    Write-Host ("=" * 80) -ForegroundColor Green
    Write-Host ""

    $issues = @()

    if (-not $user.Enabled) {
        $issues += "[X] Account is DISABLED"
    }

    if ($user.LockedOut -and -not $UnlockAccount) {
        $issues += "[X] Account is LOCKED - Use -UnlockAccount to unlock"
    }

    if ($passwordInfo.NeedsChange) {
        $issues += "[!] Password needs to be changed"
    }

    if ($user.PasswordExpired) {
        $issues += "[X] Password is EXPIRED"
    }

    if ($user.AccountExpirationDate -and $user.AccountExpirationDate -lt (Get-Date)) {
        $issues += "[X] Account has EXPIRED"
    }

    if ($user.BadLogonCount -gt 3) {
        $issues += "[!] Multiple bad logon attempts detected"
    }

    if ($actualLastLogon) {
        $daysSinceLogon = ((Get-Date) - $actualLastLogon).Days
        if ($daysSinceLogon -gt 90) {
            $issues += "[!] No logon in $daysSinceLogon days - Account may be inactive"
        }
    }

    if ($issues.Count -eq 0) {
        Write-Host "  " -NoNewline
        Write-StatusMessage "No issues detected - Account appears healthy" -Level SUCCESS
    } else {
        Write-Host "  Issues Found:" -ForegroundColor Yellow
        Write-Host ""
        foreach ($issue in $issues) {
            Write-Host "  $issue" -ForegroundColor $(if ($issue.StartsWith('[X]')) { 'Red' } else { 'Yellow' })
        }
    }

    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Green
    Write-Host " Query Complete" -ForegroundColor Green
    Write-Host ("=" * 80) -ForegroundColor Green
    Write-Host ""

    # Export report if requested
    if ($ExportReport) {
        $exportPath = "$env:USERPROFILE\Desktop\ADUser_$($user.SamAccountName)_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

        $reportData = [PSCustomObject]@{
            Username = $user.SamAccountName
            DisplayName = $user.Name
            Email = $user.EmailAddress
            Enabled = $user.Enabled
            LockedOut = $user.LockedOut
            PasswordLastSet = $user.PasswordLastSet
            PasswordExpired = $user.PasswordExpired
            PasswordNeverExpires = $user.PasswordNeverExpires
            PasswordExpirationDate = $passwordInfo.ExpirationDate
            DaysUntilPasswordExpiry = $passwordInfo.DaysUntilExpiration
            LastLogon = $actualLastLogon
            BadLogonCount = $user.BadLogonCount
            LastBadPasswordAttempt = $user.LastBadPasswordAttempt
            AccountExpirationDate = $user.AccountExpirationDate
            Department = $user.Department
            Title = $user.Title
            Created = $user.whenCreated
            LastModified = $user.whenChanged
            DistinguishedName = $user.DistinguishedName
        }

        $reportData | Export-Csv -Path $exportPath -NoTypeInformation -Force
        Write-StatusMessage "Report exported to: $exportPath" -Level SUCCESS
        Write-Host ""
    }

}
catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
    Write-Host ""
    Write-StatusMessage "User '$Username' not found in Active Directory" -Level ERROR
    Write-Host ""
    Write-Host "  Suggestions:" -ForegroundColor Yellow
    Write-Host "  - Check the username spelling" -ForegroundColor Gray
    Write-Host "  - Try using the full UserPrincipalName (user@domain.com)" -ForegroundColor Gray
    Write-Host "  - Verify the user exists in this domain" -ForegroundColor Gray
    Write-Host ""
    exit 1
}
catch {
    Write-Host ""
    Write-StatusMessage "Error querying Active Directory: $($_.Exception.Message)" -Level ERROR
    Write-Host ""
    exit 1
}
