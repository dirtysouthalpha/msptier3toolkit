# MSP Tier 3 Toolkit 🚀

Welcome to the **MSP Tier 3 Toolkit** — a collection of high-impact PowerShell scripts designed to help Service Desk Technicians, System Admins, and MSP engineers troubleshoot faster, automate routine tasks, and deliver enterprise-level support with confidence.

## 🔧 Current Scripts

| Script Name                | Description |
|---------------------------|-------------|
| `SystemHealthReport.ps1` | Outputs key system stats (RAM, disk, OS, last boot) |
| `CheckADUserStatus.ps1`  | Checks lockout, password age, login failures |
| `CleanupOldProfiles.ps1` | Deletes unused local profiles |
| `M365UserProvisioning.ps1` | Assigns license and sets usage location |
| `PrinterSpoolerFix.ps1`  | Clears stuck spool jobs |
| `RemoteUninstall.ps1`    | Removes specified program silently |
| `FixMappedDrives.ps1`    | Tests and refreshes mapped network drives |
| `WindowsUpdateFix.ps1`   | Resets update components |
| `BootTimeAnalyzer.ps1`   | Finds last boot and shutdown times |
| `ClientSystemSummary.ps1` | Creates an HTML report for end users |

## 🚧 Planned Additions

See [ROADMAP.md](./ROADMAP.md) for upcoming scripts and contributions.

## 📥 How to Use

1. Clone or download the repo
2. Right-click `.ps1` scripts and run in PowerShell (preferably as Admin)
3. Review logs/output or integrate with RMM automation

---

> 💡 Most scripts are safe to run unattended — but always test in a non-production environment first.

