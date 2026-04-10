-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Source-engine inspired ConVar library

-- Localized global functions for better performance
local next = next
local pcall = pcall
local type = type
local tonumber = tonumber
local tostring = tostring
local setmetatable = setmetatable
local math_modf = math.modf
local string_find = string.find
local string_format = string.format
local string_lower = string.lower
local string_upper = string.upper
local table_concat = table.concat
--local Console_Log, Console_Warn = Console.Log, Console.Warn
local Client_GetValue, Client_SetValue = Client and Client.GetValue, Client and Client.SetValue
local Server_SetValue = Server and Server.SetValue
local Events_SubscribeRemote, Events_CallRemote = Events.SubscribeRemote, Events.CallRemote
local Events_BroadcastRemote = Events.BroadcastRemote

-- TODO: Release command-line/chat-commands parser library; https://github.com/Cheatoid/nanos-world-vault/issues/13

-- Use Patcher to monkey-patch Console.RegisterCommand globally (make it case-insensitive)
do
	local Patcher = require("@cheatoid/standalone/patcher")
	local function Hook_ConsoleRegisterCommand(orig, command, ...)
		if command then
			command = string_lower(command)
		end
		return orig(command, ...)
	end
	Patcher.new()
	--:id("case-insensitive patch for Console.RegisterCommand")
		:target(Console, "RegisterCommand")
		:replace(Hook_ConsoleRegisterCommand)
		:apply()
	--_G.Console.RegisterCommand = Hook_ConsoleRegisterCommand
	--Console.Subscribe("PlayerSubmit", function(text)
	--	-- TODO: Handle console commands using case-insensitive matching (requires parser library)
	--end)
end
local Console_RegisterCommand = Console.RegisterCommand -- cache it after hooking

-- Import dependencies
local oop = require("@cheatoid/oop/oop")
local tc = require("@cheatoid/standalone/type_check")
local check_type, opt_type = tc.check, tc.opt
local check_boolean, check_integer, check_string, check_number, check_function, check_userdata =
	tc.check_boolean, tc.check_integer, tc.check_string, tc.check_number, tc.check_function, tc.check_userdata
local opt_number, opt_string, opt_table = tc.opt_number, tc.opt_string, tc.opt_table
local make_bit_enum = require("@cheatoid/standalone/5_3/bitflags").make_enum

local table = require("@cheatoid/standard/table")
local table_ensure_lazy = table.ensure_lazy
local table_make_case_insensitive = table.make_case_insensitive

---@class ConVar
--- Console Variable (CVar) library.
local ConVar = {}
ConVar.__index = ConVar

----------------------------------------------------------------------
-- Internal Configuration & State
----------------------------------------------------------------------
local REPLICATE_EVENT = "ConVar::Replicate"
local REQUEST_EVENT = "ConVar::RequestSet"
local USERINFO_EVENT = "ConVar::UserInfoUpdate"

--- Registry of all registered ConVars (case-insensitive keyed).
--- Structure: [string: name] = ConVar: object
---@type table<string, ConVar>
local ConVars = table_make_case_insensitive()

--- Registry for per-player userinfo (client -> server convars).
--- Structure: [Player] = { [string: cvar_name] = string: cvar_value }
local PlayerUserInfos = oop.WeakTable() -- TODO: Perhaps store directly on Player objects to persist state (support hotreload)

----------------------------------------------------------------------
-- Flags Definition
----------------------------------------------------------------------

--- Bitwise flags for ConVar behavior
local FLAG
do
	local FCVAR = make_bit_enum()
	-- @formatter:off
	FLAG = {
		NONE               = 0,
		ARCHIVE            = FCVAR(), -- Save to config (Server side) - TODO
		REPLICATED         = FCVAR(), -- Server sends this to clients
		CLIENT_CAN_EXECUTE = FCVAR(), -- Clients can change this (e.g., graphical settings)
		CHEAT              = FCVAR(), -- Only usable if sv_cheats is 1
		HIDDEN             = FCVAR(), -- Don't show in generic find commands
		NEVER_AS_STRING    = FCVAR(), -- Prevent displaying the value
		USERINFO           = FCVAR(), -- Client sends this to server automatically (client-side only)
	}
	-- @formatter:on
end

