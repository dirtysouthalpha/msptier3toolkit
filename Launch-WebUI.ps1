<#
.SYNOPSIS
    MSP Toolkit - Cyberpunk HUD Web UI v3.0
.DESCRIPTION
    Full-featured web interface with real tool execution and output decoding.
    Single-file launcher -- no dependencies. Runs from USB.
.NOTES
    Version: 3.0.0
#>

[CmdletBinding()]
param(
    [int]$Port = 8080,
    [switch]$OpenBrowser
)

function Show-Banner {
    Write-Host ""
    Write-Host "  +======================================================+" -ForegroundColor Cyan
    Write-Host "  |  MSP TOOLKIT // CYBERPUNK HUD v3.0                    |" -ForegroundColor Cyan
    Write-Host "  +======================================================+" -ForegroundColor Cyan
    Write-Host ""
}

Show-Banner
Write-Host "  [+] Initializing web server on port $Port..." -ForegroundColor Green

$toolkitRoot = $PSScriptRoot
$Script:Jobs = @{}
$Script:JobLock = [System.Object]::new()

$Script:ToolCatalog = @(
    @{id='triage';    name='Quick Triage Report';     cat='Workstation';  adm=$false; path='MSP_Tier3_Toolkit\Workstation\Get-QuickTriageReport.ps1';   desc='1-page HTML triage report for clients.'},
    @{id='outlook';   name='Reset Outlook Cache';      cat='Workstation';  adm=$false; path='MSP_Tier3_Toolkit\Workstation\Reset-OutlookCache.ps1';      desc='Clear OST, AutoComplete, cached credentials.'},
    @{id='search';    name='Repair Windows Search';    cat='Workstation';  adm=$true;  path='MSP_Tier3_Toolkit\Workstation\Repair-WindowsSearch.ps1';    desc='Rebuild Windows Search index.'},
    @{id='health';    name='System Health Report';     cat='Diagnostics';  adm=$false; path='MSP_Tier3_Toolkit\SystemHealthReport.ps1';                  desc='Full system health snapshot.'},
    @{id='boot';      name='Boot Time Analyzer';       cat='Diagnostics';  adm=$false; path='MSP_Tier3_Toolkit\BootTimeAnalyzer.ps1';                    desc='Boot/shutdown times from Event Logs.'},
    @{id='summary';   name='Client System Summary';    cat='Diagnostics';  adm=$false; path='MSP_Tier3_Toolkit\ClientSystemSummary.ps1';                 desc='HTML system summary for clients.'},
    @{id='reboot';    name='Reboot Pending Check';     cat='Diagnostics';  adm=$false; path='MSP_Tier3_Toolkit\Diagnostics\RebootPendingCheck.ps1';      desc='Multi-signal reboot detection.'},
    @{id='events';    name='Event Log Alert Summary';  cat='Diagnostics';  adm=$false; path='MSP_Tier3_Toolkit\Diagnostics\EventLogAlertSummary.ps1';    desc='Last 24h errors/warnings.'},
    @{id='perf';      name='Performance Baseline';     cat='Diagnostics';  adm=$false; path='MSP_Tier3_Toolkit\Diagnostics\Get-PerformanceBaseline.ps1'; desc='CPU/mem/disk/network sample.'},
    @{id='svc';       name='Windows Service Audit';    cat='Diagnostics';  adm=$true;  path='MSP_Tier3_Toolkit\Diagnostics\WindowsServiceAudit.ps1';     desc='Auto-start services that are stopped.'},
    @{id='logons';    name='User Logon Report';        cat='Diagnostics';  adm=$false; path='MSP_Tier3_Toolkit\Diagnostics\Get-UserLogonReport.ps1';     desc='Recent logons, RDP, failures.'},
    @{id='aduser';    name='Check AD User Status';     cat='ActiveDirectory'; adm=$false; path='MSP_Tier3_Toolkit\CheckADUserStatus.ps1';               desc='User lockout and password status.'},
    @{id='m365';      name='M365 User Provisioning';   cat='Microsoft365'; adm=$false; path='MSP_Tier3_Toolkit\M365UserProvisioning.ps1';                desc='Provision O365 licenses.'},
    @{id='profiles';  name='Cleanup Old Profiles';     cat='Maintenance';  adm=$true;  path='MSP_Tier3_Toolkit\CleanupOldProfiles.ps1';                  desc='Remove profiles older than 30 days.'},
    @{id='clean';     name='Comprehensive Cleanup';    cat='Maintenance';  adm=$true;  path='Cleanup Script\Cleanup-Auto.ps1';                          desc='Full system cleanup with logging.'},
    @{id='printfix';  name='Printer Spooler Fix';      cat='Print';        adm=$true;  path='MSP_Tier3_Toolkit\PrinterSpoolerFix.ps1';                   desc='Clear stuck jobs, restart spooler.'},
    @{id='spoolmon';  name='Spooler Monitor Setup';    cat='Print';        adm=$true;  path='Auto-Check and Start Printer Spooler\CheckAndStart-Spooler.ps1'; desc='Deploy spooler monitoring.'},
    @{id='drives';    name='Fix Mapped Drives';        cat='Network';      adm=$false; path='MSP_Tier3_Toolkit\FixMappedDrives.ps1';                     desc='Test and repair network drive mappings.'},
    @{id='uninstall'; name='Remote Software Uninstall'; cat='Software';    adm=$true;  path='MSP_Tier3_Toolkit\RemoteUninstall.ps1';                    desc='Silently uninstall software.'},
    @{id='wufix';     name='Windows Update Fix';       cat='WindowsUpdate';adm=$true;  path='MSP_Tier3_Toolkit\WindowsUpdateFix.ps1';                    desc='Reset Windows Update components.'},
    @{id='bitlocker'; name='BitLocker Status';         cat='Security';     adm=$false; path='MSP_Tier3_Toolkit\Security\BitLockerStatusCheck.ps1';       desc='Per-volume protection state.'},
    @{id='av';        name='AV Status';                cat='Security';     adm=$false; path='MSP_Tier3_Toolkit\Security\AVStatusCheck.ps1';              desc='SecurityCenter + Defender state.'},
    @{id='admins';    name='Local Admin Audit';        cat='Security';     adm=$false; path='MSP_Tier3_Toolkit\Security\LocalAdminAudit.ps1';            desc='Who has local Administrator?'},
    @{id='patches';   name='Patch Compliance';         cat='Security';     adm=$false; path='MSP_Tier3_Toolkit\Security\Get-PatchCompliance.ps1';        desc='Pending updates + install history.'},
    @{id='posture';   name='Security Posture Score';   cat='Security';     adm=$true;  path='MSP_Tier3_Toolkit\Security\Get-SecurityPostureScore.ps1';   desc='12-check 0-100 hardening score.'},
    @{id='cis';       name='CIS Benchmark Score';      cat='Security';     adm=$true;  path='MSP_Tier3_Toolkit\Security\Get-CISBenchmarkScore.ps1';     desc='30-control CIS subset scorecard.'},
    @{id='firewall';  name='Firewall Risk Audit';      cat='Security';     adm=$true;  path='MSP_Tier3_Toolkit\Security\Get-FirewallRiskAudit.ps1';     desc='Risk-scored inbound rules.'},
    @{id='certs';     name='Certificate Inventory';    cat='Security';     adm=$true;  path='MSP_Tier3_Toolkit\Security\Get-CertificateInventory.ps1';  desc='Expiry timeline, weak algorithms.'},
    @{id='laps';      name='LAPS Password';            cat='Security';     adm=$true;  path='MSP_Tier3_Toolkit\Security\Get-LAPSPassword.ps1';          desc='Retrieve LAPS managed password.'},
    @{id='lapsdep';   name='LAPS Deployment Test';     cat='Security';     adm=$true;  path='MSP_Tier3_Toolkit\Security\Test-LAPSDeployment.ps1';       desc='LAPS presence, password age.'},
    @{id='cg';        name='Credential Guard';         cat='Security';     adm=$true;  path='MSP_Tier3_Toolkit\Security\Get-CredentialGuardState.ps1';   desc='VBS, HVCI, LSASS protection.'},
    @{id='tpm';       name='Secure Boot & TPM';        cat='Security';     adm=$true;  path='MSP_Tier3_Toolkit\Security\Get-SecureBootTPMState.ps1';     desc='Secure Boot, TPM, PCR banks.'},
    @{id='exploit';   name='Exploit Guard Config';     cat='Security';     adm=$true;  path='MSP_Tier3_Toolkit\Security\Get-ExploitGuardConfig.ps1';     desc='ASR rules, network protection.'},
    @{id='unlock';    name='Unlock AD Account';        cat='Security';     adm=$true;  path='MSP_Tier3_Toolkit\Security\Unlock-ADAccountAdvanced.ps1';   desc='Advanced AD account unlock.'},
    @{id='resetpw';   name='Reset Local Admin';        cat='Security';     adm=$true;  path='MSP_Tier3_Toolkit\Security\Reset-LocalAdminPassword.ps1';   desc='Reset local admin password.'},
    @{id='canary';    name='Ransomware Canary';        cat='Security';     adm=$true;  path='MSP_Tier3_Toolkit\Security\Test-RansomwareCanary.ps1';     desc='Test ransomware canary files.'},
    @{id='netpath';   name='Test Network Path';        cat='Network';      adm=$false; path='MSP_Tier3_Toolkit\Network\Test-NetworkPath.ps1';            desc='Ping/TCP/DNS/HTTP probe.'},
    @{id='wifi';      name='WiFi Survey';              cat='Network';      adm=$false; path='MSP_Tier3_Toolkit\Network\Get-WiFiSurvey.ps1';             desc='BSSIDs, channel overlap.'},
    @{id='dnsdeep';   name='DNS Deep Dive';            cat='Network';      adm=$false; path='MSP_Tier3_Toolkit\Network\Test-DNSDeepDive.ps1';           desc='Per-server timing, split-brain.'},
    @{id='m365ep';    name='M365 Endpoint Test';       cat='Network';      adm=$false; path='MSP_Tier3_Toolkit\Network\Test-M365Endpoints.ps1';          desc='Reachability vs M365 catalog.'},
    @{id='vpn';       name='VPN Health';               cat='Network';      adm=$false; path='MSP_Tier3_Toolkit\Network\Test-VPNHealth.ps1';              desc='Tunnel state, DNS leak test.'},
    @{id='netreset';  name='Reset Network Stack';      cat='Network';      adm=$true;  path='MSP_Tier3_Toolkit\Network\Reset-NetworkStack.ps1';          desc='winsock + ip + DNS + ARP flush.'},
    @{id='snmp';      name='SNMP Walk';                cat='Network';      adm=$true;  path='MSP_Tier3_Toolkit\Network\Test-SNMPWalk.ps1';              desc='Device discovery, OID polling.'},
    @{id='vss';       name='VSS Writer Health';        cat='Backup';       adm=$true;  path='MSP_Tier3_Toolkit\Backup\Get-VSSWriterHealth.ps1';         desc='All VSS writers, auto-retry.'},
    @{id='backup';    name='Backup Status';            cat='Backup';       adm=$true;  path='MSP_Tier3_Toolkit\Backup\Get-BackupStatus.ps1';            desc='WSB job history, event log fallback.'},
    @{id='shadow';    name='Shadow Copy Report';       cat='Backup';       adm=$true;  path='MSP_Tier3_Toolkit\Backup\Get-ShadowCopyReport.ps1';        desc='Per-volume shadow copies.'},
    @{id='restore';   name='Restore Readiness';        cat='Backup';       adm=$true;  path='MSP_Tier3_Toolkit\Backup\Test-RestoreReadiness.ps1';       desc='WinRE, catalog, driver check.'},
    @{id='adrepl';    name='AD Replication Health';    cat='DomainController'; adm=$true; path='MSP_Tier3_Toolkit\DC\Get-ADReplicationHealth.ps1';       desc='Replication summary, USN drift.'},
    @{id='dnszone';   name='DNS Zone Health';          cat='DomainController'; adm=$true; path='MSP_Tier3_Toolkit\DC\Get-DNSZoneHealth.ps1';             desc='SOA serial, forwarders, scavenging.'},
    @{id='dhcp';      name='DHCP Scope Report';        cat='DomainController'; adm=$true; path='MSP_Tier3_Toolkit\DC\Get-DHCPScopeReport.ps1';           desc='Scope utilization, BAD_ADDRESS.'},
    @{id='fsmo';      name='FSMO Role Audit';          cat='DomainController'; adm=$true; path='MSP_Tier3_Toolkit\DC\Get-FSMORoleAudit.ps1';             desc='All 5 FSMO holders.'},
    @{id='gpo';       name='GPO Link Report';          cat='DomainController'; adm=$true; path='MSP_Tier3_Toolkit\DC\Get-GPOLinkReport.ps1';             desc='GPOs, links, WMI filters.'},
    @{id='dcdiag';    name='DCDiag Orchestrator';      cat='DomainController'; adm=$true; path='MSP_Tier3_Toolkit\DC\Invoke-DCDiagOrchestrator.ps1';      desc='Targeted DCDiag per-test.'},
    @{id='kerberos';  name='Kerberos Health';          cat='DomainController'; adm=$true; path='MSP_Tier3_Toolkit\DC\Get-KerberosHealth.ps1';            desc='KRBTGT, dup SPNs, delegation.'},
    @{id='trust';     name='Trust Health';             cat='DomainController'; adm=$true; path='MSP_Tier3_Toolkit\DC\Test-TrustHealth.ps1';              desc='Trust secure channel, SID filtering.'},
    @{id='adusers';   name='AD User Bulk Report';      cat='DomainController'; adm=$true; path='MSP_Tier3_Toolkit\DC\Get-ADUserBulkReport.ps1';          desc='Stale, expiring, locked, disabled.'},
    @{id='sysvol';    name='SYSVOL Health';            cat='DomainController'; adm=$true; path='MSP_Tier3_Toolkit\DC\Get-SYSVOLHealth.ps1';              desc='DFSR state, policy counts.'},
    @{id='entra';     name='Entra Connect Health';     cat='Cloud';        adm=$true;  path='MSP_Tier3_Toolkit\Cloud\Get-EntraConnectHealth.ps1';        desc='Sync cycles, connectors, errors.'},
    @{id='intune';    name='Intune Compliance';        cat='Cloud';        adm=$true;  path='MSP_Tier3_Toolkit\Cloud\Get-IntuneCompliance.ps1';          desc='Device compliance report.'},
    @{id='ca';        name='Conditional Access';       cat='Cloud';        adm=$true;  path='MSP_Tier3_Toolkit\Cloud\Get-ConditionalAccessReport.ps1';  desc='CA policies, MFA gaps.'},
    @{id='azurevm';   name='Azure VM Inventory';       cat='Cloud';        adm=$true;  path='MSP_Tier3_Toolkit\Cloud\Get-AzureVMInventory.ps1';          desc='VMs, sizes, cost estimates.'},
    @{id='exo';       name='Exchange Online Health';   cat='Cloud';        adm=$true;  path='MSP_Tier3_Toolkit\Cloud\Get-ExchangeOnlineHealth.ps1';     desc='Mailboxes, connectors, transport.'},
    @{id='teams';     name='Teams Call Quality';       cat='Cloud';        adm=$false; path='MSP_Tier3_Toolkit\Cloud\Get-TeamsCallQuality.ps1';          desc='Network readiness, latency, CQD.'},
    @{id='sql';       name='SQL Server Health';        cat='Apps';         adm=$true;  path='MSP_Tier3_Toolkit\Apps\Get-SQLServerHealth.ps1';            desc='Databases, backups, wait stats.'},
    @{id='iis';       name='IIS App Pool Status';      cat='Apps';         adm=$true;  path='MSP_Tier3_Toolkit\Apps\Get-IISAppPoolStatus.ps1';          desc='Pools, workers, recycles.'},
    @{id='exsvr';     name='Exchange Server Health';   cat='Apps';         adm=$true;  path='MSP_Tier3_Toolkit\Apps\Get-ExchangeServerHealth.ps1';      desc='Queues, DAG, DBs, certs.'},
    @{id='print';     name='Print Server Report';      cat='Apps';         adm=$true;  path='MSP_Tier3_Toolkit\Apps\Get-PrintServerReport.ps1';         desc='Printers, queues, drivers.'},
    @{id='svcdep';    name='Service Dependency Map';   cat='Apps';         adm=$true;  path='MSP_Tier3_Toolkit\Apps\Get-ServiceDependencyMap.ps1';      desc='Dependency chains, dead deps.'},
    @{id='appperf';   name='App Performance Baseline'; cat='Apps';         adm=$false; path='MSP_Tier3_Toolkit\Apps\Get-AppPerformanceBaseline.ps1';     desc='CPU, memory, handle baselines.'},
    @{id='onedrive';  name='OneDrive Sync Health';     cat='M365';         adm=$false; path='MSP_Tier3_Toolkit\M365\OneDriveSyncHealthCheck.ps1';        desc='KFM + last error per account.'}
)

