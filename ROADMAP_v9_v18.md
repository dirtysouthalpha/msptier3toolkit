# 🚀 MSP Tier 3 Toolkit -- v9 -> v18 Roadmap

> **Strategy:** Cross-platform parity, DC/server depth, awesome web GUI, automation-first.
> **Status:** Planning complete. Implementation starting 2026-06-06.

---

## 📊 Current State (v8.0.0)

| Metric | Value |
|---|---|
| PowerShell files | 82 |
| Exported functions | 54 |
| Pester tests | 22/22 passing |
| Portable bundle size | 0.64 MB |
| Core modules | 11 (.psm1 files) |
| Diagnostic scripts | 30+ |
| Playbooks | 3 bundled |
| GUI | WPF (Windows-only) + Web API (HttpListener) |

### Current Module Architecture
```
Core/
  MSPToolkit.psd1              -- Module manifest (54 exports)
  MSPToolkit.Config.psm1       -- JSON config loader + setter
  MSPToolkit.Logging.psm1      -- Structured logging with JSONL sidecar
  MSPToolkit.Common.psm1       -- New-MSPResult, Get-MSPOSFacts, Test-MSPElevation, etc.
  MSPToolkit.Remote.psm1       -- WinRM remote execution
  MSPToolkit.Fleet.psm1        -- Runspace-pool parallel executor
  MSPToolkit.Playbook.psm1     -- JSON decision-tree remediation engine
  MSPToolkit.Tenant.psm1       -- DPAPI-encrypted multi-tenant vault
  MSPToolkit.Audit.psm1        -- HMAC-SHA256 chained tamper-evident audit log
Integrations/
  MSPToolkit.Notifications.psm1
  MSPToolkit.Graph.psm1
  MSPToolkit.PSA.psm1
```

---

## 🎯 v9.0 -- Cross-Platform Engine (macOS + Linux)

### Goal
Make the MSP Toolkit run on Macs and Linux boxes with the same structured result envelope, portable bundle concept, and tool catalog experience.

### New Module: `Core/MSPToolkit.Platform.psm1`

```powershell
# Exported functions:
Get-MSPPlatform              # Returns 'Windows'|'macOS'|'Linux' with version
Test-MSPElevation            # UPGRADE: adds macOS root detection
Get-MSPPlatformFacts         # Unified CPU/RAM/Disk/Network/Security per platform
Get-MSPDiskInfo              # Cross-platform disk (PSDrive / diskutil / lsblk)
Get-MSPNetworkInfo           # Cross-platform network adapters, IPs, DNS
Get-MSPSecurityStatus        # AV/Firewall/Encryption per platform
Test-MSPPendingReboot        # UPGRADE: adds macOS needsreboot detection
Invoke-MSPNativeCommand      # Safe platform-native command wrapper with timeout
ConvertTo-MSPPlatformPath    # Path normalization per platform
Get-MSPPlatformUsers         # Local user enumeration per platform
```

### New Scripts: `MSP_Tier3_Toolkit/Mac/`

| Script | Purpose | Admin |
|---|---|---|
| `Get-MacSystemReport.ps1` | Full system_profiler dump -> MSP result envelope | No |
| `Get-MacDiskHealth.ps1` | diskutil info, SMART status, APFS snapshot age, free space | No |
| `Get-MacNetworkSurvey.ps1` | WiFi scan (airport), interface stats, DNS config, proxy settings | No |
| `Get-MacProfileAudit.ps1` | `profiles show` for MDM/config profiles, enrollment state | No |
| `Get-MacFileVaultStatus.ps1` | fdesetup status, recovery key escrow, institutional key check | Yes |
| `Get-MacMDMStatus.ps1` | MDM enrollment, managed preferences, DEP status | No |
| `Reset-MacNetworkStack.ps1` | DNS flush, interface renew, Bonjour/mDNS restart, firewall reset | Yes |
| `Get-MacSecurityPosture.ps1` | Gatekeeper, SIP (csrutil), XProtect, firewall (pfctl), T2/Silicon security | No |
| `Get-MacStartupHealth.ps1`  | LaunchAgents/Daemons audit, login items, kernel extensions | No |
| `Test-MacUpdateStatus.ps1`  | softwareupdate pending, App Store updates, XProtect/gatekeeper data age | No |

