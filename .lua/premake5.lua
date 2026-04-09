newoption {
	trigger     = "lua",
	value       = "PATH",
	description = "Path to extracted Lua folder (containing src/)"
}

if not _OPTIONS["lua"] then
	return error("You must pass --lua=foldername (e.g., --lua=lua-5.4.8)")
end

local LUA_DIR = _OPTIONS["lua"]
local SRC_DIR = LUA_DIR .. "/src"

workspace "Lua"
	configurations { "Release" }
	platforms { "x64" }
	location (SRC_DIR) -- <--- solution + vcxproj files go into src/

filter "platforms:x64"
	architecture "x86_64"

filter "configurations:Release"
	optimize "Speed"
	buildoptions {
		"/O2",      -- Maximize speed
		"/Oi",      -- Enable intrinsic functions
		"/Ot",      -- Favor fast code
		"/Oy",      -- Omit frame pointers
		"/Ob2",     -- Inline function expansion
		"/GF",      -- Enable string pooling
		"/Gy",      -- Function-level linking
		"/GL",      -- Whole program optimization
	}
	linkoptions {
		"/LTCG",    -- Link-time code generation
		"/OPT:REF", -- Eliminate unreferenced data
		"/OPT:ICF", -- Perform identical COMDAT folding
	}

project "lua"
	kind "SharedLib"
	language "C"
	targetdir (LUA_DIR)
	objdir    (SRC_DIR)
	implibdir (LUA_DIR)
	implibname "lua"

	files {
		SRC_DIR .. "/**.c",
		SRC_DIR .. "/**.h",
		SRC_DIR .. "/**.hpp"
	}

	removefiles {
		SRC_DIR .. "/lua.c",
		SRC_DIR .. "/luac.c"
	}

	filter "system:windows"
		defines { "_CRT_SECURE_NO_WARNINGS", "LUA_BUILD_AS_DLL" }
		implibextension ".lib"

project "lua_static"
	kind "StaticLib"
	language "C"
	targetdir (LUA_DIR)
	objdir    (SRC_DIR)

	files {
		SRC_DIR .. "/**.c",
		SRC_DIR .. "/**.h",
		SRC_DIR .. "/**.hpp"
	}

	removefiles {
		SRC_DIR .. "/lua.c",
		SRC_DIR .. "/luac.c"
	}

	filter "system:windows"
		defines { "_CRT_SECURE_NO_WARNINGS" }

project "lua_exe"
	kind "ConsoleApp"
	language "C"
	targetname "lua"
	targetdir (LUA_DIR)
	objdir    (SRC_DIR)

	files { SRC_DIR .. "/lua.c" }
	includedirs { SRC_DIR }
	libdirs { LUA_DIR }
	links { "lua" }
	dependson { "lua" }

project "luac_exe"
	kind "ConsoleApp"
	language "C"
	targetname "luac"
	targetdir (LUA_DIR)
	objdir    (SRC_DIR)

	files { SRC_DIR .. "/luac.c" }
	includedirs { SRC_DIR }
	libdirs { LUA_DIR }
	links { "lua_static" }
	dependson { "lua_static" }
