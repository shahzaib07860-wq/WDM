@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -File "%~dp0scripts\build-windows.ps1"
set "WDM_BUILD_EXIT=%ERRORLEVEL%"
if not "%WDM_BUILD_EXIT%"=="0" echo Build failed. See the message above and build-logs for details.
pause
exit /b %WDM_BUILD_EXIT%
