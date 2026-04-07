@echo off
cd /d "%~dp0/.."
git config core.autocrlf false
git config core.longpaths true
git config core.hooksPath .git-hooks
