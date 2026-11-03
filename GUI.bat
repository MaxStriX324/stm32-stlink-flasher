@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
where powershell.exe >nul 2>nul
if errorlevel 1 (
  echo ERROR: Windows PowerShell 5.1 is required.
  pause
  exit /b 1
)
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\gui.ps1"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
  echo GUI terminated with error code %RC%.
  pause
)
exit /b %RC%
