@echo off
REM MSP Toolkit Portable launcher.
REM Bypasses execution policy and STA-marshals so WPF works.
setlocal
set HERE=%~dp0
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%HERE%MSPToolkit.Portable.ps1" %*