--- Helper to convert flag integer to a readable string.
---@param flags number
---@return string string
local function FlagsToString(flags) -- TODO: Move to Lua lib
	if flags == 0 then return "NONE" end
	local parts = {}
	for k, v in next, FLAG do
		if (flags & v) ~= 0 then
			parts[#parts + 1] = k
		end
	end
	return #parts > 0 and table_concat(parts, ", ") or "NONE"
end

--- Validates that a value is a proper bitflag (non-negative integer or valid flag enum value).
---@param val any The value to validate.
---@param flag_enum table The flag enum table to validate against (result from MakeBitEnum()).
---@param param_name string The name of the parameter being validated (for error messages).
---@param param_pos integer The parameter position (for error messages).
---@return integer integer The validated flag value.
local function ValidateBitFlag(val, flag_enum, param_name, param_pos) -- TODO: Move to Lua lib
	-- Allow nil, default to 0
	if val == nil then return 0 end

	if type(val) ~= "number" then
		check_integer(param_pos)
	end

	if val < 0 or val ~= (math_modf(val)) then
		return error(string_format("%s must be a non-negative integer, got %s", param_name, tostring(val)), 3)
	end

	-- Validate that the value doesn't contain bits outside the defined flags
	if val > 0 and flag_enum then
		-- Create a bitmask of all valid flags
		local valid_mask = 0
		for _, flag_val in next, flag_enum do
			valid_mask = valid_mask | flag_val
		end

		-- Check if value contains any invalid bits
		if (val & ~valid_mask) ~= 0 then
			return error(string_format("%s contains invalid flag bits: %s", param_name, tostring(val)), 3)
		end
	end

	return val
end

--- Helper to detect type using modf for integer detection.
---@param val any
---@return string string
local function GetValueType(val)
	local t = type(val)
	if t == "number" then
		local _, frac_part = math_modf(val)
		return frac_part == 0 and "int" or "float"
	end
	if t == "boolean" then
		return "boolean"
	end
	if t == "string" then
		return "string"
	end
	return "unknown"
end

--- Helper to cast value to string (for networking/console).
---@param val any
---@return string string
local function ValueToString(val)
	if type(val) == "boolean" then return val and "1" or "0" end
	return tostring(val)
end

--- Helper to parse string to target type.
---@param str string
---@param targetType string
---@return any any
local function StringToValue(str, targetType)
	if targetType == "boolean" then
		-- Allow literal "true" / "false" strings
		--local str_lower = string.lower(str)
		--if str_lower == "true" then return true end
		--if str_lower == "false" then return false end
		-- Handle numeric strings (e.g. "1", "0")
		local num = tonumber(str)
		-- If num is nil (invalid input), default to false instead of returning nil
		return (num and num > 0) or false
	end
	if targetType == "int" then
		local num = tonumber(str) or 0
		return (math_modf(num))
	end
	if targetType == "float" then
		return tonumber(str) or 0.0
	end
	return str
end

----------------------------------------------------------------------
-- Metamethods
----------------------------------------------------------------------

--- Allows converting the ConVar object directly to a string representation of its value.
--- Usage: print(my_cvar)
---@return string string
function ConVar:__tostring()
	return self:GetString()
end

----------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------

--- Creates a new ConVar or retrieves an existing one.
---@param name string The name of the console variable.
---@param default boolean|number|integer|string|nil The default value.
---@param help string|nil Description of the ConVar.
---@param flags integer|nil Bitwise flags (ConVar.FLAG).
---@param min_val number|integer|nil Minimum value (numeric only).
---@param max_val number|integer|nil Maximum value (numeric only).
---@param params table|nil The list of supported parameters to display in the console (strings only).
---@return ConVar ConVar The console variable object.
local function ConVar_Register(name, default, help, flags, min_val, max_val, params)
	check_string(1)
	opt_type(default, "boolean|number|string", 2)
	opt_string(3)
	--opt_integer(4)
	flags = ValidateBitFlag(flags, FLAG, "flags", 4)
	opt_number(5)
	opt_number(6)
	opt_table(7)

	if default == nil then default = "" end
	local val_type = GetValueType(default)
	if val_type == "boolean" then
		min_val, max_val = 0, 1
	end

	-- Singleton check
	local cvar = ConVars[name]
	if cvar then
		Console.Warn("[ConVar] Warning: '%s' already registered. Returning existing instance.", name)
		return cvar
	end

	local self = setmetatable({}, ConVar)
	self.Name = string_lower(name) -- ConVar name in lowercase
	self.Type = val_type
	self.Default = default
	self.Flags = flags
	self.Help = help or ""
	--- Weak table (keys) allows callbacks to be garbage collected if no other references exist.
	self.Callbacks = {} --setmetatable({}, { __mode = "k" })
	self.Min = min_val
	self.Max = max_val

	local initial_val = default

	-- Server-side persistence logic
	if Server and (flags & FLAG.ARCHIVE) ~= 0 then
		local saved = Server.GetValue(name)
		if saved ~= nil then
			initial_val = StringToValue(saved, val_type)
		end
	end

	-- Client-side initialization from engine
	if Client then
		if (flags & FLAG.REPLICATED) ~= 0 then
			local synced_val = Client_GetValue(name)
			if synced_val ~= nil then
				initial_val = StringToValue(synced_val, val_type)
			end
		elseif (flags & FLAG.USERINFO) ~= 0 then
			local local_val = Client_GetValue(name)
			if local_val ~= nil then
				initial_val = StringToValue(local_val, val_type)
			end
		end
	end

	-- Clamp initial value
	if type(initial_val) == "number" then
		if self.Min and initial_val < self.Min then initial_val = self.Min end
		if self.Max and initial_val > self.Max then initial_val = self.Max end
	end

	self.Value = initial_val

	-- Register console command (lowercase)
	Console_RegisterCommand(self.Name, function(...)
		self:OnConsoleCommand({ ... })
	end, self.Help, params)

	ConVars[name] = self

	-- Server: Initial replication or persistence
	if Server then
		if (flags & FLAG.REPLICATED) ~= 0 or (flags & FLAG.ARCHIVE) ~= 0 then
			Server_SetValue(self.Name, ValueToString(self.Value), true)
		end
	end

	return self
end
ConVar.Register = ConVar_Register

function ConVar:__call(...)
	return ConVar_Register(...)
end

----------------------------------------------------------------------
-- Core Methods
----------------------------------------------------------------------

--- Internal handler for console input.
---@param args table
function ConVar:OnConsoleCommand(args)
	if not args or #args == 0 then
		-- Use FlagsToString for human readable output
		Console.Log(
			string_format(
				"%s%s [Flags: %s]",
				self.Name,
				(self.Flags & FLAG.NEVER_AS_STRING) ~= 0 and "" or string_format(" = %q", ValueToString(self.Value)),
				FlagsToString(self.Flags)
			)
		)
		if self.Help and #self.Help > 0 then Console.Log(" - " .. self.Help) end
		return
	end

	local input = args[1]
	local new_val = StringToValue(input, self.Type)

	if Server then
		self:SetValue(new_val, "Server Console")
	elseif Client then
		if (self.Flags & FLAG.CLIENT_CAN_EXECUTE) ~= 0 or (self.Flags & FLAG.USERINFO) ~= 0 then
			self:SetValue(new_val, "Client Console")
		else
			Events_CallRemote(REQUEST_EVENT, self.Name, ValueToString(new_val))
		end
	end
end

--- Sets the value of the ConVar.
---@param value any
---@param source string|nil Optional identifier of who changed the value.
function ConVar:SetValue(value, source)
	local typed_val
	if self.Type == "boolean" then
		if type(value) == "boolean" then
			typed_val = value
		else
			typed_val = StringToValue(tostring(value), "boolean")
		end
	elseif self.Type == "int" then
		local num = tonumber(value) or 0
		typed_val = (math_modf(num))
	elseif self.Type == "float" then
		typed_val = tonumber(value) or 0.0
	else
		typed_val = tostring(value)
	end

	-- Clamping
	if type(typed_val) == "number" then
		if self.Min and typed_val < self.Min then typed_val = self.Min end
		if self.Max and typed_val > self.Max then typed_val = self.Max end
	end

	if self.Value == typed_val then return end

	self.Value = typed_val

	-- Trigger Callbacks (Snapshot keys to avoid issues with weak table mutation during iteration)
	local callbacks = {}
	for cb in next, self.Callbacks do
		callbacks[#callbacks + 1] = cb
	end

	local value = (self.Flags & FLAG.NEVER_AS_STRING) ~= 0 and "" or self.Value

	for _, cb in next, callbacks do
		if self.Callbacks[cb] then
			local ok, err = pcall(cb, self.Name, value, source)
			if not ok then
				Console.Warn(string_format("[ConVar] Error in callback for '%s': %s", self.Name, tostring(err)))
			end
		end
	end

	if Server then
		-- Engine Sync & Persistence
		if (self.Flags & FLAG.REPLICATED) ~= 0 or (self.Flags & FLAG.ARCHIVE) ~= 0 then
			Server_SetValue(self.Name, ValueToString(value), true)
		end

		-- Lua Callback Sync (for clients)
		if (self.Flags & FLAG.REPLICATED) ~= 0 then
			Events_BroadcastRemote(REPLICATE_EVENT, self.Name, ValueToString(value))
		end
	elseif Client then
		-- USERINFO Logic: Send to server
		if (self.Flags & FLAG.USERINFO) ~= 0 then
			Events_CallRemote(USERINFO_EVENT, self.Name, ValueToString(value))
			Client_SetValue(self.Name, ValueToString(value))
		end
	end
end

--- Explicitly sets a Float value.
---@param value number
function ConVar:SetFloat(value)
	check_number(2)
	self:SetValue(value)
end

--- Explicitly sets an Int value.
---@param value integer
function ConVar:SetInt(value)
	check_integer(2)
	self:SetValue((math_modf(value)))
end

--- Explicitly sets a Bool value.
---@param value boolean
function ConVar:SetBool(value)
	check_boolean(2)
	self:SetValue(value)
end

--- Explicitly sets a String value.
---@param value string
function ConVar:SetString(value)
	check_string(2)
	self:SetValue(value)
end

--- Gets the raw value.
---@return any any
function ConVar:GetValue()
	return self.Value
end

--- Gets the value as a String.
---@return string string
function ConVar:GetString()
	return (self.Flags & FLAG.NEVER_AS_STRING) ~= 0 and "" or ValueToString(self.Value)
end

--- Gets the value as an Integer (truncated towards zero).
---@return integer integer
function ConVar:GetInt()
	local num = tonumber(self.Value)
	if not num then return 0 end
	return (math_modf(num))
end

--- Gets the value as a Float.
---@return number number
function ConVar:GetFloat()
	return tonumber(self.Value) or 0.0
end

--- Gets the value as a Boolean.
---@return boolean boolean
function ConVar:GetBool()
	local value = self.Value
	if type(value) == "boolean" then return value end
	if type(value) == "number" then return value ~= 0 end
	if type(value) == "string" then
		return (tonumber(value) or 0) ~= 0
	end
	return false
end

--- Resets the ConVar to its default value.
function ConVar:Reset()
	self:SetValue(self.Default, "Reset")
end

--- Adds a callback function to be executed when the ConVar changes.
---@param func function Signature callback(name, new_value, source)
function ConVar:AddChangeCallback(func)
	check_function(2)
	self.Callbacks[func] = true
end

--- Removes a previously added callback.
---@param func function
function ConVar:RemoveChangeCallback(func)
	check_function(2)
	self.Callbacks[func] = nil
end

----------------------------------------------------------------------
-- Static / Global Methods
----------------------------------------------------------------------

--- Retrieves a ConVar by name.
---@param name string The name of the console variable.
---@return ConVar|nil ConVar The console variable object, or nil if not found.
local function ConVar_Get(name)
	check_string(1)
	return ConVars[name]
end
ConVar.Get = ConVar_Get

--- Gets an existing ConVar or creates a new one if it doesn't exist.
---@param name string The name of the console variable.
---@param default boolean|number|integer|string|nil The default value.
---@param help string|nil Description of the ConVar.
---@param flags integer|nil Bitwise flags (ConVar.FLAG).
---@param min_val number|integer|nil Minimum value (numeric only).
---@param max_val number|integer|nil Maximum value (numeric only).
---@param params table|nil The list of supported parameters to display in the console (strings only).
---@return ConVar ConVar The console variable object.
local function ConVar_GetOrCreate(name, default, help, flags, min_val, max_val, params)
	check_string(1)
	local cvar = ConVars[name]
	if cvar then return cvar end
	return ConVar_Register(name, default, help, flags, min_val, max_val, params)
end
ConVar.GetOrCreate = ConVar_GetOrCreate

if Server then
	--- Retrieves a USERINFO value for a specific player on the server.
	--- This is used for client-side ConVars that replicate their state to the server.
	---@param player Player The player object.
	---@param name string The ConVar name.
	---@return any any The value (converted to type if registered) or string. Returns nil if not found.
	local function ConVar_GetPlayerInfo(player, name)
		check_userdata(1)
		check_string(2)

		local info = PlayerUserInfos[player]
		if not info then return end

		local str_val = info[name]
		if not str_val then return end

		local cvar = ConVars[name]
		if cvar then
			return StringToValue(str_val, cvar.Type)
		end

		return str_val
	end
	ConVar.GetPlayerInfo = ConVar_GetPlayerInfo

	function Player:GetPlayerInfo(cvar_name)
		return ConVar_GetPlayerInfo(self, cvar_name)
	end
end

--- Returns an iterator over all registered ConVars.
---@return function, table
local function ConVar_GetIterator()
	return next, ConVars
end
ConVar.GetIterator = ConVar_GetIterator

----------------------------------------------------------------------
-- Networking Setup & Utility Commands
----------------------------------------------------------------------

--- Helper function to format and log a single ConVar entry.
--- Returns true if the ConVar should be displayed, false otherwise.
---@param name string The ConVar name.
---@param cvar ConVar The ConVar object.
---@param filter string|nil Optional filter pattern string.
---@return boolean boolean True if the ConVar was displayed.
local function LogConVarEntry(name, cvar, filter)
	-- Check filter
	if filter and not string_find(name, filter, nil, false) then
		return false
	end

	-- Check hidden flag
	if (cvar.Flags & FLAG.HIDDEN) ~= 0 and not filter then
		return false
	end

	local val_str = cvar:GetString()
	local help_str = cvar.Help or ""
	local minmax_str = ""
	local flag_str = " [Flags: " .. FlagsToString(cvar.Flags) .. "]"

	if cvar.Min or cvar.Max then
		minmax_str = string_format(" [Min: %s, Max: %s]", cvar.Min or "N/A", cvar.Max or "N/A")
	end

	Console.Log(
		string_format(
			"%s%s%s%s - %s",
			cvar.Name,
			(cvar.Flags & FLAG.NEVER_AS_STRING) ~= 0 and "" or string_format(" = %q", val_str),
			minmax_str,
			flag_str,
			help_str
		)
	)
	return true
end

Console_RegisterCommand("cvarlist", function(args)
	local filter
	if args and args[1] then
		filter = string_upper(args[1])
	end

	Console.Log("-------------- ConVar List --------------")

	local count = 0
	for name, cvar in ConVar_GetIterator() do
		if getmetatable(cvar) == ConVar then
			if LogConVarEntry(cvar.Name, cvar, filter) then
				count = count + 1
			end
		end
	end

	Console.Log(string_format("------------------------------ (%d found)", count))
end)

if Server then
	local sv_cheats = ConVar_Register(
		"sv_cheats",
		Server.GetCustomSettings().cheats or false,
		"Enable cheats on the server",
		FLAG.REPLICATED,
		0, 1
	)
	sv_cheats:AddChangeCallback(function(name, new_value, source)
		Console.Log("%s has been %s by %s", name, new_value and "enabled" or "disabled", source)
	end)

	local sv_password = ConVar_Register(
		"sv_password",
		Server.GetCustomSettings().password or "",
		"Enable password-protection",
		FLAG.NEVER_AS_STRING
	)
	local Server_SetPassword = Server.SetPassword
	sv_password:AddChangeCallback(function(name, new_value, source)
		-- NOTE #1: new_value is empty string due to cvar flag NEVER_AS_STRING
		-- NOTE #2: Must use GetValue() instead of GetString() to bypass cvar flag NEVER_AS_STRING
		Server_SetPassword(sv_password:GetValue(), true)
	end)

	Events_SubscribeRemote(REQUEST_EVENT, function(player, name, value_str)
		local cvar = ConVars[name]
		if not cvar then return end

		if (cvar.Flags & FLAG.CHEAT) ~= 0 then
			--local sv_cheats = ConVars["SV_CHEATS"]
			if not sv_cheats:GetBool() then
				Console.Warn(
					string_format(
						"[ConVar] %s tried to set cheat cvar '%s' without sv_cheats 1.",
						player and ("Player " .. player:GetName()) or "Unknown",
						name
					)
				)
				return
			end
		end

		cvar:SetValue(StringToValue(value_str, cvar.Type), "Client " .. player:GetID())
	end)

	Events_SubscribeRemote(USERINFO_EVENT, function(player, name, value_str)
		print("DEBUG:" .. USERINFO_EVENT, player, name, value_str)
		local cvar = ConVars[name]
		if cvar then
			if (cvar.Flags & FLAG.USERINFO) == 0 then return end
			value_str = ValueToString(StringToValue(value_str, cvar.Type))
		end
		table_ensure_lazy(PlayerUserInfos, player, table_make_case_insensitive)[name] = value_str
	end)

	Player.Subscribe("Destroy", function(player)
		PlayerUserInfos[player] = nil
	end)
elseif Client then
	Events_SubscribeRemote(REPLICATE_EVENT, function(name, value_str)
		local cvar = ConVars[name]
		if cvar then
			cvar:SetValue(StringToValue(value_str, cvar.Type), "Server")
		end
	end)
end

-- Export the API to be accessed by other packages
return ConVar
