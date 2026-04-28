-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

--[[
	Remote Command System (remote cmd)

	A robust, permission-based remote command system that allows registering
	commands that can be invoked via the `cmd` console command.
	This provides a remote event that is used to handle console commands.
	Allows permission-based access control via the permission library.
	On server-side: remote event is broadcast to all clients.
	On client-side: remote event will be called on server-side (with the first argument being the invoker player).

	Features:
	* Permission-based access control via the permission library
	* Server-side broadcast and client-to-server remote calls
	* Command argument parsing (quoted strings, multiple args)
	* Command categories with configurable defaults
	* Player context for permission checks
	* Command help system with auto-generated documentation
]]

-- Localized global functions for better performance
local error = error
local type = type
local pcall = pcall
local print = print
local tostring = tostring
local string = require "@cheatoid/standard/string"
local string_format = string.format
local string_lower = string.lower
local string_match = string.match
local string_parse = string.parse
local string_sub = string.sub
local string_trim = string.trim
local table = require "@cheatoid/standard/table"
local table_concat = table.concat
local table_concat_safe = table.concat_safe
local table_insert = table.insert
local table_remove = table.remove
local table_unpack = table.unpack or unpack

-- Import dependencies
local file = require "FileWrapper"
local cfg_parser = require "@cheatoid/standalone/cfg_parser"
local permission = require "@cheatoid/permission/permission"
local ref = require "@cheatoid/ref/ref"

local M = {}

-- Internal state
local commands = table.make_case_insensitive() ---@type table<string, table>
local command_order = {} ---@type table<integer, string>

-- Permission registry for commands
local perm_registry
local perm_contexts = {} ---@type table<Player|"SERVER", table>

-- Remote event ID
local ID = Package.GetName() .. "::cmd"

-- State constants
local STATE_UNSET = permission.STATE_UNSET or 0
local STATE_ALLOW = permission.STATE_ALLOW or 1
local STATE_DENY = permission.STATE_DENY or 2

----------------------------------------------------------------------
-- Helper functions
----------------------------------------------------------------------

local function split_args(str)
	local args = {}
	local in_quote
	local current = ""
	local quote_char

	-- TODO/FIXME: This is inefficient... use string.parse instead
	for i = 1, #str do
		local char = string_sub(str, i, i)
		if not in_quote then
			if char == '"' or char == "'" then
				in_quote = true
				quote_char = char
			elseif string_match(char, "%s") then
				if #current > 0 then
					table_insert(args, current)
					current = ""
				end
			else
				current = current .. char
			end
		else
			if char == quote_char then
				in_quote = nil
				quote_char = nil
				table_insert(args, current)
				current = ""
			else
				current = current .. char
			end
		end
	end

	if #current > 0 then
		table_insert(args, current)
	end

	return args
end

----------------------------------------------------------------------
-- Permission system setup
----------------------------------------------------------------------

local function SetupPermissions(extras)
	--local result = cfg_parser.parse(file.read("permissions.cfg"))
	--if result.ok then
	--	-- Get nested blocks
	--	local groups = cfg_parser.getBlock(result.value, "groups")
	--	if groups then
	--		for name, groupData in next, groups.entries do
	--			print("Group:", name)
	--		end
	--	end
	--end
	--local permissions = ref.reactive(Package.GetPersistentData("permissions") or {}, function(key, value)
	--	Package.SetPersistentData("permissions." .. key, value)
	--	Package.FlushPersistentData()
	--end)
	local permissions = table.track(Package.GetPersistentData("permissions") or {}, {
		on_write = function(_, key, old, value)
			Package.SetPersistentData("permissions." .. key, value)
			Package.FlushPersistentData()
		end
	})

	perm_registry = perm_registry or permission.new_registry(STATE_DENY)

	-- Define command category (core)
	permission.define_category_on(perm_registry, "cmd", {
		{ name = "execute",   default = true,  description = "Execute remote commands" },
		{ name = "help",      default = true,  description = "View command help" },
	})

	if extras then
		for name, def in next, extras do
			permission.define_category_on(perm_registry, name, def)
		end
	end

	return permissions
end

M.SetupPermissions = SetupPermissions

----------------------------------------------------------------------
-- Permission context management
----------------------------------------------------------------------

--- Get or create a permission context for a player
---@param ply Player|string The player or "SERVER" for server context
---@return table context The permission context
local function get_context(ply)
	local key = ply == "SERVER" and "SERVER" or (ply and ply.GetSteamID and ply:GetSteamID() or tostring(ply))

	if not perm_contexts[key] then
		perm_contexts[key] = permission.new_context_on(perm_registry)

		-- Grant default permissions based on context
		if key == "SERVER" then
			permission.grant_category(perm_contexts[key], "cmd")
			permission.grant_category(perm_contexts[key], "chat")
		end
	end

	return perm_contexts[key]
end

--- Grant a permission to a player
---@param ply Player|string The player or "SERVER"
---@param perm string The permission (e.g., "admin.kick")
function M.GrantPermission(ply, perm)
	local ctx = get_context(ply)
	permission.grant(ctx, perm)
