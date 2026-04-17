@echo off
cd /d "%~dp0"
pwsh -ExecutionPolicy Bypass -File .\ver.ps1 -release
