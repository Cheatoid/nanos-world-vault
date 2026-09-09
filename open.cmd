@echo off
cd /d "%~dp0"
setlocal

rem Set custom directory path
set "WORKDIR=%~dp0\"

rem Launch a 2x2 grid layout
wt.exe -d "%WORKDIR%" -p "Command Prompt" cmd.exe /k cls ; split-pane -V -d "%WORKDIR%" -p "Command Prompt" cmd.exe /k cls ; split-pane -H -d "%WORKDIR%" -p "Command Prompt" cmd.exe /k cls ; focus-pane -t 0 ; split-pane -H -d "%WORKDIR%" -p "Command Prompt" cmd.exe /k cls

endlocal
