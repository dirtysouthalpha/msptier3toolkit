@echo off
REM MSP Toolkit - Web UI Launcher
REM Simple batch file to launch the web interface

echo.
echo ========================================
echo   MSP Toolkit - Web UI Launcher
echo ========================================
echo.

powershell.exe -ExecutionPolicy Bypass -File "%~dp0Launch-WebUI.ps1" -OpenBrowser

pause
