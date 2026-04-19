-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- A shared module implementing `lua` console command for executing Lua code via console.
-- Provides server-side `allowcslua` convar to enable client-side Lua console command.

local ID = "allowcslua"
local Enabled = false -- disabled by default

local load, pcall, select = load, pcall, select
local string_format, string_match = string.format, string.match
local table_concat, table_pack, table_unpack = table.concat, table.pack, table.unpack
local HASH = "#"

-- Import FileWrapper for file operations
local file = require "FileWrapper"

local function RunLua(...) -- TODO: Move to Lua lib (runlua)
	if select(HASH, ...) == 0 then
		return
	end
	local input = table_concat({ ... }, " ")
	local code, source
	-- Detect if input is a file path
	if file.is_file_path(input) then
		-- Try to read and load the file
		--local file_content, err = file.read(input)
		--if file_content then
		--	code = file_content
		--	source = "@" .. input -- prepend @ prefix for file source
		--	Console.Log("[lua] Executing file: " .. input)
		--	--Console.Log(file_content)
		--else
		--	-- File doesn't exist or can't be read, treat as code
		--	Console.Warn("[lua] File not found or unreadable: %s (treating as code)", err)
		--	code = input
		--	source = nil
		--end
		-- Use Package.Require force-load (more reliable)
		input = string.normalize_path(input)
		if not string_match(input, "%.[Ll][Uu][Aa]$") then
			input = input .. ".lua"
		end
		Console.Log("[lua] Executing file: " .. input)
		code = string_format("return require(%q, true);", input)
		source = input
	else
		-- Treat as code
		code = input
		source = nil
	end
	-- Load, validate, and execute the compiled code
	local fn, err = load(code, source, "t", _ENV or _G)
	if type(fn) == "function" then
		local packed = table_pack(pcall(fn))
		local ok, res = packed[1], packed[2]
		if ok then
			if #packed >= 2 then
				Console.Log("[lua] %s", table_unpack(packed, 2)) -- okay
			end
		else
			Console.Warn("[lua] %s", res) -- runtime error (e.g. attempt to index nil)
		end
	else
		Console.Error("[lua] %s", err) -- compile-time error (syntax, etc.)
	end
end

if Server then
	-- Import reference wrapper
	local ref = require "@cheatoid/ref/ref"

	--Enabled = Server.GetCustomSettings().enable_cslua or Enabled
	Enabled = Package.GetPersistentData("enable_cslua") or Enabled -- read from package toml
	--print("initial enable_cslua:", Enabled)

	-- NOTE: This writes into config.json (next to NanosWorldServer executable)
	local Config = require "Config"
	-- Create a reactive Config reference, which will automatically flush to disk upon changing a field
	local cfg = ref.reactive(Config.read(), function(_, _)
		Config.write(true)
	end) ---@type cheatoidlib.config
	-- Alternative:
	--local cfg = table.monitor({ enable_cslua = Enabled }, {
	--	on_write = function(_, key, value)
	--		Config.write(true)
	--	end
	--})
	Enabled = Config.get("enable_cslua", cfg.enable_cslua)
	print("[config] enable_cslua:", Enabled)

	-- Broadcast the convar's value initially
	Server.SetValue(ID, Enabled, true)
	--Events.BroadcastRemote(ID, Enabled)

	Enabled = nil -- NOTE: Stop using 'Enabled' after this point, and use ref cfg.enable_cslua instead :)

	-- When the server is starting
	--Server.Subscribe("Start", function()
	--	print("Server started")
	--end)

	-- When the server stops / shutdown
	Server.Subscribe("Stop", function()
		Config.write()
		--print("Server stopped")
	end)

	-- When a Player joins the server
	Player.Subscribe("Spawn", function(ply)
		--print("[Player.Spawn]", ply:GetSteamID())
		--Events.BroadcastRemote(ID, cfg.enable_cslua)
		Events.CallRemote(ID, ply, cfg.enable_cslua)
	end)

	-- When the Player leaves the server
	--Player.Subscribe("Destroy", function(ply)
	--	print("[Player.Destroy]", ply:GetSteamID())
	--end)

	-- C2S: Query the convar's value; old approach
	--Events.SubscribeRemote(ID, function(player)
	--	Events.CallRemote(ID, player, cfg.enable_cslua)
	--end)

	-- ConVar to enable/disable client-side Lua console command
	-- TODO: Use ConVar API
	Console.RegisterCommand(ID, function(state)
		local valid_input --= false
		local changed --= false

		if state then
			local num = tonumber(state)
			if num then
				valid_input = true
				if num ~= 0 then
					changed = cfg.enable_cslua == false
					if changed then
						cfg.enable_cslua = true -- automatically flushes to disk
					end
				else          --if state == "0" then
					changed = cfg.enable_cslua == true
					if changed then
						cfg.enable_cslua = false -- automatically flushes to disk
					end
				end
			end
		end

		if valid_input then
			local enabled = cfg.enable_cslua
			if changed then -- only broadcast a message if the state has changed
				Server.SetValue(ID, enabled, true)
				Events.BroadcastRemote(ID, enabled)
				Package.SetPersistentData("enable_cslua", enabled)
				--Config.set("enable_cslua", enabled)
				--Config.write(true)
				Console.Log("Client-side Lua command has been %s", enabled and "enabled" or "disabled")
				Chat.BroadcastMessage(
					string.format(
						"Client-side Lua command has been %s",
						enabled and "<green>enabled</>" or "<red>disabled</>"
					)
				)
			else
				Console.Log("Client-side Lua command is already %s", enabled and "enabled" or "disabled")
			end
		else
			Console.Warn(
				"Invalid or no argument, expected: 0 to disable, or 1 to enable client-side Lua console command")
		end
	end, "enable or disable client-side Lua console command", { "0/1" })

	Console.RegisterCommand("lua", RunLua, "run Lua", { "code string -or- file path" })
else
	Enabled = Client.GetValue(ID, Enabled)

	-- S2C: synchronise convar state
	Events.SubscribeRemote(ID, function(enable)
		--Enabled = not not enable -- old approach; make sure we have a boolean
		Enabled = Client.GetValue(ID, enable) -- new approach
		if Enabled then
			-- FIXME: Go upvote https://feedback.nanos-world.com/p/client-setconsoleenabled
			Client.SetDebugEnabled(true)
		end
	end)

	-- Query the convar's value initially
	--Events.CallRemote(ID)

	Console.RegisterCommand("lua", function(...)
		Enabled = Client.GetValue(ID, false) -- new approach
		if Enabled then
			RunLua(...)
		end
	end, "run Lua (" .. ID .. " must be enabled on server-side)", { "code string -or- file path" })
end
