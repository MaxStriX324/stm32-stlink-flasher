@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
echo =====================================
echo   STM32 ST-Link Flasher - Installer
echo =====================================
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install.ps1" %*
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
  echo.
  echo Setup failed. Error code: %RC%.
  echo Copy the error text when requesting support.
  pause
  exit /b %RC%
)
exit /b 0