function Invoke-ToolScript {
    param([string]$ToolId)
    $tool = $Script:ToolCatalog | Where-Object { $_.id -eq $ToolId }
    if (-not $tool) { return @{ status='Error'; error="Unknown tool: $ToolId" } }
    $scriptPath = Join-Path $toolkitRoot $tool.path
    if (-not (Test-Path $scriptPath)) { return @{ status='Error'; error="Script not found: $($tool.path)" } }
    try {
        $output = & $scriptPath 2>&1
        $text = ($output | Out-String)
        $structured = $null
        $hasObjects = $false
        if ($output -and $output -isnot [string] -and $output -isnot [System.Management.Automation.ErrorRecord]) {
            try {
                $structured = $output | Select-Object -First 50 | ForEach-Object {
                    if ($_ -is [string]) { $_ }
                    elseif ($_ -is [System.Collections.IDictionary]) {
                        $h = @{}; foreach ($k in $_.Keys) { $h[$k] = "$($_[$k])" }; $h
                    }
                    else {
                        $h = @{}; $_.PSObject.Properties | ForEach-Object { $h[$_.Name] = "$($_.Value)" }; $h
                    }
                }
                if ($structured -and ($structured | Where-Object { $_ -isnot [string] })) { $hasObjects = $true }
            } catch { }
        }
        $result = @{
            status = 'Completed'
            tool = $tool.name
            toolId = $tool.id
            category = $tool.cat
            timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            rawOutput = $text
            hasStructuredData = $hasObjects
        }
        if ($hasObjects) {
            $result.data = @($structured | Where-Object { $_ -isnot [string] })
            $props = @()
            $first = $structured | Where-Object { $_ -isnot [string] } | Select-Object -First 1
            if ($first) { $props = @($first.Keys) }
            $result.columns = $props
        }
        return $result
    } catch {
        return @{ status='Error'; error=$_.Exception.Message; tool=$tool.name; toolId=$tool.id; timestamp=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
    }
}

$listener = New-Object System.Net.HttpListener
$prefix = "http://localhost:$Port/"
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
    Write-Host "  [+] Server running at http://localhost:$Port" -ForegroundColor Green
    if ($OpenBrowser) {
        if ($env:OS -match "Windows") { Start-Process "http://localhost:$Port" }
    } else {
        Write-Host "  [i] Navigate to: http://localhost:$Port" -ForegroundColor Cyan
    }
    Write-Host ""

    $htmlContent = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>MSP TOOLKIT // CYBERPUNK HUD</title>
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@300;400;500;600;700&display=swap" rel="stylesheet">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
<style>
:root{--cyan:#00F0FF;--cyan-dim:rgba(0,240,255,0.3);--lime:#95E400;--amber:#FBBC00;--bg0:#050608;--bg1:#0A0C10;--bg2:#111418;--bg3:#1a1d23;--text:#e2e2e8;--text2:#b9cacb;--text3:#849495;--brd:#3b494b;--err:#ff3b3b;--ok:#95E400;--warn:#FBBC00;--a3:rgba(0,240,255,0.03);--a5:rgba(0,240,255,0.05);--a8:rgba(0,240,255,0.08);--a10:rgba(0,240,255,0.1);--a15:rgba(0,240,255,0.15);--a20:rgba(0,240,255,0.2);--a30:rgba(0,240,255,0.3);--a40:rgba(0,240,255,0.4);--fh:'Space Grotesk',sans-serif;--fb:'Inter',sans-serif;--fm:'Consolas','Monaco',monospace;--ch:polygon(0 0,calc(100% - 6px) 0,100% 6px,100% 100%,6px 100%,0 calc(100% - 6px))}
*{margin:0;padding:0;box-sizing:border-box}
.scanline{position:fixed;top:0;left:0;width:100%;height:100%;pointer-events:none;z-index:9999;background:repeating-linear-gradient(0deg,transparent,transparent 2px,rgba(0,0,0,0.04) 2px,rgba(0,0,0,0.04) 4px)}
.scanline::after{content:'';position:fixed;top:0;left:0;width:100%;height:50px;background:linear-gradient(180deg,transparent,rgba(0,240,255,0.04),rgba(0,240,255,0.06),rgba(0,240,255,0.04),transparent);animation:sweep 8s linear infinite;pointer-events:none;z-index:9999}
@keyframes sweep{0%{top:-50px}100%{top:100vh}}
.edge{position:fixed;top:0;left:0;width:3px;height:100%;background:linear-gradient(180deg,var(--cyan),var(--cyan-dim),var(--cyan));z-index:9998;pointer-events:none;animation:ep 3s ease-in-out infinite}
@keyframes ep{0%,100%{opacity:.6}50%{opacity:1}}
body{font-family:var(--fb);background:var(--bg0);color:var(--text);min-height:100vh;position:relative;z-index:1}
body::before{content:'';position:fixed;top:0;left:0;width:100%;height:100%;pointer-events:none;z-index:0;background-image:linear-gradient(var(--a3) 1px,transparent 1px),linear-gradient(90deg,var(--a3) 1px,transparent 1px);background-size:20px 20px}
.hdr{display:flex;align-items:center;justify-content:space-between;padding:8px 16px;border-bottom:1px solid var(--brd);border-top:2px solid var(--cyan);background:var(--bg1);box-shadow:0 0 12px var(--a10);z-index:10;position:relative}
.brand{font-family:var(--fh);font-size:16px;font-weight:700;color:var(--cyan);letter-spacing:2px;text-transform:uppercase;text-shadow:0 0 10px var(--a40)}
.brand .u{color:var(--lime);animation:bk 1s step-end infinite}
@keyframes bk{0%,50%{opacity:1}51%,100%{opacity:0}}
.hdr-r{display:flex;align-items:center;gap:8px;font-family:var(--fm);font-size:10px;color:var(--text2)}
.sdot{width:7px;height:7px;background:var(--ok);box-shadow:0 0 6px rgba(149,228,0,.6);animation:dp 2s ease-in-out infinite}
@keyframes dp{0%,100%{box-shadow:0 0 4px rgba(149,228,0,.4)}50%{box-shadow:0 0 10px rgba(149,228,0,.8)}}
.nav{display:flex;border-bottom:1px solid var(--brd);background:var(--bg1);z-index:10;position:relative;overflow-x:auto}
.nbtn{background:transparent;border:none;color:var(--text3);font-family:var(--fh);font-size:10px;font-weight:600;letter-spacing:1px;text-transform:uppercase;padding:8px 16px;cursor:pointer;border-bottom:2px solid transparent;white-space:nowrap;transition:all .2s}
.nbtn:hover{color:var(--cyan);background:var(--a5)}
.nbtn.on{color:var(--cyan);border-bottom-color:var(--cyan);text-shadow:0 0 4px var(--a30)}
.main{max-width:1500px;margin:0 auto;padding:16px;position:relative;z-index:1}
.pane{display:none}.pane.on{display:block}
.sbar{display:flex;align-items:center;gap:12px;padding:8px 0;margin-bottom:12px}
.search{flex:1;background:var(--bg1);border:1px solid var(--brd);color:var(--text);padding:8px 14px;font-family:var(--fm);font-size:12px;outline:none;transition:border-color .2s}
.search:focus{border-color:var(--cyan);box-shadow:0 0 6px var(--a10)}
.sbar .count{font-family:var(--fm);font-size:10px;color:var(--text3)}
.stitle{font-family:var(--fh);font-size:10px;font-weight:700;letter-spacing:2px;text-transform:uppercase;color:var(--cyan);margin:20px 0 8px;padding-bottom:6px;border-bottom:1px solid var(--brd)}
.stitle:first-child{margin-top:0}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:8px}
.card{background:var(--bg1);border:1px solid var(--brd);padding:12px;cursor:pointer;transition:all .2s;position:relative;overflow:hidden}
.card::before{content:'';position:absolute;top:0;left:0;width:3px;height:100%;background:var(--cyan);opacity:0;transition:opacity .2s}
.card:hover{border-color:var(--cyan);box-shadow:0 0 10px var(--a8),inset 0 0 16px var(--a3);transform:translateY(-1px)}
.card:hover::before{opacity:1}
.card.running{border-color:var(--amber);box-shadow:0 0 10px rgba(251,188,0,.15)}
.card.done{border-color:var(--ok)}
.card.err{border-color:var(--err)}
.cc{font-family:var(--fm);font-size:8px;font-weight:700;letter-spacing:1.2px;text-transform:uppercase;color:var(--text3);margin-bottom:4px}
.cn{font-family:var(--fh);font-size:13px;font-weight:600;color:var(--text);margin-bottom:4px}
.cd{font-size:11px;color:var(--text2);line-height:1.4;margin-bottom:8px}
.cbadges{display:flex;gap:4px}
.badge{font-family:var(--fm);font-size:8px;font-weight:700;padding:1px 6px;border:1px solid}
.badm{color:var(--err);border-color:var(--err);background:rgba(255,59,59,.06)}
.bsafe{color:var(--cyan);border-color:var(--cyan);background:var(--a5)}
.bcat{color:var(--text3);border-color:var(--brd);background:var(--bg2)}
.out{display:none;background:var(--bg1);border:1px solid var(--cyan);box-shadow:0 0 16px var(--a10);margin-top:16px;position:relative}
.out.on{display:block}
.outhdr{display:flex;align-items:center;justify-content:space-between;padding:8px 14px;background:var(--bg2);border-bottom:1px solid var(--brd)}
.outhdr-t{font-family:var(--fh);font-size:10px;font-weight:700;letter-spacing:1px;text-transform:uppercase;color:var(--cyan);text-shadow:0 0 4px var(--a30)}
.outhdr .dots{display:inline-flex;gap:3px;margin-left:8px}
.outhdr .dots span{width:4px;height:4px;background:var(--cyan);animation:dotp 1.5s ease-in-out infinite}
.outhdr .dots span:nth-child(2){animation-delay:.2s}
.outhdr .dots span:nth-child(3){animation-delay:.4s}
@keyframes dotp{0%,60%,100%{opacity:.2}30%{opacity:1;box-shadow:0 0 4px var(--cyan)}}
.ocl{background:transparent;border:1px solid var(--brd);color:var(--text3);font-size:13px;cursor:pointer;padding:2px 8px;transition:all .2s}
.ocl:hover{background:var(--err);color:var(--bg0);border-color:var(--err)}
.obody{padding:14px;max-height:500px;overflow-y:auto;font-family:var(--fm);font-size:11px;line-height:1.6;color:var(--text2)}
.obody::-webkit-scrollbar{width:5px}
.obody::-webkit-scrollbar-track{background:var(--bg0)}
.obody::-webkit-scrollbar-thumb{background:var(--brd)}
.tline{padding:2px 0;animation:tf .2s ease-out}
@keyframes tf{from{opacity:0;transform:translateX(-3px)}to{opacity:1;transform:translateX(0)}}
.tp{color:var(--cyan)}.tok{color:var(--ok)}.te{color:var(--err)}.tw{color:var(--warn)}.ti{color:var(--text3)}
table.dtable{width:100%;border-collapse:collapse;margin:8px 0;font-size:11px}
table.dtable th{background:var(--bg2);color:var(--cyan);font-family:var(--fh);font-size:9px;font-weight:700;letter-spacing:1px;text-transform:uppercase;padding:6px 8px;text-align:left;border-bottom:1px solid var(--brd)}
table.dtable td{padding:5px 8px;border-bottom:1px solid rgba(59,73,75,.3);color:var(--text2);vertical-align:top}
table.dtable tr:hover td{background:var(--a3)}
.rbox{background:var(--bg2);border:1px solid var(--brd);padding:12px;margin:8px 0;white-space:pre-wrap;word-break:break-word;max-height:200px;overflow-y:auto;font-family:var(--fm);font-size:11px;line-height:1.5;color:var(--text2)}
.rawbtn{background:var(--bg2);color:var(--text3);border:1px solid var(--brd);padding:4px 10px;font-family:var(--fh);font-size:9px;font-weight:600;letter-spacing:.5px;text-transform:uppercase;cursor:pointer;margin-top:6px;transition:all .2s}
.rawbtn:hover{border-color:var(--cyan);color:var(--cyan)}
.abtn{background:var(--cyan);color:var(--bg0);border:none;padding:6px 14px;font-family:var(--fh);font-size:10px;font-weight:700;letter-spacing:1px;text-transform:uppercase;cursor:pointer;clip-path:var(--ch);transition:all .2s}
.abtn:hover{box-shadow:0 0 8px var(--a30);transform:translateY(-1px)}
.abtn:active{transform:scale(.97)}
.abtn.sec{background:var(--bg2);color:var(--text);border:1px solid var(--brd);clip-path:none}
.abtn.sec:hover{border-color:var(--cyan);color:var(--cyan)}
.abtn:disabled{opacity:.4;cursor:default;transform:none}
.sgrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:8px;margin-top:8px}
.scard{background:var(--bg1);border:1px solid var(--brd);padding:14px}
.scard:hover{border-color:var(--cyan)}
.sl{font-family:var(--fm);font-size:8px;font-weight:700;letter-spacing:1.2px;text-transform:uppercase;color:var(--text3);margin-bottom:4px}
.sv{font-family:var(--fh);font-size:22px;font-weight:700;color:var(--cyan);text-shadow:0 0 6px var(--a30)}
.foot{text-align:center;padding:20px;border-top:1px solid var(--brd);margin-top:30px;z-index:1;position:relative}
.foot p{font-family:var(--fm);font-size:10px;color:var(--text3);letter-spacing:.5px}
.foot a{color:var(--cyan);text-decoration:none}
.qrow{display:flex;gap:6px;flex-wrap:wrap;margin-top:8px}
.ibox{background:var(--bg1);border:1px solid var(--brd);padding:14px;margin:12px 0;border-left:3px solid var(--cyan)}
.ibox h3{font-family:var(--fh);font-size:11px;font-weight:700;letter-spacing:1px;text-transform:uppercase;color:var(--cyan);margin-bottom:8px}
.ibox p,.ibox li{font-size:12px;line-height:1.6;color:var(--text2)}
.ibox code{background:var(--bg0);color:var(--cyan);padding:1px 5px;font-family:var(--fm);font-size:11px;border:1px solid var(--brd)}
</style>
</head>
<body>
<div class="scanline"></div>
<div class="edge"></div>

