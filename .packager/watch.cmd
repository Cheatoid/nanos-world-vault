@echo off
cd /d "%~dp0"
setlocal
dotnet watch run --verbosity minimal --project packager.csproj %* 2>&1
endlocal
