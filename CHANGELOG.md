# Changelog

## v25.0.0 -- Sentinel Recon Rebrand
**June 2025** | 159 files, 110 exported functions, 1.24 MB bundle

### Launch
- **PWA:** Installable Sentinel Recon Console with manifest.json, service worker, theme-color meta, and inline favicon
- **Bundle renamed:** `SentinelRecon.Portable.ps1` + `SentinelRecon.Portable.bat` (161 files, 1.25 MB, hash `CB077CFD04BA593D`)
- **Product page:** `LAUNCH.md` -- full architecture overview, brand guide, deploy matrix
- **Logo:** `assets/logo.svg` with animated scanning line + PWA manifest

### Rebrand
- **Name:** Sentinel Recon -- Cross-Platform MSP Diagnostics & Automation
- **Tagline:** *Discover. Diagnose. Deploy.*
- **Brand family:** Joins Sentinel Override and Sentinel Desktop under the Sentinel product line
- **New logo:** Crosshair/reticle motif in Sentinel Cyan (`#00F0FF`) with scanning line animation -- `assets/logo.svg`
- **GUI theme:** Pulled from Sentinel Override DNA -- deep navy `#050608` background, cyan `#00F0FF` accent, lime `#95E400` success, amber `#FBBC00` warning, Space Grotesk headlines
- **CLI banner:** Full ASCII art "SENTINEL RECON" display with cross-platform tagline
- **Manifest:** Author -> "Sentinel Recon contributors", Company -> "Sentinel", updated URIs
- **README:** Rebranded header, tagline, footer
- **Console:** "Sentinel Recon Console" with branded export filenames (`sentinel_recon_*.json`)

### Features
- **Persistence for Orchestrator & Webhooks** -- auto-save/restore from `$env:APPDATA\MSPToolkit`
- **8 Linux diagnostic scripts** -- System, Disk, Security, Network, Services, Packages, Users, Docker, Kernel
- **11 playbook JSONs** -- AD Health, Network Deep, Security Audit, Tenant Onboard, Backup Verify, Exchange, Cloud, SQL, RMM, Weekly Maint, Linux Onboard, User Offboard
- **GUI catalog:** 89 tools across 15 categories

---

## v20.0.0 -- Complete Platform

### v21 -- Persistence Layer & Tests
- **Persistence for Orchestrator:** `Save-MSPOrchestratorState` / `Restore-MSPOrchestratorState` -- workflows, maintenance windows, change requests auto-saved to `$env:APPDATA\MSPToolkit\orchestrator.json`
- **Persistence for Webhooks:** `Save-MSPWebhookState` / `Restore-MSPWebhookState` / `Save-MSPPluginState` -- webhooks, delivery history, and plugins survive module reloads
- **Tests:** Pester test structures for Orchestrator and Webhooks modules

### v22 -- Linux Support
- **8 Linux diagnostic scripts:** `Get-LinuxSystemReport` (OS/kernel/cpu/mem/load), `Get-LinuxDiskHealth` (SMART/FS/inodes/IOWait), `Get-LinuxSecurityPosture` (firewall/SELinux/SSH/updates), `Get-LinuxNetworkSurvey` (interfaces/DNS/routing), `Get-LinuxServiceAudit` (systemd failed/disabled), `Get-LinuxPackageAudit` (apt/rpm/pkg updates), `Get-LinuxUserAudit` (users/sudo/SSH keys/logins), `Get-LinuxDockerHealth` (containers/images/volumes), `Get-LinuxKernelHardening` (ASLR/NX/core dumps/sysctl)

### v23 -- Playbook Library
- **11 production playbooks:** AD Health Check, Network Diagnostics Deep, Full Security Audit, Tenant Onboarding, Backup Verification, Exchange Server Health, Cloud Tenant Audit, SQL Server Health, RMM Platform Health, Weekly Maintenance, User Offboarding Complete, Linux System Onboard

### v24 -- GUI Catalog Expansion
- **89 tools** across 15 categories (new: Linux, Docker)
- **v25 badge** in web console

