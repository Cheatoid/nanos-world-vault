rem Author: Cheatoid ~ https://github.com/Cheatoid
rem License: MIT

@echo off
cd /d "%~dp0"

setlocal

if "%~1"=="" (
	echo Download+Generate+Build script for Lua ^CMake / Premake5^)
	echo Usage: %~nx0 ^<lua_version_or_dir^> [--download] [--premake]
	echo Example: %~nx0 5.4.8
	echo          %~nx0 5.4.8 --download
	echo          %~nx0 lua-5.4.8 --premake
	exit /b 1
)

set LUA_VERSION=5.4.8
set USE_DOWNLOAD=0
set USE_PREMAKE=0

rem Auto-prepend "lua-" if the argument doesn't start with it
set LUA_SOURCE_DIR=%~1
set "PREFIX=%LUA_SOURCE_DIR:~0,4%"
if not "%PREFIX%"=="lua-" (
	set LUA_SOURCE_DIR=lua-%~1
)

rem Parse additional flags
:parse_args
if "%~2"=="" goto args_done
if "%~2"=="--download" (
	set USE_DOWNLOAD=1
	shift
	goto parse_args
)
if "%~2"=="--premake" (
	set USE_PREMAKE=1
	shift
	goto parse_args
)
shift
goto parse_args

:args_done

rem Download Lua source if requested
if %USE_DOWNLOAD%==1 (
	echo Downloading Lua %LUA_VERSION%...
	call "download.cmd" --version "%LUA_VERSION%" --force
	if %ERRORLEVEL% neq 0 (
		echo Error: Download failed
		exit /b %ERRORLEVEL%
	)
	echo.
)

if not exist "%LUA_SOURCE_DIR%\src" (
	echo Error: Invalid LUA_SOURCE_DIR '%LUA_SOURCE_DIR%'
	echo It must contain a 'src/' folder.
	echo Use --download flag to download Lua source first.
	exit /b 1
)

rem Detect which build system to use
if exist "%LUA_SOURCE_DIR%\src\Lua.slnx" (
	set USE_PREMAKE=1
)

if %USE_PREMAKE%==1 (
	echo Using Premake5 build system...
	echo.
	if not exist "%LUA_SOURCE_DIR%\src\Lua.slnx" (
		echo Generating Visual Studio 2026 project files with Premake5...
		premake5.exe --arch=x86_64 --os=windows --shell=cmd --verbose --cc=msc-v145 --dotnet=msnet vs2026 "--lua=%LUA_SOURCE_DIR%"
		if %ERRORLEVEL% neq 0 (
			echo Error: Premake5 generation failed
			exit /b %ERRORLEVEL%
		)
	) else (
		echo Using existing Premake5 project files
	)

	echo.
	echo Building project with MSBuild...
	call "C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvars64.bat" >NUL 2>&1
	msbuild "%LUA_SOURCE_DIR%\src\Lua.slnx" /p:Configuration=Release /p:Platform=x64
	if %ERRORLEVEL% neq 0 (
		echo Error: MSBuild failed
		exit /b %ERRORLEVEL%
	)
) else (
	echo Using CMake build system...
	echo.
	set BUILD_DIR=%LUA_SOURCE_DIR%\src\build
	set SOURCE_DIR=%LUA_SOURCE_DIR%\src

	echo Generating CMake build files...
	if exist "%BUILD_DIR%" rmdir /s /q "%BUILD_DIR%" >NUL 2>&1
	mkdir "%BUILD_DIR%"

	cmake -G "Visual Studio 18 2026" -A x64 -S "%SOURCE_DIR%" -B "%BUILD_DIR%" "-DLUA_SOURCE_DIR=%LUA_SOURCE_DIR%"
	if %ERRORLEVEL% neq 0 (
		echo Error: CMake generation failed
		exit /b %ERRORLEVEL%
	)

	echo.
	echo Building project...
	cmake --build "%BUILD_DIR%" --config Release
	if %ERRORLEVEL% neq 0 (
		echo Error: Build failed
		exit /b %ERRORLEVEL%
	)
)

echo.
echo Build completed successfully

endlocal

exit /b 0
