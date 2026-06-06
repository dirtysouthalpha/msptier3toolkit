@echo off
REM Sentinel Recon Portable launcher.
REM Bypasses execution policy and STA-marshals so WPF works.
setlocal
set HERE=%~dp0
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%HERE%SentinelRecon.Portable.ps1" %*