### Upgraded Existing Functions

| Function | Change |
|---|---|
| `Get-MSPOSFacts` | Add macOS/Linux branches alongside Windows CIM calls |
| `Get-MSPPaths` | Platform-appropriate default paths (`~/Library/Logs/` for Mac) |
| `Test-MSPPendingReboot` | macOS: check `/private/var/db/.AppleSetupDone` + `softwareupdate` pending |
| `Test-MSPElevation` | macOS: `id -u` check for root (UID 0) |
| `ConvertTo-MSPSize` | Already platform-neutral (byte math) -- no changes needed |
| `New-MSPResult` | Already platform-neutral -- no changes needed |

### Portable Bundle v2

- **`dist/MSPToolkit.Portable.ps1`** -- continues for Windows
- **`dist/MSPToolkit.Portable.sh`** -- ★ NEW: self-extracting bash script for Mac/Linux
  - Embeds all .ps1/.psm1/.json files as base64
  - Requires PowerShell 7+ (pwsh) pre-installed
  - Extracts to `/tmp/MSPToolkit_<hash>/`
  - Launches web GUI (or console if no display)

### Tests
- `Tests/MSPToolkit.Platform.Tests.ps1` -- Pester tests for platform detection, path handling, elevation

---

## 🎯 v10.0 -- Domain Controller Operations Toolkit

### Goal
First-class tooling for the most common DC health checks MSPs do manually: AD replication, DNS, DHCP, FSMO, GPO, Kerberos, trusts.

### New Module: `Core/MSPToolkit.DC.psm1`

```powershell
# Exported functions:
Get-MSPDCList                # Enumerate DCs, detect RODC/RWDC/GC, OS version
Get-MSPSiteForDC             # Map DC -> AD site + subnet
Invoke-MSPRepAdmin           # Safe repadmin wrapper -> structured output
Test-MSPPortDC               # Required DC ports (53,88,135,389,445,3268,636,3269,9389)
Get-MSPFSMOInventory         # All FSMO role holders with connectivity check
Get-MSPADDatabaseInfo        # NTDS.dit size, white space, partition info
Get-MSPPasswordPolicy        # Fine-grained password policies, default domain policy
Test-MSPLDAPBind             # LDAP + LDAPS connectivity test with timing
Get-MSPKRBTGTInfo            # KRBTGT password age, rotation recommendation
```

### New Scripts: `MSP_Tier3_Toolkit/DC/`

| Script | Purpose | Key Data |
|---|---|---|
| `Get-ADReplicationHealth.ps1` | repadmin /replsummary, lingering objects, inter-site latency, USN drift | Last success, fail count, delta |
| `Get-DNSZoneHealth.ps1` | Per-zone SOA serial consistency, aging/scavenging config, forwarder resolution | Serial mismatch, scavenge state |
| `Get-DHCPScopeReport.ps1` | Scope utilization %, exclusions, reservations, lease distribution, BAD_ADDRESS count | % used, available, conflicts |
| `Get-FSMORoleAudit.ps1` | All 5 FSMO holders, connectivity, best-practice placement, role seizure risk | Each role: holder, reachable, RODC? |
| `Get-GPOLinkReport.ps1` | All GPOs, link order, enforced/disabled, WMI filter status, SYSVOL version mismatch | Per-GPO: links, filters, health |
| `Invoke-DCDiagOrchestrator.ps1` | Targeted DCDiag tests, parsed into MSP result envelope, per-test pass/fail | test: result, detail |
| `Get-KerberosHealth.ps1` | TGT analysis, duplicate SPNs, unconstrained delegation, KRBTGT age, ticket size trends | Duplicate SPNs, delegation audit |
| `Test-TrustHealth.ps1` | Inter-domain/forest trust validation, secure channel, SID filtering, name suffix routing | Trust: type, direction, status |
| `Get-ADUserBulkReport.ps1` | Stale users (lastLogon), password expiry pipeline, locked-out users across domain | Per-user: state, expiry, lockout |
| `Get-SYSVOLHealth.ps1` | SYSVOL share accessibility, DFSR/FRS state, file count consistency across DCs | Per-DC: SYSVOL state, DFSR state |

