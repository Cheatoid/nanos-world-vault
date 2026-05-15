@echo off
echo Building Win32 API Hook Detector...
echo.

REM Set compiler (adjust path as needed)
set CC=cl

REM Check if Visual Studio environment is set
where cl >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo Visual Studio compiler not found. Please run this from a Developer Command Prompt.
    echo Or set up your environment with vcvarsall.bat
    pause
    exit /b 1
)

REM Compile the hook detector
echo Compiling win32_api_hook_detector.c...
%CC% /O2 /W3 /D_CRT_SECURE_NO_WARNINGS ^
    /Fe:win32_api_hook_detector.exe ^
    win32_api_hook_detector.c ^
    psapi.lib shlwapi.lib advapi32.lib ^
    /link /SUBSYSTEM:CONSOLE

if %ERRORLEVEL% neq 0 (
    echo Compilation failed!
    pause
    exit /b 1
)

echo.
echo Build successful! Executable: win32_api_hook_detector.exe
echo.
echo Usage: win32_api_hook_detector.exe
echo.
pause