### v25 -- Final Polish
- **Manifest:** v25.0.0 with persistence function exports
- **Bundle:** 159 files, 1.19 MB, hash B3DD5C0D5638D42D
- **Multi-platform parity:** Windows + macOS + Linux with full diagnostic coverage

---

## v20.0.0 -- Complete Platform
**June 2025** | 136 files, 105 exported functions, 1.12 MB bundle

### v13 -- RMM Deep Integration
- **4 RMM health checkers:** `Get-NinjaOneHealth.ps1`, `Get-ConnectWiseIntegration.ps1`, `Test-DattoBackupStatus.ps1`, `Get-AutotaskTicketSync.ps1` -- scored health reports for all major RMM platforms
- **`Integrations/MSPToolkit.RMM.psm1`** -- 8 functions: NinjaOne device sync/ticketing, ConnectWise config/ticketing, Datto component deployment, Autotask ticketing, diagnostic-to-ticket pipeline, bulk device sync

### v14 -- Cloud & Hybrid Operations
- **6 cloud scripts:** `Get-EntraConnectHealth.ps1` (sync cycles, connectors, PTA), `Get-IntuneCompliance.ps1` (device compliance, non-compliant reasons), `Get-ConditionalAccessReport.ps1` (CA policy audit, MFA gaps, broad exclusions), `Get-AzureVMInventory.ps1` (VM sizes, cost estimates, regions), `Get-ExchangeOnlineHealth.ps1` (mailboxes, transport rules, connectors), `Get-TeamsCallQuality.ps1` (network readiness, latency, CQD)

### v15 -- Application & Database Health
- **6 app health scripts:** `Get-SQLServerHealth.ps1` (databases, backups, wait stats, error logs), `Get-IISAppPoolStatus.ps1` (app pools, worker processes, recycles), `Get-ExchangeServerHealth.ps1` (queues, DAG, databases, certificates), `Get-ServiceDependencyMap.ps1` (dependency chains, dead-dependency detection), `Get-PrintServerReport.ps1` (printers, queues, drivers, spooler crashes), `Get-AppPerformanceBaseline.ps1` (multi-sample CPU/memory/handle baselines)

### v16 -- Orchestration & Change Management
- **`Core/MSPToolkit.Orchestrator.psm1`** -- 10 functions: DAG workflow engine with parallel execution/resolution/cycle detection, maintenance windows with scheduling, change management with approval workflow, workflow stop/resume with checkpointing

### v17 -- Business Intelligence & Reporting
- **`Core/MSPToolkit.Reporting.psm1`** -- 7 functions: executive HTML dashboard, SLA metrics tracker, cost optimizer (license/VM savings), compliance report generator, multi-format report exporter (HTML/CSV/JSON), tenant scorecard, utilization trend analyzer

### v18 -- Community & Extensibility
- **`Core/MSPToolkit.Webhooks.psm1`** -- 8 functions: plugin marketplace (install/browse/publish), custom tool builder (JSON template to compliant .ps1), OpenAPI 3.0 spec generator, webhook engine (register/dispatch/history with HMAC signing)

### v19 -- Advanced Network Diagnostics
- **6 network scripts:** `Get-PacketCapture.ps1` (pktmon capture, retransmit/reset analysis), `Get-NetworkTopology.ps1` (ARP+traceroute topology map), `Test-SNMPWalk.ps1` (OID polling, device discovery), `Test-LANThroughput.ps1` (iperf3 TCP/UDP with SMB fallback), `Get-ARPCacheAudit.ps1` (duplicate IPs, rogue devices, OUI lookup), `Test-BandwidthSaturation.ps1` (graduated load testing, saturation point detection)

### v20 -- Final Polish
- **Manifest:** v20.0.0 with 4 new nested modules, 32 new exported functions (105 total), expanded tags
- **GUI Catalog:** 78 tools across 12 categories (Backup, Security, RMM, Cloud, Apps, Network, plus existing)
- **Bundle:** 136 files, 1.12 MB, hash B64E65C9516C05E1
- **Quality:** Critical bugs fixed -- job module loading, workflow job scoping, Exchange 2016+ compatibility, pktmon filter isolation, iperf3 server detection