### Playbooks: `Playbooks/`

| Playbook | Steps | Verifies |
|---|---|---|
| `Repair-ADReplication.json` | Check connectivity -> force sync -> check again -> escalate if USN drift | replsummary passes |
| `Fix-DCHealth.json` | DCDiag baseline -> stop problem services -> re-test -> restart netlogon -> verify | DCDiag all pass |
| `Repair-DNSZone.json` | Check SOA -> scavenge stale -> check forwarders -> reload zone -> verify | All SOAs match |

### Upgrade to `Get-CrossTenantReport.ps1` (Inventory/)
- Add DC-specific report type: replication health across all tenant DCs
- Add DNS zone report type

---

## 🎨 GUI v2 -- "MSP Toolkit Console" (Web-Based)

### Goal
Replace the WPF GUI (Windows-only) with a single-file web app served by the existing HttpListener. Zero external dependencies. Works on Windows, Mac, and Linux. Works in any modern browser.

### Architecture

```
Tools/Start-MSPApi.ps1          ← Single file containing:
  ├── HttpListener server        (existing, upgraded)
  ├── Job registry               (existing, upgraded)
  ├── Script catalog             (existing, expanded)
  ├── Embedded HTML/CSS/JS       ★ NEW -- full SPA (replaces tiny current dashboard)
  ├── REST API routes            (existing, expanded)
  └── WebSocket server           ★ NEW -- optional PS 7 terminal (graceful fallback)
```

### GUI Feature Spec

#### Phase 1 -- Shell & Navigation
- **Layout:** Collapsible sidebar (280px -> 48px) with tool catalog, main content area
- **Dark/Light themes:** CSS custom properties, `prefers-color-scheme` auto, manual toggle saved to localStorage
- **Keyboard shortcuts:**
  - `Ctrl+K` -- Open command palette / search
  - `Ctrl+R` -- Run selected tool
  - `Ctrl+E` -- Export last result
  - `Ctrl+Shift+C` -- Copy result to clipboard
  - `Ctrl+/` -- Toggle sidebar
- **Toolbar:** Hostname, user, API key input, theme toggle, settings gear

#### Phase 2 -- Real-Time Dashboard
- **Live metrics:** CPU %, RAM %, disk free (per volume), uptime, pending reboot, admin status
- **Polling:** 2-second interval (configurable)
- **Sparklines:** Small inline charts for CPU/memory trend (last 60 samples)
- **SSE log stream:** Server-Sent Events endpoint streams `audit.jsonl` lines in real time
- **Job queue:** All running/completed jobs listed with status pills and progress bars

#### Phase 3 -- Smart Tool Catalog
- **Fuzzy search:** Type to filter by name, category, description, keyword tags
- **Favorites:** Star tools, persisted to localStorage
- **Recently used:** Last 10 tools auto-tracked
- **Category grouping:** Collapsible sections with tool counts
- **Admin badge:** Clear `[ADMIN]` indicator + elevation warning
- **Platform badge:** `[Win]` `[Mac]` `[Win/Mac]` compatibility badges

#### Phase 4 -- Multi-Tab Execution
- **Tabs:** Run multiple tools simultaneously, each in its own output tab
- **Tab state:** Running/Success/Warning/Failure color coding
- **Close/keep:** Close completed tabs or keep all
- **Re-run:** Re-run button per tab

#### Phase 5 -- Export & Share
- **Download JSON:** Save result as `.json` file
- **Copy to clipboard:** One-click copy
- **Export CSV:** Flatten result.data to CSV (when possible)
- **Print/PDF:** Print-friendly CSS, browser print-to-PDF
- **Share link:** Copy API endpoint URL for that specific result

#### Phase 6 -- Terminal Embed (PS 7+)
- **WebSocket terminal:** Full PowerShell session in-browser
- **Command history:** Up/down arrow
- **Auto-complete:** Tab completion
- **Output streaming:** Real-time stdout/stderr
- **Graceful fallback:** Hidden on PS 5.1, shown on PS 7+

#### Phase 7 -- PWA (Progressive Web App)
- **Service worker:** Cache tool catalog + shell for offline access
- **manifest.json:** Installable on desktop/mobile
- **App icon:** Toolkit logo
- **Offline indicator:** Banner when disconnected

