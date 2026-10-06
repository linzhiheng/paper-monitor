@echo off
rem Wrapper for paper-monitor-windows-amd64.ps1: bypasses PowerShell execution
rem policy for this invocation only, so no system setting has to be changed.
setlocal
if "%~1"=="" (
  echo Usage: %~nx0 {menu^|run^|uninstall}
  exit /b 64
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0paper-monitor-windows-amd64.ps1" %*
exit /b %ERRORLEVEL%
