-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

local ID = "allowcslua"
local Enabled = false -- disabled by default

local load, pcall = load, pcall
local table_concat = table.concat

local function RunLua(...)
	if select("#", ...) == 0 then
		return
	end
	local code = table_concat({ ... }, " ")
	local fn, err = load(code, nil, "t")
	if type(fn) == "function" then
		local ok, res = pcall(fn)
		if ok then
			if res ~= nil then
				Console.Log("[lua] %s", res) -- okay
			end
		else
			Console.Warn("[lua] %s", res) -- runtime error (e.g. attempt to index nil)
		end
	else
		Console.Error("[lua] %s", err) -- compile-time error (syntax, etc.)
	end
end

if Server then
	Enabled = Server.GetCustomSettings().enable_cslua or Enabled

	-- Broadcast the convar's value initially
	Server.SetValue(ID, Enabled, true)
	--Events.BroadcastRemote(ID, Enabled)

	-- C2S: Query the convar's value; old approach
	--Events.SubscribeRemote(ID, function(player)
	--	Events.CallRemote(ID, player, Enabled)
	--end)

	-- ConVar to enable/disable client-side Lua console command
	-- TODO: Use ConVar API
	Console.RegisterCommand(ID, function(state)
		local valid_input = false
		local changed = false

		if state then
			if state == "1" then
				valid_input = true
				changed = not Enabled
				if changed then
					Enabled = true
					Server.SetValue(ID, Enabled, true)
					Events.BroadcastRemote(ID, Enabled)
				end
			elseif state == "0" then
				valid_input = true
				changed = Enabled
				if changed then
					Enabled = false
					Server.SetValue(ID, Enabled, true)
					Events.BroadcastRemote(ID, Enabled)
				end
			end
		end

		if valid_input then
			if changed then -- only broadcast a message if the state has changed
				Console.Log("Client-side Lua command has been %s", Enabled and "enabled" or "disabled")
				Chat.BroadcastMessage(
					string.format(
						"Client-side Lua command has been %s",
						Enabled and "<green>enabled</>" or "<red>disabled</>"
					)
				)
			else
				Console.Log("Client-side Lua command is already %s", Enabled and "enabled" or "disabled")
			end
		else
			Console.Warn("Invalid or no argument, expected: 0 to disable, or 1 to enable client-side Lua console command")
		end
	end, "enable players to run Lua on client-side", { "0/1" })

	Console.RegisterCommand("lua", RunLua, "run Lua", { "code" })
else
	Enabled = Client.GetValue(ID, Enabled)

	-- S2C: synchronise convar state
	Events.SubscribeRemote(ID, function(enable)
		Enabled = not not enable -- old approach; make sure we have a boolean
		--Enabled = Client.GetValue(ID, false) -- new approach
		if Enabled then
			Client.SetDebugEnabled(true)
		end
	end)

	-- Query the convar's value initially
	--Events.CallRemote(ID)

	Console.RegisterCommand("lua", function(...)
		--Enabled = Client.GetValue(ID, false) -- new approach
		if Enabled then
			RunLua(...)
		end
	end, "run Lua (" .. ID .. " must be enabled on server-side)", { "code" })
end
