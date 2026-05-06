-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Console engine

-- Import dependencies
local fuzzy = require "@cheatoid/standalone/fuzzy"
local console = require "@cheatoid/standalone/console"
local autocompleter = require "@cheatoid/autocompleter/autocompleter"
local permission = require "@cheatoid/permission/permission"
local plugin_framework = require "@cheatoid/plugin_framework/plugin_framework"
local chat_commander = require "@cheatoid/chat_commander/chat_commander"

local M = {}
local ConsoleWebUI = _G.ConsoleWebUI

-- Create ChatCommander instance
local commander = chat_commander.new("/")

-- Register theme suggestions for autocompletion
local themes = { "amber", "arctic", "aurora", "bloodmoon", "cyberpunk", "matrix", "midnight", "glass" }
commander:register_suggestions("theme", function(partial)
	local partial_lower = string.lower(partial or "")
	local matches = {}
	for i = 1, #themes do
		local theme = themes[i]
		if string.sub(string.lower(theme), 1, #partial_lower) == partial_lower then
			table.insert(matches, theme)
		end
	end
	return matches
end)

-- Register theme command with chat_commander for autocompletion
commander:register_command("theme", {
	description = "Switch console theme",
	args = {
		{ name = "name", type = "string", required = false, enum = themes }
	},
	handler = function(ctx, args)
		local themeName = args.name
		if not themeName then
			M.Info("Available themes: " .. table.concat(themes, ", "))
			return
		end

		-- Theme validation is handled automatically by ChatCommander enum validation
		M.SetTheme(themeName)
		M.Success("Theme changed to: " .. themeName)
	end
})

-- Register help command to show available commands
commander:register_command("help", {
	description = "Show available commands or get help for a specific command",
	args = {
		{ name = "command", type = "string", required = false }
	},
	handler = function(ctx, args)
		print("HELLO?!?!?!?")
		local cmdName = args.command
		if cmdName then
			-- Show help for specific command
			local helpText, error = commander:get_help(cmdName)
			if helpText then
				M.Info(helpText)
			else
				M.Error(error or "Unknown command: " .. cmdName)
			end
		else
			-- List all available commands
			local commands = commander:list_commands()
			if #commands > 0 then
				M.Info("Available commands:")
				for _, cmd in ipairs(commands) do
					local desc = cmd.description or "No description available"
					M.Info("  " .. cmd.name .. " - " .. desc)
				end
				M.Info("Use 'help <command>' to get detailed help for a specific command")
			else
				M.Info("No commands registered")
			end
		end
	end
})

-- Register time command
commander:register_command("time", {
	description = "Show current time",
	handler = function(ctx, args)
		local currentTime = os.date("%H:%M:%S")
		M.Info("Current time: " .. currentTime)
	end
})

-- Register date command
commander:register_command("date", {
	description = "Show current date",
	handler = function(ctx, args)
		local currentDate = os.date("%Y-%m-%d")
		M.Info("Current date: " .. currentDate)
	end
})

-- Register version command
commander:register_command("version", {
	description = "Show version info",
	handler = function(ctx, args)
		M.Info("Console Engine v0.1")
	end
})

-- Register stats command
commander:register_command("stats", {
	description = "Show message statistics",
	handler = function(ctx, args)
		-- Get stats from JavaScript side
		if M.IsReady() then
			ConsoleWebUI:CallEvent("getStats")
		else
			M.Info("Console not ready - cannot retrieve stats")
		end
	end
})

-- Register about command
commander:register_command("about", {
	description = "About this console",
	handler = function(ctx, args)
		M.Info("In-Game Console UI")
		M.Info("A modular, themeable, and extensible console system.")
		M.Info("")
		M.Info("Press Tab for autocomplete, Up/Down for history.")
	end
})

-- Register echo command
commander:register_command("echo", {
	description = "Print text to console",
	args = {
		{ name = "text", type = "string", required = true }
	},
	handler = function(ctx, args)
		M.Info(args.text or "")
	end
})

-- Register clear command
commander:register_command("clear", {
	description = "Clear console output",
	aliases = { "cls" },
	handler = function(ctx, args)
		print("CLEARING...")
		M.Clear()
	end
})

-- Register a simple test command to verify chat_commander is working
commander:register_command("testcmd", {
	description = "Test command for autocompletion",
	args = {
		{ name = "arg1", type = "string", required = false }
	},
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
	print("DEBUG: ConsoleEngine.Initialize() called!")
	if ConsoleWebUI then
		print("DEBUG: ConsoleWebUI already exists, recreating")
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

	print("DEBUG: Creating new ConsoleWebUI instance")
	ConsoleWebUI = _G.ConsoleWebUI or WebUI(
		Package.GetName() .. ":console",
		"file://UI/ConsoleEngine.html",
		WidgetVisibility.Hidden, true, true
	)
	_G.ConsoleWebUI = ConsoleWebUI
	print("DEBUG: ConsoleWebUI instance created")

	ConsoleWebUI:Subscribe("ConsoleReady", function()
		M.Info("DEBUG: ConsoleReady event fired!")
		-- Initialize with default theme
		ConsoleWebUI:CallEvent("setTheme", "amber")
		M.Toggle(true)

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
	end)

	ConsoleWebUI:Subscribe("clipboardWrite", function(text)
		Client.CopyToClipboard(text)
	end)

	-- Handle command execution from JS
	ConsoleWebUI:Subscribe("onCommand", function(name, args)
		-- Debug: Log command execution attempt
		M.Info("DEBUG: onCommand event fired! Received command '" .. name .. "' with " .. #args .. " args")

		-- Build full command line for chat_commander
		local fullCommand = name
		if args and #args > 0 then
			fullCommand = fullCommand .. " " .. table.concat(args, " ")
		end

		M.Info("DEBUG: Full command: '" .. fullCommand .. "'")

		-- Try to execute with chat_commander first
		local success, result = pcall(function()
			return commander:handle_line({}, fullCommand)
		end)

		M.Info("DEBUG: chat_commander result - success: " .. tostring(success) .. ", result: " .. tostring(result))

		if success and result then
			-- Command was handled by chat_commander successfully
			-- chat_commander returns true for successful execution, result contains error message if any
			if result ~= true then
				M.Error(result)
			end
		else
			-- Forward to Console.RunCommand for game console commands
			M.Info("DEBUG: Forwarding to Console.RunCommand")
			Console.RunCommand(fullCommand)
		end
	end)

	-- Handle toggle events from JS
	ConsoleWebUI:Subscribe("onToggle", function(isOpen)
		-- TODO: Add custom logic when console opens/closes
	end)

	-- Handle stats request from JS
	ConsoleWebUI:Subscribe("statsResponse", function(stats)
		if stats then
			local statsText = string.format(
				"Messages - Total: %d | Log: %d | Info: %d | Warn: %d | Error: %d | Debug: %d | Success: %d | Cmd: %d",
				stats.total or 0, stats.log or 0, stats.info or 0, stats.warn or 0,
				stats.error or 0, stats.debug or 0, stats.success or 0, stats.cmd or 0)
			M.Info(statsText)
		end
	end)

	-- Subscribe to caret position events from JS
	ConsoleWebUI:Subscribe("caretPosition", function(position, inputValue, wordBeforeCaret)
		if caretPositionCallback then
			caretPositionCallback(position, inputValue, wordBeforeCaret)
		end
	end)

	-- Handle autocomplete requests from JS
	ConsoleWebUI:Subscribe("getAutocomplete", function(line, caret)
		-- Add prefix for chat_commander since it expects slash commands
		local line_with_slash = commander.prefix .. line
		local suggestions = commander:suggest_at(line_with_slash, caret, { max_results = 8 })
		print("Autocomplete requested: line=" .. line .. " caret=" .. caret .. " suggestions=" .. #suggestions)

		-- Convert suggestions to the format expected by JavaScript
		local formatted_suggestions = {}
		if suggestions then
			for _, suggestion in next, suggestions do
				if type(suggestion) == "table" and suggestion.text then
					table.insert(formatted_suggestions, {
						name = suggestion.text:gsub("^" .. commander.prefix, ""), -- Remove prefix
						desc = suggestion.description or ""
					})
				elseif type(suggestion) == "string" then
					table.insert(formatted_suggestions, {
						name = suggestion:gsub("^" .. commander.prefix, ""), -- Remove prefix
						desc = ""
					})
				end
			end
		end

		ConsoleWebUI:CallEvent("autocompleteSuggestions", formatted_suggestions)
	end)

	-- Test event to verify JavaScript-to-Lua communication
	ConsoleWebUI:Subscribe("testEvent", function(message)
		M.Info("DEBUG: Lua received testEvent: " .. tostring(message))
	end)

	M.Initialize = function() end
end

-- Logging functions
function M.Log(type, text)
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("log", type, text)
	end
end

function M.Info(text)
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("info", text)
	end
end

function M.Warn(text)
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("warn", text)
	end
end

function M.Error(text)
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("error", text)
	end
end

function M.Debug(text)
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("debug", text)
	end
end

function M.Success(text)
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("success", text)
	end
end

-- Console control
function M.Clear()
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("clear")
	end
end

function M.Toggle(show)
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("toggle", show)
	end
end

function M.SetTheme(theme)
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("setTheme", theme)
	end
end

function M.RegisterCommand(name, desc, handler, args)
	commander:register_command(name, { description = desc, handler = handler, args = args })
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("registerCommand", name, desc, args)
	end
end

-- Autocomplete provider functions
function M.RegisterAutocomplete(name, desc, type, category)
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("registerAutocomplete", name, desc, type or "command", category)
	end
end

function M.UnregisterAutocomplete(name)
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("unregisterAutocomplete", name)
	end
end

function M.ClearAutocomplete()
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("clearAutocomplete")
	end
end

-- Caret position functions
function M.GetCaretPosition()
	if ConsoleWebUI then
		ConsoleWebUI:CallEvent("getCaretPosition")
	end
end

function M.SetCaretPositionCallback(callback)
	caretPositionCallback = callback
end

-- Export
return M
