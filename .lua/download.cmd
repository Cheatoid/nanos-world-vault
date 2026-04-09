@echo off
cd /d "%~dp0"
setlocal
dotnet run --verbosity minimal DownloadLua.cs -- %* 2>&1
endlocal
exit /b %ERRORLEVEL%
