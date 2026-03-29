-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

---@uses TypeCheck

local ID = "BroadcastLua"

if Server then
	local function BroadcastLua(code)
		TypeCheckArg(1, "string")
		return Events.BroadcastRemote(ID, code)
	end

	local function SendLua(player, code)
		TypeCheckArg(2, "string")
		return Events.CallRemote(ID, player, code)
	end

	-- Export the API to be accessed by other packages
	return {
		BroadcastLua = BroadcastLua,
		SendLua = SendLua,
	}
end

-- Client-side
local load, pcall = load, pcall
Events.SubscribeRemote(ID, function(code)
	local fn = load(code, ID, "t")
	if type(fn) == "function" then
		pcall(fn)
	end
end)