---

## v12.0.0 -- Backup & Security Suite

## 12.0.0 -- 2026-06-06

### Added -- Backup & DR Verification + Advanced Security Suite

**v11 -- Backup & Disaster Recovery**
- 6 new diagnostic scripts under `MSP_Tier3_Toolkit/Backup/`:
  - `Get-VSSWriterHealth.ps1` -- all VSS writers, state, optional auto-retry
  - `Get-BackupStatus.ps1` -- WSB job history, last good backup age, event log fallback
  - `Test-SystemStateIntegrity.ps1` -- BCD, critical system files, registry hives, WinRE -- 0-100 score
  - `Get-ShadowCopyReport.ps1` -- per-volume shadow copies, schedule, storage
  - `Test-RestoreReadiness.ps1` -- WinRE, catalog, drivers, disk layout, EFI -- block/no-block verdict
  - `Get-RecoveryPartitionStatus.ps1` -- WinRE state, partition info, version match, sizing

**v12 -- Advanced Security & Compliance**
- 7 new diagnostic scripts under `MSP_Tier3_Toolkit/Security/`:
  - `Get-FullCISBenchmark.ps1` -- 30-control CIS Level 1 scorecard with per-category scoring
  - `Get-FirewallRiskAudit.ps1` -- risk-scored inbound rules (Any/Any, edge traversal, broad ports)
  - `Get-CertificateInventory.ps1` -- all certs across stores, expiry timeline, weak algo detection
  - `Test-LAPSDeployment.ps1` -- LAPS presence, password rotation age, AD-backed check
  - `Get-CredentialGuardState.ps1` -- VBS, HVCI, Credential Guard, LSASS protection, Secure Launch
  - `Get-SecureBootTPMState.ps1` -- Secure Boot, TPM version/PCR banks, firmware type
  - `Get-ExploitGuardConfig.ps1` -- ASR rules, network protection, controlled folder access, exploit protection

### Changed
- **`Core/MSPToolkit.psd1`** -- bumped to v12.0.0
- **Portable bundle** rebuilt: 108 files, 0.91 MB, hash AA1E9AB84E1ADD87

## 10.0.0 -- 2026-06-06

### Added -- Cross-Platform Engine + DC Operations Toolkit + GUI v2

**v9 -- Cross-Platform (macOS + Linux)**
- **`MSPToolkit.Platform.psm1`** -- OS detection, elevation, unified facts,
  disk/network/security/pending-reboot, native command wrapper, path normalization,
  and local user enumeration across Windows, macOS, and Linux.
- **10 Mac diagnostic scripts** under `MSP_Tier3_Toolkit/Mac/`:
  - `Get-MacSystemReport.ps1` -- full system_profiler -> MSP result
  - `Get-MacDiskHealth.ps1` -- SMART, APFS, FileVault, Time Machine
  - `Get-MacNetworkSurvey.ps1` -- airport WiFi scan, DNS, interfaces
  - `Get-MacProfileAudit.ps1` -- MDM enrollment, config profiles
  - `Get-MacFileVaultStatus.ps1` -- FileVault + recovery key escrow
  - `Get-MacMDMStatus.ps1` -- MDM, bootstrap token, KEXT policy
  - `Get-MacSecurityPosture.ps1` -- 12-check 0-100 hardening score
  - `Get-MacStartupHealth.ps1` -- LaunchAgents/Daemons, kexts
  - `Test-MacUpdateStatus.ps1` -- softwareupdate + XProtect freshness
  - `Reset-MacNetworkStack.ps1` -- DNS flush, DHCP renew, mDNS restart

**v10 -- Domain Controller Operations**
- **`MSPToolkit.DC.psm1`** -- DC enumeration, site mapping, FSMO inventory,
  repadmin wrapper, port checker, AD database info, password policy,
  LDAP bind test, KRBTGT health.