<div class="hdr">
  <div class="brand">MSP<span class="u">_</span>TOOLKIT <span style="color:var(--text3);font-size:10px;font-weight:400">v3.0</span></div>
  <div class="hdr-r"><div class="sdot"></div><span>ONLINE</span><span style="color:var(--text3)">|</span><span id="clk"></span></div>
</div>

<div class="nav">
  <button class="nbtn on" data-p="tools">TOOLS</button>
  <button class="nbtn" data-p="results">RESULTS</button>
  <button class="nbtn" data-p="dashboard">DASHBOARD</button>
  <button class="nbtn" data-p="guide">GUIDE</button>
</div>

<div class="main">
<!-- TOOLS -->
<div class="pane on" id="p-tools">
<div class="sbar">
  <input type="text" class="search" id="searchBox" placeholder="Search tools... (type to filter)">
  <span class="count" id="toolCount"></span>
</div>
<div id="toolGrid"></div>
<div class="out" id="runOut">
  <div class="outhdr">
    <div style="display:flex;align-items:center"><span class="outhdr-t" id="runTitle">OUTPUT //</span><span class="dots" id="runDots"><span></span><span></span><span></span></span></div>
    <div style="display:flex;gap:6px"><button class="rawbtn" id="toggleRaw" onclick="toggleRawView()">RAW</button><button class="ocl" onclick="document.getElementById('runOut').classList.remove('on')">&times;</button></div>
  </div>
  <div class="obody" id="runBody"></div>
