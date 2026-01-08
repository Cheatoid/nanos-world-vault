-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

--if _G.ConVar then return _G.ConVar end

--- @class ConVar
--- Console Variable (CVar) library.
local ConVar = {}
ConVar.__index = ConVar

-- ==========================================
-- Internal Configuration & State
-- ==========================================
local REPLICATE_EVENT = "ConVar::Replicate"
local REQUEST_EVENT = "ConVar::RequestSet"
local USERINFO_EVENT = "ConVar::UserInfoUpdate"

--- Structure: [name] = ConVar
local ConVars = {}
--- Registry for per-player userinfo (client -> server convars).
--- Structure: [Player] = { ["cvar_name"] = value_string }
local PlayerUserInfos = setmetatable({}, { __mode = "k" }) -- TODO: Perhaps store directly on Player objects to persist state (support hotreload)

-- ==========================================
-- Bitwise Helpers
-- TODO: Move to a separate script
-- ==========================================

--- Checks if the value contains all of the specified flags.
--- @param val number: The current bitmask.
--- @param flag number: The flag or bitmask to check.
--- @return boolean: True if all bits in flag are set in val.
local function HasFlags(val, flags)
	return (val & flags) == flags
end

--- Checks if the value contains any of the specified flags.
--- @param val number: The current bitmask.
--- @param flags number: A mask of flags to check against.
--- @return boolean: True if any bit in flags is set in val.
local function HasAnyFlag(val, flags)
	return (val & flags) ~= 0
end

--- Adds (sets) the specified flags to the value.
--- @param val number: The current bitmask.
--- @param flag number: The flag or bitmask to add.
--- @return number: The new bitmask with flags added.
local function AddFlag(val, flag)
	return val | flag
end

--- Removes (clears) the specified flags from the value.
--- @param val number: The current bitmask.
--- @param flag number: The flag or bitmask to remove.
--- @return number: The new bitmask with flags removed.
local function RemoveFlag(val, flag)
	return val & (~flag)
end

--- Creates a factory function for generating sequential bit flags.
--- Each call to the returned function returns the next power of 2 (1, 2, 4, 8...).
--- @return function: A function that returns a new flag number.
local function MakeBitEnum()
	local bit_index = 0
	return function()
		local flag = 1 << bit_index
		bit_index = bit_index + 1
		return flag
	end
end

-- ==========================================
-- Type Checker
-- TODO: Move to a separate script
-- ==========================================

--- Gets a list of parameter names for the function at the given stack level.
--- @param level number: The stack level (1 = current function, 2 = function calling this, etc.)
--- @return table|nil: A list of strings representing the parameter names, or nil if out of bounds.
local function GetParameterNames(level)
	-- Get info about the function at this level.
	-- "u" includes: 'nparams' (number of parameters) and 'isvararg'
	local info = debug.getinfo(level, "u")
	if not info then
		return -- Invalid level
	end

	local params = {}

	-- Iterate strictly from 1 to nparams.
	-- This prevents reading internal locals defined in the function body.
	for i = 1, info.nparams do
		local name = debug.getlocal(level, i)
		params[i] = name
	end

	return params
end

--- Helper to get a specific parameter name by index.
--- @param level number: The stack level.
--- @param index number: The argument index (1-based).
--- @return string|nil: The name of the parameter, or nil if out of bounds.
local function GetParameterName(level, index)
	local info = debug.getinfo(level, "u")
	if info and 1 <= index and index <= info.nparams then
		-- debug.getlocal returns the name as the first return value
		return debug.getlocal(level, index)
	end
end