- **10 DC diagnostic scripts** under `MSP_Tier3_Toolkit/DC/`:
  - `Get-ADReplicationHealth.ps1` -- replsummary, lingering, USN drift
  - `Get-DNSZoneHealth.ps1` -- SOA serial, forwarders, scavenging, conflicts
  - `Get-DHCPScopeReport.ps1` -- utilization %, BAD_ADDRESS, exclusions
  - `Get-FSMORoleAudit.ps1` -- 5 FSMO holders with reachability + scoring
  - `Get-GPOLinkReport.ps1` -- GPOs, links, WMI filters, orphan detection
  - `Invoke-DCDiagOrchestrator.ps1` -- targeted DCDiag, per-test results
  - `Get-KerberosHealth.ps1` -- KRBTGT, duplicate SPNs, unconstrained delegation
  - `Test-TrustHealth.ps1` -- secure channel, SID filtering, name routing
  - `Get-ADUserBulkReport.ps1` -- stale, expiring, locked, disabled users
  - `Get-SYSVOLHealth.ps1` -- DFSR state, policy counts across DCs

**GUI v2 -- Web Console Rewrite**
- **`Tools/Start-MSPApi.ps1`** -- complete rewrite into single-file SPA:
  - Collapsible sidebar with fuzzy search
  - Dark/light theme toggle (persisted)
  - Multi-tab execution with live status polling
  - Live metrics dashboard (CPU, RAM, disk, uptime, reboot, platform)
  - Favorites + recent tools (localStorage)
  - Keyboard shortcuts (Ctrl+K search, Ctrl+R run, Ctrl+E export)
  - Export JSON + copy to clipboard
  - Toast notifications on job completion
  - Inline status pills (Success/Warning/Failure/Running)
  - Responsive layout (mobile-friendly)
  - 38-tool catalog (Windows + Mac + DC categories)
  - ADMIN/PLATFORM badges per tool
- **`ROADMAP_v9_v18.md`** -- full 10-version blueprint through v18

### Changed
- **`Core/MSPToolkit.psd1`** -- bumped to v10.0.0, added Platform + DC
  nested modules, 19 new exported functions, expanded tags
- **`Test-MSPPendingReboot`** -- now in Platform.psm1 as the canonical
  cross-platform version (macOS and Linux support added)
- **`Test-MSPElevation`** -- Platform.psm1 adds macOS root detection,
  shadows the Common.psm1 Windows-only version

### Added Tests
- `Tests/MSPToolkit.Platform.Tests.ps1` -- 13 Pester tests
- `Tests/MSPToolkit.DC.Tests.ps1` -- 10 Pester tests

### Metrics
- New files: 25 (2 modules + 10 Mac scripts + 10 DC scripts + 2 tests + roadmap)
- New exported functions: 19 (10 Platform + 9 DC)
- New Pester tests: 23
- GUI catalog: expanded from 16 to 38 tools

### Added -- Multi-tenant MSP Operations Platform
- **`MSPToolkit.Tenant`** -- per-tenant credential vault (DPAPI per-machine
  encrypted XML), tenant selection (`Select-MSPTenant`), `Invoke-MSPAcross`
  fan-out across every registered tenant.
- **`MSPToolkit.Audit`** -- append-only, HMAC-SHA256 chained audit log
  (`<Logs>\audit.jsonl`) with `Write-MSPAudit` and `Test-MSPAuditChain`
  for tamper detection. Includes Pester coverage that verifies a
  deliberate mid-chain modification breaks verification at the right
  index.
- **`Inventory\Get-CrossTenantReport.ps1`** -- runs License / Risk /
  Users / Custom queries across every tenant, flattens results to one
  CSV per report.

## 7.0.0 -- 2026-06-06

### Added -- Playbook Engine + Self-Healing
- **`MSPToolkit.Playbook`** -- JSON-driven decision-tree remediation
  runner with per-step retry, verify, rollback, and timeout. Re-checks
  overall verify between steps so it stops as soon as the box is
  healthy.
