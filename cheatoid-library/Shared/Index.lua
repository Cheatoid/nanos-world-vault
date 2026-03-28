-- TODO: automatic loader & DSL for loading dependencies...

--for _, file in next, Package.GetFiles(nil, ".lua") do
--	print("[package file]", file)
--end

local r = Package.Require
r"DebugHelper.lua"
r"TypeCheck.lua"
r"RequireFolder.lua"
r"ConVar.lua"
r"@cheatoid/oop/oop.lua"
r"BroadcastLua.lua"
r"ClientsideLua.lua"
