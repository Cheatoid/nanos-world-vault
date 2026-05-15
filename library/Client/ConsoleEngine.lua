-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Console engine (a.k.a. Better Console)

-- Import dependencies
local Bind = require "Bind"
local fuzzy = require "@cheatoid/standalone/fuzzy"
local console_lib = require "@cheatoid/standalone/console"
local autocompleter = require "@cheatoid/autocompleter/autocompleter"
local permission = require "@cheatoid/permission/permission"
local plugin_framework = require "@cheatoid/plugin_framework/plugin_framework"

local M = {}
local ConsoleWebUI = _G.ConsoleWebUI

-- Create Console instance
local console = console_lib.Console.new()
-- Create IntelliSense instance for the console
local intellisense = console_lib.IntelliSense.new(console)

-- Realm management
local currentRealm = "client" -- Default to client realm

-- Define themes for theme command
local themes = { "amber", "arctic", "aurora", "bloodmoon", "cyberpunk", "matrix", "midnight", "glass" }

-- Register theme command
console:register({
	name = "theme",
	desc = "Switch console theme",
	args = {
		{ name = "name", type = "enum", optional = true, choices = themes, desc = "Theme name" }
	},
	handler = function(ctx, args)
		local themeName = args.name and args.name:match("^%s*(.-)%s*$") or ""
		if not themeName or themeName == "" then
			M.Info("Available themes: " .. table.concat(themes, ", "))
			return
		end

		M.SetTheme(themeName)
		M.Success("Theme changed to: " .. themeName)
	end
})

