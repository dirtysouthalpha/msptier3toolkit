# MSP Toolkit - Web UI Instructions

## 🚀 Quick Start

The web interface is now **SUPER EASY** to use! Just follow one of these methods:

### Method 1: Double-Click Launch (Windows)
1. Double-click **`Launch Web UI.bat`**
2. Your browser will open automatically
3. Done! 🎉

### Method 2: PowerShell (All Platforms)
```powershell
.\Launch-WebUI.ps1
```

Then open your browser to: **http://localhost:8080**

### Method 3: PowerShell with Auto-Open Browser
```powershell
.\Launch-WebUI.ps1 -OpenBrowser
```

### Method 4: Custom Port
```powershell
.\Launch-WebUI.ps1 -Port 9000
```

## 📋 What You'll See

The web interface provides:

- **Beautiful Dashboard** - Visual overview of all tools
- **12 Automation Scripts** - All your MSP toolkit scripts in one place
- **API Endpoints** - For integration and automation
- **Real-time Status** - See what's running

## 🛠️ Available Tools

### Diagnostics
- System Health Report
- Boot Time Analyzer
- Client System Summary

### Maintenance
- Cleanup Old Profiles
- Comprehensive Cleanup

### Print Management
- Printer Spooler Fix
- Spooler Monitor Setup

### Network & Software
- Fix Mapped Drives
- Remote Software Uninstall

### Windows Update
- Windows Update Fix

### Active Directory & M365
- Check AD User Status
- M365 User Provisioning

## 🔧 Troubleshooting

### Error: "Port already in use"
Try a different port:
```powershell
.\Launch-WebUI.ps1 -Port 8081
```

### Error: "Access denied"
Run PowerShell as Administrator

### Web page won't load
1. Check that the server is running (look for green "RUNNING" message)
2. Make sure you're using the correct URL: http://localhost:8080
3. Try a different browser

## 💡 Tips

- **Keep the PowerShell window open** - Closing it stops the server
- **Press Ctrl+C** to stop the server
- **Bookmark the URL** for quick access
- **Share the link** with others on your network (if configured)

## 📊 API Endpoints

For automation and integration:

- `/` - Main web interface
- `/api/status` - Server status (JSON)
- `/api/health` - System health (JSON)
- `/api/scripts` - List of all scripts (JSON)
- `/dashboard` - Dashboard page

## 🎯 Configuration

The web interface is enabled in `config.json`:

```json
"webInterface": {
  "enabled": true,
  "port": 8080,
  "useSSL": false,
  "allowRemoteConnections": false
}
```

## 🔒 Security Notes

- By default, only accessible from localhost
- To allow remote connections, edit config.json
- Consider using a reverse proxy with SSL for production
- API key authentication coming in future version

## 📞 Support

- **Issues?** Check the troubleshooting section above
- **Questions?** See the main README.md
- **GitHub:** https://github.com/dirtysouthalpha/msptier3toolkit

---

**Version:** 2.0.0
**Last Updated:** 2025-11-11

Enjoy your new web interface! 🚀