- **Bundled playbooks** under `Playbooks/`:
  - `Fix-Printing.json` -- five-step print-failure recovery
  - `Fix-OutlookHang.json` -- escalating fixes ending at OST nuke
  - `Fix-NoInternet.json` -- DHCP renew -> DNS flush -> ARP -> winsock
- **`Security\Get-CISBenchmarkScore.ps1`** -- 30-control CIS-subset
  hardening scorecard (account lockout, SMB signing, NTLM, BitLocker,
  Defender ASR, etc.).
- **`Security\Install-RansomwareCanary.ps1`** + **`Test-RansomwareCanary.ps1`**
  -- seeds canary files in high-priority locations and registers a
  5-minute Scheduled Task to detect tampering; auto-fires
  `Send-MSPNotification` + `New-MSPTicket` on drift.

## 6.0.0 -- 2026-06-06

### Added -- Field Network Diagnostics
- `Network\Get-WiFiSurvey.ps1` -- current association, visible BSSIDs by
  signal, 2.4 GHz channel-overlap, driver roam aggressiveness
- `Network\Test-DNSDeepDive.ps1` -- per-server resolution timing across
  configured + public resolvers with split-brain detection
- `Network\Test-M365Endpoints.ps1` -- full reachability matrix of
  Microsoft's published M365 endpoint catalog, bucketed by service area
- `Network\Get-NeighborDiscovery.ps1` -- LLDP/CDP neighbour discovery via
  NDIS cache + pktmon capture
- `Network\Test-CaptivePortal.ps1` -- multi-probe captive portal
  detection with redirect URL surfacing
- `Network\Test-MTU.ps1` -- binary-search Path-MTU discovery via DF-bit
  ping with interface MTU mismatch detection
- `Network\Test-VPNHealth.ps1` -- installed clients, tunnel adapter
  state, split-tunnel route detection, DNS leak test

## 5.0.0 -- 2026-06-06

### Added -- Account Lifecycle Wizards
- `Lifecycle\Invoke-UserOnboarding.ps1` -- AD + Entra + groups + license +
  OneDrive + welcome email + PSA ticket, driven by JSON template
- `Lifecycle\Invoke-UserOffboarding.ps1` -- preserve-then-disable
  workflow: snapshot, block sign-in, reset password, revoke sessions,
  set OOO, remove groups, reclaim licenses, AD disable + move OU
- `Lifecycle\Reset-UserPasswordEverywhere.ps1` -- cross-stack reset (AD +
  Entra + revoke refresh tokens + optional MFA method wipe)
- `Lifecycle\Unlock-ADUserWithFailover.ps1` -- finds the DC with the
  most recent lockout (event 4740), unlocks on lockout source AND
  PDC emulator, surfaces the workstation that caused the lockout
- `Lifecycle\Get-LicenseRecoveryReport.ps1` -- finds zombie licenses,
  disabled-users-with-licenses, and quantifies monthly savings

## 4.0.0 -- 2026-06-06

### Added
- **WPF GUI** (`GUI\MSPToolkit.GUI.ps1`) -- native-feeling Windows desktop
  app with sidebar tool catalog, live CPU/memory/disk/uptime/reboot
  metrics, click-to-run, inline JSON results, export + copy buttons,
  splash screen. Self-aware: drops to console fallback on Server Core /
  headless boxes.
- **Portable single-file bundler** (`Build\Build-MSPPortable.ps1`) --
  packs every script + module into a single self-extracting `.ps1`
  (~0.5 MB), plus a `.bat` launcher for double-click use and a normal
  `.zip` for users who want to browse the tree. Drop on a USB stick and
  run on any client box without installing anything.
- **High-volume ticket fixers**:
  - `Workstation\Reset-OutlookCache.ps1` -- kill Outlook, blow away OST +
    AutoComplete + cached creds, optional profile reset
  - `Workstation\Repair-WindowsSearch.ps1` -- stop WSearch, delete
    Windows.edb, trigger rebuild
  - `Workstation\Get-QuickTriageReport.ps1` -- one-page client-friendly
    HTML triage report with hardware/disk/AV/BitLocker/events/network
    snapshot
  - `Network\Reset-NetworkStack.ps1` -- winsock + ip + DNS + ARP + nbtstat
    full reset with before/after snapshots and optional firewall reset

