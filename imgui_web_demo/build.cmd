rem Author: Cheatoid ~ https://github.com/Cheatoid
rem License: MIT

@echo off
cd /d "%~dp0"

del "index.html" >NUL 2>&1

call "..\emsdk\emsdk_env.bat"

rem call emcmake cmake -S . -B build -DCMAKE_BUILD_TYPE=MinSizeRel -DIMGUI_EMSCRIPTEN_WEBGPU_FLAG="--use-port=%~dp0emdawnwebgpu_pkg\emdawnwebgpu.port.py" -G Ninja
call emcmake cmake -S . -B build -DCMAKE_BUILD_TYPE=MinSizeRel -G Ninja

cmake --build build --config MinSizeRel

rem emcc main.cpp ../imgui/*.cpp ../imgui/backends/imgui_impl_glfw.cpp ../imgui/backends/imgui_impl_opengl3.cpp -I../imgui -s SINGLE_FILE -sNO_FILESYSTEM=1 -s USE_GLFW=3 -s USE_ZLIB=1 -s USE_LIBPNG=1 -s FULL_ES3=1 -s WASM=1 -s ALLOW_MEMORY_GROWTH=1 -s NO_EXIT_RUNTIME=0 -s ASSERTIONS=1 -s EXPORTED_FUNCTIONS="['_main']" -s EXPORTED_RUNTIME_METHODS="['ccall','cwrap']" -O3 --shell-file "../imgui/examples/libs/emscripten/shell_minimal.html" -o build/index.html

copy "build\index.html" "index.html"

call emrun build/index.html
rem call emrun --no_browser --port 8000 .
rem python -m http.server 8000
rem http://localhost:8000/index.html
