-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Source-engine inspired bind system for console commands

-- Localized global functions for better performance
local error = error
local next = next
local type = type
local string_upper = string.upper

-- Import dependencies
local printf = require "@cheatoid/standalone/printf"
local table = require "@cheatoid/standard/table"
local table_concat = table.concat
local table_keys = table.keys
local table_remove = table.remove
local table_sort = table.sort
local table_unpack = table.unpack
--local ref = require "@cheatoid/ref/ref"
local Console = Console
local Input = Input

local M = {}
local BIND_PREFIX = "Bind:"

-- TODO: Load and save keybinds

---@type table<string, string>
local keyBindings = table.track(
	table.make_case_insensitive(Package.GetPersistentData("keybinds") or {}), {
		on_write = function(_, key, old, value)
			Package.SetPersistentData("keybinds." .. key, tostring(value))
			Package.FlushPersistentData()
		end
	})
---@type table<string, function>
local actions = table.track(
	table.make_case_insensitive(Package.GetPersistentData("actions") or {}), {
		on_write = function(_, key, old, value)
			Package.SetPersistentData("actions." .. key, tostring(value))
			Package.FlushPersistentData()
		end
	})

--- Register a new action that can be bound to keys.
---@param name string The name of the action
---@param callback function The function to call when the action is triggered
---@usage <br>
--- ```
--- Bind.RegisterAction("my_action", function()
---   print("Action triggered!")
--- end)
--- ```
function M.RegisterAction(name, callback)
	if not name or type(name) ~= "string" then
		return error("Bind.RegisterAction: name must be a string", 2)
	end
	if not callback or type(callback) ~= "function" then
		return error("Bind.RegisterAction: callback must be a function", 2)
	end
	actions[name] = callback
end

M.Register = M.RegisterAction

--- Registers a console command and creates a bindable action for it.<br>
--- This is a convenience function that combines `RegisterAction` and `Console.RegisterCommand`.
---@param name string The name of the command/action
---@param callback function The function to execute when the command is run
---@param description string|nil The command description to display in the console (default: "")
---@param parameters string[]|nil The list of supported parameters to display in the console (default: {})
function M.RegisterCommand(name, callback, description, parameters)
	M.RegisterAction(name, callback)
	return Console.RegisterCommand(name, callback, description, parameters)
end

--- Get all registered actions (actual reference table).
---@return table<string, function> actions Table mapping action names to their callbacks
function M.GetActions()
	return actions
end

--- Get all current key bindings (actual reference table).
---@return table<string, string> bindings Table mapping keys to their bound actions
function M.GetBindings()
	return keyBindings
end

