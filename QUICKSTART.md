# 🚀 MSP Toolkit - Quick Start Guide

## **Zero Dependencies. Just Works!**

The MSP Toolkit requires **NOTHING** but Windows 10/11 with built-in PowerShell. No installation, no setup, no modules to install!

---

## 📦 **Getting Started (30 Seconds)**

### **Option 1: Double-Click (Easiest!)**

1. **Download** or clone this repository
2. **Double-click** `Launch MSP Toolkit.bat`
3. **Done!** 🎉

That's it! The menu will appear and you can start using any script.

---

### **Option 2: PowerShell**

1. Open PowerShell in the toolkit folder
2. Run: `.\Launch-MSPToolkit.ps1`
3. Done!

---

## 🎯 **How to Use**

Once the menu appears:

1. **Enter a number** (1-12) to run a script
2. Press **H** for help
3. Press **Q** to quit

**That's literally it!** No training needed.

---

## 🔑 **Do I Need Admin Rights?**

**NO!** Many scripts work without admin rights.

Scripts that need admin rights are marked with **[ADMIN]** in red.

**To run as admin:**
- Right-click PowerShell -> "Run as Administrator"
- Then run the launcher

---

## 📊 **Most Popular Scripts**

| Number | Script | What It Does | Admin? |
|--------|--------|--------------|--------|
| **1** | System Health Report | Quick system diagnostics | No |
| **7** | Comprehensive Cleanup | Free up disk space | Yes |
| **8** | Printer Spooler Fix | Restart stuck printer | Yes |
| **12** | Windows Update Fix | Fix Windows Update | Yes |

---

## ❓ **Common Questions**

### **Q: Do I need to install anything?**
**A:** NO! Just run it. Windows 10/11 has everything needed.

### **Q: Will this break my computer?**
**A:** NO! All scripts are safe and widely used by MSPs.

### **Q: Can I run this on multiple computers?**
**A:** YES! Copy the folder to any Windows computer and run.

### **Q: What if I get an "execution policy" error?**
**A:** The `.bat` file handles this automatically. If using PowerShell directly:
```powershell
powershell -ExecutionPolicy Bypass -File .\Launch-MSPToolkit.ps1
```

### **Q: Can I run individual scripts without the menu?**
**A:** YES! All scripts are in the `MSP_Tier3_Toolkit` folder. Run them directly.

---

## 🎨 **What You'll See**

```
    ███╗   ███╗███████╗██████╗     ████████╗ ██████╗  ██████╗ ██╗
    ████╗ ████║██╔════╝██╔══██╗    ╚══██╔══╝██╔═══██╗██╔═══██╗██║
    ██╔████╔██║███████╗██████╔╝       ██║   ██║   ██║██║   ██║██║
    ██║╚██╔╝██║╚════██║██╔═══╝        ██║   ██║   ██║██║   ██║██║
    ██║ ╚═╝ ██║███████║██║            ██║   ╚██████╔╝╚██████╔╝███████╗
    ╚═╝     ╚═╝╚══════╝╚═╝            ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝

              TIER 3 SUPPORT AUTOMATION PLATFORM

    Select a script by number, press H for help, Q to quit
```

---

## 📁 **File Structure**

```
msptier3toolkit/
│
├── Launch MSP Toolkit.bat     ← Double-click this!
├── Launch-MSPToolkit.ps1      ← Or run this in PowerShell
├── QUICKSTART.md              ← You are here
│
└── MSP_Tier3_Toolkit/         ← All 12 scripts
    ├── SystemHealthReport.ps1
    ├── PrinterSpoolerFix.ps1
    └── ... (10 more scripts)
```

---

## 🎓 **Script Descriptions**

### **Diagnostics (No Admin Required)**
- **[1] System Health Report** - Shows RAM, disk, CPU, uptime
- **[2] Boot Time Analyzer** - Shows boot/shutdown history
- **[3] Client System Summary** - Creates HTML report for clients

### **User Management**
- **[4] Check AD User Status** - Check lockouts, password age
- **[5] M365 User Provisioning** - Assign Office 365 licenses

### **Maintenance (Admin Required)**
- **[6] Cleanup Old Profiles** - Remove profiles older than 30 days
- **[7] Comprehensive Cleanup** - Deep cleanup of temp files

### **Print Management (Admin Required)**
- **[8] Printer Spooler Fix** - Fix stuck print jobs
- **[9] Spooler Monitor Setup** - Deploy automatic monitoring

### **Network & Software**
- **[10] Fix Mapped Drives** - Test and reconnect network drives
- **[11] Remote Software Uninstall** - Silently uninstall programs

### **Windows Update (Admin Required)**
- **[12] Windows Update Fix** - Reset Windows Update components

---

## 💡 **Pro Tips**

1. **Bookmark frequently used scripts** - They appear in "Recently Used"
2. **Create shortcuts** - Copy the `.bat` file to your desktop
3. **Run remotely** - Copy the whole folder to remote computers
4. **Schedule scripts** - Use Task Scheduler to run scripts automatically
5. **Combine with RMM** - Deploy via your RMM tool (N-able, Datto, etc.)

---

## 🆘 **Getting Help**

- **In the menu:** Press **H** for built-in help
- **Full docs:** See `README_v2.md` for detailed documentation
- **Issues:** GitHub issues for bug reports
- **Questions:** Check documentation first!

---

## ✅ **System Requirements**

- **OS:** Windows 10 or Windows 11 (Windows Server 2016+ also works)
- **PowerShell:** 5.1+ (built into Windows 10/11)
- **Admin Rights:** Only for scripts marked [ADMIN]
- **Modules:** NONE required! (Some scripts have optional module dependencies)

---

## 🎉 **You're Ready!**

That's it! You now know everything you need.

**Just double-click `Launch MSP Toolkit.bat` and start automating!**

---

*Built with ❤️ for MSP technicians everywhere*
