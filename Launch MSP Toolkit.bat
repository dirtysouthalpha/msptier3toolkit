@echo off
REM MSP Toolkit Launcher
REM Double-click this file to start the toolkit!

title MSP Toolkit Launcher

REM Check if PowerShell is available
where powershell >nul 2>nul
if %errorlevel% neq 0 (
    echo.
    echo ERROR: PowerShell not found!
    echo This toolkit requires PowerShell 5.1 or higher.
    echo PowerShell comes built-in with Windows 10 and 11.
    echo.
    pause
    exit /b 1
)

REM Launch the toolkit
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0Launch-MSPToolkit.ps1"

REM If PowerShell exits with error, pause to show message
if %errorlevel% neq 0 (
    echo.
    echo Script exited with error code: %errorlevel%
    pause
)
