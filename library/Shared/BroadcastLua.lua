-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Import type_check
local tc = require "@cheatoid/standalone/type_check"
local check_string = tc.check_string

local ID = "BroadcastLua"

if Server then
	local function BroadcastLua(code)
		check_string(1)
		return Events.BroadcastRemote(ID, code)
	end

	local function SendLua(player, code)
		check_string(2)
		return Events.CallRemote(ID, player, code)
	end

	-- Export the API to be accessed by other packages
	return {
		BroadcastLua = BroadcastLua,
		SendLua = SendLua,
	}
end

-- Client-side
local load, pcall, type = load, pcall, type
Events.SubscribeRemote(ID, function(code)
	local fn = load(code, ID, "t")
	if type(fn) == "function" then
		pcall(fn)
	end
end)
