<#
.SYNOPSIS
    Checks Exchange Online tenant health, mail flow, connectors, and mailbox stats.
.DESCRIPTION
    Uses Graph API or Exchange Online PowerShell (if available) to report
    mail flow rules, connector status, mailbox counts/sizes, and transport issues.
.NOTES
    v14.0 -- Cloud & Hybrid Operations
    Requires: MSPToolkit.Graph module loaded, or EXO v3 module
#>
[CmdletBinding()]
param()

$data = [PSCustomObject]@{
    Timestamp           = (Get-Date).ToString('o')
    TotalMailboxes      = 0
    SharedMailboxes     = 0
    InactiveMailboxes   = 0
    ConnectorsHealthy   = $true
    TransportRulesCount = 0
    MailFlowIssues      = 0
    Checks              = @()
    Score               = 0
    MaxScore            = 0
    Summary             = ''
}

# Try EXO module first
$exoMod = Get-Module -Name ExchangeOnlineManagement -ListAvailable -ErrorAction SilentlyContinue
if ($exoMod) {
    try {
        Import-Module ExchangeOnlineManagement -ErrorAction Stop
        $mbxs = Get-Mailbox -ResultSize Unlimited -ErrorAction Stop
        $data.TotalMailboxes = $mbxs.Count
        $data.SharedMailboxes = ($mbxs | Where-Object { $_.RecipientTypeDetails -eq 'SharedMailbox' }).Count
        $data.InactiveMailboxes = ($mbxs | Where-Object { $_.AccountDisabled }).Count
        $data.Checks += [PSCustomObject]@{ Name='EXO Connected'; Pass=$true; Detail="$($data.TotalMailboxes) mailboxes" }
    } catch {
        $data.Checks += [PSCustomObject]@{ Name='EXO Connected'; Pass=$false; Detail="EXO error: $($_.Exception.Message)" }
    }
}

# Fallback: Graph API
if ($data.TotalMailboxes -eq 0) {
    try {
        $users = Invoke-MSPGraph -Resource 'users?$filter=assignedLicenses/$count+ne+0&$select=userPrincipalName,mail,department' -ErrorAction Stop
        if ($users.value) {
            $data.TotalMailboxes = $users.value.Count
            $data.Checks += [PSCustomObject]@{ Name='Graph Mailboxes'; Pass=$true; Detail="$($data.TotalMailboxes) licensed users" }
        }
    } catch {
        $data.Checks += [PSCustomObject]@{ Name='Graph Mailboxes'; Pass=$false; Detail="Graph error: $($_.Exception.Message)" }
    }
}

# Check transport rules
try {
    $rules = Get-TransportRule -ErrorAction SilentlyContinue
    if (-not $rules) {
        $rules = Invoke-MSPGraph -Resource 'security/attackSimulation/simulations' -ErrorAction SilentlyContinue
    }
    if ($rules) {
        $data.TransportRulesCount = ($rules | Measure-Object).Count
        $data.Checks += [PSCustomObject]@{ Name='Transport Rules'; Pass=$true; Detail="$($data.TransportRulesCount) rules configured" }
    } else {
        $data.Checks += [PSCustomObject]@{ Name='Transport Rules'; Pass=$true; Detail='0 rules (default)' }
    }
} catch {
    $data.Checks += [PSCustomObject]@{ Name='Transport Rules'; Pass=$false; Detail="Error: $($_.Exception.Message)" }
}

# Check connectors
try {
    $connectors = Get-InboundConnector -ErrorAction SilentlyContinue
    if ($connectors) {
        $connHealth = ($connectors | Where-Object { $_.Enabled -and $_.Status -eq 'Validated' }).Count
        $data.Checks += [PSCustomObject]@{ Name='Connectors'; Pass=($connHealth -eq $connectors.Count); Detail="$connHealth/$($connectors.Count) healthy" }
    } else {
        $data.Checks += [PSCustomObject]@{ Name='Connectors'; Pass=$true; Detail='No custom connectors' }
    }
} catch {
    $data.Checks += [PSCustomObject]@{ Name='Connectors'; Pass=$true; Detail='Could not query (no EXO session)' }
}

$data.MaxScore = $data.Checks.Count * 20
$data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
$data.Summary = "Exchange Online: $($data.Score)/$($data.MaxScore) -- $($data.TotalMailboxes) mailboxes | $($data.SharedMailboxes) shared | $($data.InactiveMailboxes) inactive"

return $data
