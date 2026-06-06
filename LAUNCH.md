# Sentinel Recon v25 -- Product Launch

**June 2025**

---

## 🎯 What is Sentinel Recon?

**Sentinel Recon** is the cross-platform MSP diagnostics and automation platform built for Tier-3 engineers. It's the third product in the **Sentinel** family, alongside **Sentinel Override** (AI browser automation) and **Sentinel Desktop**.

> *Discover. Diagnose. Deploy.* -- 159 scripts, 110 functions, 15 categories. One portable file. Any platform.

---

## 🚀 Instant Deploy

```powershell
# Option A -- USB stick (zero install)
Copy dist\SentinelRecon.Portable.ps1 + dist\SentinelRecon.Portable.bat to USB
Double-click .bat on any Windows 10/11 box
-> Self-extracts -> Launches web console on :8080

# Option B -- Module import
Import-Module .\Core\MSPToolkit.psd1
Get-SecurityPostureScore

# Option C -- REST API + Web Console
.\Tools\Start-MSPApi.ps1 -OpenBrowser
```

---

## 📦 What's Inside

### 🔍 Diagnostics (7 tools)
System health, reboot detection, event log alerts, performance baselines, service audits, boot analysis, user logon reports

### 🛡️ Security (13 tools)
BitLocker, AV status, local admin audit, patch compliance, security posture scoring, full CIS benchmark, firewall risk, certificate inventory, LAPS, Credential Guard, Secure Boot/TPM, Exploit Guard, ransomware canary

### 🧹 Maintenance (6 tools)
Temp cleanup, profile cleanup, bloatware removal, Windows Update fix, print spooler fix, mapped drive repair

### 🌐 Network (15 tools)
Network stack reset, path test, WiFi survey, DNS deep dive, M365 endpoints, VPN health, captive portal, MTU test, neighbor discovery, packet capture, network topology, SNMP walk, LAN throughput, ARP cache audit, bandwidth saturation

### ☁️ Cloud & Hybrid (6 tools)
Entra Connect health, Intune compliance, Conditional Access audit, Azure VM inventory, Exchange Online health, Teams call quality

### 🖥️ App & DB Health (6 tools)
SQL Server health, IIS app pool status, Exchange Server health, print server report, service dependency map, app performance baseline

### 🏢 DC Operations (10 tools)
AD replication, DNS zone, DHCP scope, FSMO roles, GPO links, DCDiag orchestrator, Kerberos health, trust health, AD user bulk report, SYSVOL health

### 💾 Backup & DR (6 tools)
VSS writer health, backup status, shadow copies, system state integrity, restore readiness, recovery partition

### 🔗 RMM Integration (4 tools)
NinjaOne, ConnectWise, Datto, Autotask -- health checks + bi-directional ticketing

### 🐧 Cross-Platform (18 tools)
**macOS:** System report, disk, network, profiles, FileVault, MDM, security posture, startup, updates
**Linux:** System report, disk, network, security, services, packages, users, Docker, kernel hardening

### ⚙️ Platform
- **Orchestrator** -- DAG workflow engine, maintenance windows, change management (persisted to disk)
- **Reporting** -- Executive dashboards, SLA metrics, cost optimizer, compliance reports, trend analysis
- **Webhooks** -- Plugin marketplace, custom tool builder, OpenAPI spec, event dispatch with HMAC
- **Playbooks** -- 14 JSON decision-tree playbooks for automated remediation
- **Multi-Tenant** -- Per-tenant DPAPI vault, cross-tenant reporting
- **Audit** -- HMAC-SHA256 chained tamper-evident audit log

---

## 🎨 Brand

| Element | Value |
|---|---|
| **Name** | Sentinel Recon |
| **Tagline** | Discover. Diagnose. Deploy. |
| **Primary accent** | `#00F0FF` -- Sentinel Cyan |
| **Background** | `#050608` -- Deep Navy |
| **Success** | `#95E400` -- Sentinel Lime |
| **Warning** | `#FBBC00` -- Sentinel Amber |
| **Error** | `#ff3b3b` -- Sentinel Red |
| **Font** | Space Grotesk / Inter / Consolas |

---

## 🏗️ Architecture

```
Sentinel Recon/
├── Core/               # 13 PowerShell modules (105 exported functions)
│   ├── MSPToolkit.psd1 # Module manifest v25.0.0
│   ├── MSPToolkit.Platform.psm1    # Cross-platform abstraction
│   ├── MSPToolkit.Orchestrator.psm1 # DAG workflow engine
│   ├── MSPToolkit.Reporting.psm1   # BI + dashboards
│   ├── MSPToolkit.Webhooks.psm1    # Extensibility framework
│   └── ...
├── MSP_Tier3_Toolkit/  # 89 diagnostic scripts in 15 categories
│   ├── Security/       # 13 security audit tools
│   ├── Network/        # 15 network diagnostics
│   ├── DC/             # 10 domain controller operations
│   ├── Cloud/          # 6 cloud/hybrid tools
│   ├── Apps/           # 6 app/DB health checkers
│   ├── Backup/         # 6 backup/DR verification
│   ├── RMM/            # 4 RMM platform health checkers
│   ├── Mac/            # 10 macOS diagnostics
│   ├── Linux/          # 8 Linux diagnostics
│   └── ...
├── Integrations/       # Graph, Notifications, PSA, RMM
├── Playbooks/          # 14 JSON decision-tree playbooks
├── Tools/              # REST API + Web Console (HttpListener SPA)
├── GUI/                # WPF desktop GUI
├── Build/              # Portable bundle builder
├── assets/             # Logo, icons, PWA manifest
└── dist/               # Built bundles
```

---

## 📊 By the Numbers

| Metric | Value |
|---|---|
| Total files | **159** |
| Exported functions | **110** |
| Diagnostic scripts | **89** |
| Categories | **15** |
| Playbooks | **14** |
| Platforms | **Windows**, **macOS**, **Linux** |
| Portable bundle | **1.24 MB** single-file |
| Bundle hash | `CE946B33C0C413CA` |

---

## 🔒 Security

- **HMAC-SHA256 chained audit log** -- tamper-evident, verifiable
- **DPAPI per-tenant credential vault**
- **API key authentication** on all REST endpoints
- **Webhook HMAC signing**
- **RBAC-ready** multi-user console architecture
- **CIS Level 1 benchmark** scoring (30 controls)

---

## 🚢 Deploy Anywhere

| Platform | Method |
|---|---|
| **Windows 10/11** | Double-click `.bat` from USB, or `Import-Module` |
| **Windows Server** | Same -- works on DCs, file servers, RDS hosts |
| **macOS** | PowerShell 7+ -- run Mac scripts directly |
| **Linux** | PowerShell 7+ -- run Linux scripts directly |
| **Headless** | `-Console` flag for SSH/headless boxes |
| **API mode** | `-ApiOnly` for programmatic access on :8080 |

---

## 🤝 Part of the Sentinel Family

| Product | Purpose |
|---|---|
| **Sentinel Override** | AI browser automation for IT Pros & MSPs |
| **Sentinel Desktop** | Desktop management & deployment |
| **Sentinel Recon** | Cross-platform diagnostics & automation |

All share the Sentinel Cyan `#00F0FF` accent, Space Grotesk typography, and "built for work where being wrong has consequences" engineering philosophy.

---

**Sentinel Recon v25.0.0** -- *Discover. Diagnose. Deploy.*
