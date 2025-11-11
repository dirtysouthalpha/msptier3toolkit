# 🚀 MSP Toolkit v2.0 - Enterprise Automation Platform

<div align="center">

**Dazzle. Automate. Dominate.**

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.0.0-orange.svg)](CHANGELOG.md)

Transform your MSP operations with the most comprehensive PowerShell automation platform for Windows administration.

[Quick Start](#-quick-start) • [Features](#-features) • [Installation](#-installation) • [Documentation](#-documentation) • [Support](#-support)

</div>

---

## 📖 Table of Contents

- [Overview](#-overview)
- [Features](#-features)
- [Quick Start](#-quick-start)
- [Installation](#-installation)
- [Core Scripts](#-core-scripts)
- [Advanced Features](#-advanced-features)
- [Configuration](#-configuration)
- [Web Interface](#-web-interface)
- [Remote Execution](#-remote-execution)
- [Self-Healing](#-self-healing-automation)
- [Templates](#-templates)
- [Knowledge Base](#-team-knowledge-base)
- [RMM Integration](#-rmm-integration)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)

---

## 🎯 Overview

The **MSP Toolkit** is a professional-grade automation platform designed for:

- **Service Desk Technicians** - Resolve issues faster with one-click fixes
- **System Administrators** - Automate routine maintenance and monitoring
- **MSP Engineers** - Deploy enterprise-level solutions across multiple clients
- **IT Managers** - Gain visibility with comprehensive reporting and analytics

### What's New in v2.0?

🎨 **Epic Interactive Launcher** - Beautiful menu system with categories, search, and favorites
📊 **HTML Dashboard** - Stunning analytics and system health visualization
🌐 **Web Interface** - Access toolkit from any browser with REST API
🤖 **Self-Healing Engine** - Automatic detection and remediation of common issues
🔄 **Auto-Update System** - Git-based updates with automatic backups
🎯 **Templates** - Pre-configured script sequences for common tasks
📚 **Knowledge Base** - Team collaboration and documentation system
🔌 **RMM Integration** - ConnectWise, Autotask, Datto, and more
🌍 **Remote Execution** - Run scripts on multiple computers simultaneously
🎨 **Beautiful Logging** - Color-coded, formatted output with session tracking

---

## ✨ Features

### 🛠️ Core Capabilities

| Feature | Description |
|---------|-------------|
| **12 Production Scripts** | Battle-tested automation for common IT tasks |
| **Unified Launcher** | Interactive menu with categorization and search |
| **Remote Execution** | Run scripts on single or multiple computers |
| **Template System** | Save and replay script sequences |
| **Self-Healing** | Automatic monitoring and remediation |
| **HTML Reports** | Beautiful, shareable system reports |
| **Web Interface** | Browser-based access with REST API |
| **Knowledge Base** | Team tips, tricks, and solutions |
| **Auto-Updates** | Git-based updates with backup/rollback |
| **RMM Integration** | Connect to your existing tools |

### 📊 Diagnostics & Reporting

- **System Health Report** - Comprehensive system information
- **Boot Time Analyzer** - Event log analysis for boot/shutdown
- **Client System Summary** - Professional HTML reports for clients
- **Dashboard Generator** - Real-time analytics and metrics

### 🔧 Maintenance & Cleanup

- **Comprehensive Cleanup** - Automated system cleanup with logging
- **Profile Cleanup** - Remove old user profiles
- **Disk Space Management** - Automatic threshold-based cleanup
- **Windows Update Repair** - Reset and repair update components

### 👥 User Management

- **AD User Status Checker** - Lockout, password, and login analysis
- **M365 Provisioning** - Automated license assignment
- **Bulk Operations** - Process multiple users from CSV

### 🖨️ Print Management

- **Spooler Fix** - Clear stuck jobs and restart service
- **Spooler Monitor** - Automatic monitoring and restart
- **Print Queue Analysis** - Detailed troubleshooting

### 🌐 Network & Software

- **Mapped Drive Repair** - Test and reconnect network drives
- **Remote Software Uninstall** - Silent uninstallation
- **Network Diagnostics** - Connection testing and analysis

---

## 🚀 Quick Start

### One-Line Installation

```powershell
# Run as Administrator
powershell -ExecutionPolicy Bypass -File .\Install-MSPToolkit.ps1
```

### Launch the Toolkit

```powershell
# Double-click the desktop shortcut, or:
.\Start-MSPToolkit.ps1
```

### Your First Automation

1. **Launch** the toolkit
2. **Select** a script from the menu (e.g., `1` for System Health Report)
3. **Review** the output
4. **Done!** 🎉

---

## 💿 Installation

### Prerequisites

- Windows 10/11 or Windows Server 2016+
- PowerShell 5.1 or higher
- Administrator rights (recommended)
- Git (for auto-updates)

### Standard Installation

1. **Clone the repository:**
   ```powershell
   git clone https://github.com/dirtysouthalpha/msptier3toolkit.git
   cd msptier3toolkit
   ```

2. **Run the installer:**
   ```powershell
   .\Install-MSPToolkit.ps1
   ```

3. **Follow the wizard:**
   - Creates required directories
   - Installs PowerShell modules
   - Sets up scheduled tasks
   - Creates shortcuts
   - Initializes configuration

### Manual Installation

If you prefer manual setup:

1. Extract the toolkit to a permanent location
2. Edit `config.json` with your settings
3. Run scripts individually or use the launcher

### Uninstallation

```powershell
.\Install-MSPToolkit.ps1 -Uninstall
```

---

## 📜 Core Scripts

### Diagnostics (Category 1)

#### 1️⃣ System Health Report
**Path:** `MSP_Tier3_Toolkit\SystemHealthReport.ps1`

Generates comprehensive system health information including:
- RAM usage and capacity
- Disk space and partitions
- Operating system details
- CPU information
- Last boot time
- Network configuration

**Usage:**
```powershell
.\SystemHealthReport.ps1
```

**Output:** Text file on desktop

---

#### 2️⃣ Boot Time Analyzer
**Path:** `MSP_Tier3_Toolkit\BootTimeAnalyzer.ps1`

Analyzes Windows Event Logs to determine:
- Last boot time
- Last shutdown time
- Boot duration
- Event IDs 6005 and 6006 analysis

**Usage:**
```powershell
.\BootTimeAnalyzer.ps1
```

---

#### 3️⃣ Client System Summary
**Path:** `MSP_Tier3_Toolkit\ClientSystemSummary.ps1`

Creates professional HTML reports for end users with:
- System specifications
- Warranty information
- Software inventory
- Recent issues

**Usage:**
```powershell
.\ClientSystemSummary.ps1
```

**Output:** HTML file on desktop

---

### User Management (Category 2)

#### 4️⃣ Check AD User Status
**Path:** `MSP_Tier3_Toolkit\CheckADUserStatus.ps1`

Checks Active Directory user account status:
- Account lockout status
- Password age
- Bad logon attempts
- Last bad password attempt
- Account expiration

**Usage:**
```powershell
.\CheckADUserStatus.ps1 -Username "john.doe"
```

**Requirements:** Active Directory module

---

#### 5️⃣ M365 User Provisioning
**Path:** `MSP_Tier3_Toolkit\M365UserProvisioning.ps1`

Automates Microsoft 365 user provisioning:
- Sets usage location
- Assigns licenses
- Configures mailbox
- Sends welcome email

**Usage:**
```powershell
.\M365UserProvisioning.ps1 -UserPrincipalName "user@domain.com"
```

**Requirements:** MSOnline module

---

### Maintenance (Category 3)

#### 6️⃣ Cleanup Old Profiles
**Path:** `MSP_Tier3_Toolkit\CleanupOldProfiles.ps1`

Removes user profiles older than specified days:
- Configurable age threshold (default: 30 days)
- Protects Administrator and Default profiles
- Detailed logging
- Disk space recovery calculation

**Usage:**
```powershell
.\CleanupOldProfiles.ps1 -DaysOld 30
```

⚠️ **Requires Administrator rights**

---

#### 7️⃣ Comprehensive Cleanup
**Path:** `Cleanup Script\Cleanup-Auto.ps1`

Full system cleanup automation:
- Clears user TEMP folders
- Clears system TEMP folders
- Clears print spooler queue
- Runs Disk Cleanup utility
- Detailed logging to C:\CleanupLogs
- Progress indicators

**Usage:**
```powershell
.\Cleanup-Auto.ps1
```

⚠️ **Requires Administrator rights**

---

### Print Management (Category 4)

#### 8️⃣ Printer Spooler Fix
**Path:** `MSP_Tier3_Toolkit\PrinterSpoolerFix.ps1`

Quick fix for printing issues:
- Stops Print Spooler service
- Clears stuck jobs
- Restarts service
- Verifies operation

**Usage:**
```powershell
.\PrinterSpoolerFix.ps1
```

⚠️ **Requires Administrator rights**

---

#### 9️⃣ Spooler Monitor Setup
**Path:** `Auto-Check and Start Printer Spooler\CheckAndStart-Spooler.ps1`

Monitoring script for Print Spooler:
- Checks service status
- Auto-restarts if stopped
- Logging to C:\Logs\SpoolerMonitor.log
- Suitable for scheduled tasks

**Usage:**
```powershell
# One-time run
.\CheckAndStart-Spooler.ps1

# Via Scheduled Task (recommended)
# Created automatically by installer
```

---

### Network & Software (Category 5)

#### 🔟 Fix Mapped Drives
**Path:** `MSP_Tier3_Toolkit\FixMappedDrives.ps1`

Tests and repairs network drive mappings:
- Tests connectivity to each mapped drive
- Identifies broken mappings
- Attempts reconnection
- Reports results

**Usage:**
```powershell
.\FixMappedDrives.ps1
```

---

#### 1️⃣1️⃣ Remote Software Uninstall
**Path:** `MSP_Tier3_Toolkit\RemoteUninstall.ps1`

Silently uninstalls software:
- Uses WMI Win32_Product class
- Silent uninstallation
- Works locally or remotely
- Detailed logging

**Usage:**
```powershell
.\RemoteUninstall.ps1 -ProgramName "Adobe Reader"
```

⚠️ **Requires Administrator rights**

---

#### 1️⃣2️⃣ Windows Update Fix
**Path:** `MSP_Tier3_Toolkit\WindowsUpdateFix.ps1`

Repairs Windows Update issues:
- Stops Windows Update services
- Clears SoftwareDistribution folder
- Resets update components
- Forces update check
- Restarts services

**Usage:**
```powershell
.\WindowsUpdateFix.ps1
```

⚠️ **Requires Administrator rights**

---

## 🎯 Advanced Features

### 🎨 Epic Launcher

The unified launcher provides:

- **Categorized Menu** - Scripts organized by function
- **Color-Coded Output** - Visual feedback for all operations
- **Status Indicators** - See which scripts require admin rights
- **Recent Tools** - Quick access to frequently used scripts
- **Search & Filter** - Find tools quickly
- **System Info Bar** - Current computer, user, and admin status

**Launch:**
```powershell
.\Start-MSPToolkit.ps1
```

**Features:**
- `[1-12]` - Run a specific script
- `[D]` - View Dashboard
- `[U]` - Check for Updates
- `[S]` - Settings & Configuration
- `[R]` - Remote Execution Mode
- `[K]` - Knowledge Base
- `[W]` - Start Web Interface
- `[Q]` - Quit

---

### 📊 HTML Dashboard

Beautiful analytics dashboard with:

- **Execution Statistics** - Scripts run today, errors, success rate
- **System Health** - Memory, disk, CPU, uptime
- **Resource Usage** - Real-time monitoring with color-coded alerts
- **Configuration Status** - Enabled/disabled features
- **Log Analytics** - Log file counts and sizes
- **Auto-Refresh** - Updates on each generation

**Generate Dashboard:**
```powershell
.\Tools\Generate-Dashboard.ps1 -OpenInBrowser
```

**From Launcher:**
Press `[D]` in the main menu

**Output:** HTML file in `C:\MSPToolkit\Reports\`

---

### 🌐 Web Interface

Access toolkit from any browser:

- **REST API** - Programmatic access to all features
- **Interactive UI** - Click-to-run script execution
- **Real-Time Status** - System health monitoring
- **Mobile-Friendly** - Responsive design
- **Secure** - Optional SSL and API key authentication

**Start Web Interface:**
```powershell
.\Tools\Start-WebInterface.ps1 -OpenBrowser
```

**Access:** http://localhost:8080

**API Endpoints:**
- `/api/status` - Platform status
- `/api/health` - System health
- `/api/scripts` - Available scripts
- `/dashboard` - Visual dashboard

**Configuration:**
Edit `config.json`:
```json
{
  "webInterface": {
    "enabled": true,
    "port": 8080,
    "useSSL": false,
    "allowRemoteConnections": false
  }
}
```

---

### 🌍 Remote Execution

Run scripts on single or multiple computers:

**From Launcher:**
1. Press `[R]` for Remote Execution Mode
2. Enter computer name(s) or path to CSV file
3. Select a script to run

**Via PowerShell:**
```powershell
# Single computer
.\Start-MSPToolkit.ps1 -ComputerName "PC-01"

# Multiple computers
$computers = @("PC-01", "PC-02", "PC-03")
Invoke-MSPRemoteScript -ComputerName $computers -ScriptPath ".\MSP_Tier3_Toolkit\SystemHealthReport.ps1"

# From CSV file
$computers = Import-MSPComputerList -Path ".\computers.csv"
Invoke-MSPRemoteScriptFile -ComputerName $computers -ScriptPath ".\MSP_Tier3_Toolkit\WindowsUpdateFix.ps1"
```

**CSV Format:**
```csv
ComputerName
PC-01
PC-02
PC-03
```

**Features:**
- Connectivity testing before execution
- Parallel execution support
- Progress tracking
- Error handling and reporting
- Credential management

---

### 🤖 Self-Healing Automation

Automatic monitoring and remediation:

**Monitors:**
- Print Spooler service status
- Disk space thresholds
- Windows Update service
- Memory usage
- Network drive connectivity

**Auto-Fixes:**
- Restarts stopped Print Spooler
- Clears temp files when disk space low
- Restarts Windows Update service
- Reconnects network drives
- Sends alerts for high memory usage

**Start Self-Healing:**
```powershell
# Run once
.\Tools\Start-SelfHealing.ps1 -RunOnce

# Continuous monitoring (5-minute intervals)
.\Tools\Start-SelfHealing.ps1 -IntervalMinutes 5

# With notifications
.\Tools\Start-SelfHealing.ps1 -EnableNotifications
```

**Scheduled Task:**
Created automatically by installer, runs every 15 minutes

**Configuration:**
```json
{
  "monitoring": {
    "autoHealEnabled": true,
    "diskSpaceThresholdPercent": 15,
    "memoryThresholdPercent": 90,
    "enableAlerts": true
  }
}
```

**Notifications:**
- Teams webhook support
- Slack webhook support
- Email alerts
- RMM platform integration

---

### 🎯 Templates

Pre-configured script sequences for common tasks:

**Built-in Templates:**

#### New Hire Provisioning
Automates new employee setup:
1. M365 User Provisioning
2. Comprehensive Cleanup
3. Windows Update Fix

#### Monthly Workstation Maintenance
Standard maintenance routine:
1. System Health Report
2. Comprehensive Cleanup
3. Cleanup Old Profiles
4. Windows Update Fix

**Run a Template:**
```powershell
# Interactive selection
.\Tools\Invoke-Template.ps1

# Specific template
.\Tools\Invoke-Template.ps1 -TemplateName "NewHireProvisioning"

# On remote computers
.\Tools\Invoke-Template.ps1 -TemplateName "WorkstationMaintenance" -ComputerName "PC-01"

# List available templates
.\Tools\Invoke-Template.ps1 -ListTemplates
```

**Create Custom Templates:**

Create a JSON file in `Templates\` folder:

```json
{
  "templateName": "My Custom Template",
  "description": "Description of what this does",
  "category": "Maintenance",
  "scripts": [
    {
      "id": 1,
      "name": "System Health Report",
      "parameters": {}
    },
    {
      "id": 7,
      "name": "Comprehensive Cleanup",
      "parameters": {
        "IncludeTempFiles": true
      }
    }
  ],
  "settings": {
    "runSequentially": true,
    "continueOnError": false,
    "generateReport": true
  },
  "notes": "Additional notes here"
}
```

---

### 📚 Team Knowledge Base

Collaborative documentation system:

**Features:**
- **Tips & Tricks** - Share helpful techniques
- **Common Issues** - Document problems and solutions
- **Best Practices** - Team standards and procedures
- **General Notes** - Additional context and information

**Access Knowledge Base:**
```powershell
# Interactive mode
.\Tools\Show-KnowledgeBase.ps1

# View all entries
.\Tools\Show-KnowledgeBase.ps1 -ViewAll

# View specific script
.\Tools\Show-KnowledgeBase.ps1 -ScriptID 8

# Add new entry
.\Tools\Show-KnowledgeBase.ps1 -AddNote -ScriptID 8
```

**From Launcher:**
Press `[K]` in the main menu

**Entry Types:**
1. **Tip/Trick** - Helpful shortcuts or techniques
2. **Common Issue & Solution** - Documented problems and fixes
3. **Best Practice** - Recommended approaches
4. **General Note** - Any other relevant information

**Storage:** `C:\MSPToolkit\KnowledgeBase\`

**Example Workflow:**
1. Technician encounters an issue while using a script
2. Documents the problem and solution in Knowledge Base
3. Other team members can reference this when they encounter similar issues
4. Builds institutional knowledge over time

---

### 🔄 Auto-Update System

Git-based automatic updates:

**Features:**
- Automatic update checking
- Git repository integration
- Automatic backups before update
- Rollback capability
- Version tracking
- Changelog display

**Check for Updates:**
```powershell
# From launcher
Press [U] in main menu

# Via PowerShell
.\Tools\Update-MSPToolkit.ps1

# Check only (don't apply)
.\Tools\Update-MSPToolkit.ps1 -CheckOnly

# Force update without confirmation
.\Tools\Update-MSPToolkit.ps1 -Force

# Update without backup
.\Tools\Update-MSPToolkit.ps1 -NoBackup
```

**Configuration:**
```json
{
  "updates": {
    "autoCheckForUpdates": true,
    "updateBranch": "main",
    "gitRepoUrl": "https://github.com/dirtysouthalpha/msptier3toolkit.git",
    "backupBeforeUpdate": true
  }
}
```

**Update Process:**
1. Fetches latest changes from Git repository
2. Displays changelog of new commits
3. Creates backup of current version
4. Applies updates
5. Cleans old backups (keeps last 5)
6. Prompts to restart toolkit

**Backup Location:** `C:\MSPToolkit\Backups\`

---

### 🔌 RMM Integration

Connect to your existing tools:

**Supported Platforms:**
- ConnectWise
- Autotask
- Datto RMM
- Kaseya
- NinjaRMM
- Generic Webhook (any platform)

**Send Alerts:**
```powershell
Send-RMMAlert -Title "High Memory Usage" -Message "Memory usage at 95%" -Severity "High"
```

**Create Tickets:**
```powershell
New-RMMTicket -Title "Disk Space Critical" -Description "Drive C: at 5% free" -Priority "High"
```

**Update Tickets:**
```powershell
Update-RMMTicket -TicketID "12345" -Note "Issue resolved via MSP Toolkit" -Status "Resolved"
```

**Configuration:**
```json
{
  "rmmIntegration": {
    "enabled": true,
    "platform": "connectwise",
    "apiEndpoint": "https://api.connectwise.com/v2020_3",
    "apiKey": "YOUR_API_KEY_HERE",
    "autoCreateTickets": true,
    "updateTicketStatus": true
  }
}
```

**Webhook Example (Generic):**
```json
{
  "rmmIntegration": {
    "enabled": true,
    "platform": "generic",
    "apiEndpoint": "https://your-webhook-url.com/endpoint",
    "apiKey": "optional-api-key"
  }
}
```

---

## ⚙️ Configuration

### Main Configuration File

**Location:** `config.json` in toolkit root

**Key Sections:**

#### Company Settings
```json
{
  "company": {
    "name": "Your MSP Company",
    "domain": "yourdomain.local",
    "timezone": "Eastern Standard Time"
  }
}
```

#### Logging
```json
{
  "logging": {
    "enabled": true,
    "level": "Info",
    "maxLogSizeMB": 50,
    "retentionDays": 90,
    "logToFile": true,
    "logToConsole": true,
    "enableColors": true
  }
}
```

#### Monitoring & Self-Healing
```json
{
  "monitoring": {
    "printSpoolerCheckIntervalMinutes": 5,
    "diskSpaceThresholdPercent": 15,
    "memoryThresholdPercent": 90,
    "autoHealEnabled": true,
    "enableAlerts": true
  }
}
```

#### Notifications
```json
{
  "notifications": {
    "emailEnabled": false,
    "smtpServer": "smtp.office365.com",
    "smtpPort": 587,
    "fromAddress": "alerts@yourcompany.com",
    "toAddresses": ["it@yourcompany.com"],
    "teamsWebhookUrl": "https://outlook.office.com/webhook/...",
    "slackWebhookUrl": "https://hooks.slack.com/services/..."
  }
}
```

### Directory Structure

```
C:\MSPToolkit\
├── Logs\              # Execution logs
├── Reports\           # Generated reports
├── Cache\             # Temporary data and credentials
├── Templates\         # Custom script templates
├── KnowledgeBase\     # Team documentation
└── Backups\           # Update backups
```

---

## 🐛 Troubleshooting

### Common Issues

#### "Execution Policy" Error

**Problem:** Scripts won't run due to execution policy

**Solution:**
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass
```

#### "Module Not Found" Error

**Problem:** Required PowerShell modules missing

**Solution:**
```powershell
# Active Directory module
Install-Module -Name ActiveDirectory -Force

# Microsoft Online (M365)
Install-Module -Name MSOnline -Force
```

#### Scripts Require Admin Rights

**Problem:** Scripts fail without administrator privileges

**Solution:** Right-click PowerShell and select "Run as Administrator"

#### Remote Execution Fails

**Problem:** Cannot execute scripts on remote computers

**Solution:**
```powershell
# Enable PSRemoting on target computer
Enable-PSRemoting -Force

# Test connection
Test-WSMan -ComputerName "TARGET-PC"
```

#### Dashboard Not Generating

**Problem:** Dashboard generation fails

**Solution:**
- Check that `C:\MSPToolkit\Reports\` exists
- Run dashboard script with verbose output:
  ```powershell
  .\Tools\Generate-Dashboard.ps1 -Verbose
  ```

### Log Files

Check logs for detailed error information:

**Locations:**
- Main logs: `C:\MSPToolkit\Logs\`
- Cleanup logs: `C:\CleanupLogs\`
- Spooler monitor: `C:\Logs\SpoolerMonitor.log`
- Self-healing: `C:\MSPToolkit\Logs\SelfHealing_YYYYMMDD.log`

**View Recent Errors:**
```powershell
Get-Content "C:\MSPToolkit\Logs\Launcher_*.log" | Select-String "ERROR"
```

### Getting Help

1. **Check documentation** in this README
2. **Review log files** for error details
3. **Search Knowledge Base** for known issues
4. **Create GitHub issue** with:
   - Error message
   - Log file excerpt
   - PowerShell version
   - Windows version
   - Steps to reproduce

---

## 🤝 Contributing

We welcome contributions! Here's how:

### Reporting Issues

1. Search existing issues first
2. Create new issue with template
3. Include logs and screenshots
4. Describe steps to reproduce

### Submitting Code

1. Fork the repository
2. Create feature branch
3. Make your changes
4. Test thoroughly
5. Submit pull request

### Coding Standards

- Follow PowerShell best practices
- Include comment-based help
- Add error handling
- Test on multiple Windows versions
- Update documentation

### Adding Scripts

To add a new script to the toolkit:

1. Create script in appropriate folder
2. Add to launcher catalog in `Start-MSPToolkit.ps1`
3. Create template examples if applicable
4. Update README with description
5. Add entry to ROADMAP if in progress

---

## 📄 License

This project is licensed under the MIT License - see LICENSE file for details.

---

## 🙏 Acknowledgments

- PowerShell Community
- MSP community for feedback and ideas
- All contributors and testers

---

## 📞 Support

- **Documentation:** This README and inline script help
- **Issues:** GitHub Issues
- **Updates:** Watch repository for releases

---

<div align="center">

**Made with ❤️ for the MSP Community**

[⬆ Back to Top](#-msp-toolkit-v20---enterprise-automation-platform)

</div>