</div>
</div>

<!-- RESULTS -->
<div class="pane" id="p-results">
<div class="stitle" style="margin-top:0">Execution History</div>
<div id="historyList"></div>
<div class="out" id="histOut">
  <div class="outhdr">
    <div style="display:flex;align-items:center"><span class="outhdr-t" id="histTitle">RESULT</span></div>
    <button class="ocl" onclick="document.getElementById('histOut').classList.remove('on')">&times;</button>
  </div>
  <div class="obody" id="histBody"></div>
</div>
</div>

<!-- DASHBOARD -->
<div class="pane" id="p-dashboard">
<div class="stitle" style="margin-top:0">System Status</div>
<div class="sgrid" id="statsGrid">
  <div class="scard"><div class="sl">COMPUTER</div><div class="sv" id="sComp">--</div></div>
  <div class="scard"><div class="sl">TOOLS</div><div class="sv" id="sTools">--</div></div>
  <div class="scard"><div class="sl">STATUS</div><div class="sv" style="color:var(--ok)">ONLINE</div></div>
  <div class="scard"><div class="sl">EXECUTIONS</div><div class="sv" id="sRuns">0</div></div>
</div>
<div class="stitle">Quick Actions</div>
<div class="qrow">
  <button class="abtn" onclick="apiGet('/api/health')">HEALTH CHECK</button>
  <button class="abtn sec" onclick="apiGet('/api/scripts')">SCRIPT CATALOG</button>
