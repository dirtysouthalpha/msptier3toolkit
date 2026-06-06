# Sentinel Recon

[![CI](https://img.shields.io/badge/CI-PowerShell%205.1%20%26%207-blue)]()
[![License](https://img.shields.io/badge/license-MIT-green)]()
[![Version](https://img.shields.io/badge/version-25.0.0-blueviolet)]()
[![Multi-tenant](https://img.shields.io/badge/multi--tenant-yes-success)]()
[![Audit](https://img.shields.io/badge/audit-HMAC--chained-orange)]()
[![Orchestrator](https://img.shields.io/badge/orchestrator-DAG%20engine-success)]()
[![Portable](https://img.shields.io/badge/portable-159%20files-brightgreen)]()
[![GUI](https://img.shields.io/badge/GUI-WPF-blue)]()

**Cross-Platform MSP Diagnostics & Automation Platform**

*Discover. Diagnose. Deploy.* -- The complete field toolkit for MSP Tier-3 engineers.

Built from the ground up around three ideas:

1. **Every script returns the same JSON-shaped result** -- so the API,
   dashboard, fleet runner, and your PSA can all parse output the same way.
2. **Fan out to a thousand boxes in parallel without spawning a thousand
   shells** -- runspace-based fleet runner instead of `Start-Job`.
3. **No SDK bloat** -- Graph integration is ~150 lines, no 600 MB
   `Microsoft.Graph` install required.

---

## Quick start

### Option A -- Portable, single-file (USB stick / drag-drop)

```powershell
# Build the portable bundle once
.\Build\Build-MSPPortable.ps1
# -> dist\MSPToolkit.Portable.ps1   (single 0.5 MB file with EVERYTHING inside)
# -> dist\MSPToolkit.Portable.bat   (double-click launcher)
# -> dist\MSPToolkit.zip            (zip with the normal repo tree)
```

Copy the two `dist\` files to a USB stick. On any Windows 10/11 box, double-click the `.bat` -- it self-extracts to `%TEMP%` and launches the WPF GUI.

### Option B -- Run as a module

```powershell
Import-Module .\Core\MSPToolkit.psd1
.\MSP_Tier3_Toolkit\Security\Get-SecurityPostureScore.ps1
Import-Csv .\hosts.csv | Invoke-MSPFleet -ScriptPath .\MSP_Tier3_Toolkit\Security\BitLockerStatusCheck.ps1
.\Tools\Start-MSPApi.ps1 -OpenBrowser   # REST API + browser UI on :8080
```

### Option C -- Launch the WPF GUI directly

```powershell
.\GUI\MSPToolkit.GUI.ps1
```

---

## What's in the box

### Diagnostics
| Script | Purpose |
|---|---|
| `SystemHealthReport.ps1`        | Full system health snapshot |
| `RebootPendingCheck.ps1`        | Multi-signal pending-reboot detection (CBS, WU, CCM, etc.) |
| `EventLogAlertSummary.ps1`      | High-signal Errors/Warnings grouped by source + ID |
| `WindowsServiceAudit.ps1`       | Auto-start services that are stopped (+ optional repair) |
| `Get-PerformanceBaseline.ps1`   | CPU/memory/disk/network counter sampling with top processes |
| `Get-UserLogonReport.ps1`       | 4624/4625/4740 logon/failure/lockout summary |
| `BootTimeAnalyzer.ps1`          | Boot + shutdown duration analysis |

### Security
| Script | Purpose |
|---|---|
| `BitLockerStatusCheck.ps1`      | Per-volume protection, encryption %, key protectors |
| `AVStatusCheck.ps1`             | SecurityCenter2 + Defender state, signature freshness |
| `LocalAdminAudit.ps1`           | Members of local Administrators (LocalAccounts + `net` fallback) |
| `Get-PatchCompliance.ps1`       | Pending updates + install history via Microsoft.Update COM |
| `Get-SecurityPostureScore.ps1`  | 12-check 0-100 hardening score with remediation hints |

### Maintenance
| Script | Purpose |
|---|---|
| `Cleanup-Auto.ps1`              | Comprehensive system cleanup |
| `CleanupOldProfiles.ps1`        | SID-safe stale profile removal |
| `ScheduledTempCleanup.ps1`      | Curated temp-folder sweep for Task Scheduler |
| `OEMBloatwareRemover.ps1`       | Installed + provisioned AppX bloat remover |
| `WindowsUpdateFix.ps1`          | Reset WU components with backup |
| `PrinterSpoolerFix.ps1`         | Spooler restart + spool clear with backup |

### M365 / Active Directory
| Script | Purpose |
|---|---|
| `CheckADUserStatus.ps1`         | AD lockout + password status |
| `M365UserProvisioning.ps1`      | License + mailbox provisioning |
| `OneDriveSyncHealthCheck.ps1`   | OneDrive process / KFM / LastError audit |

### Cross-Platform (macOS + Linux)
| Script | Purpose |
|---|---|
| `Get-MacSystemReport.ps1`       | Full system_profiler report |
| `Get-MacDiskHealth.ps1`         | SMART, APFS, FileVault, Time Machine |
| `Get-MacNetworkSurvey.ps1`      | Airport scan, DNS, reachability |
| `Get-MacMDMStatus.ps1`          | MDM enrollment, bootstrap token |
| `Get-MacSecurityPosture.ps1`    | Gatekeeper, SIP, XProtect score |

### DC Operations
| Script | Purpose |
|---|---|
| `Get-ADReplicationHealth.ps1`   | Repadmin summary, USN drift, lingering objects |
| `Get-DNSZoneHealth.ps1`         | SOA serial, forwarders, scavenging |
| `Get-DHCPScopeReport.ps1`       | Scope utilization, BAD_ADDRESS |
| `Get-FSMORoleAudit.ps1`         | All 5 FSMO holders, reachability |
| `Get-GPOLinkReport.ps1`         | GPOs, links, WMI filters |
| `Invoke-DCDiagOrchestrator.ps1` | Targeted DCDiag, per-test results |

### Backup & DR
| Script | Purpose |
|---|---|
| `Get-VSSWriterHealth.ps1`       | VSS writers, auto-retry on failures |
| `Get-BackupStatus.ps1`          | WSB jobs + event log fallback |
| `Get-ShadowCopyReport.ps1`      | Per-volume shadows, schedule, storage |
| `Test-RestoreReadiness.ps1`     | WinRE, catalog, drivers, ready verdict |

### Cloud & Hybrid
| Script | Purpose |
|---|---|
| `Get-EntraConnectHealth.ps1`    | Sync cycles, connectors, PTA |
| `Get-IntuneCompliance.ps1`      | Device compliance dashboard |
| `Get-ConditionalAccessReport.ps1` | CA policy audit, MFA gaps |
| `Get-AzureVMInventory.ps1`      | VMs, sizes, cost estimates |
| `Get-ExchangeOnlineHealth.ps1`  | Mailboxes, transport, connectors |

### App & DB Health
| Script | Purpose |
|---|---|
| `Get-SQLServerHealth.ps1`       | Databases, backups, wait stats |
| `Get-IISAppPoolStatus.ps1`      | App pools, workers, recycles |
| `Get-ExchangeServerHealth.ps1`  | Queues, DAG, DBs, certs |
| `Get-ServiceDependencyMap.ps1`  | Dependency chains, dead deps |

### Network
| Script | Purpose |
|---|---|
| `FixMappedDrives.ps1`           | Test + repair mapped drives |
| `Test-NetworkPath.ps1`          | Ping + TCP + DNS + HTTP + traceroute against N targets |

### Inventory
| Script | Purpose |
|---|---|
| `Export-AssetInventory.ps1`     | PSA-ready hardware/software/BitLocker/AV export (JSON/CSV/HTML) |

---

## Core modules (`Core/MSPToolkit.psd1`)

| Module | What it provides |
|---|---|
| `MSPToolkit.Common`        | `New-MSPResult`, `Save-MSPResult`, `Get-MSPOSFacts`, `Invoke-MSPWithRetry`, `Test-MSPPendingReboot`, `Assert-MSPElevation` |
| `MSPToolkit.Config`        | `Get-MSPConfig`, `Set-MSPConfigValue`, `Initialize-MSPDirectories` |
| `MSPToolkit.Logging`       | `Write-MSPLog`, `Show-MSPBanner`, structured JSONL sidecar |
| `MSPToolkit.Remote`        | `Invoke-MSPRemoteScript`, credential vault |
| `MSPToolkit.Fleet`         | `Invoke-MSPFleet` -- runspace-pool parallel WinRM runner |
| `MSPToolkit.Notifications` | `Send-MSPNotification` -> Teams, Slack, Discord, SMTP |
| `MSPToolkit.Graph`         | Thin Microsoft Graph client (app-only OAuth, paging, throttling) |
| `MSPToolkit.PSA`           | `New-MSPTicket` for Generic / NinjaOne / ConnectWise Manage |
| `MSPToolkit.RMM`           | `Sync-MSPNinjaOneDevice`, `Sync-MSPBulkDeviceDiagnostics` -- bi-directional RMM integration |
| `MSPToolkit.Orchestrator`  | `New-MSPWorkflow`, `Invoke-MSPWorkflow` -- DAG engine + change management |
| `MSPToolkit.Reporting`     | `New-MSPDashboard`, `Export-MSPReport` -- executive BI + compliance reports |
| `MSPToolkit.Webhooks`      | `Register-MSPWebhook`, `New-MSPCustomTool` -- extensibility framework |
| `MSPToolkit.Orchestrator`  | `Save-MSPOrchestratorState`, `Restore-MSPOrchestratorState` -- persistence |
| `MSPToolkit.Webhooks`      | `Save-MSPWebhookState`, `Restore-MSPWebhookState` -- persistence |

---

## REST API + web console

`Tools\Start-MSPApi.ps1` boots an HTTP listener with:

- `GET /api/health` -- live CPU / memory / disk / uptime / pending-reboot
- `GET /api/scripts` -- script catalog
- `POST /api/scripts/run` `{"id":"posture"}` -- launches in background runspace
- `GET /api/jobs/<id>` -- poll job status
- `GET /api/jobs/<id>/result` -- fetch structured result
- `GET /api/inventory` -- cached OS facts
- `GET /` -- single-page dashboard (vanilla JS, no build step)

All `/api/*` routes require an `X-Api-Key` header. Set it in
`config.json -> webInterface.apiKey`. Localhost requests can bypass if
`security.requireApiKeyForLocalhost` is `false`.

---

## Standard result envelope

Every diagnostic emits this shape:

```json
{
  "schema": "msp-result/v1",
  "tool": "Get-SecurityPostureScore",
  "computerName": "WS-01",
  "userName": "alice",
  "status": "Warning",
  "summary": "Score 72/100 (9/12 checks passed)",
  "data": { ... },
  "errors": [],
  "metrics": { "Score": 72, "CheckCount": 12, "Passed": 9 },
  "timestamp": "2026-06-06T10:14:01.123Z",
  "sessionId": "abc123def456"
}
```

`status` is one of `Success | Warning | Failure | Skipped`.

---

## Tests + CI

```powershell
.\Tests\Invoke-Tests.ps1
```

GitHub Actions (`.github/workflows/ci.yml`) runs `PSScriptAnalyzer` plus
Pester across:

- Windows / PowerShell 5.1
- Windows / PowerShell 7
- Ubuntu / PowerShell 7

---

## Requirements

- **PowerShell 5.1** (built into Win10/11) or **PowerShell 7+**
- **Administrator** for the scripts that touch services, the registry,
  Security log, BitLocker, or AppX provisioning
- **WinRM** enabled on targets for `Invoke-MSPFleet`
- **Entra app registration** for any `Graph` cmdlets

---

## Contributing

PRs welcome. Keep these conventions:

- Scripts return `New-MSPResult` objects.
- Anything destructive supports `-WhatIf` and `-Confirm`.
- No new dependencies without a discussion in an issue first.
- Add a Pester test under `Tests/` for new core helpers.

---

**Sentinel Recon v25.0.0** · 159 files, 110 functions, 15 categories, Windows + macOS + Linux