end

--- Deny a permission to a player
---@param ply Player|string The player or "SERVER"
---@param perm string The permission (e.g., "admin.kick")
function M.DenyPermission(ply, perm)
	local ctx = get_context(ply)
	permission.deny(ctx, perm)
end

--- Reset a permission for a player (back to default)
---@param ply Player|string The player or "SERVER"
---@param perm string The permission (e.g., "admin.kick")
function M.ResetPermission(ply, perm)
	local ctx = get_context(ply)
	permission.reset(ctx, perm)
end

--- Check if a player has a permission
---@param ply Player|string The player or "SERVER"
---@param perm string The permission (e.g., "admin.kick")
---@return boolean allowed Whether the permission is granted
function M.HasPermission(ply, perm)
	local ctx = get_context(ply)
	return permission.is_allowed(ctx, perm)
end

--- Require a permission for a player (throws error if not granted)
---@param ply Player|string The player or "SERVER"
---@param perm string The permission (e.g., "admin.kick")
function M.RequirePermission(ply, perm)
	local ctx = get_context(ply)
	permission.require(ctx, perm)
end

----------------------------------------------------------------------
-- Command registration
----------------------------------------------------------------------

--- Register a new command
---@param name string The command name
---@param opts table|function Options table or handler function:
--- - `handler` function(ply, ...args): The command handler
--- - `permission` string|nil: Required permission (e.g., "admin.kick")
--- - `description` string|nil: Command description for help
--- - `args` table|nil: Argument names for help (e.g., {"player", "reason"})
--- - `hidden` boolean|nil: If true, command won't show in help
--- - `server_only` boolean|nil: If true, only executable on server
--- - `client_only` boolean|nil: If true, only executable on client
--- - `local_only` boolean|nil: If true, command runs locally (no remote broadcast/call)
function M.Register(name, opts)
	if type(name) ~= "string" or name == "" then
		return error("Command name must be a non-empty string", 2)
	end

	if commands[name] then
		return error("Command already registered: " .. name, 2)
	end

	-- Handle simple function registration
	if type(opts) == "function" then
		opts = { handler = opts }
	end

	if type(opts) ~= "table" then
		return error("Options must be a table or function", 2)
	end

	if type(opts.handler) ~= "function" then
		return error("Command must have a handler function", 2)
	end

	local cmd = {
		name = name,
		handler = opts.handler,
		permission = opts.permission,
		description = opts.description or "No description available",
		args = opts.args or {},
		hidden = opts.hidden or false,
		server_only = opts.server_only or false,
		client_only = opts.client_only or false,
		local_only = opts.local_only or false,
	}

	commands[name] = cmd
	table_insert(command_order, name)

	return cmd
end

--- Unregister a command
---@param name string The command name
function M.Unregister(name)
	if commands[name] then
		commands[name] = nil
		for i = 1, #command_order do
			local cmd_name = command_order[i]
			if cmd_name == name then
				table_remove(command_order, i)
				break
			end
		end
	end
end

--- Get a registered command
---@param name string The command name
---@return table|nil cmd The command definition or nil
function M.GetCommand(name)
	return commands[name]
end

--- List all registered commands
---@return table commands Table of command definitions
function M.ListCommands()
	local result = {}
	for i = 1, #command_order do
		local name = command_order[i]
		local cmd = commands[name]
		if cmd and not cmd.hidden then
			table_insert(result, cmd)
		end
	end
	return result
end

----------------------------------------------------------------------
-- Command execution
----------------------------------------------------------------------

--- Execute a command
---@param name string The command name
---@param ply Player|string The invoking player or "SERVER"
---@param args table The command arguments
---@return boolean success Whether the command executed successfully
---@return string|nil error Error message if failed
function M.Execute(name, ply, args)
	local cmd = commands[name]

	if not cmd then
		return false, "Unknown command: " .. name
	end

	-- Check server/client restrictions
	if Server and cmd.client_only then
		return false, "Command can only be executed on client"
	end
	if not Server and cmd.server_only then
		return false, "Command can only be executed on server"
	end

	-- Check permission
	if cmd.permission then
		if not M.HasPermission(ply, cmd.permission) then
			return false, "Permission denied: " .. cmd.permission
		end
	else
		-- Default permission check
		if not M.HasPermission(ply, "cmd.execute") then
			return false, "Permission denied: cmd.execute"
		end
	end

	-- Execute the command
	local success, result = pcall(function()
		return cmd.handler(ply, table_unpack(args))
	end)

	if not success then
		return false, "Command error: " .. tostring(result)
	end

	return true, result
end

--- Handle a command string (parses command and arguments)
---@param str string The command string (e.g., "kick player1 reason")
---@param ply Player|string The invoking player or "SERVER"
---@return boolean success Whether the command executed successfully
---@return string|nil output Output or error message
function M.HandleCommand(str, ply)
	str = string_trim(str) --string_match(str, "^%s*(.-)%s*$") -- trim
	if str == "" then
		return false, "Empty command"
	end

	local parts = split_args(str)
	local name = string_lower(parts[1])
	local args = {}

	for i = 2, #parts do
		args[i - 1] = parts[i]
	end

	return M.Execute(name, ply, args)