--- Helper for strict type checking.
--- @param val any: The value to check.
--- @param expected_type string|table: The expected Lua type (e.g., "string") or a list of types (e.g., {"string", "number"} or "string|number").
--- @param arg_index number: The argument positional index (1, 2, 3...).
--- @param optional boolean|nil: If true, the argument is optional (nil is accepted).
--- @param stack_level number|nil: Stack level for error reporting (defaults to 3).
local function TypeCheck(val, expected_type, arg_index, optional, stack_level)
	-- Set default stack level.
	-- We add 1 to the base level (usually 3) to account for this helper function,
	-- ensuring the error points to the calling library function, not this helper.
	stack_level = (stack_level or 3) + 1

	-- If optional is true and value is nil, pass immediately
	if optional and val == nil then
		return
	end

	-- Normalize expected_type into a list of allowed types
	local allowed_types = {}
	if type(expected_type) == "table" then
		allowed_types = expected_type
	else
		-- Assume string. Check for union syntax "string|number"
		for t in string.gmatch(expected_type, "([^|]+)") do
			allowed_types[#allowed_types + 1] = t
		end
	end

	-- Perform Type Check using pairs
	local actual_type = type(val)
	local is_valid = false

	for _, t in next, allowed_types do
		if actual_type == t or t == "any" or (t == "nil" and val == nil) then
			is_valid = true
			break
		end
	end

	-- Handle Error
	if not is_valid then
		-- Build the type string using pairs to ensure order is captured into a list
		local type_list = {}
		for i, t in next, allowed_types do
			type_list[#type_list + 1] = t
		end

		local type_str = ""
		local count = #type_list

		for i, t in next, type_list do
			if i > 1 then
				type_str = (i == count) and (type_str .. " or ") or (type_str .. ", ")
			end
			type_str = type_str .. t
		end

		local funcName = debug.getinfo(2, "n")
		funcName = funcName.name or "?"

		local prefix = optional and "optional " or ""

		-- arg_index is used for the message (#1, #2...), stack_level is used for the trace
		return error(string.format(
				"bad argument #%d (%s) to '%s' (expected %s%s, got %s)",
				arg_index or "?",
				GetParameterName(2, arg_index) or "",
				funcName,
				prefix,
				type_str,
				actual_type),
			stack_level
		)
	end
end

-- ==========================================
-- Flags Definition
-- ==========================================

--- bitwise flags for ConVar behavior.
do
	local FCVAR = MakeBitEnum()
	ConVar.FLAG = {
		NONE = 0,
		ARCHIVE = FCVAR(),          -- Save to config (Server side) - TODO
		REPLICATED = FCVAR(),       -- Server sends this to clients
		CLIENT_CAN_EXECUTE = FCVAR(), -- Clients can change this (e.g., graphical settings)
		CHEAT = FCVAR(),            -- Only usable if sv_cheats is 1
		HIDDEN = FCVAR(),           -- Don't show in generic find commands
		NEVER_AS_STRING = FCVAR(),  -- Prevent displaying the value - TODO
		USERINFO = FCVAR(),         -- Client sends this to server automatically (client-side only)
	}
end

--- Helper to convert flag integer to a readable string.
--- @param flags number:
--- @return string:
local function FlagsToString(flags)
	if flags == 0 then return "NONE" end
	local parts = {}
	for k, v in next, ConVar.FLAG do
		if (flags & v) ~= 0 then
			parts[#parts + 1] = k
		end
	end
	return #parts > 0 and table.concat(parts, ", ") or "NONE"
end

--- Helper to detect type using modf for integer detection.
--- @param val any:
--- @return string:
local function GetValueType(val)
	local t = type(val)
	if t == "number" then
		local _, frac_part = math.modf(val)
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
--- @param val any:
--- @return string:
local function ValueToString(val)
	if type(val) == "boolean" then return val and "1" or "0" end
	return tostring(val)
end

--- Helper to parse string to target type.
--- @param str string:
--- @param targetType string:
--- @return any:
local function StringToValue(str, targetType)
	if targetType == "boolean" then
		--if str == "true" then return true end
		--if str == "false" then return false end
		local num = tonumber(str)
		return num and num > 0
	end
	if targetType == "int" then
		local num = tonumber(str) or 0
		return (math.modf(num))
	end
	if targetType == "float" then
		return tonumber(str) or 0.0
	end
	return str
end

-- ==========================================
-- Metamethods
-- ==========================================

--- Allows converting the ConVar object directly to a string representation of its value.
--- Usage: print(my_cvar)
--- @return string:
function ConVar:__tostring()
	return self:GetString()
end

-- ==========================================
-- Constructor
-- ==========================================

--- Creates a new ConVar or retrieves an existing one.
--- @param name string: The name of the console variable.
--- @param default boolean|number|string|nil: The default value.
--- @param help string|nil: Description of the ConVar.
--- @param flags number|nil: Bitwise flags (ConVar.FLAG).
--- @param min_val number|nil: Minimum value (numeric only).
--- @param max_val number|nil: Maximum value (numeric only).
--- @param params table|nil: The list of supported parameters to display in the console (strings only).
--- @return ConVar: The console variable object.
function ConVar.Register(name, default, help, flags, min_val, max_val, params)
	TypeCheck(name, "string", 1)
	TypeCheck(default, "boolean|number|string|nil", 2)
	TypeCheck(help, "string|nil", 3)
	TypeCheck(flags, "number|nil", 4)
	TypeCheck(min_val, "number|nil", 5)
	TypeCheck(max_val, "number|nil", 6)
	TypeCheck(params, "table|nil", 7)

	flags = flags or ConVar.FLAG.NONE
	if default == nil then default = "" end
	local val_type = GetValueType(default)
	if val_type == "boolean" then
		min_val, max_val = 0, 1
	end

	-- Singleton check
	name = string.lower(name)
	if ConVars[name] then
		Console.Log("[ConVar] Warning: '%s' already registered. Returning existing instance.", name)
		return ConVars[name]
	end

	local self = setmetatable({}, ConVar)
	self.Name = name
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
	if Server and (flags & ConVar.FLAG.ARCHIVE) ~= 0 then
		local saved = Server.GetValue(name)
		if saved ~= nil then
			initial_val = StringToValue(saved, val_type)
		end
	end

	-- Client-side initialization from Engine
	if Client then
		if (flags & ConVar.FLAG.REPLICATED) ~= 0 then
			local synced_val = Client.GetValue(name)
			if synced_val ~= nil then
				initial_val = StringToValue(synced_val, val_type)
			end
		elseif (flags & ConVar.FLAG.USERINFO) ~= 0 then
			local local_val = Client.GetValue(name)
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

	-- Register Console Command
	Console.RegisterCommand(name, function(...)
		self:OnConsoleCommand({ ... })
	end, self.Help, params)

	ConVars[name] = self

	-- Server: Initial replication or persistence
	if Server then
		if (flags & ConVar.FLAG.REPLICATED) ~= 0 or (flags & ConVar.FLAG.ARCHIVE) ~= 0 then
			Server.SetValue(self.Name, ValueToString(self.Value), true)
		end
	end

	return self
end

-- ==========================================
-- Core Methods
-- ==========================================

--- Internal handler for console input.
--- @param args table:
function ConVar:OnConsoleCommand(args)
	if not args or #args == 0 then
		-- Use FlagsToString for human readable output
		Console.Log(string.format("%s%s [Flags: %s]", self.Name,
			(self.Flags & ConVar.FLAG.NEVER_AS_STRING) ~= 0 and "" or string.format(" = %q", ValueToString(self.Value)),
			FlagsToString(self.Flags)))
		if self.Help and #self.Help > 0 then Console.Log(" - " .. self.Help) end
		return
	end

	local input = args[1]
	local new_val = StringToValue(input, self.Type)

	if Server then
		self:SetValue(new_val, "Server Console")
	elseif Client then
		if (self.Flags & ConVar.FLAG.CLIENT_CAN_EXECUTE) ~= 0 or (self.Flags & ConVar.FLAG.USERINFO) ~= 0 then
			self:SetValue(new_val, "Client Console")
		else
			Events.CallRemote(REQUEST_EVENT, self.Name, ValueToString(new_val))
		end
	end
end

--- Sets the value of the ConVar.
--- @param value any:
--- @param source string|nil: Optional identifier of who changed the value.
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
		typed_val = math.modf(num)
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

	local value = (self.Flags & ConVar.FLAG.NEVER_AS_STRING) ~= 0 and "" or self.Value

	for _, cb in next, callbacks do
		if self.Callbacks[cb] then
			local ok, err = pcall(cb, self.Name, value, source)
			if not ok then
				Console.Log(string.format("[ConVar] Error in callback for '%s': %s", self.Name, tostring(err)))
			end
		end
	end

	if Server then
		-- Engine Sync & Persistence
		if (self.Flags & ConVar.FLAG.REPLICATED) ~= 0 or (self.Flags & ConVar.FLAG.ARCHIVE) ~= 0 then
			Server.SetValue(self.Name, ValueToString(value), true)
		end

		-- Lua Callback Sync (for clients)
		if (self.Flags & ConVar.FLAG.REPLICATED) ~= 0 then
			Events.BroadcastRemote(REPLICATE_EVENT, self.Name, ValueToString(value))
		end
	elseif Client then
		-- USERINFO Logic: Send to server
		if (self.Flags & ConVar.FLAG.USERINFO) ~= 0 then
			Events.CallRemote(USERINFO_EVENT, self.Name, ValueToString(value))
			Client.SetValue(self.Name, ValueToString(value))
		end
	end
end

--- Explicitly sets a Float value.
--- @param value number:
function ConVar:SetFloat(value)
	TypeCheck(value, "number", 1)
	self:SetValue(value)
end

--- Explicitly sets an Int value.
--- @param value number:
function ConVar:SetInt(value)
	TypeCheck(value, "number", 1)
	self:SetValue((math.modf(value)))
end

--- Explicitly sets a Bool value.
--- @param value boolean:
function ConVar:SetBool(value)
	TypeCheck(value, "boolean", 1)
	self:SetValue(value)
end

--- Explicitly sets a String value.
--- @param value string:
function ConVar:SetString(value)
	TypeCheck(value, "string", 1)
	self:SetValue(value)
end

--- Gets the raw value.
--- @return any:
function ConVar:GetValue()
	return self.Value
end

--- Gets the value as a String.
--- @return string:
function ConVar:GetString()
	return (self.Flags & ConVar.FLAG.NEVER_AS_STRING) ~= 0 and "" or ValueToString(self.Value)
end

--- Gets the value as an Integer (truncated towards zero).
--- @return integer:
function ConVar:GetInt()
	local num = tonumber(self.Value)
	if not num then return 0 end
	return (math.modf(num))
end

--- Gets the value as a Float.
--- @return number:
function ConVar:GetFloat()
	return tonumber(self.Value) or 0.0
end

--- Gets the value as a Boolean.
--- @return boolean:
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
--- @param func function: Signature: callback(name, new_value, source)
function ConVar:AddChangeCallback(func)
	TypeCheck(func, "function", 1)
	self.Callbacks[func] = true
end

--- Removes a previously added callback.
--- @param func function:
function ConVar:RemoveChangeCallback(func)
	TypeCheck(func, "function", 1)
	self.Callbacks[func] = nil
end

-- ==========================================
-- Static / Global Methods
-- ==========================================

--- Retrieves a ConVar by name.
--- @param name string:
--- @return ConVar|nil:
function ConVar.Get(name)
	TypeCheck(name, "string", 1)
	return ConVars[string.lower(name)]
end

--- Gets an existing ConVar or creates a new one if it doesn't exist.
--- @param name string: The name of the console variable.
--- @param default boolean|number|string|nil: The default value.
--- @param help string|nil: Description of the ConVar.
--- @param flags number|nil: Bitwise flags (ConVar.FLAG).
--- @param min_val number|nil: Minimum value (numeric only).
--- @param max_val number|nil: Maximum value (numeric only).
--- @param params table|nil: The list of supported parameters to display in the console (strings only).
--- @return ConVar: The console variable object.
function ConVar.GetOrCreate(name, default, help, flags, min_val, max_val, params)
	TypeCheck(name, "string", 1)
	local cvar = ConVars[string.lower(name)]
	if cvar then return cvar end
	return ConVar.Register(name, default, help, flags, min_val, max_val, params)
end

if Server then
	--- Retrieves a USERINFO value for a specific player on the server.
	--- This is used for client-side ConVars that replicate their state to the server.
	--- @param player Player: The player object.
	--- @param name string: The ConVar name.
	--- @return any: The value (converted to type if registered) or string. Returns nil if not found.
	function ConVar.GetPlayerInfo(player, name)
		TypeCheck(player, "userdata", 1)
		TypeCheck(name, "string", 2)

		local info = PlayerUserInfos[player]
		if not info then return end

		name = string.lower(name)
		local str_val = info[name]
		if not str_val then return end

		local cvar = ConVars[name]
		if cvar then
			return StringToValue(str_val, cvar.Type)
		end

		return str_val
	end

	function Player:GetPlayerInfo(cvar_name)
		return ConVar.GetPlayerInfo(self, cvar_name)
	end
end

--- Returns an iterator over all registered ConVars.
--- @return function, table
function ConVar.GetIterator()
	return next, ConVars
end

-- ==========================================
-- Networking Setup & Utility Commands
-- ==========================================

Console.RegisterCommand("cvarlist", function(args)
	local filter
	if args and args[1] then
		filter = string.lower(args[1])
	end
	local count = 0

	Console.Log("-------------- ConVar List --------------")

	for name, cvar in next, ConVars do
		-- Check filter
		if filter and not string.find(string.lower(name), filter) then
			goto continue
		end

		if (cvar.Flags & ConVar.FLAG.HIDDEN) ~= 0 and not filter then
			goto continue
		end

		local val_str = cvar:GetString()
		local help_str = cvar.Help or ""
		local minmax_str = ""
		local flag_str = " [Flags: " .. FlagsToString(cvar.Flags) .. "]"

		if cvar.Min or cvar.Max then
			minmax_str = string.format(" [Min: %s, Max: %s]", cvar.Min or "N/A", cvar.Max or "N/A")
		end

		Console.Log(string.format("%s%s%s%s - %s", name,
			(cvar.Flags & ConVar.FLAG.NEVER_AS_STRING) ~= 0 and "" or string.format(" = %q", val_str), minmax_str, flag_str,
			help_str))
		count = count + 1

		::continue::
	end

	Console.Log(string.format("------------------------------ (%d found)", count))
end)

if Server then
	local sv_cheats = ConVar.Register(
		"sv_cheats",
		Server.GetCustomSettings().cheats or false,
		"Enable cheats on the server",
		ConVar.FLAG.REPLICATED,
		0, 1
	)
	sv_cheats:AddChangeCallback(function(name, new_value, source)
		Console.Log("%s has been %s by %s", name, new_value and "enabled" or "disabled", source)
	end)
	local sv_password = ConVar.Register(
		"sv_password",
		Server.GetCustomSettings().password or "",
		"Enable password-protection",
		ConVar.FLAG.NEVER_AS_STRING
	)
	sv_password:AddChangeCallback(function(name, new_value, source)
		Server.SetPassword(sv_password.Value, true)
	end)

	Events.SubscribeRemote(REQUEST_EVENT, function(player, name, value_str)
		name = string.lower(name)
		local cvar = ConVars[name]
		if not cvar then return end

		if (cvar.Flags & ConVar.FLAG.CHEAT) ~= 0 then
			--local sv_cheats = ConVars["sv_cheats"]
			if not sv_cheats:GetBool() then
				Console.Log("[ConVar] %s tried to set cheat cvar '%s' without sv_cheats 1.",
					player and ("Player " .. player:GetName()) or "Unknown", name)
				return
			end
		end

		cvar:SetValue(StringToValue(value_str, cvar.Type), "Client " .. player:GetID())
	end)

	Events.SubscribeRemote(USERINFO_EVENT, function(player, name, value_str)
		name = string.lower(name)
		local cvar = ConVars[name]
		if cvar then
			if (cvar.Flags & ConVar.FLAG.USERINFO) == 0 then return end
			value_str = ValueToString(StringToValue(value_str, cvar.Type))
		end
		if not PlayerUserInfos[player] then
			PlayerUserInfos[player] = {}
		end
		PlayerUserInfos[player][name] = value_str
	end)

	Player.Subscribe("Destroy", function(player)
		PlayerUserInfos[player] = nil
	end)
end

if Client then
	Events.SubscribeRemote(REPLICATE_EVENT, function(name, value_str)
		name = string.lower(name)
		local cvar = ConVars[name]
		if cvar then
			cvar:SetValue(StringToValue(value_str, cvar.Type), "Server")
		end
	end)
end

-- Exports the table to be accessed by other Packages
_G.ConVar = ConVar
Package.Export("ConVar", ConVar)
return ConVar
