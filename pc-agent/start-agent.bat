@echo off
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo.
  echo Node.js was not found. Install the LTS build from https://nodejs.org
  echo then run this file again.
  echo.
  pause
  exit /b 1
)
node server.js
pause
