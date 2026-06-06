<#
.SYNOPSIS
    Find auto-start Windows services that are not running.
.DESCRIPTION
    Filters out the noisy delayed-trigger services that are *expected* to be
    stopped at any given time (sppsvc, MapsBroker, etc.) so the output is
    actionable. Optionally try to start them with -Repair.
.PARAMETER Repair
    Attempt to start any auto-start service that's stopped. Skips services
    in the safe-stopped list.
.EXAMPLE
    .\WindowsServiceAudit.ps1
.EXAMPLE
    .\WindowsServiceAudit.ps1 -Repair
#>
#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Repair,
    [switch]$AsJson
)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

# Services that are frequently stopped despite being auto -- known false positives
$safeStopped = @(
    'sppsvc','MapsBroker','RemoteRegistry','TrustedInstaller',
    'edgeupdate','gupdate','CDPSvc','WaaSMedicSvc','tiledatamodelsvc',
    'CldFlt','wisvc','GoogleChromeElevationService'
)

$errors  = New-Object System.Collections.Generic.List[string]
$broken  = @()
$started = @()

try {
    $broken = Get-CimInstance Win32_Service -Filter "StartMode='Auto' AND State<>'Running'" |
        Where-Object { $safeStopped -notcontains $_.Name } |
        ForEach-Object {
            [pscustomobject]@{
                Name         = $_.Name
                DisplayName  = $_.DisplayName
                State        = $_.State
                StartMode    = $_.StartMode
                StartName    = $_.StartName
                ExitCode     = $_.ExitCode
                PathName     = $_.PathName
            }
        }

    if ($Repair -and $broken.Count) {
        foreach ($svc in $broken) {
            if ($PSCmdlet.ShouldProcess($svc.Name, 'Start service')) {
                try {
                    Start-Service -Name $svc.Name -ErrorAction Stop
                    $started += $svc.Name
                } catch {
                    $errors.Add("Start $($svc.Name): $($_.Exception.Message)")
                }
            }
        }
    }
}
catch { $errors.Add($_.Exception.Message) }

$status = if ($errors.Count) { 'Failure' } elseif ($broken.Count) { 'Warning' } else { 'Success' }
$summary = if ($broken.Count -eq 0) { 'All auto-start services running.' }
           elseif ($Repair) { "$($broken.Count) broken; restarted $($started.Count)." }
           else { "$($broken.Count) auto-start service(s) stopped." }

$result = New-MSPResult `
    -Tool 'WindowsServiceAudit' `
    -Status $status `
    -Summary $summary `
    -Data @{ Broken = $broken; Restarted = $started; Safelist = $safeStopped } `
    -Errors $errors.ToArray() `
    -Metrics @{ BrokenCount = $broken.Count; RestartedCount = $started.Count }

[void](Save-MSPResult -Result $result -Subfolder 'Diagnostics')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
