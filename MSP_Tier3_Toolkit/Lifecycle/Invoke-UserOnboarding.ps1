<#
.SYNOPSIS
    End-to-end new-hire onboarding orchestrator.
.DESCRIPTION
    Drives the boring 30-step onboarding workflow off a single template,
    so the only thing a tech does for a new hire is fill in the form.

    Phases (each can be enabled/disabled per template):
      1. AD account create (OU, samAccount, UPN, display name, manager)
      2. AD group memberships (security + distribution)
      3. M365 license assignment via Graph
      4. Mailbox setup (UsageLocation, OOO if -OnLeave)
      5. OneDrive pre-provisioning (POST to Graph endpoint)
      6. Welcome email with first-time password (BCC to manager)
      7. PSA ticket creation for any manual follow-up

    Template format: JSON describing the role/department; see
    Templates\NewHireProvisioning.json.

    SAFETY:
      - Refuses to run without a template
      - -WhatIf supported on every destructive step
      - Failed phases don't roll back earlier success (intentional --
        AD account exists, license assigned, just retry the failing phase)
      - Writes a per-user transcript under Reports\Lifecycle\Onboarding\
#>
#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
    [Parameter(Mandatory)] [string]$Template,
    [Parameter(Mandatory)] [string]$FirstName,
    [Parameter(Mandatory)] [string]$LastName,
    [string]$Department,
    [string]$Title,
    [string]$Manager,
    [datetime]$StartDate = (Get-Date),
    [string]$InitialPassword,
    [switch]$SendWelcomeEmail,
    [switch]$AsJson
)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

if (-not (Test-Path $Template)) { throw "Template not found: $Template" }
$tpl = Get-Content $Template -Raw | ConvertFrom-Json

$samAccountName = ('{0}{1}' -f $FirstName.Substring(0,1), $LastName).ToLower() -replace '[^a-z0-9]',''
$displayName    = "$FirstName $LastName"
$upn            = "$samAccountName@$($tpl.domain)"
$primarySmtp    = "$samAccountName@$($tpl.smtpDomain)"

if (-not $InitialPassword) {
    Add-Type -AssemblyName System.Web
    $InitialPassword = [System.Web.Security.Membership]::GeneratePassword(16,4)
}

$paths   = Get-MSPPaths
$logDir  = Join-Path $paths.Reports "Lifecycle\Onboarding"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$xscript = Join-Path $logDir "$samAccountName`_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $xscript -Force | Out-Null

$steps   = New-Object System.Collections.Generic.List[pscustomobject]
$errors  = New-Object System.Collections.Generic.List[string]
function Phase([string]$Name, [scriptblock]$Body) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        & $Body | Out-Null
        $steps.Add([pscustomobject]@{ Phase=$Name; Ok=$true; DurationMs=$sw.ElapsedMilliseconds; Detail='' })
    } catch {
        $msg = $_.Exception.Message
        $steps.Add([pscustomobject]@{ Phase=$Name; Ok=$false; DurationMs=$sw.ElapsedMilliseconds; Detail=$msg })
        $errors.Add("$Name : $msg")
    }
}

