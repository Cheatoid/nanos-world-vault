-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- TODO: Build DSL for dependency graph & automatic loader for loading modules/packages/dependencies...
-- TODO: HTTP/GitHub package importing (for dynamic/zipped modules, etc.)

--for _, f in next, Package.GetFiles(nil, ".lua") do
--	print("[package file]", f)
--end

-- Localized global functions for better performance
local assert, next, type, debug = assert, next, type, debug

-- Patch require
require("@cheatoid/patch/require.lua")

-- Import dependencies
local curry = require("@cheatoid/standalone/curry")
local table = require("@cheatoid/standard/table")
local deep_copy = table.deep_copy
local shallow_copy = table.shallow_copy
local table_pack = table.pack
local table_unpack = table.unpack

----------------------------------------------------------------------
-- Initialize modules/packages
----------------------------------------------------------------------
m "DebugHelper"
m "TypeCheck"
r "RequireFolder"
r "ConVar"
g "oop" "@cheatoid/oop/oop"
m "BroadcastLua"
r "ClientsideLua"
