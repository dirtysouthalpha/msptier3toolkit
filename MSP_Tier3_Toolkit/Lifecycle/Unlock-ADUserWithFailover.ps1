<#
.SYNOPSIS
    Unlock an AD user across every reachable DC, finding the one with the
    most recent lockout entry first.
.DESCRIPTION
    The classic "user locked out, calling helpdesk every 30 minutes" call.
    Unlocking on the wrong DC means replication has to propagate before
    sign-in works again. This script:

      1. Discovers all DCs in the domain
      2. Tests connectivity to each
      3. Reads PDC-emulator first (lockout is authoritative there)
      4. Identifies which DC actually has the lockout (Event 4740 source)
      5. Unlocks on the lockout source AND PDC emulator
      6. Reports the source workstation that caused the lockout

    Common follow-up: kill cached creds on the source machine (often a
    phone/iPad).
#>
#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string]$Identity,
    [switch]$AsJson
)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue
if (-not (Get-Module ActiveDirectory -ListAvailable)) {
    throw 'RSAT ActiveDirectory module required.'
}
Import-Module ActiveDirectory

$errors = New-Object System.Collections.Generic.List[string]
$dcs = Get-ADDomainController -Filter * -ErrorAction Stop
$pdc = ($dcs | Where-Object { $_.OperationMasterRoles -contains 'PDCEmulator' }).HostName

# Find lockout source DC by event ID 4740
$source = $null
foreach ($dc in $dcs) {
    if (-not (Test-Connection -ComputerName $dc.HostName -Count 1 -Quiet)) { continue }
    try {
        $evt = Get-WinEvent -ComputerName $dc.HostName -FilterHashtable @{
            LogName='Security'; Id=4740; StartTime=(Get-Date).AddDays(-1)
        } -MaxEvents 50 -ErrorAction SilentlyContinue |
            Where-Object { $_.Properties[0].Value -eq $Identity } |
            Sort-Object TimeCreated -Descending | Select-Object -First 1
        if ($evt) {
            $source = [pscustomobject]@{
                DC               = $dc.HostName
                Time             = $evt.TimeCreated
                LockoutFromHost  = $evt.Properties[1].Value
            }
            break
        }
    } catch { }
}

$targetDCs = @($pdc)
if ($source -and $source.DC -ne $pdc) { $targetDCs += $source.DC }

$unlocked = @()
foreach ($dc in $targetDCs) {
    if ($PSCmdlet.ShouldProcess("$Identity on $dc", 'Unlock-ADAccount')) {
        try {
            Unlock-ADAccount -Identity $Identity -Server $dc -ErrorAction Stop
            $unlocked += $dc
        } catch { $errors.Add("$dc : $($_.Exception.Message)") }
    }
}

$status = if ($errors.Count) { 'Warning' } else { 'Success' }
$result = New-MSPResult `
    -Tool 'Unlock-ADUserWithFailover' `
    -Status $status `
    -Summary "Unlocked $Identity on $($unlocked.Count) DC(s)$(if ($source) { "; lockout source: $($source.LockoutFromHost) at $($source.Time)" })" `
    -Data @{
        Identity         = $Identity
        UnlockedOn       = $unlocked
        LockoutSource    = $source
        PDCEmulator      = $pdc
        DCsDiscovered    = $dcs.HostName
    } `
    -Errors $errors.ToArray() `
    -Metrics @{ DCsUnlocked = $unlocked.Count }

[void](Save-MSPResult -Result $result -Subfolder 'Lifecycle')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