</div>
<div class="out" id="dashOut" style="margin-top:12px">
  <div class="outhdr"><div class="outhdr-t">API RESPONSE</div><button class="ocl" onclick="document.getElementById('dashOut').classList.remove('on')">&times;</button></div>
  <div class="obody" id="dashBody"></div>
</div>
</div>

<!-- GUIDE -->
<div class="pane" id="p-guide">
<div class="stitle" style="margin-top:0">Quick Start</div>
<div class="ibox">
  <h3>From This Web UI</h3>
  <p><strong>1.</strong> Click any tool card to execute it.</p>
  <p><strong>2.</strong> Output is decoded automatically -- tables, status, errors.</p>
  <p><strong>3.</strong> Check RESULTS tab for execution history.</p>
  <p><strong>4.</strong> Use the search bar to filter tools.</p>
</div>
<div class="ibox">
  <h3>One-Click Launch</h3>
  <p>Double-click <code>MSP_START.bat</code> -- auto-starts the Web UI and opens the browser. No setup required. Works from USB.</p>
</div>
<div class="ibox">
  <h3>From PowerShell</h3>
  <p><code>.\Launch-MSPToolkit.ps1</code> for the full menu, or <code>.\WORKING_LAUNCHER_USE_THIS.ps1</code> for standalone mode.</p>
