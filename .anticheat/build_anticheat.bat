@echo off
setlocal

:: Set the path to your Visual Studio installation.
:: You might need to adjust this path based on your VS version and installation directory.
:: For VS 2022, it's typically under "C:\Program Files (x86)\Microsoft Visual Studio\2022\7<EDITION>"
:: Example for VS 2026 Community: C:\Program Files\Microsoft Visual Studio\18\Community
set "VS_PATH=C:\Program Files\Microsoft Visual Studio\18\Insiders"

:: Set up the Visual Studio build environment (for 64-bit).
:: For 32-bit compilation, change "amd64" to "x86" in the path, e.g., "VsDevCmd.bat -arch=x86" or call "vcvars32.bat" directly.
:: Note: Inline assembly used in ac_anti_vm.c (AC_CheckRedPill, AC_CheckVMwareBackdoor) is only supported in 32-bit MSVC.
:: If compiling for 64-bit, these specific functions will need to be re-written using intrinsics or external assembly,
:: or simply return FALSE as implemented in the provided code for 64-bit.
if exist "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat" (
    call "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat"
) else if exist "%VS_PATH%\VC\Auxiliary\Build\vcvarsall.bat" (
    call "%VS_PATH%\VC\Auxiliary\Build\vcvarsall.bat" amd64
) else (
    echo Error: Visual Studio build environment script not found.
    echo Please verify the VS_PATH variable in this script.
    goto :eof
)

echo Compiling Anti-Cheat C files...

:: Compile each C file into an object file
cl /c /Zi /W4 /WX /GR- /EHsc /O2 /GS /analyze /D_CRT_SECURE_NO_WARNINGS /I. ac_crc.c ac_process.c ac_hooks.c ac_anti_debug.c ac_anti_vm.c

if errorlevel 1 (
    echo Compilation failed.
    goto :eof
)

echo Creating static library...

:: Create a static library from the object files
lib /OUT:anticheat.lib ac_crc.obj ac_process.obj ac_hooks.obj ac_anti_debug.obj ac_anti_vm.obj

if errorlevel 1 (
    echo Library creation failed.
    goto :eof
)

echo Build successful! anticheat.lib created.

:: Optional: Clean up intermediate object files
del *.obj

endlocal