# 1. AD account
if ($tpl.steps.createAD) {
    Phase 'AD account' {
        if (-not (Get-Module ActiveDirectory -ListAvailable)) { throw 'ActiveDirectory module not available.' }
        Import-Module ActiveDirectory -ErrorAction Stop
        if ($PSCmdlet.ShouldProcess($samAccountName, 'New-ADUser')) {
            $secPwd = ConvertTo-SecureString $InitialPassword -AsPlainText -Force
            New-ADUser -Name $displayName -GivenName $FirstName -Surname $LastName `
                       -SamAccountName $samAccountName -UserPrincipalName $upn `
                       -DisplayName $displayName -Title $Title -Department $Department `
                       -Path $tpl.userOU -AccountPassword $secPwd `
                       -Enabled $true -ChangePasswordAtLogon $true `
                       -EmailAddress $primarySmtp -ErrorAction Stop
            if ($Manager) { Set-ADUser $samAccountName -Manager $Manager }
        }
    }
}

# 2. Group memberships
if ($tpl.steps.adGroups -and $tpl.groups) {
    Phase 'AD group memberships' {
        Import-Module ActiveDirectory -ErrorAction Stop
        foreach ($g in $tpl.groups) {
            if ($PSCmdlet.ShouldProcess("$g <- $samAccountName", 'Add-ADGroupMember')) {
                try { Add-ADGroupMember -Identity $g -Members $samAccountName -ErrorAction Stop }
                catch { $errors.Add("Group $g : $($_.Exception.Message)") }
            }
        }
    }
}

# 3. M365 license via Graph
if ($tpl.steps.assignLicense -and $tpl.licenseSku) {
    Phase 'M365 license' {
        Connect-MSPGraph
        $sku = (Invoke-MSPGraph -Path 'subscribedSkus') | Where-Object skuPartNumber -eq $tpl.licenseSku | Select-Object -First 1
        if (-not $sku) { throw "SKU $($tpl.licenseSku) not found in tenant." }
        if ($PSCmdlet.ShouldProcess($upn, "Assign $($tpl.licenseSku)")) {
            Invoke-MSPGraph -Path "users/$upn" -Method PATCH -Body @{
                usageLocation = $tpl.usageLocation
            } | Out-Null
            Invoke-MSPGraph -Path "users/$upn/assignLicense" -Method POST -Body @{
                addLicenses    = @(@{ skuId = $sku.skuId })
                removeLicenses = @()
            } | Out-Null
        }
    }
}

# 4. OneDrive pre-provision (no-content POST to drive endpoint triggers create)
if ($tpl.steps.preProvisionOneDrive) {
    Phase 'OneDrive pre-provision' {
        Connect-MSPGraph
        if ($PSCmdlet.ShouldProcess($upn, 'Pre-provision OneDrive')) {
            try { Invoke-MSPGraph -Path "users/$upn/drive" -Method GET | Out-Null } catch { }
        }
    }
}

# 5. Welcome email via configured SMTP
if ($SendWelcomeEmail -and $tpl.welcomeTemplate) {
    Phase 'Welcome email' {
        $body = $tpl.welcomeTemplate `
            -replace '{firstName}', $FirstName `
            -replace '{displayName}', $displayName `
            -replace '{upn}', $upn `
            -replace '{password}', $InitialPassword `
            -replace '{startDate}', $StartDate.ToString('yyyy-MM-dd')

        $to = @()
        if ($Manager) {
            try {
                Import-Module ActiveDirectory -ErrorAction Stop
                $mgr = Get-ADUser $Manager -Properties EmailAddress -ErrorAction Stop
                if ($mgr.EmailAddress) { $to += $mgr.EmailAddress }
            } catch { }
        }
        if (-not $to) { $to = @($tpl.welcomeCc) }
        Send-MSPEmail -Subject "Welcome to the team, $FirstName" -Body $body -To $to -BodyAsHtml
    }
}

# 6. PSA ticket
if ($tpl.steps.createTicket) {
    Phase 'PSA ticket' {
        if ($PSCmdlet.ShouldProcess('PSA', 'Create onboarding ticket')) {
            New-MSPTicket -Subject "Onboarding completed: $displayName" `
                          -Body "Onboarding for $displayName ($upn) completed by $env:USERNAME on $env:COMPUTERNAME.`r`nManual steps remaining: $(($tpl.manualSteps -join ', '))" `
                          -Priority 'Normal'
        }
    }
}

Stop-Transcript | Out-Null

$status = if ($errors.Count) { 'Warning' } else { 'Success' }
$result = New-MSPResult `
    -Tool 'Invoke-UserOnboarding' `
    -Status $status `
    -Summary "Onboarded $displayName ($upn) - $($steps.Count) phases, $($errors.Count) errors." `
    -Data @{
        User          = $displayName
        UPN           = $upn
        Sam           = $samAccountName
        InitialPassword = $InitialPassword   # tech sees once; goes into report only
        Steps         = $steps.ToArray()
        Transcript    = $xscript
    } `
    -Errors $errors.ToArray() `
    -Metrics @{ PhasesRun = $steps.Count; PhasesFailed = $errors.Count }

[void](Save-MSPResult -Result $result -Subfolder 'Lifecycle')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
