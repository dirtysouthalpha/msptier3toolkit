@echo off
REM  ============================================================
REM  MSP TOOLKIT // CYBERPUNK HUD -- One-Click Launcher
REM  Double-click this file to launch everything automatically.
REM  ============================================================
title MSP TOOLKIT // CYBERPUNK HUD
color 0A

echo.
echo   +======================================================+
echo   ^|                                                      ^|
echo   ^|     MSP TOOLKIT // CYBERPUNK HUD v3.0                ^|
echo   ^|     Initializing...                                  ^|
echo   ^|                                                      ^|
echo   +======================================================+
echo.

REM Check PowerShell availability
where powershell >nul 2>nul
if %errorlevel% neq 0 (
    echo   [ERROR] PowerShell not found!
    echo   This toolkit requires PowerShell 5.1+
    echo.
    pause
    exit /b 1
)

REM Check if port 8080 is already in use
netstat -ano 2>nul | findstr ":8080.*LISTENING" >nul 2>nul
if %errorlevel% equ 0 (
    echo   [WARN] Port 8080 already in use. Attempting to open browser...
    start "" "http://localhost:8080"
    goto :eof
)

REM Launch the Web UI (auto-opens browser)
echo   [+] Starting Cyberpunk HUD on port 8080...
echo   [+] Browser will open automatically.
echo   [+] Press Ctrl+C in this window to stop the server.
echo.

powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0Launch-WebUI.ps1" -Port 8080 -OpenBrowser

if %errorlevel% neq 0 (
    echo.
    echo   [ERROR] Server exited with code: %errorlevel%
    pause
)
