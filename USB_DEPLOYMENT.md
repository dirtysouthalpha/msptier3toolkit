# MSP Toolkit -- USB / Portable Deployment Guide

The MSP Toolkit is designed to run **from a USB thumb drive** and be
**drag-and-dropped onto a Windows 10/11 server or workstation** -- no MSI,
no installer, no source code required.

## Quick start: single-file portable launch

### 1. Build the bundle (one-time)

On any build machine (developer laptop, build server):

```powershell
.\Build\Build-MSPPortable.ps1
```

This produces `dist\` with:

| File                         | Purpose                                         |
| ---------------------------- | ----------------------------------------------- |
| `MSPToolkit.Portable.ps1`    | Single self-extracting PowerShell bundle (~0.5 MB) |
| `MSPToolkit.Portable.bat`    | Double-click launcher (bypasses execution policy) |
| `MSPToolkit.Portable.exe`    | Optional PS2EXE wrapper (no PowerShell window)   |
| `MSPToolkit.zip`             | Full repo tree for advanced users               |

### 2. Copy to USB

Copy the `dist\` files to the **root of a FAT32 or NTFS USB stick**:

```
E:\
  ├─ MSPToolkit.Portable.ps1
  ├─ MSPToolkit.Portable.bat
  └─ MSPToolkit.Portable.exe  (optional)
```

### 3. Launch on target

Double-click **MSPToolkit.Portable.bat** on the target Windows machine:

1. Bypasses PowerShell execution policy automatically
2. Extracts to `%TEMP%\MSPToolkit_<hash>\` (reuses cached copy)
3. Launches the WPF GUI  

If WPF is unavailable (Server Core, remote session), falls back to the
REST API dashboard opened in your default browser.

### Alternative launch modes

```powershell
# Console mode (list available commands)
.\MSPToolkit.Portable.ps1 -Console

# API-only mode (background service on :8080)
.\MSPToolkit.Portable.ps1 -ApiOnly -OpenBrowser

# Extract without launching
.\MSPToolkit.Portable.ps1 -Extract

# Extract to custom path
.\MSPToolkit.Portable.ps1 -Extract -ExtractTo "D:\MSPToolkit"
```

## Read-only network share / drag-and-drop

You can point multiple workstations at the same share:

```
\\fileserver\tools\MSPToolkit\  (UNC path mounted as a drive letter)
```

Right-click `MSPToolkit.Portable.ps1` -> **Run with PowerShell**.

> **Tip:** If SmartScreen blocks the `.ps1`, sign it with an internal
> code-signing certificate and the `Build-MSPPortable.ps1` bundler will
> embed the signature automatically.

## First-run configuration

On first launch after USB insertion, the toolkit writes a `config.json`
next to the portable bundle. Because the `paths` block uses relative
paths, **all logs and reports land on the USB stick alongside the tools**
by default:

```json
{
  "paths": {
    "logs": ".\\Logs",
    "reports": ".\\Reports",
    "cache": ".\\Cache"
  },
  "security": {
    "requireAdminForScripts": false,
    "auditScriptExecution": false,
    "requireApiKeyForLocalhost": true
  }
}
```

To leave logs **on the target machine** instead, edit config.json and
point paths to `%ProgramData%\MSPToolkit\...` (or any local path).

## API key for USB deployments

Set an API key in `config.json` so the REST dashboard is protected when
someone else plugs the USB into a different network:

```json
{
  "webInterface": {
    "apiKey": "your-random-key-here",
    "allowRemoteConnections": false,
    "requireApiKeyForLocalhost": true
  }
}
```

## Updating the USB bundle

1. Rebuild locally: `.\Build\Build-MSPPortable.ps1 -SkipZip`
2. Copy only the two `dist\` files to the USB stick
3. Re-run `MSPToolkit.Portable.bat` -- the hash check detects the new
   bundle and re-extracts automatically.

## Offline / air-gapped environments

The portable bundle contains everything it needs -- no NuGet, no internet,
no Graph SDK required for local diagnostics.  AD tools require the
`ActiveDirectory` module (RSAT), which is built into Domain Controllers
and can be pre-installed on workstations via RSAT.

## Troubleshooting

| Symptem                        | Fix                                                        |
| ------------------------------ | ---------------------------------------------------------- |
| "WPF unavailable" fallback     | Normal on Server Core / no desktop -- use API or `-Console` |
| "Access denied" on scripts     | Re-run the `.bat` from an elevated PowerShell              |
| SMARTSCREEN blocks the `.ps1`  | Right-click -> Properties -> Unblock, or code-sign the bundle |
| `%TEMP%` is full               | run `.ps1 -ExtractTo D:\MSPToolkit` manually               |
