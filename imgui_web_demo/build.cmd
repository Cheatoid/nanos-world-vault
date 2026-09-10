@echo off
cd /d "%~dp0"

rem Author: Cheatoid ~ https://github.com/Cheatoid
rem License: MIT
rem
rem Usage: build.cmd [release|debug] [norun]
rem
rem   release (default) - minified SINGLE_FILE demo for GitHub Pages.
rem                       Configures MinSizeRel (-O3) in build\ and copies
rem                       build\index.html over imgui_web_demo\index.html.
rem   debug             - UNMINIFIED SINGLE_FILE demo for local nanos WebUI.
rem                       Configures Debug (-O0 -g3, full assertions, same
rem                       shell_minimal.html shell + bridge) in build-debug\
rem                       and copies build-debug\index.debug.html over
rem                       library\Client\UI\ImGuiDemo.html, which the local
rem                       library\Client\UI\ImGui.html bootstrap loads first
rem                       (no network, no iframe delegation warning).
rem   norun             - skip the emrun browser launch at the end.
rem
rem Examples:
rem   build.cmd               (release + run)
rem   build.cmd debug         (unminified local demo + run)
rem   build.cmd debug norun   (unminified local demo, no browser)

set MODE=%~1
if "%MODE%"=="" set MODE=release
set NORUN=%~2

if /i "%MODE%"=="debug" goto :debug

:release
del "index.html" >NUL 2>&1
ver >NUL

call "..\emsdk\emsdk_env.bat"
if errorlevel 1 (
	echo FAILED: emsdk_env.bat release.
	exit /b 1
)

echo Cleaning CMake cache and build directory...
if exist "build" (
	rmdir /s /q "build" >NUL 2>&1
)

echo Configuring with CMake (MinSizeRel, minified)...
rem NOTE: shell is the LOCAL shell_minimal.html (bridge + window.UI facade),
rem NOT ../imgui/examples/libs/emscripten/shell_minimal.html (bare upstream
rem shell without the Lua bridge - Lua could not drive that one).
call emcmake cmake -S . -B build -DCMAKE_BUILD_TYPE=MinSizeRel -G Ninja
if errorlevel 1 (
	echo CMake configure FAILED - release.
	exit /b 1
)

cmake --build build --config MinSizeRel
if errorlevel 1 (
	echo Build FAILED - release, see ninja/em++ output above.
	exit /b 1
)

if not exist "build\index.html" (
	echo Build FAILED: build\index.html was not produced.
	exit /b 1
)
copy /Y "build\index.html" "index.html"
if errorlevel 1 (
	echo FAILED: could not copy build\index.html over index.html.
	exit /b 1
)

if /i "%NORUN%"=="norun" goto :done
call emrun build/index.html
rem call emrun --no_browser --port 8000 .
rem python -m http.server 8000
rem http://localhost:8000/index.html
goto :done

:debug
if exist "build-debug" (
	echo Cleaning CMake cache and debug build directory...
	rmdir /s /q "build-debug" >NUL 2>&1
)

call "..\emsdk\emsdk_env.bat"
if errorlevel 1 (
	echo FAILED: emsdk_env.bat debug.
	exit /b 1
)

echo Configuring with CMake (Debug, UNMINIFIED)...
call emcmake cmake -S . -B build-debug -DCMAKE_BUILD_TYPE=Debug -G Ninja
if errorlevel 1 (
	echo CMake configure FAILED - debug.
	exit /b 1
)

cmake --build build-debug --config Debug
if errorlevel 1 (
	echo Build FAILED - debug, see ninja/em++ output above.
	exit /b 1
)

if not exist "build-debug\index.debug.html" (
	echo Build FAILED: build-debug\index.debug.html was not produced.
	exit /b 1
)
if not exist "..\library\Client\UI" (
	echo FAILED: destination directory ..\library\Client\UI does not exist.
	exit /b 1
)
copy /Y "build-debug\index.debug.html" "..\library\Client\UI\ImGuiDemo.html"
if errorlevel 1 (
	echo FAILED: could not copy build-debug\index.debug.html over library\Client\UI\ImGuiDemo.html.
	exit /b 1
)

echo.
echo Unminified local demo written to library\Client\UI\ImGuiDemo.html
echo In-game command: imgui_init + imgui_demo
echo Zero-iframe alternative: lua imgui.Initialize({url="file://UI/ImGuiDemo.html"})
echo.

if /i "%NORUN%"=="norun" goto :done
call emrun build-debug/index.debug.html

:done
