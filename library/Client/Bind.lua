-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Source-engine inspired bind system for console commands

-- Localized global functions for better performance
local error = error
local next = next
local type = type

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
	if next(actions) == nil then
		print("No actions available")
		return
	end
	print("Available actions:")
	local actionNames = table_keys(actions)
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
	if next(keyBindings) == nil then
		print("No key bindings available")
		return
	end
	print("Current key bindings:")
	local bindingKeys = table_keys(keyBindings)
	table_sort(bindingKeys)
	for _, key in next, bindingKeys do
		printf("  %s: %s", key, keyBindings[key])
	end
end

--- Bind a key to an action.
---@param key string The key to bind (e.g., "F10", "Space", "A")
---@param action string The action name to bind to
---@param description string|nil The action description to display in the tooltip
---@return boolean success Whether the binding was successful
---@usage <br>
--- ```
--- Bind.BindKey("F10", "browser_toggle")
--- ```
function M.BindKey(key, action, description)
	if not key or not action then
		print("Usage: bind <key> <action>")
		return false
	end

	if not actions[action] then
		print("Unknown action: " .. action)
		return false
	end

	-- Unbind existing key if any
	local oldAction = keyBindings[key]
	if oldAction then
		Input.Unbind(BIND_PREFIX .. oldAction, InputEvent.Pressed)
	end

	-- Register the keybinding
	local bindingName = BIND_PREFIX .. action
	Input.Register(bindingName, key, description or ("Bind: " .. action))
	Input.Bind(bindingName, InputEvent.Pressed, actions[action])

	-- Store the binding
	keyBindings[key] = action

	printf("Bound %q to %q", key, action)
	return true
end

M.Bind = M.BindKey

--- Unbind a key from its action.
---@param key string The key to unbind
---@return boolean success Whether the unbinding was successful
---@usage <br>
--- ```
--- Bind.UnbindKey("F10")
--- ```
function M.UnbindKey(key)
	if not key then
		print("Usage: unbind <key>")
		return false
	end

	if not keyBindings[key] then
		printf("Key %q is not bound to any action", key)
		return false
	end

	local action = keyBindings[key]
	Input.Unbind(BIND_PREFIX .. action, InputEvent.Pressed)
	keyBindings[key] = nil

	printf("Unbound %q from %q", key, action)
	return true
end

M.Unbind = M.UnbindKey

--- Unregister a keybinding.
---@param key string The key to unregister
---@return boolean success Whether the unregistration was successful
---@usage <br>
--- ```
--- Bind.Unregister("F10")
--- ```
function M.Unregister(key)
	if not key then
		print("Usage: unregister <key>")
		return false
	end

	if not keyBindings[key] then
		printf("Key %q is not bound to any action", key)
		return false
	end

	local action = keyBindings[key]
	Input.Unregister(BIND_PREFIX .. action, key)
	keyBindings[key] = nil

	printf("Unregistered %q from %q", key, action)
	return true
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
	Console.RunCommand(table_concat({ ... }, " "))
end

-- I had run into a case where input was glitched and prevented me from playing... This command rescued me.
local function FixInput()
	Input.SetInputEnabled(true)
	Input.SetMouseEnabled(false)
end

function M.Initialize()
	-- Register builtin commands and actions
	Console.RegisterCommand("action", function(name, ...)
		local command = table_concat({ ... }, " ")
		M.RegisterAction(name, function(...)
			RunCommand(command, ...)
		end)
	end)
	Console.RegisterCommand("alias", function(name, ...)
		local command = table_concat({ ... }, " ")
		Console.RegisterCommand(name, function(...)
			RunCommand(command)
		end)
	end, "Creates an alias for a command")
	Console.RegisterCommand("bind", function(key, ...)
		local action = table_concat({ ... }, " ")
		M.BindKey(key, action)
	end, "Binds a key to an action")
	Console.RegisterCommand("unbind", M.UnbindKey, "Unbinds a key from its action")
	Console.RegisterCommand("unregister", M.Unregister, "Unregisters a keybinding")
	Console.RegisterCommand("actions", M.ListActions, "Lists all available actions")
	Console.RegisterCommand("bindlist", M.ListBindings, "Lists all key bindings")
	Console.RegisterCommand("run", RunCommand, "Runs the given input as a console command")
	M.RegisterAction("run", RunCommand)
	Console.RegisterCommand("flush", Package.FlushPersistentData, "Flushes the persistent data")
	M.RegisterCommand("fixinput", FixInput, "Fix the input (i.e. when you can't move or look around)")

	-- NOTE: This must be on the bottom!
	M.Initialize = function() end
end

-- Export the API to be accessed by other packages
return M
