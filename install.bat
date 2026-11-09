@echo off
title Speedtest.net Shortcut Installer
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [!] Setup encountered an error. Press any key to close...
    pause >nul
) else (
    timeout /t 3 >nul
)
