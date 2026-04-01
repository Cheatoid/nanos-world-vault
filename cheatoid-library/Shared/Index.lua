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
gaimers.r = require
local g = gaimers.g
local a = gaimers.a
local i = gaimers.i
local m = gaimers.m
local e = gaimers.e
local r = gaimers.r
local s = gaimers.s

----------------------------------------------------------------------
-- TODO: Auto initialize modules/packages
----------------------------------------------------------------------
m "@cheatoid/standalone/debug_helper"
m "@cheatoid/standalone/type_check"
r "RequireFolder"
r "ConVar"
g "oop" "@cheatoid/oop/oop"
m "BroadcastLua"
r "ClientsideLua"