--- List all registered actions to the console.
---@usage <br>
--- ```
--- Bind.ListActions()
--- ```
function M.ListActions()
	local actionNames = {}

	-- Collect action names using pairs, filtering out metamethods
	for k, v in pairs(actions) do
		if k ~= "__index" and k ~= "__newindex" then
			actionNames[#actionNames + 1] = k
		end
	end

	if #actionNames == 0 then
		print("No actions available")
		return
	end

	print("Available actions:")
	table_sort(actionNames)
	for _, name in next, actionNames do
		printf("  %s", name)
	end
end

--- List all current key bindings to the console.
---@usage <br>
--- ```
--- Bind.ListBindings()
--- ```
function M.ListBindings()
	local bindingKeys = {}

	-- Collect keys using pairs, filtering out metamethods
	for k, v in pairs(keyBindings) do
		if k ~= "__index" and k ~= "__newindex" then
			bindingKeys[#bindingKeys + 1] = k
		end
	end

	if #bindingKeys == 0 then
		print("No key bindings available")
		return
	end

	print("Current key bindings:")
	table_sort(bindingKeys)
	for _, key in next, bindingKeys do
		printf("  %s: %s", key, keyBindings[key])
	end
end

--- Bind a key to an action.
---@param key string The key to bind (e.g., "F10", "Space", "A")
---@param action string The action name to bind to
---@param description string|nil The action description to display in the tooltip
---@param force boolean|nil Whether to force the binding even if the action doesn't exist (default: false)
---@return boolean success Whether the binding was successful
---@usage <br>
--- ```
--- Bind.BindKey("F9", "browser")
--- ```
function M.BindKey(key, action, description, force)
	if not key or not action or #key == 0 or #action == 0 then
		return false, "Usage: bind <key> <action>"
	end

	local resolvedAction = actions[action]
	if not resolvedAction and not force then
		return false, "Unknown action: " .. action
	end

	-- Unbind existing key if any
	local binding = keyBindings[key]
	if binding then
		Input.Unbind(BIND_PREFIX .. binding, InputEvent.Pressed, resolvedAction)
	end

	-- Register the keybinding
	local bindingName = BIND_PREFIX .. action
	Input.Register(bindingName, key, description or bindingName)
	Input.Bind(bindingName, InputEvent.Pressed, resolvedAction)

	-- Store the binding
	keyBindings[key] = action

	return true
end

M.Bind = M.BindKey

--- Unbind a key from its action.
---@param key string The key to unbind
---@return boolean success Whether the unbinding was successful
---@usage <br>
--- ```
--- Bind.UnbindKey("F9")
--- ```
function M.UnbindKey(key)
	if not key or #key == 0 then
		return false, "Usage: unbind <key>"
	end

	local binding = keyBindings[key]
	if not binding then
		return false, "Key \"" .. key .. "\" is not bound to any action"
	end

	local callback = actions[binding]
	if not callback then
		return false, "Key \"" .. key .. "\" is not bound to any action"
	end
	printf("DEBUG: Unbinding key \"" .. key .. "\" from action \"" .. binding .. "\"")
	print("callback: " .. tostring(callback))

	Input.Unbind(BIND_PREFIX .. binding, InputEvent.Pressed, callback)
	Input.Unregister(BIND_PREFIX .. binding, key)

	-- Find the actual key in the table (case-insensitive) and remove it
	for k, v in pairs(keyBindings) do
		if k ~= "__index" and k ~= "__newindex" and string_upper(k) == string_upper(key) then
			keyBindings[k] = nil
			return true, binding
		end
	end

	return false
end

M.Unbind = M.UnbindKey

--- Unregister a keybinding.
---@param key string The key to unregister
---@return boolean success Whether the unregistration was successful
---@usage <br>
--- ```
--- Bind.Unregister("F9")
--- ```
function M.Unregister(key)
	if not key or #key == 0 then
		return false, "Usage: unregister <key>"
	end

	local binding = keyBindings[key]
	if not binding then
		return false, "Key \"" .. key .. "\" is not bound to any action"
	end

	Input.Unregister(BIND_PREFIX .. binding, key)

	-- Find the actual key in the table (case-insensitive) and remove it
	for k, v in pairs(keyBindings) do
		if k ~= "__index" and k ~= "__newindex" and string_upper(k) == string_upper(key) then
			keyBindings[k] = nil
			return true, binding
		end
	end

	return false
end

local function PreProcessArgs(...)
	local args = { ... }
	for i = #args, 1, -1 do
		local arg = args[i]
		if #arg == 0 then
			table_remove(args, i)
		else
			args[i] = arg
		end
	end
	return table_unpack(args)
end

local function RunCommand(...)
	local cmd = table_concat({ ... }, " ")
	Console.RunCommand(cmd)
	--return cmd
end

-- I had run into a case where input was glitched and prevented me from playing... This command rescued me.
local function FixInput()
	Input.SetInputEnabled(true)
	Input.SetMouseEnabled(false)
end

function M.Initialize()
	-- Register builtin commands and actions
	Console.RegisterCommand("action", function(name, ...)
		if not name or name == "" then
			print("Usage: action <name> <command>")
			return
		end
		local command = table_concat({ ... }, " ")

		-- If command is empty, remove the action if it exists
		if command == "" then
			if actions[name] then
				-- Find the actual key in the case-insensitive table and remove it
				for k, v in pairs(actions) do
					if k ~= "__index" and k ~= "__newindex" and string_upper(k) == string_upper(name) then
						actions[k] = nil
						printf("Removed action %q", name)
						break
					end
				end
			else
				printf("Action %q does not exist", name)
			end
			return
		end

		local callback = function(...)
			-- Use delayed execution to avoid Lua stack issues
			Timer.SetTimeout(function()
				Console.RunCommand(command)
			end, 0)
		end
		local actionExists = actions[name] ~= nil
		local ok, err = pcall(M.RegisterAction, name, callback)
		if ok then
			if actionExists then
				printf("Replaced action %q with command: %s", name, command)
			else
				printf("Created action %q for command: %s", name, command)
			end
		else
			printf("Failed to create action %q: %s", name, err)
		end
	end, "Creates an action for a command")
	Console.RegisterCommand("alias", function(name, ...)
		if not name or name == "" then
			print("Usage: alias <name> <command>")
			return
		end
		local command = table_concat({ ... }, " ")
		local callback = function(...)
			-- Use delayed execution to avoid Lua stack issues
			Timer.SetTimeout(function()
				Console.RunCommand(command)
			end, 0)
		end
		local ok, err = pcall(Console.RegisterCommand, name, callback)
		if ok then
			printf("Created alias %q for command: %s", name, command)
		else
			printf("Failed to create alias %q: %s", name, err)
		end
	end, "Creates an alias for a command")
	Console.RegisterCommand("bind", function(key, ...)
		local action = table_concat({ ... }, " ")
		local ok, success, err = pcall(M.BindKey, key, action)
		if ok then
			if success then
				printf("Bound %q to %q", key, action)
			else
				printf("Failed to bind %q: %s", key, err or "unknown error")
			end
		else
			printf("Failed to bind %q: %s", key, success or "unknown error")
		end
	end, "Binds a key to an action")
	Console.RegisterCommand("unbind", function(key)
		local ok, success, result = pcall(M.UnbindKey, key)
		if ok then
			if success then
				printf("Unbound %q from %q", key, result)
			else
				print(result or "Failed to unbind key")
			end
		else
			print("Failed to unbind key: " .. (success or "unknown error"))
		end
	end, "Unbinds a key from its action")
	Console.RegisterCommand("unregister", function(key)
		local ok, result = M.Unregister(key)
		if ok then
			printf("Unregistered %q from %q", key, result)
		else
			print(result or "Failed to unregister key")
		end
	end, "Unregisters a keybinding")
	Console.RegisterCommand("actions", M.ListActions, "Lists all available actions")
	Console.RegisterCommand("bindlist", M.ListBindings, "Lists all key bindings")
	M.RegisterCommand("run", RunCommand, "Runs the given input as a console command")
	Console.RegisterCommand("flush", Package.FlushPersistentData, "Flushes the persistent data")
	M.RegisterCommand("fixinput", FixInput, "Fixes the input (i.e. when you can't move or look around)")
	M.RegisterCommand("disconnect", Client.Disconnect, "Disconnects from the server")

	-- NOTE: This must be on the bottom!
	M.Initialize = function()
		for bind, t in next, Input.GetScriptingKeyBindings() do
			local actionName = string.match(bind, "^" .. BIND_PREFIX .. "(.+)$")
			if actionName then
				for i = 1, #t do
					local key = t[i]
					--local action = actions[actionName]
					--if action then
					--	keyBindings[key] = actionName
					--	Input.Bind(bind, InputEvent.Pressed, action)
					--	printf("Loaded key binding: %q -> %q", key, actionName)
					--else
					--	printf("Warning: No action found for binding %q (key: %q)", bind, key)
					--end
					M.BindKey(key, actionName)
				end
			end
		end
	end
	M.Initialize()
end

-- Export the API to be accessed by other packages
return M