### Changed
- README quick-start now leads with the portable single-file path --
  that's the killer feature for field techs.

## 3.0.0 -- 2026-06-06

### Added
- **Module manifest** (`Core/MSPToolkit.psd1`) -- `Import-Module MSPToolkit`
  now loads every helper, integration, and the fleet runner in one call.
- **MSPToolkit.Common** -- shared helpers used everywhere: `New-MSPResult`,
  `Save-MSPResult`, `Get-MSPOSFacts`, `Test-MSPPendingReboot`,
  `Invoke-MSPWithRetry`, `Assert-MSPElevation`, `ConvertTo-MSPSize`,
  `Get-MSPPaths`.
- **Structured result envelope** (`msp-result/v1`) -- uniform JSON shape
  emitted by every diagnostic so the REST API, fleet runner, and downstream
  PSAs all parse the same way.
- **MSPToolkit.Fleet** -- `Invoke-MSPFleet` runspace-pool parallel WinRM
  runner. Sub-second per-host startup, throttled, with per-host timeout.
- **MSPToolkit.Notifications** -- `Send-MSPNotification` routes to Teams /
  Slack / Discord / SMTP; pipe an MSP result and theme/title are inferred.
- **MSPToolkit.Graph** -- thin Microsoft Graph client (~150 lines), app-only
  OAuth, automatic paging + throttling retry; no `Microsoft.Graph` SDK
  required. Helpers for users, licenses, password reset, account
  enable/disable, risky sign-in audit.
- **MSPToolkit.PSA** -- vendor-neutral `New-MSPTicket` with built-in
  backends for Generic webhook, NinjaOne, and ConnectWise Manage.
- **Real REST API + Web Console** (`Tools/Start-MSPApi.ps1`) -- replaces the
  placeholder web UI. Job queue, API-key auth, live dashboard.
- **New diagnostic scripts** (all in `MSP_Tier3_Toolkit/<category>/`):
  - `Diagnostics/RebootPendingCheck.ps1`
  - `Diagnostics/EventLogAlertSummary.ps1`
  - `Diagnostics/WindowsServiceAudit.ps1`
  - `Diagnostics/Get-PerformanceBaseline.ps1`
  - `Diagnostics/Get-UserLogonReport.ps1`
  - `Security/BitLockerStatusCheck.ps1`
  - `Security/AVStatusCheck.ps1`
  - `Security/LocalAdminAudit.ps1`
  - `Security/Get-PatchCompliance.ps1`
  - `Security/Get-SecurityPostureScore.ps1`
  - `Maintenance/ScheduledTempCleanup.ps1`
  - `Maintenance/OEMBloatwareRemover.ps1`
  - `M365/OneDriveSyncHealthCheck.ps1`
  - `Network/Test-NetworkPath.ps1`
  - `Inventory/Export-AssetInventory.ps1`
- **Pester 5 test suite** under `Tests/` with `Invoke-Tests.ps1` runner.
- **GitHub Actions CI** matrix across Windows PS 5.1, Windows PS 7,
  Ubuntu PS 7 -- runs PSScriptAnalyzer + Pester.
- **Structured JSONL logging** sidecar alongside the text log
  (`<log>.jsonl`) -- SIEM-ingest ready.

### Changed
- `config.json` gained `notifications.discordWebhookUrl`,
  `rmmIntegration.extra`, `graph`, `fleet`, and
  `security.requireApiKeyForLocalhost` sections.
- README rewritten around the new architecture.

### Fixed
- Removed PowerShell 7-only ternary operator from the Notifications
  module (the project supports PS 5.1).

## 2.0.0 (prior)
- See `CODE_QUALITY_IMPROVEMENTS.md` for the v2 hardening pass on the
  original scripts (WindowsUpdateFix, CleanupOldProfiles, PrinterSpoolerFix).
