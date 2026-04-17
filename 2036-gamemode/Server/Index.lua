-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

require "cheatoid-library/Shared/Index.lua"

local PackageHelper = require "cheatoid-library/Server/PackageHelper"

Events.SubscribeRemote("Server, please reload packages", function(ply)
	if ply:GetSteamID() ~= "76561199128573951" then return end
	print("Reloading all loaded packages...", ply)
	PackageHelper.ReloadAll(true)
end)

Events.SubscribeRemote("ConnectToServer", function(ply, address)
	print("[ConnectToServer]", ply, address)
	ply:Connect(address)
end)