### New API Routes

| Route | Method | Purpose |
|---|---|---|
| `GET /api/health/live` | GET | Real-time metrics (SSE stream) |
| `GET /api/audit/stream` | GET | Audit log SSE stream |
| `GET /api/scripts/search?q=` | GET | Fuzzy search across catalog |
| `POST /api/scripts/run-batch` | POST | Run multiple tools in parallel |
| `GET /api/export/:id/:format` | GET | Export result as JSON/CSV/HTML |
| `WS /ws/terminal` | WS | PS terminal (PS 7+ only) |
| `GET /manifest.json` | GET | PWA manifest |
| `GET /sw.js` | GET | Service worker |

### Design System

```css
/* Color Tokens */
--bg-primary:     #0a0e1a;    /* Main background */
--bg-secondary:   #141b2d;    /* Cards, panels */
--bg-tertiary:    #1e2746;    /* Hover states */
--border:          #2a3352;    /* Borders */
--text-primary:    #e8ecf4;    /* Main text */
--text-secondary:  #7a85a6;    /* Muted text */
--accent:          #5b6cfa;    /* Primary action */
--accent-hover:    #7b88ff;    /* Hover */
--success:         #21c186;    /* OK/Success */
--warning:         #e8a93b;    /* Warning */
--danger:          #e8505b;    /* Error/Failure */

/* Typography */
--font-sans:  'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
--font-mono:  'JetBrains Mono', 'Cascadia Code', 'Fira Code', 'Consolas', monospace;
```

---

## 🎯 v11.0 -- Backup & Disaster Recovery Verification

| Script | Purpose |
|---|---|
| `Get-VSSWriterHealth.ps1` | All VSS writers, state, last error, auto-retry on failures |
| `Get-BackupStatus.ps1` | Windows Server Backup job history, last good, next scheduled |
| `Test-SystemStateIntegrity.ps1` | Boot-critical files hash verification, registry hive health |
| `Get-ShadowCopyReport.ps1` | Per-volume shadow copies, schedule, space usage, oldest/newest |
| `Test-RestoreReadiness.ps1` | Simulated BMR check (validates backup metadata, no actual restore) |
| `Get-RecoveryPartitionStatus.ps1` | WinRE presence, reagentc status, version match to OS |

---

## 🎯 v12.0 -- Advanced Security & Compliance Suite

| Script | Purpose |
|---|---|
| `Get-FullCISBenchmark.ps1` | 150+ control CIS Level 1 benchmark (expand from 30-control subset) |
| `Get-FirewallRiskAudit.ps1` | Inbound/outbound rules with risk scoring on wide-open rules |
| `Get-CertificateInventory.ps1` | All certs across stores, expiry timeline, weak algorithm detection |
| `Test-LAPSDeployment.ps1` | Check LAPS presence, local admin password rotation age |
| `Get-CredentialGuardState.ps1` | VBS, LSASS protection, HVCI, Secure Launch |
| `Get-SecureBootTPMState.ps1` | UEFI Secure Boot, TPM version, PCR bank audit, attestation |
| `Get-ExploitGuardConfig.ps1` | Defender ASR, network protection, controlled folder access, attack surface reduction |

---

## 🎯 v13.0 -- RMM & PSA Deep Integration

| Integration | Sync Direction | Key Features |
|---|---|---|
| **NinjaOne** | Bi-directional | Device sync, custom fields from posture scores, automated ticketing |
| **ConnectWise Manage** | Bi-directional | Configuration sync, agreement mapping, time entry |
| **Datto RMM** | Outbound | Component deployment, monitor creation from toolkit scripts |
| **Autotask** | Outbound | Queue-based ticket routing with priority from diagnostics |
| **Generic Webhook** | Outbound | Already exists -- expand with templated payloads |

---

## 🎯 v14.0 -- Cloud & Hybrid Infrastructure

| Script | Purpose |
|---|---|
| `Get-EntraConnectHealth.ps1` | Sync cycle, connector space, export errors, last successful sync |
| `Get-HybridExchangeHealth.ps1` | Mailbox migration status, connector health, transport rules audit |
| `Get-IntuneCompliance.ps1` | Device compliance policy coverage, enrollment failures, config drift |
| `Get-ConditionalAccessAudit.ps1` | Policy coverage, risky sign-in correlation, gap analysis |
| `Get-M365ServiceHealth.ps1` | Service communications API, current incidents, advisory correlation |
| `Get-AzureVMInventory.ps1` | All VMs across subscriptions, cost estimation, idle detection |

