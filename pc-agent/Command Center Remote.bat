@echo off
rem Opens the Command Center remote in its own phone-shaped window.
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0remote.ps1"