end

----------------------------------------------------------------------
-- Help system
----------------------------------------------------------------------

--- Get help for a command
---@param name string|nil Command name or nil for general help
---@return string help The help text
function M.GetHelp(name)
	if not name then
		-- General help - list all commands
		local lines = { "Available commands:" }
		local cmd_list = M.ListCommands()

		for i = 1, #cmd_list do
			local cmd = cmd_list[i]
			local args_str = table_concat_safe(cmd.args, " ")
			if args_str ~= "" then
				args_str = " " .. args_str
			end
			table_insert(lines, string_format("  %s%s - %s", cmd.name, args_str, cmd.description))
		end

		table_insert(lines, "\nUse 'cmd help <command>' for detailed help")
		return table_concat(lines, "\n")
	end

	-- Specific command help
	local cmd = commands[name]
	if not cmd then
		return "Unknown command: " .. name
	end

	local lines = {
		string_format("Command: %s", cmd.name),
		string_format("Description: %s", cmd.description),
	}

	if #cmd.args > 0 then
		table_insert(lines, "Arguments:")
		for i = 1, #cmd.args do
			local arg = cmd.args[i]
			table_insert(lines, string_format("  %d. %s", i, arg))
		end
	end

	if cmd.permission then
		table_insert(lines, string_format("Required permission: %s", cmd.permission))
	end

	if cmd.server_only then
		table_insert(lines, "Note: Server-side only")
	elseif cmd.client_only then
		table_insert(lines, "Note: Client-side only")
	end

	return table_concat(lines, "\n")
end

----------------------------------------------------------------------
-- Remote event handlers
----------------------------------------------------------------------

--- Server-side handler (called when a command is executed on client-side)
---@param ply Player|string The invoking player or "SERVER"
---@param ... any Additional arguments
local function server_handler(ply, ...)
	local args = { ... }
	local cmd_str = table_concat_safe(args, " ")
	print(string_format("[cmd] %s: %s", ply and ply:GetSteamID() or "Unknown", cmd_str))
	local success, result = M.HandleCommand(cmd_str, ply or "SERVER")
	if not success then
		Console.Error(string_format("[cmd ERROR] %s", result))
	else
		if result then
			print(string_format("[cmd] %s", tostring(result)))
		end
	end
end

--- Client-side handler (called when a command is executed on server-side)
---@param ... any Additional arguments
local function client_handler(...)
	local args = { ... }
	local cmd_str = table_concat_safe(args, " ")
	print(string_format("[cmd] %s", cmd_str))
	local success, result = M.HandleCommand(cmd_str, Client.GetLocalPlayer())
	if not success then
		Console.Error(string_format("[cmd ERROR] %s", result))
	else
		if result then
			print(string_format("[cmd] %s", tostring(result)))
		end
	end
end

--- Console command callback
---@param ... any Additional arguments
local function console_callback(...)
	local args = { ... }
	local cmd_str = table_concat_safe(args, " ")

	-- Parse command name to check if it should run locally only
	local parts = split_args(cmd_str)
	local cmd_name = parts[1] or ""
	local cmd_def = commands[cmd_name]

	-- If command is local_only, run it locally without remote broadcast
	if cmd_def and cmd_def.local_only then
		Events.Call(ID, ...)
		if Server then
			M.HandleCommand(cmd_str, "SERVER")
		else
			M.HandleCommand(cmd_str, Client.GetLocalPlayer())
		end
		return
	end

	if Server then
		-- Broadcast to all clients
		Events.BroadcastRemote(ID, ...)
		-- Also execute on server
		M.HandleCommand(cmd_str, "SERVER")
	else
		-- NOTE: nanos world engine will inject the local player as the first argument
		Events.CallRemote(ID, ...)
		-- Also execute on client
		M.HandleCommand(cmd_str, Client.GetLocalPlayer())
	end
end

----------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------

function M.Initialize(include_commands)
	-- Initialize permission system
	M.SetupPermissions(include_commands and {
		cmd = {
			{ name = "reloadlib", default = false, description = "Reload the cheatoid-library package itself" },
		}
	} or false)

	-- Subscribe to remote events
	Events.SubscribeRemote(ID, Server and server_handler or client_handler)

	-- Register console command
	Console.RegisterCommand("cmd", console_callback)

	-- Register built-in help command (local only - shows help on the executing side)
	M.Register("help", {
		permission = "cmd.help",
		description = "Show help for commands",
		args = { "[command]" },
		local_only = true,
		handler = function(ply, name)
			print(M.GetHelp(name))
		end
	})

	if not include_commands then return end

	-- Reload cheatoid-library package
	M.Register("reloadlib", {
		permission = "cmd.reloadlib",
		description = "Reload the cheatoid-library package itself",
		server_only = true,
		handler = function(ply)
			require("../Server/PackageHelper").ReloadLib()
		end
	})
end

-- Export the API to be accessed by other packages
return M
