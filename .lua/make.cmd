@echo off
setlocal EnableExtensions
cd /d "%~dp0"

rem Author: Cheatoid ~ https://github.com/Cheatoid
rem License: MIT

if "%~1"=="" (
	echo Download+Generate+Build script for Lua ^(CMake / Premake5^)
	echo Usage  : %~nx0 ^<lua_version_or_dir^> [--download] [--premake]
	echo Example: %~nx0 5.4.9
	echo          %~nx0 5.4.9 --download
	echo          %~nx0 lua-5.4.9 --premake
	exit /b 1
)

set "USE_DOWNLOAD=0"
set "USE_PREMAKE=0"

rem Resolve source dir + version from first arg (accept "5.4.9" or "lua-5.4.9")
set "LUA_SOURCE_DIR=%~1"
if /i not "%LUA_SOURCE_DIR:~0,4%"=="lua-" set "LUA_SOURCE_DIR=lua-%~1"
set "LUA_VERSION=%LUA_SOURCE_DIR%"
if /i "%LUA_SOURCE_DIR:~0,4%"=="lua-" set "LUA_VERSION=%LUA_SOURCE_DIR:~4%"

rem Parse additional flags (preserve %1-derived vars, iterate over rest)
shift
:parse_args
if "%~1"=="" goto :args_done
if "%~1"=="--download" (
	set "USE_DOWNLOAD=1"
	shift
	goto :parse_args
)
if "%~1"=="--premake" (
	set "USE_PREMAKE=1"
	shift
	goto :parse_args
)
echo Warning: Unknown argument "%~1" - ignoring.
shift
goto :parse_args

:args_done

rem Download Lua source if requested (goto-style to avoid parens-in-block parsing bug)
if not "%USE_DOWNLOAD%"=="1" goto :skip_download
echo Cleaning up previous %LUA_VERSION% ...
rmdir /s /q "%LUA_SOURCE_DIR%" >NUL 2>&1
echo Downloading Lua %LUA_VERSION% ...
call "download.cmd" --version "%LUA_VERSION%" --force
if errorlevel 1 (
	echo Error: Download failed.
	exit /b 1
)
echo.
:skip_download

if not exist "%LUA_SOURCE_DIR%\src" (
	echo Error: Invalid LUA_SOURCE_DIR '%LUA_SOURCE_DIR%'
	echo It must contain a 'src/' folder.
	echo Use --download flag to download Lua source first.
	exit /b 1
)

rem Auto-detect premake project
if exist "%LUA_SOURCE_DIR%\src\Lua.slnx" set "USE_PREMAKE=1"

if "%USE_PREMAKE%"=="1" goto :build_premake
goto :build_cmake

:build_premake
echo Using Premake5 build system...
echo.
if not exist "%LUA_SOURCE_DIR%\src\Lua.slnx" goto :premake_generate
echo Using existing Premake5 project files.
goto :premake_build

:premake_generate
echo Generating Visual Studio 2026 project files with Premake5...
if exist "%~dp0premake5.exe" goto :have_premake
where premake5.exe >NUL 2>&1
if errorlevel 1 (
	echo Error: premake5.exe not found in PATH.
	exit /b 1
)
:have_premake
premake5.exe --arch=x86_64 --os=windows --shell=cmd --verbose --cc=msc-v145 --dotnet=msnet vs2026 "--lua=%LUA_SOURCE_DIR%"
if errorlevel 1 (
	echo Error: Premake5 generation failed.
	exit /b 1
)

:premake_build
echo.
echo Building project with MSBuild...
if exist "C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvars64.bat" call "C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvars64.bat" >NUL 2>&1
msbuild "%LUA_SOURCE_DIR%\src\Lua.slnx" /p:Configuration=Release /p:Platform=x64
if errorlevel 1 (
	echo Error: MSBuild failed.
	exit /b 1
)
goto :build_ok

:build_cmake
echo Using CMake build system...
echo.
set "BUILD_DIR=%LUA_SOURCE_DIR%\src\build"
set "SOURCE_DIR=%LUA_SOURCE_DIR%\src"
echo Generating CMake build files...
if exist "%BUILD_DIR%" rmdir /s /q "%BUILD_DIR%" >NUL 2>&1
mkdir "%BUILD_DIR%" >NUL 2>&1
cmake -G "Visual Studio 18 2026" -A x64 -S "%SOURCE_DIR%" -B "%BUILD_DIR%" "-DLUA_SOURCE_DIR=%LUA_SOURCE_DIR%"
if errorlevel 1 (
	echo Error: CMake generation failed.
	exit /b 1
)
echo.
echo Building project...
cmake --build "%BUILD_DIR%" --config Release
if errorlevel 1 (
	echo Error: Build failed.
	exit /b 1
)
goto :build_ok

:build_ok
echo.
echo Build completed successfully.

endlocal

exit /b 0