</div>
<div class="ibox">
  <h3>Badge Legend</h3>
  <p><span class="badge badm">ADMIN</span> Requires admin rights &nbsp; <span class="badge bsafe">SAFE</span> Read-only</p>
</div>
<div class="ibox">
  <h3>USB Deployment</h3>
  <p>Copy entire folder to USB. Run <code>MSP_START.bat</code> from any Windows machine. Fully portable -- no installation.</p>
</div>
</div>
</div>

<div class="foot"><p>MSP TIER 3 TOOLKIT v3.0 // CYBERPUNK HUD // <a href="https://github.com/dirtysouthalpha/msptier3toolkit" target="_blank">GITHUB</a></p></div>

<script>
(function(){
var catalog=[], history=[], runCount=0, currentRaw='';
var CLK=document.getElementById('clk');
setInterval(function(){var d=new Date();CLK.textContent=d.toLocaleTimeString('en-US',{hour12:false})+'.'+String(d.getMilliseconds()).padStart(3,'0')},100);

document.querySelectorAll('.nbtn').forEach(function(b){b.addEventListener('click',function(){document.querySelectorAll('.nbtn').forEach(function(x){x.classList.remove('on')});document.querySelectorAll('.pane').forEach(function(x){x.classList.remove('on')});b.classList.add('on');var t=document.getElementById('p-'+b.dataset.p);if(t)t.classList.add('on')})});

fetch('/api/scripts').then(function(r){return r.json()}).then(function(data){
  catalog=data;
  document.getElementById('sTools').textContent=data.length;
  document.getElementById('sComp').textContent=window.location.hostname||'LOCALHOST';
  renderTools(data);
}).catch(function(e){console.error(e)});

function renderTools(tools){
  var g=document.getElementById('toolGrid');g.innerHTML='';
  var cats={};tools.forEach(function(t){if(!cats[t.cat])cats[t.cat]=[];cats[t.cat].push(t)});
  document.getElementById('toolCount').textContent=tools.length+' tools';
  Object.keys(cats).sort().forEach(function(cat){
    var st=document.createElement('div');st.className='stitle';st.textContent=cat.toUpperCase().replace(/[^A-Z0-9]/g,' ');g.appendChild(st);
    var gr=document.createElement('div');gr.className='grid';g.appendChild(gr);
    cats[cat].forEach(function(t){
      var c=document.createElement('div');c.className='card';c.dataset.id=t.id;
      c.innerHTML='<div class="cc">// '+esc(cat)+'</div><div class="cn">'+esc(t.name)+'</div><div class="cd">'+esc(t.desc)+'</div><div class="cbadges">'+(t.adm?'<span class="badge badm">ADMIN</span>':'<span class="badge bsafe">SAFE</span>')+'</div>';
      c.addEventListener('click',function(){runTool(t.id,t.name,c)});
      gr.appendChild(c);
    });
  });
}

document.getElementById('searchBox').addEventListener('input',function(){
  var q=this.value.toLowerCase().trim();
  if(!q){renderTools(catalog);return}
  var f=catalog.filter(function(t){return t.name.toLowerCase().indexOf(q)!==-1||t.desc.toLowerCase().indexOf(q)!==-1||t.cat.toLowerCase().indexOf(q)!==-1||t.id.toLowerCase().indexOf(q)!==-1});
  renderTools(f);
});

function runTool(id,name,cardEl){
  var out=document.getElementById('runOut'),body=document.getElementById('runBody'),title=document.getElementById('runTitle'),dots=document.getElementById('runDots');
  title.textContent='EXECUTING // '+name.toUpperCase();
  dots.style.display='inline-flex';
  body.innerHTML='';
  out.classList.add('on');
  out.scrollIntoView({behavior:'smooth',block:'start'});
  if(cardEl){cardEl.classList.remove('done','err');cardEl.classList.add('running')}
  addLine(body,'prompt','> Launching '+name+'...');
  addLine(body,'info','[POST] /api/run/'+id);
  runCount++;document.getElementById('sRuns').textContent=runCount;
  fetch('/api/run/'+id,{method:'POST'}).then(function(r){return r.json()}).then(function(res){
    dots.style.display='none';
    if(cardEl){cardEl.classList.remove('running');cardEl.classList.add(res.status==='Completed'?'done':'err')}
    if(res.status==='Completed'){
      title.textContent='OUTPUT // '+name.toUpperCase();
      addLine(body,'ok','[OK] Completed at '+res.timestamp);
      if(res.hasStructuredData&&res.data&&res.data.length>0){
        addLine(body,'info','[DATA] '+res.data.length+' records returned');
        renderTable(body,res);
        var rb=document.createElement('button');rb.className='rawbtn';rb.textContent='SHOW RAW OUTPUT';
        rb.onclick=function(){var pre=document.createElement('div');pre.className='rbox';pre.textContent=res.rawOutput;body.appendChild(pre);rb.remove()};
        body.appendChild(rb);
      } else {
        addLine(body,'info','[OUTPUT]');
        var lines=(res.rawOutput||'No output').split('\n');
        lines.forEach(function(l){if(l.trim())addLine(body,'info','  '+l)});
      }
      history.unshift(res);renderHistory();
    } else {
      title.textContent='ERROR // '+name.toUpperCase();
      addLine(body,'err','[ERROR] '+(res.error||'Unknown error'));
    }
  }).catch(function(e){
    dots.style.display='none';
    title.textContent='ERROR // '+name.toUpperCase();
    addLine(body,'err','[NET] '+e.message);
    if(cardEl){cardEl.classList.remove('running');cardEl.classList.add('err')}
  });
}

function renderTable(container,res){
  if(!res.data||!res.data.length)return;
  var cols=res.columns||[];
  if(!cols.length){var f=res.data[0];if(f)cols=Object.keys(f)}
  if(!cols.length)return;
  var t=document.createElement('table');t.className='dtable';
  var thead=document.createElement('thead'),hr=document.createElement('tr');
  cols.forEach(function(c){var th=document.createElement('th');th.textContent=c;hr.appendChild(th)});
  thead.appendChild(hr);t.appendChild(thead);
  var tbody=document.createElement('tbody');
  res.data.forEach(function(row){
    var tr=document.createElement('tr');
    cols.forEach(function(c){var td=document.createElement('td');var v=row[c];if(v===undefined||v===null)v='';td.textContent=String(v).substring(0,200);tr.appendChild(td)});
    tbody.appendChild(tr);
  });
  t.appendChild(tbody);container.appendChild(t);
}

function renderHistory(){
  var list=document.getElementById('historyList');list.innerHTML='';
  if(!history.length){list.innerHTML='<div class="ibox"><p>No tools executed yet.</p></div>';return}
  history.slice(0,20).forEach(function(h,i){
    var d=document.createElement('div');d.className='card';
    d.style.marginBottom='6px';d.style.cursor='pointer';
    var statusClass=h.status==='Completed'?'tok':'te';
    d.innerHTML='<div style="display:flex;justify-content:space-between;align-items:center"><div><span class="cn" style="margin:0">'+esc(h.tool||h.toolId)+'</span><span class="cc" style="margin-left:8px">'+esc(h.category||'')+'</span></div><span class="'+statusClass+'" style="font-family:var(--fm);font-size:10px">'+h.status+' | '+esc(h.timestamp||'')+'</span></div>';
    d.addEventListener('click',function(){showHistoryResult(h)});
    list.appendChild(d);
  });
}

function showHistoryResult(h){
  var out=document.getElementById('histOut'),body=document.getElementById('histBody'),title=document.getElementById('histTitle');
  title.textContent='RESULT // '+(h.tool||h.toolId).toUpperCase();
  body.innerHTML='';
  out.classList.add('on');
  addLine(body,h.status==='Completed'?'ok':'err','Status: '+h.status+' | '+h.timestamp);
  if(h.error){addLine(body,'err','Error: '+h.error)}
  if(h.hasStructuredData&&h.data&&h.data.length>0){
    addLine(body,'info',h.data.length+' structured records:');
    renderTable(body,h);
    var rb=document.createElement('button');rb.className='rawbtn';rb.textContent='SHOW RAW OUTPUT';
    rb.onclick=function(){var pre=document.createElement('div');pre.className='rbox';pre.textContent=h.rawOutput;body.appendChild(pre);rb.remove()};
    body.appendChild(rb);
  } else if(h.rawOutput){
    addLine(body,'info','Output:');
    h.rawOutput.split('\n').forEach(function(l){if(l.trim())addLine(body,'info','  '+l)});
  }
}

window.toggleRawView=function(){
  var body=document.getElementById('runBody');
  var existing=body.querySelector('.rbox');
  if(existing){existing.remove();return}
};

window.apiGet=function(url){
  var panel=document.getElementById('dashOut'),body=document.getElementById('dashBody');
  body.innerHTML='';panel.classList.add('on');
  addLine(body,'prompt','> GET '+url);
  fetch(url).then(function(r){return r.text()}).then(function(txt){
    try{var o=JSON.parse(txt);txt=JSON.stringify(o,null,2)}catch(e){}
    txt.split('\n').forEach(function(l){addLine(body,'ok',l)});
  }).catch(function(e){addLine(body,'err','[ERROR] '+e.message)});
};

function addLine(container,type,text){
  var el=document.createElement('div');el.className='tline t'+type;el.textContent=text;container.appendChild(el);container.scrollTop=container.scrollHeight;
}
function esc(s){if(!s)return '';var d=document.createElement('div');d.textContent=s;return d.innerHTML}
renderHistory();
})();
</script>
</body>
</html>
'@

    while ($listener.IsListening) {
        try {
            $context = $listener.GetContext()
            $request = $context.Request
            $response = $context.Response
            $url = $request.Url.LocalPath
            $ts = Get-Date -Format "HH:mm:ss"
            Write-Host "  [$ts] $($request.HttpMethod) $url" -ForegroundColor Gray

            $responseString = ""
            $contentType = "text/html; charset=utf-8"

            switch -Regex ($url) {
                '^/$' {
                    $responseString = $htmlContent
                }
                '^/api/health$' {
                    $contentType = "application/json"
                    $responseString = @{
                        status = "healthy"
                        computerName = $env:COMPUTERNAME
                        user = $env:USERNAME
                        powershellVersion = $PSVersionTable.PSVersion.ToString()
                        toolCount = $Script:ToolCatalog.Count
                        jobsRun = $Script:Jobs.Count
                        timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    } | ConvertTo-Json -Compress
                }
                '^/api/scripts$' {
                    $contentType = "application/json"
                    $responseString = ($Script:ToolCatalog | Select-Object id, name, cat, adm, desc | ConvertTo-Json -Compress)
                }
                '^/api/run/([a-zA-Z0-9_-]+)$' {
                    $contentType = "application/json"
                    if ($request.HttpMethod -eq 'POST') {
                        $toolId = $url -replace '^/api/run/',''
                        Write-Host "  [$ts] EXEC $toolId" -ForegroundColor Yellow
                        $result = Invoke-ToolScript -ToolId $toolId
                        $responseString = $result | ConvertTo-Json -Depth 5 -Compress
                        $Script:Jobs[$toolId + '_' + (Get-Date -Format 'yyyyMMddHHmmss')] = $result
                    } else {
                        $response.StatusCode = 405
                        $responseString = '{"error":"POST required"}'
                    }
                }
                '^/api/status$' {
                    $contentType = "application/json"
                    $responseString = @{
                        status = "online"
                        version = "3.0.0"
                        toolCount = $Script:ToolCatalog.Count
                        timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    } | ConvertTo-Json -Compress
                }
                default {
                    $response.StatusCode = 404
                    $responseString = '{"error":"not_found","path":"' + $url + '"}'
                    $contentType = "application/json"
                }
            }

            $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseString)
            $response.ContentLength64 = $buffer.Length
            $response.ContentType = $contentType
            if ($response.StatusCode -eq 0) { $response.StatusCode = 200 }
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
        }
        catch {
            Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
catch {
    Write-Host ""
    Write-Host "  [X] Error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Message -match "access is denied") {
        Write-Host "  [!] Run PowerShell as Administrator" -ForegroundColor Yellow
    }
    elseif ($_.Exception.Message -match "already in use") {
        Write-Host "  [!] Port $Port in use. Try: .\Launch-WebUI.ps1 -Port 8081" -ForegroundColor Yellow
    }
    Read-Host "Press Enter to exit"
}
finally {
    if ($listener -and $listener.IsListening) {
        $listener.Stop()
        $listener.Close()
        Write-Host "  [i] Stopped." -ForegroundColor Cyan
    }
}
