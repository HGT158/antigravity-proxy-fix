@echo off
rem ============================================================
rem  Antigravity Proxy Fixer - double-click launcher
rem  Calls Windows PowerShell using the current user's permissions.
rem  Run with " -ProbeOnly" / " -SkipRelaunch" etc. to pass args:
rem      fix-antigravity.cmd -ProbeOnly
rem ============================================================
setlocal DisableDelayedExpansion

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
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File "%~dp0antigravity-proxy-fix.ps1" %*
set "RC=%ERRORLEVEL%"

echo.
if not "%RC%"=="0" (
  echo  [FAILED] Exit code %RC%. See messages above.
)
echo.
pause
endlocal & exit /b %RC%