---

## 🎯 v15.0 -- Application & Database Health

| Script | Purpose |
|---|---|
| `Get-SQLServerHealth.ps1` | DB size/auto-growth, index fragmentation, backup age, error log |
| `Get-IISAppPoolHealth.ps1` | Pool state, rapid-fail detection, worker process memory |
| `Get-ServiceDependencyMap.ps1` | Build trees, detect circular deps, orphaned services |
| `Get-ScheduledTaskHealth.ps1` | Last run result, missed runs, task overlap |
| `Get-PrintServerHealth.ps1` | Queue depth, driver isolation, spooler memory |
| `Get-ExchangeServerHealth.ps1` | DB mount state, queue length, DAG copy status |

---

## 🎯 v16.0 -- Workflow Orchestration Engine

| Component | Purpose |
|---|---|
| **DAG Engine** (`MSPToolkit.Orchestrator.psm1`) | Directed acyclic graph steps -- parallel branches, conditional paths, dependency resolution |
| **Maintenance Windows** | Calendar-based scheduling with blackout periods, timezone-aware |
| **Change Management** | Pre-execution approval, post-execution validation, audit trail |
| **Auto-Rollback** | Snapshot before changes, automated rollback on verify-fail |
| **ServiceNow/Jira Integration** | CR creation, task linking, evidence attachment |

---

## 🎯 v17.0 -- Reporting & Business Intelligence

| Component | Purpose |
|---|---|
| **Executive Dashboard** | Multi-tenant rollup -- posture scores, patch %, license $ savings |
| **SLA Tracker** | MTTR per ticket, tool success rate, per-tech metrics |
| **Trend Engine** | Time-series from repeated fleet runs, anomaly detection |
| **Cost Optimizer v2** | Zombie licenses, oversized Azure VMs, idle resources |
| **Client Reports** | Branded PDF/HTML one-pagers per tenant |
| **Compliance Pack** | Auto-generated evidence for SOC 2 / ISO 27001 |

---

## 🎯 v18.0 -- Community Platform & Extensibility

| Component | Purpose |
|---|---|
| **Plugin Marketplace** | GitHub-based registry of community scripts, versioned |
| **Custom Tool Builder** | GUI wizard to wrap any script into MSP result envelope |
| **Webhook Engine** | Outgoing webhooks with payload templates on tool events |
| **OpenAPI Spec** | Full REST API documentation with Swagger UI |
| **SDK + Docs** | Module SDK, contribution guide, video walkthroughs |
| **Telemetry (opt-in)** | Anonymized usage stats to prioritize development |

---

## 📁 Complete File Structure (v18 End-State)

