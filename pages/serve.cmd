@echo off
cd /d "%~dp0"

rem http://localhost:8000/

python -m http.server -b 0.0.0.0 -d . 8000
