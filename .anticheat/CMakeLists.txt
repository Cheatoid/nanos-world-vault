cmake_minimum_required(VERSION 3.10)
project(anticheat_library C)

# Define the source files for the static library
set(ANTICHET_SOURCES
    ac_crc.c
    ac_process.c
    ac_hooks.c
    ac_anti_debug.c
    ac_anti_vm.c
)

# Define the header files
set(ANTICHET_HEADERS
    ac_common.h
)

# Add the static library target
add_library(anticheat STATIC ${ANTICHET_SOURCES} ${ANTICHET_HEADERS})

# Specify include directories
target_include_directories(anticheat PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

# Link necessary Windows libraries
target_link_libraries(anticheat PRIVATE
    psapi
    shlwapi
    ntdll
    iphlpapi
    wbemuuid
    comsuppw
)

# Set compile options for Windows
if(WIN32)
    target_compile_definitions(anticheat PRIVATE _CRT_SECURE_NO_WARNINGS)
    target_compile_options(anticheat PRIVATE /W4 /WX /Zi /GR- /EHsc /O2 /GS /analyze)
endif()

# Note about inline assembly in ac_anti_vm.c:
# The inline assembly sections for AC_CheckRedPill and AC_CheckVMwareBackdoor
# are typically only supported by MSVC in 32-bit mode.
# In 64-bit builds, the current implementation in ac_anti_vm.c uses preprocessor directives
# to conditionally compile these sections, where they will effectively return FALSE.
# For full 32-bit compilation with inline assembly, ensure your CMake generator
# and toolchain are configured for 32-bit (e.g., -A Win32 for Visual Studio).
