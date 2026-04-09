cmake_minimum_required(VERSION 3.31)

project(Lua LANGUAGES C)

set(LUA_SOURCE_DIR "" CACHE PATH "Path to extracted Lua source directory (containing src/)")
if(NOT EXISTS "${LUA_SOURCE_DIR}/src")
	message(FATAL_ERROR "Invalid LUA_SOURCE_DIR: '${LUA_SOURCE_DIR}'. It must contain a 'src/' folder.")
endif()

set(LUA_DIR "${LUA_SOURCE_DIR}")
set(SRC_DIR "${LUA_SOURCE_DIR}/src")

# Collect all source/header files
file(GLOB LUA_SOURCES CONFIGURE_DEPENDS
	"${SRC_DIR}/*.c"
	"${SRC_DIR}/*.h"
	"${SRC_DIR}/*.hpp"
)

# Remove interpreter and compiler sources from library build
list(REMOVE_ITEM LUA_SOURCES "${SRC_DIR}/lua.c")
list(REMOVE_ITEM LUA_SOURCES "${SRC_DIR}/luac.c")

# Only Release configuration
set(CMAKE_CONFIGURATION_TYPES "Release" CACHE STRING "" FORCE)
set(CMAKE_BUILD_TYPE "Release" CACHE STRING "" FORCE)

# Only x64 platform
set(CMAKE_GENERATOR_PLATFORM "x64" CACHE STRING "" FORCE)

# Output directory configuration (same as premake: LUA_DIR for binaries, SRC_DIR for intermediate)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${LUA_DIR}")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${LUA_DIR}")
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${LUA_DIR}")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_RELEASE "${LUA_DIR}")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY_RELEASE "${LUA_DIR}")
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY_RELEASE "${LUA_DIR}")

set(CMAKE_OBJECT_OUTPUT_DIRECTORY "${SRC_DIR}")

# Build lua (SharedLib/DLL)
add_library(lua SHARED ${LUA_SOURCES})
target_include_directories(lua PUBLIC "${SRC_DIR}")
set_target_properties(lua PROPERTIES
	OUTPUT_NAME "lua"
	ARCHIVE_OUTPUT_NAME "lua"
)

# Windows-specific configuration for lua
if(WIN32)
	target_compile_definitions(lua PRIVATE _CRT_SECURE_NO_WARNINGS LUA_BUILD_AS_DLL)
endif()

# Build lua_static (StaticLib)
add_library(lua_static STATIC ${LUA_SOURCES})
target_include_directories(lua_static PUBLIC "${SRC_DIR}")
set_target_properties(lua_static PROPERTIES
	OUTPUT_NAME "lua_static"
	ARCHIVE_OUTPUT_NAME "lua_static"
)

# Windows-specific configuration for lua_static
if(WIN32)
	target_compile_definitions(lua_static PRIVATE _CRT_SECURE_NO_WARNINGS)
endif()

# Build lua_exe (ConsoleApp)
add_executable(lua_exe "${SRC_DIR}/lua.c")
target_include_directories(lua_exe PRIVATE "${SRC_DIR}")
set_target_properties(lua_exe PROPERTIES
	OUTPUT_NAME "lua"
)
target_link_libraries(lua_exe PRIVATE lua)
add_dependencies(lua_exe lua)

# Build luac_exe (ConsoleApp)
add_executable(luac_exe "${SRC_DIR}/luac.c")
target_include_directories(luac_exe PRIVATE "${SRC_DIR}")
set_target_properties(luac_exe PROPERTIES
	OUTPUT_NAME "luac"
)
target_link_libraries(luac_exe PRIVATE lua_static)
add_dependencies(luac_exe lua_static)

# Release configuration optimizations (matching premake5.lua)
set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} /O2 /Oi /Ot /Oy /Ob2 /GF /Gy /GL")
set(CMAKE_EXE_LINKER_FLAGS_RELEASE "${CMAKE_EXE_LINKER_FLAGS_RELEASE} /LTCG /OPT:REF /OPT:ICF")
set(CMAKE_SHARED_LINKER_FLAGS_RELEASE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE} /LTCG /OPT:REF /OPT:ICF")
set(CMAKE_STATIC_LINKER_FLAGS_RELEASE "${CMAKE_STATIC_LINKER_FLAGS_RELEASE} /LTCG /OPT:REF /OPT:ICF")
