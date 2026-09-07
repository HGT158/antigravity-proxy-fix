@echo off
rem ============================================================
rem  Antigravity Proxy Fixer - double-click launcher
rem  Calls the main PowerShell script with execution policy bypass.
rem  Run with " -ProbeOnly" / " -SkipRelaunch" etc. to pass args:
rem      fix-antigravity.cmd -ProbeOnly
rem ============================================================
setlocal
cd /d "%~dp0"

echo.
echo  ==================================================
echo    Antigravity Proxy Fixer  (double-click to run)
echo  ==================================================
echo.
echo  [i] Make sure your proxy client (Clash Verge / Clash
echo      / v2rayN ...) is RUNNING, then press any key.
echo      Press Ctrl+C to abort.
echo.
pause >nul

echo.
echo  [*] Running fix script ...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0antigravity-proxy-fix.ps1" %*
set RC=%ERRORLEVEL%

echo.
if "%RC%"=="0" (
  echo  [OK] Done. Now open Antigravity from the desktop icon.
  echo       Keep the proxy client running whenever you use it.
) else (
  echo  [FAILED] Exit code %RC%. See messages above.
)
echo.
pause
endlocal
