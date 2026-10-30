@echo off
REM Windows entry point for freellmapi-cc-setup.
REM Double-click this file (or run it from cmd) instead of run.sh.
REM
REM It finds a working bash (WSL, Git Bash, or Cygwin), runs the real
REM script, and keeps the window open if anything fails so the error is
REM visible instead of vanishing.

setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%.."

REM --- Find a usable bash --------------------------------------------------
set "BASH_EXE="

REM 1. WSL (preferred — gives a real Unix environment)
where wsl.exe >nul 2>&1
if %errorlevel% equ 0 (
  set "BASH_EXE=wsl.exe"
  goto :run
)

REM 2. Git Bash
where bash.exe >nul 2>&1
if %errorlevel% equ 0 (
  set "BASH_EXE=bash.exe"
  goto :run
)

REM 3. Any bash on PATH
where bash >nul 2>&1
if %errorlevel% equ 0 (
  for /f "tokens=*" %%a in ('where bash') do set "BASH_EXE=%%a"
  goto :run
)

echo.
echo ERROR: No usable bash found.
echo.
echo freellmapi-cc-setup needs a Unix shell. Install one of:
echo   - WSL2 (recommended): run "wsl --install" in an elevated PowerShell
echo   - Git Bash:    https://git-scm.com/download/win
echo   - Cygwin:      https://cygwin.com
echo.
echo Then re-run this file.
echo.
goto :fail

:run
echo === freellmapi-cc-setup ===
echo Bash: %BASH_EXE%
echo Repo:  %REPO_ROOT%
echo.

REM Run the real script. Pass through all command-line arguments.
%BASH_EXE% "%REPO_ROOT%\scripts\run.sh" %*
set "EXIT_CODE=%errorlevel%"

if %EXIT_CODE% neq 0 (
  echo.
  echo ============================================================
  echo Script exited with error code %EXIT_CODE%.
  echo Common causes on Windows 11:
  echo   - Docker Desktop isn't running (start it, wait for the whale)
  echo   - WSL is installed but broken  (see README "WSL opens and crashes")
  echo   - Port 80 or 3001 is blocked by Windows Defender Firewall
  echo   - Run this from an elevated terminal if you see permission errors
  echo ============================================================
  echo.
  echo Full output above. Press any key to close this window...
  pause >nul
  exit /b %EXIT_CODE%
)

echo.
echo Done. Press any key to close this window...
pause >nul
exit /b 0

:fail
pause >nul
exit /b 1