@echo off
cd /d "%~dp0"

setlocal

rem Get the absolute path of the folder containing this batch file
set "REPO_ROOT=%~dp0"
rem Remove the trailing backslash
set "REPO_ROOT=%REPO_ROOT:~0,-1%"

rem 1. Tell Neovim your repo is the "Home" for config
rem Neovim looks for a folder named 'nvim' inside XDG_CONFIG_HOME
set "XDG_CONFIG_HOME=%REPO_ROOT%"

rem 2. Redirect all data/plugins to stay inside the repo
set "XDG_DATA_HOME=%REPO_ROOT%\.nvim-data"
set "XDG_STATE_HOME=%REPO_ROOT%\.nvim-data\state"
set "XDG_CACHE_HOME=%REPO_ROOT%\.nvim-data\cache"

rem 3. Launch the portable Neovim binary
rem %* allows you to pass arguments (like: launch-nvim.bat myfile.lua)
"%REPO_ROOT%\.nvim-win64\bin\nvim.exe" -u "%REPO_ROOT%\nvim\init.lua" %*

endlocal

rem exit /b 0
