<#
.SYNOPSIS
    MSP Toolkit - REST API + Web Console v2 (HttpListener SPA).
.DESCRIPTION
    Serves a full single-page-application web console for the MSP Toolkit.
    GUI v2 features: dark/light themes, fuzzy search, multi-tab execution,
    live metrics, favorites + recents, keyboard shortcuts, export/copy/share.
    Zero build step -- all HTML/CSS/JS embedded inline.

    Routes:
      GET  /                  -- GUI v2 SPA
      GET  /api/health        -- live metrics
      GET  /api/scripts       -- full tool catalog (searchable)
      POST /api/scripts/run   -- run a tool
      GET  /api/jobs/:id      -- poll job status
      GET  /api/jobs/:id/result -- fetch result
      GET  /api/jobs          -- all jobs
      GET  /api/inventory     -- OS facts snapshot
      GET  /api/export/:id    -- export result as JSON download

.PARAMETER Port
    Override port (default from config: 8080).
.PARAMETER BindAll
    Bind to 0.0.0.0 instead of localhost.
.PARAMETER OpenBrowser
    Launch browser on startup.
#>
#Requires -Version 5.1
[CmdletBinding()]
param([int]$Port, [switch]$BindAll, [switch]$OpenBrowser)

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent $PSScriptRoot
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch {
    Write-Host "Warning: MSPToolkit module not fully loaded. Some features may be limited." -ForegroundColor Yellow
}

# Config
$cfg = $null
try { $cfg = Get-MSPConfig } catch { $cfg = @{ webInterface = @{ port = 8080; apiKey = '' }; security = @{ requireApiKeyForLocalhost = $false } } }
if (-not $Port) { $Port = if ($cfg.webInterface.port) { [int]$cfg.webInterface.port } else { 8080 } }
$apiKey = if ($cfg.webInterface.apiKey) { $cfg.webInterface.apiKey } else { [guid]::NewGuid().ToString('N') }

Write-Host ""
Write-Host "  SENTINEL RECON CONSOLE" -ForegroundColor Cyan
Write-Host "  API Key: $apiKey" -ForegroundColor DarkGray
Write-Host "  Port: $Port" -ForegroundColor DarkGray
Write-Host ""

# Job registry
$Script:Jobs = [System.Collections.Concurrent.ConcurrentDictionary[string,object]]::new()
$Script:RunspacePool = [runspacefactory]::CreateRunspacePool(1, 8)
$Script:RunspacePool.Open()

function New-MSPApiJob { param($Tool, $Block, $Args)
    $id = [guid]::NewGuid().ToString('N').Substring(0,12)
    $ps = [powershell]::Create(); $ps.RunspacePool = $Script:RunspacePool
    [void]$ps.AddScript({ param($b,$a) try { & $b @a } catch { [pscustomobject]@{ status='Failure'; summary=$_.Exception.Message } } })
    [void]$ps.AddArgument($Block); [void]$ps.AddArgument($Args)
    $h = $ps.BeginInvoke()
    $job = [pscustomobject]@{ Id=$id; Tool=$Tool; StartedAt=(Get-Date).ToString('o'); Status='Running'; Handle=$h; Pipe=$ps; Result=$null }
    $Script:Jobs[$id] = $job
    return $id
}
function Update-MSPJobStatus { param($Id)
    if (-not $Script:Jobs.ContainsKey($Id)) { return $null }
    $j = $Script:Jobs[$Id]
    if ($j.Status -eq 'Running' -and $j.Handle.IsCompleted) {
        try { $o = $j.Pipe.EndInvoke($j.Handle); $j.Result = $o | Select-Object -Last 1; $j.Status = if ($j.Result.status) { "$($j.Result.status)" } else { 'Completed' } }
        catch { $j.Status = 'Failed'; $j.Result = @{ summary = $_.Exception.Message } }
        finally { $j.Pipe.Dispose() }
    }
    return $j
}