```
msptier3toolkit/
├── Core/
│   ├── MSPToolkit.psd1                     ← Manifest (grows to ~100+ exports)
│   ├── MSPToolkit.psm1                     ← Root shim
│   ├── MSPToolkit.Audit.psm1               ← HMAC-chained audit (v8)
│   ├── MSPToolkit.Common.psm1              ← Result envelope, OS facts, retries (v3)
│   ├── MSPToolkit.Config.psm1              ← JSON config management (v3)
│   ├── MSPToolkit.DC.psm1                  ★ Domain controller operations (v10)
│   ├── MSPToolkit.Fleet.psm1               ← Runspace pool parallel executor (v3)
│   ├── MSPToolkit.Logging.psm1             ← Structured logging + JSONL (v3)
│   ├── MSPToolkit.Orchestrator.psm1        ★ DAG workflow engine (v16)
│   ├── MSPToolkit.Platform.psm1            ★ Cross-platform abstraction (v9)
│   ├── MSPToolkit.Playbook.psm1            ← JSON decision-tree runner (v7)
│   ├── MSPToolkit.Remote.psm1              ← WinRM remote execution (v3)
│   ├── MSPToolkit.Reporting.psm1           ★ BI + dashboards (v17)
│   ├── MSPToolkit.Tenant.psm1              ← Multi-tenant vault (v8)
│   └── MSPToolkit.Webhooks.psm1            ★ Outgoing webhook engine (v18)
│
├── Integrations/
│   ├── MSPToolkit.Graph.psm1               ← Microsoft Graph client (v3)
│   ├── MSPToolkit.Notifications.psm1       ← Teams/Slack/Discord/SMTP (v3)
│   ├── MSPToolkit.PSA.psm1                 ← NinjaOne/CW/Autotask (v3)
│   └── MSPToolkit.RMM.psm1                 ★ Deep RMM bi-directional sync (v13)
│
├── MSP_Tier3_Toolkit/
│   ├── Diagnostics/                        (6 scripts -- v3)
│   ├── Security/                           (7 scripts -- v3+v7+v12)
│   ├── Maintenance/                        (4 scripts -- v3)
│   ├── Network/                            (8 scripts -- v6)
│   ├── Workstation/                        (3 scripts -- v4)
│   ├── M365/                               (1 script -- v3)
│   ├── Lifecycle/                          (5 scripts -- v5)
│   ├── Inventory/                          (2 scripts -- v3+v8)
│   ├── Mac/                                ★ (10 scripts -- v9)
│   ├── DC/                                 ★ (10 scripts -- v10)
│   ├── Backup/                             ★ (6 scripts -- v11)
│   ├── Cloud/                              ★ (6 scripts -- v14)
│   ├── Apps/                               ★ (6 scripts -- v15)
│   └── SystemHealthReport.ps1, etc.
│
├── Playbooks/
│   ├── Fix-Printing.json                   (v7)
│   ├── Fix-OutlookHang.json                (v7)
│   ├── Fix-NoInternet.json                 (v7)
│   ├── Repair-ADReplication.json           ★ (v10)
│   ├── Fix-DCHealth.json                   ★ (v10)
│   ├── Repair-DNSZone.json                 ★ (v10)
│   ├── Fix-MacNetwork.json                 ★ (v9)
│   └── Recover-Backup.json                 ★ (v11)
│
├── Templates/
│   ├── NewHireProvisioning.json            (v5)
│   └── WorkstationMaintenance.json         (v3)
│
├── GUI/
│   ├── MSPToolkit.GUI.ps1                  ← WPF GUI (v4, retained as fallback)
│   └── web/                                ★ GUI v2 assets
│       ├── index.html
│       ├── app.js
│       └── styles.css
│
├── Tools/
│   ├── Start-MSPApi.ps1                    ★ UPGRADED -- GUI v2 server
│   ├── Start-WebInterface.ps1              ← Legacy (v3)
│   ├── Generate-Dashboard.ps1              ★ UPGRADED -- v17 reporting
│   ├── Invoke-Template.ps1                 (v3)
│   ├── Start-SelfHealing.ps1               (v7)
│   ├── Update-MSPToolkit.ps1               (v3)
│   └── Generate-CompliancePack.ps1         ★ (v17)
│
├── Tests/
│   ├── Invoke-Tests.ps1                    ← Test runner
│   ├── MSPToolkit.Audit.Tests.ps1          (v8)
│   ├── MSPToolkit.Common.Tests.ps1         (v3)
│   ├── MSPToolkit.Config.Tests.ps1         (v3)
│   ├── MSPToolkit.Notifications.Tests.ps1  (v3)
│   ├── MSPToolkit.Playbook.Tests.ps1       (v7)
│   ├── MSPToolkit.Platform.Tests.ps1       ★ (v9)
│   ├── MSPToolkit.DC.Tests.ps1             ★ (v10)
│   ├── MSPToolkit.Orchestrator.Tests.ps1   ★ (v16)
│   └── MSPToolkit.Reporting.Tests.ps1     ★ (v17)
│
├── Build/
│   └── Build-MSPPortable.ps1               ★ UPGRADED -- multi-platform bundle (v9)
│
├── dist/
│   ├── MSPToolkit.Portable.ps1             ← Windows bundle
│   ├── MSPToolkit.Portable.bat             ← Windows launcher
│   ├── MSPToolkit.Portable.sh              ★ Mac/Linux bundle (v9)
│   └── MSPToolkit.zip                      ← Full tree zip
│
├── config.json                             (v3, expanded per version)
├── README.md
├── CHANGELOG.md
├── ROADMAP.md                              ← Original roadmap
└── ROADMAP_v9_v18.md                       ★ This document
```

