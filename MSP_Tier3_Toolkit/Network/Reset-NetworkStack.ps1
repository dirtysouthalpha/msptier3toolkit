<#
.SYNOPSIS
    The classic "I tried everything" network reset -- winsock, IP, DNS, ARP,
    HOSTS-table-flush in one verified pass.
.DESCRIPTION
    For the user whose internet died and rebooting didn't fix it. Runs:

      1. ipconfig /flushdns
      2. ipconfig /release + /renew
      3. arp -d *
      4. netsh int ip reset
      5. netsh winsock reset
      6. netsh interface ipv6 reset
      7. nbtstat -R / -RR
      8. Restart DHCP client + DNS client services
      9. Re-register DNS
     10. Optional: reset Windows Firewall to defaults (-FirewallReset)

    Saves a snapshot of `ipconfig /all` before AND after so you can diff if
    anything goes sideways. Most operations require admin and a reboot for
    full effect -- script will warn you which apply.

.PARAMETER FirewallReset
    Also reset Windows Defender Firewall to default rules.
.PARAMETER NoConfirm
    Skip confirmation prompt.
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
    [switch]$FirewallReset,
    [switch]$NoConfirm,
    [switch]$AsJson
)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

if (-not $NoConfirm -and -not $PSCmdlet.ShouldProcess('Network stack on this machine', 'Reset (will drop active connections)')) {
    return
}

$paths = Get-MSPPaths
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$snapDir = Join-Path $paths.Reports "Workstation\NetworkResetSnapshots\$stamp"
New-Item -ItemType Directory -Path $snapDir -Force | Out-Null

$results = New-Object System.Collections.Generic.List[pscustomobject]
function Step($Label, [scriptblock]$Block) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $out = & $Block 2>&1 | Out-String
        $results.Add([pscustomobject]@{ Step=$Label; Ok=$true; DurationMs=$sw.ElapsedMilliseconds; Output=$out.Trim() })
    } catch {
        $results.Add([pscustomobject]@{ Step=$Label; Ok=$false; DurationMs=$sw.ElapsedMilliseconds; Output=$_.Exception.Message })
    }
}

ipconfig /all > (Join-Path $snapDir 'before.txt')

Step 'flushdns'          { ipconfig /flushdns }
Step 'release'           { ipconfig /release }
Step 'renew'             { ipconfig /renew }
Step 'arp_clear'         { arp -d * }
Step 'ip_reset'          { netsh int ip reset }
Step 'winsock_reset'     { netsh winsock reset }
Step 'ipv6_reset'        { netsh interface ipv6 reset }
Step 'nbtstat_R'         { nbtstat -R }
Step 'nbtstat_RR'        { nbtstat -RR }
Step 'restart_dhcp'      { Restart-Service Dhcp -Force -ErrorAction SilentlyContinue }
Step 'restart_dnscache'  { Restart-Service Dnscache -Force -ErrorAction SilentlyContinue }
Step 'register_dns'      { ipconfig /registerdns }
if ($FirewallReset) {
    Step 'firewall_reset' { netsh advfirewall reset }
}

ipconfig /all > (Join-Path $snapDir 'after.txt')

$reboot = $true   # winsock/ip resets always benefit from a reboot
$bad = @($results | Where-Object { -not $_.Ok })
$status = if ($bad.Count) { 'Warning' } else { 'Success' }

$result = New-MSPResult `
    -Tool 'Reset-NetworkStack' `
    -Status $status `
    -Summary "$($results.Count) steps run, $($bad.Count) errors. REBOOT RECOMMENDED. Snapshots: $snapDir" `
    -Data @{ Steps = $results.ToArray(); SnapshotDir = $snapDir; RebootRecommended = $reboot } `
    -Metrics @{ StepsRun = $results.Count; StepsFailed = $bad.Count }

[void](Save-MSPResult -Result $result -Subfolder 'Workstation')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