# Full tool catalog (Windows + Mac + DC)
$Script:Catalog = @(
    @{id='triage';    name='Quick Triage Report';     cat='Workstation';   adm=$false; plat='Win';    path='..\MSP_Tier3_Toolkit\Workstation\Get-QuickTriageReport.ps1';      desc='1-page HTML report for clients.'},
    @{id='outlook';   name='Reset Outlook Cache';      cat='Workstation';   adm=$false; plat='Win';    path='..\MSP_Tier3_Toolkit\Workstation\Reset-OutlookCache.ps1';         desc='Nuke OST, AutoComplete, cached creds.'},
    @{id='search';    name='Repair Windows Search';    cat='Workstation';   adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Workstation\Repair-WindowsSearch.ps1';       desc='Rebuild Windows Search index.'},
    @{id='health';    name='System Health Report';     cat='Diagnostics';   adm=$false; plat='Win';    path='..\MSP_Tier3_Toolkit\SystemHealthReport.ps1';                   desc='Full system health snapshot.'},
    @{id='reboot';    name='Reboot Pending Check';     cat='Diagnostics';   adm=$false; plat='Win';    path='..\MSP_Tier3_Toolkit\Diagnostics\RebootPendingCheck.ps1';         desc='Multi-signal reboot detection.'},
    @{id='events';    name='Event Log Alert Summary';  cat='Diagnostics';   adm=$false; plat='Win';    path='..\MSP_Tier3_Toolkit\Diagnostics\EventLogAlertSummary.ps1';      desc='Last 24h errors/warnings.'},
    @{id='perf';      name='Performance Baseline';     cat='Diagnostics';   adm=$false; plat='Win';    path='..\MSP_Tier3_Toolkit\Diagnostics\Get-PerformanceBaseline.ps1';   desc='30s CPU/mem/disk/network sample.'},
    @{id='services';  name='Windows Service Audit';    cat='Diagnostics';   adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Diagnostics\WindowsServiceAudit.ps1';       desc='Auto-start services that are stopped.'},
    @{id='bitlocker'; name='BitLocker Status';         cat='Security';      adm=$false; plat='Win';    path='..\MSP_Tier3_Toolkit\Security\BitLockerStatusCheck.ps1';         desc='Per-volume protection state.'},
    @{id='av';        name='AV Status';                cat='Security';      adm=$false; plat='Win';    path='..\MSP_Tier3_Toolkit\Security\AVStatusCheck.ps1';                desc='SecurityCenter + Defender state.'},
    @{id='admins';    name='Local Admin Audit';        cat='Security';      adm=$false; plat='Win';    path='..\MSP_Tier3_Toolkit\Security\LocalAdminAudit.ps1';              desc='Who has local Administrator?'},
    @{id='patches';   name='Patch Compliance';         cat='Security';      adm=$false; plat='Win';    path='..\MSP_Tier3_Toolkit\Security\Get-PatchCompliance.ps1';          desc='Pending updates + install history.'},
    @{id='posture';   name='Security Posture Score';   cat='Security';      adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Security\Get-SecurityPostureScore.ps1';     desc='12-check 0-100 hardening score.'},
    @{id='cis';       name='CIS Benchmark Score';      cat='Security';      adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Security\Get-CISBenchmarkScore.ps1';      desc='30-control CIS subset scorecard.'},
    @{id='cleanup';   name='Temp Cleanup';             cat='Maintenance';   adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Maintenance\ScheduledTempCleanup.ps1';      desc='Safe temp-folder cleanup.'},
    @{id='bloat';     name='OEM Bloatware Remover';    cat='Maintenance';   adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Maintenance\OEMBloatwareRemover.ps1';       desc='Remove Candy Crush, et al.'},
    @{id='netreset';  name='Reset Network Stack';      cat='Network';       adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Network\Reset-NetworkStack.ps1';             desc='winsock + ip + DNS + ARP + nbtstat.'},
    @{id='netpath';   name='Test Network Path';        cat='Network';       adm=$false; plat='Win';    path='..\MSP_Tier3_Toolkit\Network\Test-NetworkPath.ps1';               desc='Ping/TCP/DNS/HTTP probe.'},
    @{id='wifi';      name='WiFi Survey';              cat='Network';       adm=$false; plat='Win';    path='..\MSP_Tier3_Toolkit\Network\Get-WiFiSurvey.ps1';                desc='BSSIDs, channel overlap, roam.'},
    @{id='dnsdeep';   name='DNS Deep Dive';            cat='Network';       adm=$false; plat='Win';    path='..\MSP_Tier3_Toolkit\Network\Test-DNSDeepDive.ps1';              desc='Per-server timing, split-brain.'},
    @{id='m365ep';    name='M365 Endpoint Test';        cat='Network';       adm=$false; plat='Win';    path='..\MSP_Tier3_Toolkit\Network\Test-M365Endpoints.ps1';             desc='Reachability vs M365 catalog.'},
    @{id='vpn';       name='VPN Health';               cat='Network';       adm=$false; plat='Win';    path='..\MSP_Tier3_Toolkit\Network\Test-VPNHealth.ps1';                desc='Tunnel state, DNS leak.'},
    @{id='onedrive';  name='OneDrive Sync Health';     cat='M365';          adm=$false; plat='Win';    path='..\MSP_Tier3_Toolkit\M365\OneDriveSyncHealthCheck.ps1';          desc='KFM + last error per account.'},
    @{id='inventory'; name='Asset Inventory Export';   cat='Inventory';     adm=$false; plat='Win';    path='..\MSP_Tier3_Toolkit\Inventory\Export-AssetInventory.ps1';      desc='PSA-ready hardware+software dump.'},
    @{id='onboard';   name='User Onboarding';          cat='Lifecycle';     adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Lifecycle\Invoke-UserOnboarding.ps1';      desc='AD+Entra+groups+license+welcome.'},
    @{id='offboard';  name='User Offboarding';         cat='Lifecycle';     adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Lifecycle\Invoke-UserOffboarding.ps1';     desc='Snapshot->block->revoke->move.'},
    @{id='macsys';    name='Mac System Report';        cat='Mac';           adm=$false; plat='Mac';    path='..\MSP_Tier3_Toolkit\Mac\Get-MacSystemReport.ps1';              desc='Full system_profiler report.'},
    @{id='macdisk';   name='Mac Disk Health';          cat='Mac';           adm=$false; plat='Mac';    path='..\MSP_Tier3_Toolkit\Mac\Get-MacDiskHealth.ps1';               desc='SMART, APFS, FileVault, TM.'},
    @{id='macwifi';   name='Mac WiFi Survey';          cat='Mac';           adm=$false; plat='Mac';    path='..\MSP_Tier3_Toolkit\Mac\Get-MacNetworkSurvey.ps1';             desc='Airport scan, DNS, reachability.'},
    @{id='macprofile';name='Mac Profile Audit';        cat='Mac';           adm=$false; plat='Mac';    path='..\MSP_Tier3_Toolkit\Mac\Get-MacProfileAudit.ps1';             desc='MDM enrollment, config profiles.'},
    @{id='macfv';     name='Mac FileVault Status';     cat='Mac';           adm=$false; plat='Mac';    path='..\MSP_Tier3_Toolkit\Mac\Get-MacFileVaultStatus.ps1';          desc='FileVault + recovery key escrow.'},
    @{id='macmdm';    name='Mac MDM Status';           cat='Mac';           adm=$false; plat='Mac';    path='..\MSP_Tier3_Toolkit\Mac\Get-MacMDMStatus.ps1';                desc='MDM enrollment, bootstrap token.'},
    @{id='macsec';    name='Mac Security Posture';     cat='Mac';           adm=$false; plat='Mac';    path='..\MSP_Tier3_Toolkit\Mac\Get-MacSecurityPosture.ps1';          desc='Gatekeeper, SIP, XProtect, score.'},
    @{id='adrepl';    name='AD Replication Health';    cat='DC';            adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\DC\Get-ADReplicationHealth.ps1';          desc='Replsummary, lingering, USN drift.'},
    @{id='dnszone';   name='DNS Zone Health';          cat='DC';            adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\DC\Get-DNSZoneHealth.ps1';               desc='SOA serial, forwarders, scavenging.'},
    @{id='dhcp';      name='DHCP Scope Report';        cat='DC';            adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\DC\Get-DHCPScopeReport.ps1';             desc='Scope utilization, BAD_ADDRESS.'},
    @{id='fsmo';      name='FSMO Role Audit';          cat='DC';            adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\DC\Get-FSMORoleAudit.ps1';               desc='All 5 FSMO holders, reachability.'},
    @{id='gpo';       name='GPO Link Report';          cat='DC';            adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\DC\Get-GPOLinkReport.ps1';               desc='GPOs, links, WMI filters.'},
    @{id='dcdiag';    name='DCDiag Orchestrator';      cat='DC';            adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\DC\Invoke-DCDiagOrchestrator.ps1';        desc='Targeted DCDiag, per-test results.'},
    @{id='kerberos';  name='Kerberos Health';          cat='DC';            adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\DC\Get-KerberosHealth.ps1';               desc='KRBTGT, dup SPNs, delegation.'},
    @{id='trust';     name='Trust Health';             cat='DC';            adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\DC\Test-TrustHealth.ps1';                 desc='Trust secure channel, SID filtering.'},
    @{id='adusers';   name='AD User Bulk Report';      cat='DC';            adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\DC\Get-ADUserBulkReport.ps1';             desc='Stale, expiring, locked, disabled.'},
    @{id='sysvol';    name='SYSVOL Health';            cat='DC';            adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\DC\Get-SYSVOLHealth.ps1';                 desc='DFSR state, policy counts, share.'},
    @{id='vss';       name='VSS Writer Health';        cat='Backup';        adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Backup\Get-VSSWriterHealth.ps1';          desc='All VSS writers, auto-retry.'},
    @{id='backup';    name='Backup Status';            cat='Backup';        adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Backup\Get-BackupStatus.ps1';              desc='WSB job history, event log fallback.'},
    @{id='shadow';    name='Shadow Copy Report';       cat='Backup';        adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Backup\Get-ShadowCopyReport.ps1';          desc='Per-volume shadows, schedule.'},
    @{id='restore';   name='Restore Readiness';        cat='Backup';        adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Backup\Test-RestoreReadiness.ps1';          desc='WinRE, catalog, driver check.'},
    @{id='cisfull';   name='Full CIS Benchmark';       cat='Security';      adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Security\Get-FullCISBenchmark.ps1';        desc='30-control CIS Level 1 scoring.'},
    @{id='fwrisk';    name='Firewall Risk Audit';      cat='Security';      adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Security\Get-FirewallRiskAudit.ps1';       desc='Risk-scored inbound rules.'},
    @{id='certs';     name='Certificate Inventory';    cat='Security';      adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Security\Get-CertificateInventory.ps1';     desc='Expiry timeline, weak algorithms.'},
    @{id='laps';      name='LAPS Deployment';          cat='Security';      adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Security\Test-LAPSDeployment.ps1';           desc='LAPS presence, password age.'},
    @{id='cg';        name='Credential Guard';         cat='Security';      adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Security\Get-CredentialGuardState.ps1';      desc='VBS, HVCI, LSASS protection.'},
    @{id='tpm';       name='Secure Boot & TPM';        cat='Security';      adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Security\Get-SecureBootTPMState.ps1';        desc='Secure Boot, TPM, PCR banks.'},
    @{id='exploit';   name='Exploit Guard Config';     cat='Security';      adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Security\Get-ExploitGuardConfig.ps1';        desc='ASR rules, network protection.'},
    @{id='ninja';     name='NinjaOne Health';          cat='RMM';           adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\RMM\Get-NinjaOneHealth.ps1';                desc='Agent, service, connectivity.'},
    @{id='cw';        name='ConnectWise Integration';  cat='RMM';           adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\RMM\Get-ConnectWiseIntegration.ps1';       desc='Manage API, tickets, agent.'},
    @{id='datto';     name='Datto Backup Status';      cat='RMM';           adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\RMM\Test-DattoBackupStatus.ps1';           desc='Agent, appliance, VSS, backup.'},
    @{id='autotask';  name='Autotask Ticket Sync';     cat='RMM';           adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\RMM\Get-AutotaskTicketSync.ps1';           desc='API, resources, tickets.'},
    @{id='entra';     name='Entra Connect Health';     cat='Cloud';         adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Cloud\Get-EntraConnectHealth.ps1';           desc='Sync cycles, connectors, errors.'},
    @{id='intune';    name='Intune Compliance';        cat='Cloud';         adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Cloud\Get-IntuneCompliance.ps1';             desc='Device compliance, non-compliant.'},
    @{id='ca';        name='Conditional Access';       cat='Cloud';         adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Cloud\Get-ConditionalAccessReport.ps1';     desc='CA policies, MFA gaps, exclusions.'},
    @{id='azurevm';   name='Azure VM Inventory';       cat='Cloud';         adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Cloud\Get-AzureVMInventory.ps1';              desc='VMs, sizes, cost estimates.'},
    @{id='exo';       name='Exchange Online Health';   cat='Cloud';         adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Cloud\Get-ExchangeOnlineHealth.ps1';         desc='Mailboxes, connectors, transport.'},
    @{id='teams';     name='Teams Call Quality';       cat='Cloud';         adm=$false; plat='Win';    path='..\MSP_Tier3_Toolkit\Cloud\Get-TeamsCallQuality.ps1';              desc='Network readiness, latency, CQD.'},
    @{id='sql';       name='SQL Server Health';        cat='Apps';          adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Apps\Get-SQLServerHealth.ps1';               desc='Databases, backups, wait stats.'},
    @{id='iis';       name='IIS App Pool Status';      cat='Apps';          adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Apps\Get-IISAppPoolStatus.ps1';             desc='Pools, workers, recycles.'},
    @{id='exsvr';     name='Exchange Server Health';   cat='Apps';          adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Apps\Get-ExchangeServerHealth.ps1';          desc='Queues, DAG, DBs, certs.'},
    @{id='print';     name='Print Server Report';      cat='Apps';          adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Apps\Get-PrintServerReport.ps1';             desc='Printers, queues, drivers.'},
    @{id='svcdep';    name='Service Dependency Map';   cat='Apps';          adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Apps\Get-ServiceDependencyMap.ps1';         desc='Dependency chains, dead deps.'},
    @{id='appperf';   name='App Performance Baseline'; cat='Apps';          adm=$false; plat='Win';    path='..\MSP_Tier3_Toolkit\Apps\Get-AppPerformanceBaseline.ps1';        desc='CPU, memory, handle baselines.'},
    @{id='pktcap';    name='Packet Capture';           cat='Network';       adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Network\Get-PacketCapture.ps1';               desc='pktmon capture, retransmits.'},
    @{id='topo';      name='Network Topology';         cat='Network';       adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Network\Get-NetworkTopology.ps1';             desc='ARP, traceroute, topology map.'},
    @{id='snmp';      name='SNMP Walk';                cat='Network';       adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Network\Test-SNMPWalk.ps1';                   desc='Device discovery, OID polling.'},
    @{id='lanperf';   name='LAN Throughput';           cat='Network';       adm=$false; plat='Win';    path='..\MSP_Tier3_Toolkit\Network\Test-LANThroughput.ps1';              desc='iperf TCP/UDP, SMB fallback.'},
    @{id='arp';       name='ARP Cache Audit';          cat='Network';       adm=$false; plat='Win';    path='..\MSP_Tier3_Toolkit\Network\Get-ARPCacheAudit.ps1';               desc='Duplicate IPs, rogue, OUI.'},
    @{id='saturate';  name='Bandwidth Saturation';     cat='Network';       adm=$true;  plat='Win';    path='..\MSP_Tier3_Toolkit\Network\Test-BandwidthSaturation.ps1';       desc='Saturation point, headroom.'}
)

# HTTP listener
$prefix = if ($BindAll) { "http://+:$Port/" } else { "http://localhost:$Port/" }
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($prefix)
$listener.Start()
Write-Host "  Listening on $prefix" -ForegroundColor Green
if ($OpenBrowser) { Start-Process "http://localhost:$Port" }

# -----------------------------------------------------------------------
#  GUI v2 HTML/CSS/JS -- embedded SPA
# -----------------------------------------------------------------------
$uiHtml = @'
<!doctype html><html lang="en"><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><meta name="theme-color" content="#050608"/><meta name="description" content="Sentinel Recon -- Cross-Platform MSP Diagnostics & Automation. Discover. Diagnose. Deploy."/><link rel="manifest" href="/manifest.json"/><title>Sentinel Recon Console</title><link rel="icon" type="image/svg+xml" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'><circle cx='16' cy='16' r='14' fill='none' stroke='%2300F0FF' stroke-width='2'/><line x1='2' y1='16' x2='30' y2='16' stroke='%2300F0FF' stroke-width='1.5'/><line x1='16' y1='2' x2='16' y2='30' stroke='%2300F0FF' stroke-width='1.5'/><circle cx='16' cy='16' r='3' fill='%2300F0FF'/></svg>"/><style>
:root{--bg:#050608;--panel:#0A0C10;--line:#1a2530;--muted:#849495;--accent:#00F0FF;--ok:#95E400;--warn:#FBBC00;--bad:#ff3b3b;--text:#e2e2e8;--radius:8px;--font:'Space Grotesk','Inter',-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;--mono:'JetBrains Mono','Cascadia Code','Fira Code','Consolas',monospace}
[data-theme="light"]{--bg:#f5f5f5;--panel:#fff;--line:#d0d0d0;--muted:#8a8a9a;--accent:#0066ff;--text:#1a1a2e}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:var(--font);background:var(--bg);color:var(--text);min-height:100vh;display:flex;flex-direction:column}
.topbar{display:flex;justify-content:space-between;align-items:center;padding:12px 24px;border-bottom:1px solid var(--line);background:var(--panel);flex-shrink:0}
.brand{display:flex;align-items:center;gap:10px;font-weight:700;font-size:17px;letter-spacing:.3px}
.brand .dot{width:10px;height:10px;border-radius:50%;background:var(--accent)}
.topbar-right{display:flex;gap:10px;align-items:center}
.topbar input{background:var(--bg);border:1px solid var(--line);color:var(--text);padding:6px 10px;border-radius:var(--radius);width:260px;font-family:var(--mono);font-size:12px}
.layout{display:grid;grid-template-columns:270px 1fr;gap:0;flex:1;overflow:hidden}
.sidebar{background:var(--panel);border-right:1px solid var(--line);overflow-y:auto;display:flex;flex-direction:column}
.sidebar.closed{display:none}
.sidebar-header{padding:12px 16px;border-bottom:1px solid var(--line)}
.search-box{width:100%;background:var(--bg);border:1px solid var(--line);color:var(--text);padding:8px 12px;border-radius:var(--radius);font-size:13px;outline:none}
.search-box:focus{border-color:var(--accent)}
.cat-label{color:var(--muted);font-size:10px;text-transform:uppercase;letter-spacing:1.2px;padding:12px 16px 4px;font-weight:700}
.tool-item{padding:8px 16px;cursor:pointer;display:flex;justify-content:space-between;align-items:center;font-size:13px;border-left:3px solid transparent;transition:all .15s;gap:6px}
.tool-item:hover{background:var(--bg);border-left-color:var(--accent)}
.tool-item.active{background:var(--accent);color:#fff;border-left-color:var(--accent)}
.tool-item .tool-name{flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.badge{font-size:10px;padding:1px 6px;border-radius:8px;font-weight:700;text-transform:uppercase}
.badge.adm{background:rgba(255,59,59,.2);color:var(--bad)}.badge.mac{background:rgba(0,240,255,.2);color:var(--accent)}.badge.win{background:rgba(149,228,0,.2);color:var(--ok)}.badge.linux{background:rgba(251,188,0,.2);color:var(--warn)}
.main-content{padding:24px;overflow-y:auto;overflow-x:hidden}
.metrics-row{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:12px;margin-bottom:20px}
.metric-box{background:var(--panel);padding:14px 16px;border-radius:var(--radius);border:1px solid var(--line)}
.metric-box .m-label{color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.7px}
.metric-box .m-value{font-size:22px;font-weight:700;margin-top:4px}
.metric-box .m-sub{font-size:11px;color:var(--muted);margin-top:2px}
.section-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:12px}
.section-header h2{font-size:16px;font-weight:700}
.btn{background:var(--accent);color:#fff;border:none;padding:8px 16px;border-radius:var(--radius);cursor:pointer;font-weight:600;font-size:13px;display:inline-flex;align-items:center;gap:6px;transition:filter .15s}
.btn:hover{filter:brightness(1.15)}
.btn:disabled{opacity:.4;cursor:default;filter:none}
.btn.s{background:var(--bg);color:var(--text);border:1px solid var(--line)}
.btn.s:hover{background:var(--line)}
.btn.danger{background:var(--bad)}
.panel-card{background:var(--panel);border:1px solid var(--line);border-radius:var(--radius);padding:18px;margin-bottom:16px}
.tab-bar{display:flex;gap:2px;margin-bottom:0}
.tab-btn{background:var(--bg);border:1px solid var(--line);border-bottom:none;color:var(--muted);padding:8px 14px;border-radius:var(--radius) var(--radius) 0 0;cursor:pointer;font-size:13px;max-width:200px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;display:flex;align-items:center;gap:6px}
.tab-btn.active{background:var(--panel);color:var(--text);border-color:var(--line)}
.tab-btn .tb-close{margin-left:4px;opacity:.5;font-size:11px;cursor:pointer}
.tab-btn .tb-close:hover{opacity:1;color:var(--bad)}
.output-area{background:var(--bg);border:1px solid var(--line);border-radius:0 0 var(--radius) var(--radius);padding:16px;font-family:var(--mono);font-size:12px;white-space:pre-wrap;word-break:break-word;max-height:450px;overflow:auto;min-height:80px;line-height:1.5}
.output-area.empty{color:var(--muted);font-family:var(--font);text-align:center;padding:40px}
.jobs-list{display:flex;flex-direction:column;gap:6px;max-height:200px;overflow-y:auto}
.job-row{display:flex;justify-content:space-between;align-items:center;padding:8px 12px;background:var(--bg);border-radius:var(--radius);font-size:12px}
.job-row .j-tool{font-weight:600}
.pill{display:inline-block;padding:2px 8px;border-radius:10px;font-size:10px;font-weight:700;text-transform:uppercase}
.pill.ok{background:rgba(149,228,0,.15);color:var(--ok)}.pill.warn{background:rgba(251,188,0,.15);color:var(--warn)}.pill.bad{background:rgba(255,59,59,.15);color:var(--bad)}.pill.run{background:rgba(0,240,255,.15);color:var(--accent)}
.row-gap{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
.status-bar{display:flex;justify-content:space-between;padding:6px 24px;border-top:1px solid var(--line);background:var(--panel);font-size:11px;color:var(--muted);flex-shrink:0}
kbd{background:var(--bg);border:1px solid var(--line);border-radius:4px;padding:1px 5px;font-size:10px;font-family:var(--mono)}
.theme-toggle{cursor:pointer;font-size:16px;padding:4px 8px;border-radius:var(--radius);background:var(--bg);border:1px solid var(--line)}
.toast{position:fixed;top:16px;right:16px;background:var(--panel);border:1px solid var(--line);border-radius:var(--radius);padding:12px 18px;z-index:999;box-shadow:0 4px 20px rgba(0,0,0,.4);animation:slideIn .3s ease;font-size:13px;max-width:360px}
@keyframes slideIn{from{opacity:0;transform:translateX(20px)}to{opacity:1;transform:translateX(0)}}
@media(max-width:800px){.layout{grid-template-columns:1fr}.sidebar{position:fixed;z-index:10;top:0;left:0;height:100vh;width:260px;display:none}.sidebar.open{display:flex}}
</style></head><body>
<div class="topbar">
  <div class="brand"><span class="dot"></span>Sentinel Recon<span class="pill run" style="margin-left:8px">v25</span></div>
  <div class="topbar-right">
    <input id="apiKey" type="password" placeholder="API Key" autocomplete="off"/>
    <button class="btn s" onclick="saveKey()" title="Save API Key">Save</button>
    <button class="theme-toggle" onclick="toggleTheme()" title="Toggle theme">&#9681;</button>
    <button class="btn s" onclick="toggleSidebar()" title="Toggle sidebar">&#9776;</button>
  </div>
</div>
<div class="layout">
  <aside class="sidebar" id="sidebar">
    <div class="sidebar-header"><input class="search-box" id="searchBox" placeholder="Search tools... (Ctrl+K)" oninput="renderToolList()" autocomplete="off"/></div>
    <div id="toolList" style="flex:1;overflow-y:auto"></div>
    <div class="cat-label">Favorites</div><div id="favList" style="padding-bottom:16px"></div>
  </aside>
  <main class="main-content">
    <div class="metrics-row" id="metrics"></div>
    <div class="panel-card">
      <div class="section-header"><h2 id="selectedName">Select a tool</h2><span class="pill run" id="selectedCat"></span></div>
      <div class="row-gap" style="margin-bottom:12px">
        <button class="btn" onclick="runSelected()" id="runBtn" disabled>&#9654; Run</button>
        <button class="btn s" onclick="exportResult()" id="exportBtn" disabled>Export</button>
        <button class="btn s" onclick="copyResult()" id="copyBtn" disabled>Copy</button>
        <span style="font-size:11px;color:var(--muted)" id="hint">Pick a tool from the sidebar to begin.</span>
      </div>
      <div class="tab-bar" id="tabBar"></div>
      <div class="output-area empty" id="output">Run a tool to see results here.</div>
    </div>
    <div class="panel-card"><h2 style="font-size:14px;margin-bottom:10px">Recent Jobs</h2><div class="jobs-list" id="jobs"><div style="color:var(--muted);text-align:center;padding:16px">No jobs yet this session.</div></div></div>
  </main>
</div>
<div class="status-bar"><span id="statusText">Ready</span><span id="hostLabel"></span><span>Shortcuts: <kbd>Ctrl+K</kbd> Search <kbd>Ctrl+R</kbd> Run <kbd>Ctrl+E</kbd> Export</span></div>
<div id="toastContainer"></div>
<script>
const $=id=>document.getElementById(id);
let selected=null,catalog=[],tabs=[],activeTab=null,pollers={},favorites=JSON.parse(localStorage.getItem('mspFavs')||'[]'),recents=JSON.parse(localStorage.getItem('mspRecents')||'[]'),theme=localStorage.getItem('mspTheme')||'dark';
function getKey(){return $('apiKey').value||localStorage.getItem('mspApiKey')||''}
function saveKey(){localStorage.setItem('mspApiKey',$('apiKey').value);toast('API key saved')}
function loadKey(){$('apiKey').value=localStorage.getItem('mspApiKey')||''}
function toggleTheme(){theme=theme==='dark'?'light':'dark';document.documentElement.setAttribute('data-theme',theme);localStorage.setItem('mspTheme',theme)}
function toggleSidebar(){document.getElementById('sidebar').classList.toggle('open')}
function toast(msg){const c=$('toastContainer');const t=document.createElement('div');t.className='toast';t.textContent=msg;c.appendChild(t);setTimeout(()=>{t.style.opacity='0';t.style.transition='opacity .3s';setTimeout(()=>t.remove(),300)},2500)}
async function api(path,opts={}){opts.headers=Object.assign({'X-Api-Key':getKey()},opts.headers||{});const r=await fetch(path,opts);if(!r.ok)throw new Error(r.status+' '+await r.text());const ct=r.headers.get('content-type')||'';return ct.includes('json')?r.json():r.text()}
function pill(s){return'<span class="pill '+(s==='Success'?'ok':s==='Warning'?'warn':(s==='Failure'||s==='Failed')?'bad':'run')+'">'+s+'</span>'}
async function loadCatalog(){catalog=await api('/api/scripts');renderToolList();renderFavList()}
function renderToolList(){const q=($('searchBox').value||'').toLowerCase();const grouped={};catalog.forEach(c=>{if(q&&!c.name.toLowerCase().includes(q)&&!c.cat.toLowerCase().includes(q)&&!c.desc.toLowerCase().includes(q))return;(grouped[c.cat]=grouped[c.cat]||[]).push(c)});let h='';Object.keys(grouped).sort().forEach(cat=>{h+='<div class="cat-label">'+cat+'</div>';grouped[cat].forEach(c=>{const stars=favorites.includes(c.id)?' *':'';h+='<div class="tool-item'+(selected&&selected.id===c.id?' active':'')+'" data-id="'+c.id+'" onclick="select(\''+c.id+'\')"><span class="tool-name">'+c.name+stars+'</span><span class="badge '+(c.adm?'adm':'')+'">'+(c.adm?'ADMIN':'')+'</span><span class="badge '+(c.plat==='Mac'?'mac':c.plat==='Linux'?'linux':'win')+'">'+c.plat+'</span></div>'})});$('toolList').innerHTML=h||'<div style="color:var(--muted);padding:16px;font-size:13px">No tools match.</div>'}
function renderFavList(){if(!favorites.length)return;$('favList').innerHTML=favorites.map(id=>{const c=catalog.find(t=>t.id===id);return c?'<div class="tool-item" data-id="'+c.id+'" onclick="select(\''+c.id+'\')"><span class="tool-name">'+c.name+'</span></div>':''}).join('')}
function select(id){selected=catalog.find(c=>c.id===id);if(!selected)return;addRecent(id);document.querySelectorAll('.tool-item').forEach(e=>{e.classList.remove('active');if(e.dataset.id===id)e.classList.add('active')});$('selectedName').textContent=selected.name;$('selectedCat').textContent=selected.cat;$('runBtn').disabled=false;$('hint').textContent=selected.desc;if(selected.adm)$('hint').innerHTML+=' <span class="badge adm">ADMIN REQUIRED</span>'}
function addRecent(id){recents=recents.filter(r=>r!==id);recents.unshift(id);recents=recents.slice(0,15);localStorage.setItem('mspRecents',JSON.stringify(recents))}
async function runSelected(){if(!selected)return;
  const tabId='tab_'+Date.now();tabs.push({id:tabId,name:selected.name,status:'Running',result:null,jobId:null});activeTab=tabId;renderTabs();
  $('runBtn').disabled=true;
  try{const r=await api('/api/scripts/run',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:selected.id})});
    const tab=tabs.find(t=>t.id===tabId);if(tab)tab.jobId=r.jobId;addJobRow(r.jobId,selected.name);pollJob(r.jobId,tabId);
    toast('Running: '+selected.name)}catch(e){$('output').textContent='Error: '+e.message;$('runBtn').disabled=false}
}
function renderTabs(){let h='';tabs.forEach(t=>{h+='<div class="tab-btn'+(t.id===activeTab?' active':'')+'" onclick="switchTab(\''+t.id+'\')">'+t.name+' '+pill(t.status)+'<span class="tb-close" onclick="event.stopPropagation();closeTab(\''+t.id+'\')">&times;</span></div>'});$('tabBar').innerHTML=h;if(activeTab){const t=tabs.find(x=>x.id===activeTab);if(t){$('output').className='output-area'+(t.result?'':' empty');$('output').textContent=t.result?JSON.stringify(t.result,null,2):(t.status==='Running'?'Running...':'Awaiting result...');$('exportBtn').disabled=!t.result;$('copyBtn').disabled=!t.result}}}
function switchTab(id){activeTab=id;renderTabs()}
function closeTab(id){tabs=tabs.filter(t=>t.id!==id);if(activeTab===id){activeTab=tabs.length?tabs[tabs.length-1].id:null}renderTabs()}
async function pollJob(jobId,tabId){pollers[jobId]=setInterval(async()=>{try{const j=await api('/api/jobs/'+jobId);updateJobRow(jobId,j.status);const tab=tabs.find(t=>t.id===tabId);if(tab)tab.status=j.status;
    if(j.status!=='Running'){clearInterval(pollers[jobId]);$('runBtn').disabled=false;
      const res=await api('/api/jobs/'+jobId+'/result');if(tab){tab.result=res;tab.status=j.status}renderTabs();toast(j.status+': '+tab.name)}}catch(e){clearInterval(pollers[jobId]);$('runBtn').disabled=false}},1000)}
function addJobRow(id,name){const j=$('jobs');if(j.querySelector('div[style]'))j.innerHTML='';const r=document.createElement('div');r.className='job-row';r.id='job-'+id;r.innerHTML='<div><span class="j-tool">'+name+'</span> <span style="font-size:10px;color:var(--muted)">'+id+'</span></div><div>'+pill('Running')+'</div>';j.prepend(r)}
function updateJobRow(id,status){const r=$('job-'+id);if(r)r.children[1].innerHTML=pill(status)}
async function loadHealth(){try{const h=await api('/api/health');$('hostLabel').textContent=h.computerName||'';$('metrics').innerHTML='<div class="metric-box"><div class="m-label">CPU</div><div class="m-value">'+h.cpuPercent+'%</div></div><div class="metric-box"><div class="m-label">Memory</div><div class="m-value">'+h.memoryUsagePercent+'%</div></div><div class="metric-box"><div class="m-label">Disk Free</div><div class="m-value">'+h.diskFreeGB+' GB</div></div><div class="metric-box"><div class="m-label">Uptime</div><div class="m-value">'+h.uptimeHours+'h</div></div><div class="metric-box"><div class="m-label">Reboot</div><div class="m-value" style="color:'+(h.pendingReboot?'var(--bad)':'var(--ok)')+'">'+(h.pendingReboot?'YES':'No')+'</div></div><div class="metric-box"><div class="m-label">Platform</div><div class="m-value" style="font-size:16px">'+h.platform+'</div></div>'}catch(e){$('metrics').innerHTML='<div class="metric-box"><div class="m-label">Error</div><div class="m-value" style="font-size:14px">'+e.message+'</div></div>'}}
function exportResult(){const tab=tabs.find(t=>t.id===activeTab);if(!tab||!tab.result)return;const blob=new Blob([JSON.stringify(tab.result,null,2)],{type:'application/json'});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='sentinel_recon_'+new Date().toISOString().slice(0,19).replace(/:/g,'-')+'.json';a.click();toast('Result exported')}
function copyResult(){const tab=tabs.find(t=>t.id===activeTab);if(!tab||!tab.result)return;navigator.clipboard.writeText(JSON.stringify(tab.result,null,2)).then(()=>toast('Copied to clipboard'))}
document.addEventListener('keydown',e=>{if(e.ctrlKey&&e.key==='k'){e.preventDefault();$('searchBox').focus()}if(e.ctrlKey&&e.key==='r'){e.preventDefault();runSelected()}if(e.ctrlKey&&e.key==='e'){e.preventDefault();exportResult()}});
loadKey();loadCatalog();loadHealth();setInterval(loadHealth,10000);
document.documentElement.setAttribute('data-theme',theme);
if('serviceWorker' in navigator){navigator.serviceWorker.register('/sw.js').catch(()=>{})}
</script></body></html>
'@

# -----------------------------------------------------------------------
#  HTTP helpers
# -----------------------------------------------------------------------
function Write-MSPHttpJson($Response, $Obj, [int]$Code=200) {
    $Response.StatusCode = $Code; $Response.ContentType = 'application/json'
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Obj | ConvertTo-Json -Depth 10))
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.Close()
}
function Write-MSPHttpHtml($Response, $Html, [int]$Code=200) {
    $Response.StatusCode = $Code; $Response.ContentType = 'text/html; charset=utf-8'
    $bytes = [Text.Encoding]::UTF8.GetBytes($Html)
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.Close()
}
function Test-MSPAuth($Request) {
    if ($Request.IsLocal -and (-not $cfg.security.requireApiKeyForLocalhost)) { return $true }
    return ($Request.Headers['X-Api-Key'] -eq $apiKey)
}

# Request loop
try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $req = $ctx.Request; $res = $ctx.Response
        $path = $req.Url.AbsolutePath; $method = $req.HttpMethod
        try {
            if ($path -eq '/' -and $method -eq 'GET') { Write-MSPHttpHtml $res $uiHtml; continue }
            if ($path -eq '/manifest.json' -and $method -eq 'GET') {
                $manifestContent = Get-Content (Join-Path $PSScriptRoot '..\assets\manifest.json') -Raw -ErrorAction SilentlyContinue
                $res.ContentType = 'application/manifest+json'
                $bytes = [Text.Encoding]::UTF8.GetBytes($manifestContent)
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
                $res.Close(); continue
            }
            if ($path -eq '/sw.js' -and $method -eq 'GET') {
                $swJs = @'
const CACHE='sentinel-recon-v25';
self.addEventListener('install',e=>{e.waitUntil(caches.open(CACHE).then(c=>c.addAll(['/'])).then(()=>self.skipWaiting()))});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(n=>n!==CACHE).map(n=>caches.delete(n)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',e=>{e.respondWith(caches.match(e.request).then(r=>r||fetch(e.request).then(res=>{if(res.ok){const clone=res.clone();caches.open(CACHE).then(c=>c.put(e.request,clone))}return res})))}
'@
                $res.ContentType = 'application/javascript'
                $bytes = [Text.Encoding]::UTF8.GetBytes($swJs)
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
                $res.Close(); continue
            }
            if ($path -like '/api/*' -and -not (Test-MSPAuth $req)) { Write-MSPHttpJson $res @{error='unauthorized'} 401; continue }

            switch -Regex ($path) {
                '^/api/health$' {
                    try {
                        $facts = Get-MSPPlatformFacts
                        $plat = Get-MSPPlatform
                        $pendingReboot = Test-MSPPendingReboot
                        Write-MSPHttpJson $res @{
                            computerName=$facts.ComputerName; cpuPercent=0; memoryUsagePercent=0
                            diskFreeGB=0; uptimeHours=0; pendingReboot=$pendingReboot.PendingReboot
                            platform=$plat.Platform; timestamp=(Get-Date).ToString('o')
                        }
                    } catch {
                        try {
                            if ($plat.IsWindows) {
                                $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
                                $cpu = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue).CounterSamples.CookedValue
                                $diskC = Get-PSDrive C -ErrorAction SilentlyContinue
                                Write-MSPHttpJson $res @{
                                    computerName=$env:COMPUTERNAME; cpuPercent=[math]::Round($cpu); memoryUsagePercent=[math]::Round((($os.TotalVisibleMemorySize-$os.FreePhysicalMemory)/$os.TotalVisibleMemorySize)*100)
                                    diskFreeGB=[math]::Round($diskC.Free/1GB,1); uptimeHours=[math]::Round(((Get-Date)-$os.LastBootUpTime).TotalHours,1)
                                    pendingReboot=(Test-MSPPendingReboot).PendingReboot; platform='Windows'; timestamp=(Get-Date).ToString('o')
                                }
                            } else {
                                $facts = Get-MSPPlatformFacts
                                Write-MSPHttpJson $res @{ computerName=$facts.ComputerName; cpuPercent=0; memoryUsagePercent=0; diskFreeGB=0; uptimeHours=0; pendingReboot=(Test-MSPPendingReboot).PendingReboot; platform=$plat.Platform; timestamp=(Get-Date).ToString('o') }
                            }
                        } catch { Write-MSPHttpJson $res @{ computerName=$env:COMPUTERNAME; cpuPercent=0; memoryUsagePercent=0; diskFreeGB=0; uptimeHours=0; pendingReboot=$false; platform='Unknown'; timestamp=(Get-Date).ToString('o') } }
                    }
                }
                '^/api/scripts$' {
                    $q = $req.QueryString['q']; $list = $Script:Catalog
                    if ($q) { $list = $list | Where-Object { $_.name -like "*$q*" -or $_.cat -like "*$q*" -or $_.desc -like "*$q*" } }
                    Write-MSPHttpJson $res @($list)
                }
                '^/api/scripts/run$' {
                    if ($method -ne 'POST') { Write-MSPHttpJson $res @{error='method'} 405; break }
                    $body = (New-Object IO.StreamReader($req.InputStream)).ReadToEnd() | ConvertFrom-Json
                    $tool = $Script:Catalog | Where-Object id -eq $body.id | Select-Object -First 1
                    if (-not $tool) { Write-MSPHttpJson $res @{error='unknown tool'} 404; break }
                    $scriptPath = Join-Path $PSScriptRoot $tool.path
                    if (-not (Test-Path $scriptPath)) { Write-MSPHttpJson $res @{error="script missing: $scriptPath"} 500; break }
                    $sb = [scriptblock]::Create("& '$scriptPath'")
                    $jobId = New-MSPApiJob -Tool $tool.id -Block $sb -Args @{}
                    Write-MSPHttpJson $res @{ jobId=$jobId; tool=$tool.id; startedAt=(Get-Date).ToString('o') }
                }
                '^/api/jobs/(?<id>[a-f0-9]+)/result$' { $id=$matches.id; $j=Update-MSPJobStatus -Id $id; if(-not $j){Write-MSPHttpJson $res @{error='not found'} 404}else{Write-MSPHttpJson $res $j.Result} }
                '^/api/jobs/(?<id>[a-f0-9]+)$' { $id=$matches.id; $j=Update-MSPJobStatus -Id $id; if(-not $j){Write-MSPHttpJson $res @{error='not found'} 404}else{Write-MSPHttpJson $res @{id=$j.Id;tool=$j.Tool;status=$j.Status;startedAt=$j.StartedAt}} }
                '^/api/jobs$' { $l=$Script:Jobs.Values|%{@{id=$_.Id;tool=$_.Tool;status=$_.Status;startedAt=$_.StartedAt}}; Write-MSPHttpJson $res @($l) }
                '^/api/inventory$' {
                    try { $facts = Get-MSPOSFacts -Refresh; Write-MSPHttpJson $res $facts } catch {
                        try { $p = Get-MSPPlatformFacts; Write-MSPHttpJson $res $p } catch { Write-MSPHttpJson $res @{error='inventory unavailable'} 500 }
                    }
                }
                '^/api/export/(?<id>[a-f0-9]+)$' {
                    $id=$matches.id; $j=Update-MSPJobStatus -Id $id
                    if(-not $j){Write-MSPHttpJson $res @{error='not found'} 404;break}
                    $res.AddHeader('Content-Disposition','attachment; filename=msp_'+$j.Tool+'_'+$id+'.json')
                    Write-MSPHttpJson $res $j.Result
                }
                default { Write-MSPHttpJson $res @{error='not found';path=$path} 404 }
            }
        } catch { Write-MSPHttpJson $res @{error=$_.Exception.Message} 500 }
    }
} finally {
    $listener.Stop(); $listener.Close(); $Script:RunspacePool.Close(); $Script:RunspacePool.Dispose()
    Write-Host "  Server stopped." -ForegroundColor DarkGray
}
