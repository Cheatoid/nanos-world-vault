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
gaimers.r = require

-- Globally export GAIMERS + require for convenience
_G.GAIMERS = gaimers
_G.r = require

-- Localized global functions for better performance
local g, a, i, m, e, r, s = gaimers.g, gaimers.a, gaimers.i, gaimers.m, gaimers.e, gaimers.r, gaimers.s

----------------------------------------------------------------------
-- TODO: Auto initialize modules/packages, add dependency injection...
----------------------------------------------------------------------

-- As much as I like my custom loader GAIMERS, it is not fully cooperative with LuaLS...
-- So I am rethinking my approach and will use the standard require function instead;
-- Most likely, I will end up making a custom script that will "compile" the dependency graph,
-- use the standard require function to load them, in order to have proper editor navigation...

print("Package name:", Package.GetName())
print("Package version:", Package.GetVersion())
--do
--	local filename = string.format("test_%s.txt", Server and "server" or "client")
--	print("Creating " .. filename)
--	local testfile = File(filename, true)
--	testfile:Write(string.format("Hello %s\n", Server and "Server" or "Client"))
--	testfile:Flush()
--	testfile:Close()
--	print("Created " .. filename)
--end

r "metadata.g"
r "Config"
m "@cheatoid/standalone/debug_helper"
m "@cheatoid/standalone/type_check"
r "RequireFolder"
r "ConVar"
g "oop" "@cheatoid/oop/oop"
m "BroadcastLua"
r "ClientsideLua"