-- Register help command to show available commands
console:register({
	name = "help",
	desc = "Show available commands or get help for a specific command",
	args = {
		{
			name = "command",
			type = "enum",
			optional = true,
			choices = function()
				-- Get all registered command names dynamically
				local command_names = {}
				for name, cmd in next, console.commands do
					command_names[#command_names + 1] = name -- or cmd.name
				end
				return command_names
			end,
			desc = "Command name"
		}
	},
	handler = function(ctx, args)
		local cmdName = args.command
		if cmdName then
			-- Show help for specific command
			local helpText = console:help(cmdName)
			M.Info(helpText)
		else
			-- List all available commands
			local helpText = console:help()
			M.Info(helpText)
		end
	end
})

-- Register time command
console:register({
	name = "time",
	desc = "Show current time",
	handler = function(ctx, args)
		local currentTime = os.date("%H:%M:%S")
		M.Info("Current time: " .. currentTime)
	end
})

-- Register date command
console:register({
	name = "date",
	desc = "Show current date",
	handler = function(ctx, args)
		local currentDate = os.date("%Y-%m-%d")
		M.Info("Current date: " .. currentDate)
	end
})

-- Register version command
console:register({
	name = "version",
	desc = "Show version info",
	handler = function(ctx, args)
		M.Info("Console Engine v0.2")
	end
})

-- Register stats command
console:register({
	name = "stats",
	desc = "Show message statistics",
	handler = function(ctx, args)
		-- Get stats from JavaScript side
		if M.IsReady() then
			ConsoleWebUI:CallEvent("GetStats")
		else
			M.Info("Console not ready - cannot retrieve stats")
		end
	end
})

-- Register about command
console:register({
	name = "about",
	desc = "About this console",
	handler = function(ctx, args)
		M.Info("Console Engine v0.2")
		M.Info("Press Tab for autocomplete, Up/Down arrow for history.")
	end
})

-- Register echo command
console:register({
	name = "echo",
	desc = "Print text to console",
	args = {
		{ name = "text", type = "string", optional = true, desc = "Text to echo" }
	},
	no_arg_suggest = true, -- Disable argument autocompletion since echo accepts arbitrary varargs text
	handler = function(ctx, args)
		local result = args.text or ""
		if args._rest then
			result = result .. " " .. table.concat(args._rest, " ")
		end
		M.Info(result)
	end
})

-- Register realm command
console:register({
	name = "realm",
	desc = "Switch between CLIENT and SERVER output realms",
	aliases = { "client", "server" },
	args = {
		{ name = "name", type = "enum", optional = true, choices = { "client", "server" }, desc = "Realm name (client or server)" }
	},
	handler = function(ctx, args)
		-- Handle aliases - if command is "client" or "server", switch to that realm directly
		local cmdName = ctx.command or "realm"
		if cmdName == "client" then
			if ConsoleWebUI then
				ConsoleWebUI:CallEvent("OnRealmChanged", "client")
			end
			M.Success("Switched to CLIENT realm")
			return
		elseif cmdName == "server" then
			if ConsoleWebUI then
				ConsoleWebUI:CallEvent("OnRealmChanged", "server")
			end
			M.Success("Switched to SERVER realm")
			return
		end

		-- Handle regular realm command with arguments
		if not args.name then
			M.Info("Current realm: " .. currentRealm:upper())
			M.Info("Available realms: client, server")
			M.Info("Usage: realm <client|server>")
			M.Info("Shorthands: 'client' or 'server' commands")
		else
			if args.name == "client" or args.name == "server" then
				if ConsoleWebUI then
					ConsoleWebUI:CallEvent("OnRealmChanged", args.name)
				end
				M.Success("Switched to " .. args.name:upper() .. " realm")
			else
				M.Error("Invalid realm. Use 'client' or 'server'")
			end
		end
	end
})

-- Register clear command
console:register({
	name = "clear",
	desc = "Clear console output",
	aliases = { "cls" },
	handler = function(ctx, args)
		M.Clear()
	end
})

-- Register a simple test command to verify console is working
console:register({
	name = "testcmd",
	desc = "Test command for autocompletion",
	args = {
		{ name = "arg1", type = "string", optional = true, desc = "Test argument" }
	},
	no_arg_suggest = true,
	handler = function(ctx, args)
		M.Info("Test command executed with arg: " .. (args.arg1 or "nil"))
	end
})

-- Set callback for caret position updates
local caretPositionCallback

function M.IsReady()
	return ConsoleWebUI and ConsoleWebUI:IsReady() or false
end

function M.Initialize()
	Bind.Initialize()

	-- print("DEBUG: ConsoleEngine.Initialize() called!")
	if ConsoleWebUI then
		-- print("DEBUG: ConsoleWebUI already exists, recreating")
		--ConsoleWebUI:Destroy()
		ConsoleWebUI = nil
		_G.ConsoleWebUI = nil
		collectgarbage()
		collectgarbage()
	end

	Package.Subscribe("Unload", function()
		if ConsoleWebUI then
			ConsoleWebUI:Destroy()
			ConsoleWebUI = nil
			_G.ConsoleWebUI = nil
			collectgarbage()
			collectgarbage()
		end
	end)

	-- print("DEBUG: Creating new ConsoleWebUI instance")
	ConsoleWebUI = _G.ConsoleWebUI or WebUI(
		Package.GetName() .. ":console",
		"file://UI/ConsoleEngine.html",
		WidgetVisibility.Hidden, true, true
	)
	_G.ConsoleWebUI = ConsoleWebUI
	-- print("DEBUG: ConsoleWebUI instance created")

	ConsoleWebUI:Subscribe("Ready", function()
		-- M.Info("DEBUG: Ready event fired!")
		-- Initialize with default theme
		M.SetTheme("amber")

		-- Subscribe to game console logs
		Console.Subscribe("LogEntry", function(text, type)
			-- Map LogType to console UI types
			local logType = "log"
			if type == LogType.Error or type == LogType.Fatal or type == LogType.ScriptingError then
				logType = "error"
			elseif type == LogType.ScriptingWarn then
				logType = "warn"
			elseif type == LogType.Debug or type == LogType.Verbose then
				logType = "debug"
			elseif type == LogType.Success then
				logType = "success"
			elseif type == LogType.Chat then
				logType = "info"
			end
			M.Log(logType, text)
		end)

		ConsoleWebUI:Subscribe("CopyToClipboard", Client.CopyToClipboard)

		-- Handle realm changes from JS
		ConsoleWebUI:Subscribe("OnRealmChanged", function(realm)
			currentRealm = realm
			-- M.Info("Realm changed to: " .. realm)
		end)

		-- Handle command execution from JS
		ConsoleWebUI:Subscribe("OnCommand", function(name, args)
			-- Debug: Log command execution attempt
			-- M.Info("DEBUG: OnCommand event fired! Received command '" .. name .. "' with " .. #args .. " args")

			-- Build full command line for console
			local fullCommand = name
			if args and #args > 0 then
				fullCommand = fullCommand .. " " .. table.concat(args, " ")
			end

			-- M.Info("DEBUG: Full command: '" .. fullCommand .. "'")

			-- Try to execute with console first
			local success, result = pcall(function()
				return console:input_line(fullCommand, {})
			end)

			-- M.Info("DEBUG: console result - success: " .. tostring(success) .. ", result: " .. tostring(result))

			if success and result ~= nil then
				-- Command was handled by console successfully and returned a result
				if type(result) == "string" then
					M.Info(result)
				end
			else
				-- Either console execution failed, or command was unknown (result = nil)
				-- Forward to Console.RunCommand for game console commands
				-- M.Info("DEBUG: Forwarding to Console.RunCommand")
				Console.RunCommand(fullCommand)
			end
		end)

		-- Handle toggle events from JS
		ConsoleWebUI:Subscribe("OnToggle", function(isOpen)
			-- Simple state tracking - no complex logic needed
		end)

		-- Handle stats request from JS
		ConsoleWebUI:Subscribe("StatsResponse", function(stats)
			if stats then
				local statsText = string.format(
					"Messages - Total: %d | Log: %d | Info: %d | Warn: %d | Error: %d | Debug: %d | Success: %d | Cmd: %d",
					stats.total or 0, stats.log or 0, stats.info or 0, stats.warn or 0,
					stats.error or 0, stats.debug or 0, stats.success or 0, stats.cmd or 0)
				M.Info(statsText)
			end
		end)

		-- Subscribe to caret position events from JS
		ConsoleWebUI:Subscribe("CaretPosition", function(position, inputValue, wordBeforeCaret)
			if caretPositionCallback then
				caretPositionCallback(position, inputValue, wordBeforeCaret)
			end
		end)

		-- Handle autocomplete requests from JS
		ConsoleWebUI:Subscribe("GetAutocomplete", function(line, caret)
			-- Use IntelliSense with proper caret position awareness
			local suggestions = intellisense:suggest_at(line, caret)

			-- Convert IntelliSense suggestions to the format expected by JavaScript
			local formatted_suggestions = {}
			if suggestions then
				for _, suggestion in next, suggestions do
					if type(suggestion) == "table" and suggestion.key then
						table.insert(formatted_suggestions, {
							name = suggestion.key,
							desc = suggestion.meta and suggestion.meta.desc or "",
							start_pos = suggestion.start_pos,
							end_pos = suggestion.end_pos,
							replace = suggestion.replace
						})
					elseif type(suggestion) == "string" then
						table.insert(formatted_suggestions, {
							name = suggestion,
							desc = ""
						})
					end
				end
			end

			ConsoleWebUI:CallEvent("AutocompleteSuggestions", formatted_suggestions)
		end)

		ConsoleWebUI:Subscribe("OnConsoleOpened", function()
			-- Console is now open and interactive
			-- Disable game input to prevent interference
			Input.SetInputEnabled(false)
			Input.SetMouseEnabled(true)
		end)

		ConsoleWebUI:Subscribe("OnConsoleClosed", function()
			-- Console is now closed - hide it and disable mouse
			ConsoleWebUI:SetVisibility(WidgetVisibility.Hidden)
			-- Re-enable game input
			Input.SetInputEnabled(true)
			Input.SetMouseEnabled(false)
		end)

		ConsoleWebUI:Subscribe("CloseConsole", function()
			-- Just toggle closed - let JavaScript handle the UI state
			M.Toggle(false)
		end)
	end)

	--Input.Subscribe("KeyDown", function(key_name, delta)
	--	if ConsoleWebUI:GetVisibility() == WidgetVisibility.Visible and not Input.IsInputEnabled() then
	--		return false
	--	end
	--end)

	Input.Subscribe("KeyPress", function(key_name, delta)
		-- Block all keys that would interfere with console when it's open
		if ConsoleWebUI:GetVisibility() == WidgetVisibility.Visible and not Input.IsInputEnabled() then
			return false
		end
	end)

	Bind.RegisterCommand("console", M.Toggle, "Toggles the console")

	-- NOTE: This must be on the bottom!
	M.Initialize = function() end
end

-- Logging functions
function M.Log(type, text, realm)
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("log", type, text, realm or currentRealm)
	end
end

function M.Info(text, realm)
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("info", text, realm or currentRealm)
	end
end

function M.Warn(text, realm)
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("warn", text, realm or currentRealm)
	end
end

function M.Error(text, realm)
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("error", text, realm or currentRealm)
	end
end

function M.Debug(text, realm)
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("debug", text, realm or currentRealm)
	end
end

function M.Success(text, realm)
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("success", text, realm or currentRealm)
	end
end

-- Realm-specific logging functions
function M.ClientLog(type, text)
	M.Log(type, text, "client")
end

function M.ClientInfo(text)
	M.Info(text, "client")
end

function M.ClientWarn(text)
	M.Warn(text, "client")
end

function M.ClientError(text)
	M.Error(text, "client")
end

function M.ClientDebug(text)
	M.Debug(text, "client")
end

function M.ClientSuccess(text)
	M.Success(text, "client")
end

function M.ServerLog(type, text)
	M.Log(type, text, "server")
end

function M.ServerInfo(text)
	M.Info(text, "server")
end

function M.ServerWarn(text)
	M.Warn(text, "server")
end

function M.ServerError(text)
	M.Error(text, "server")
end

function M.ServerDebug(text)
	M.Debug(text, "server")
end

function M.ServerSuccess(text)
	M.Success(text, "server")
end

-- Console control
function M.Clear()
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("Clear")
	end
end

function M.Toggle(show)
	if ConsoleWebUI then
		if show == nil then
			local currentVisibility = ConsoleWebUI:GetVisibility()
			show = currentVisibility == WidgetVisibility.Hidden
		end

		if show then
			ConsoleWebUI:SetVisibility(WidgetVisibility.Visible)
			ConsoleWebUI:BringToFront()
		end

		ConsoleWebUI:CallEvent("Toggle", show)
	end
end

function M.SetTheme(theme)
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("SetTheme", theme)
	end
end

function M.RegisterCommand(name, desc, handler, args)
	console:register({ name = name, desc = desc, handler = handler, args = args })
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("RegisterCommand", name, desc, args)
	end
end

-- Autocomplete provider functions
function M.RegisterAutocomplete(name, desc, type, category)
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("RegisterAutocomplete", name, desc, type or "command", category)
	end
end

function M.UnregisterAutocomplete(name)
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("UnregisterAutocomplete", name)
	end
end

function M.ClearAutocomplete()
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("ClearAutocomplete")
	end
end

-- Caret position functions
function M.GetCaretPosition()
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("GetCaretPosition")
	end
end

function M.SetCaretPositionCallback(callback)
	caretPositionCallback = callback
end

-- Export the API to be accessed by other packages
return M