---

## 📊 Version Timeline & Metrics

| Version | New Files | New Functions | New Tests | Bundle Size Est. |
|---|---|---|---|---|
| v8.0 (current) | 82 | 54 | 22 | 0.64 MB |
| v9.0 (Platform) | +15 | +10 | +8 | ~0.85 MB |
| v10.0 (DC) | +16 | +12 | +10 | ~1.10 MB |
| v11.0 (Backup) | +8 | +4 | +6 | ~1.25 MB |
| v12.0 (Security) | +8 | +4 | +8 | ~1.40 MB |
| v13.0 (RMM) | +3 | +8 | +6 | ~1.55 MB |
| v14.0 (Cloud) | +7 | +5 | +6 | ~1.70 MB |
| v15.0 (Apps) | +7 | +5 | +6 | ~1.85 MB |
| v16.0 (Orchestrator) | +3 | +12 | +8 | ~2.00 MB |
| v17.0 (Reporting) | +5 | +10 | +6 | ~2.15 MB |
| v18.0 (Community) | +4 | +8 | +6 | ~2.30 MB |
| **v18.0 (total)** | **~158** | **~132** | **~92** | **~2.30 MB** |

---

## 🔧 Implementation Order (Parallel Tracks)

### Phase 1 -- Foundation (Now)
```
Track A: GUI v2 Shell (A1-A3)  ──┐
Track B: MSPToolkit.Platform.psm1 ──┼── Integration test ──► Phase 1 done
Track C: MSPToolkit.DC.psm1     ──┘
```

### Phase 2 -- Depth
```
Track A: GUI v2 Advanced (A4-A6)  ──┐
Track B: Mac scripts (8 of 10)     ──┼── Integration test ──► Phase 2 done
Track C: DC scripts (8 of 10)      ──┘
```

### Phase 3 -- Polish
```
Track A: GUI v2 PWA (A7)                    ──┐
Track B: Cross-platform existing upgrades     ──┼── Full integration ──► v9.0 + v10.0 + GUI v2 SHIP
Track C: DC playbooks + last 2 scripts       ──┘
```

### Phase 4 -- Expand (After v9+v10 ship)
```
v11--v18 built sequentially, ~2 weeks per version
```

---

## 🎨 GUI v2 Architecture Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Framework | Vanilla HTML/CSS/JS | Zero dependencies, works anywhere |
| Bundling | Single string in PowerShell | Matches current approach, no build step |
| CSS approach | CSS custom properties | Theme switching without re-render |
| State management | Plain JS objects + events | Simple, no framework needed |
| Real-time updates | Server-Sent Events (SSE) | Simpler than WebSocket, unidirectional is fine |
| Terminal | WebSocket (PS 7 only) | Only advanced feature needing PS 7 |
| Offline | Service Worker | PWA standard, caches shell + catalog |
| Charts | Canvas API (no library) | Small inline sparklines, no Chart.js |
| Accessibility | ARIA labels, keyboard nav | Required for professional tool |

---

## ⚠️ Key Design Principles (Carried Forward)

1. **Every script returns `New-MSPResult`** -- same envelope on Mac and Windows
2. **Zero dependencies** -- HttpListener, .NET Framework, nothing to install
3. **Portable single-file** -- drop on USB, run anywhere
4. **HMAC audit trail** -- tamper-evident logging for every privileged operation
5. **WhatIf + Confirm** -- every destructive action supports safety guards
6. **PS 5.1 compatible core** -- advanced features (WebSocket) are PS 7 opt-in
7. **No `any` type casts** -- strong typing throughout PowerShell functions

---

## 📋 Governance

- **Breaking changes:** Bump major version
- **New scripts:** Bump minor version
- **Fixes/patches:** Bump patch version
- **All PRs:** Must include Pester tests, pass PSScriptAnalyzer
- **Bundle rebuild:** Required after any file change; hash must update

---

*Last updated: 2026-06-06*
*Next milestone: v9.0 + v10.0 + GUI v2 ship target -- see Phase 1-3 above*
