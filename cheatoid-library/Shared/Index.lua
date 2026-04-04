-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- TODO: Build DSL for dependency graph & automatic loader for loading modules/packages/dependencies...
-- TODO: HTTP/GitHub package importing (for dynamic/zipped modules, etc.)

--for _, f in next, Package.GetFiles(nil, ".lua") do
--	print("[package file]", f)
--end

-- Patch require like a good boi
if "INTERNAL - Package Lua Implementation" == debug.getinfo(require, "S").source then
	require = require("@cheatoid/patch/require.lua")
end

-- Import dependencies
local gaimers = require("@cheatoid/loader/gaimers")

-- Localized global functions for better performance
_G.GAIMERS = gaimers
_G.r = require
gaimers.r = require
local g, a, i, m, e, r, s = gaimers.g, gaimers.a, gaimers.i, gaimers.m, gaimers.e, gaimers.r, gaimers.s

----------------------------------------------------------------------
-- TODO: Auto initialize modules/packages, add dependency injection...
----------------------------------------------------------------------

-- As much as I like my custom loader GAIMERS, it is not particularly hintful to LuaLS...
-- So I am rethinking my approach and will use the standard require function instead;
-- Most likely, I will end up making a custom script that will "compile" the dependency graph,
-- use the standard require function to load them, in order to have proper editor navigation...

r "Config"
m "@cheatoid/standalone/debug_helper"
m "@cheatoid/standalone/type_check"
r "RequireFolder"
r "ConVar"
g "oop" "@cheatoid/oop/oop"
m "BroadcastLua"
r "ClientsideLua"
