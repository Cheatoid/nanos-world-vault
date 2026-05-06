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
local ConsoleWebUI

-- Command registration
local commands = {}

-- Set callback for caret position updates
local caretPositionCallback

function M.IsReady()
	return ConsoleWebUI and ConsoleWebUI:IsReady()
end

function M.Initialize()
	if ConsoleWebUI then
	else
		ConsoleWebUI = WebUI(
			Package.GetName() .. ":console",
			"file://UI/ConsoleEngine.html",
			WidgetVisibility.Hidden, true, true
		)

		ConsoleWebUI:Subscribe("ConsoleReady", function()
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

		-- Handle command execution from JS
		ConsoleWebUI:Subscribe("onCommand", function(name, args)
			local cmd = commands[name]
			if cmd and cmd.handler then
				local result = cmd.handler(args)
				if result then
					M.Log(result.type or "log", result.text)
				end
			else
				-- Forward to Console.RunCommand for game console commands
				local fullCommand = name
				if args and #args > 0 then
					fullCommand = fullCommand .. " " .. table.concat(args, " ")
				end
				Console.RunCommand(fullCommand)
			end
		end)

		-- Handle toggle events from JS
		ConsoleWebUI:Subscribe("onToggle", function(isOpen)
			-- TODO: Add custom logic when console opens/closes
		end)

		-- Subscribe to caret position events from JS
		ConsoleWebUI:Subscribe("caretPosition", function(position, inputValue, wordBeforeCaret)
			if caretPositionCallback then
				caretPositionCallback(position, inputValue, wordBeforeCaret)
			end
		end)

		-- Handle autocomplete requests from JS
		ConsoleWebUI:Subscribe("getAutocomplete", function(line, caret)
			local suggestions = chat_commander.suggest_at(line, caret, { max_results = 8 })
			ConsoleWebUI:CallEvent("autocompleteSuggestions", suggestions)
		end)
	end
end

-- Logging functions
function M.Log(type, text)
	if M.IsReady() then
		ConsoleWebUI:CallEvent("log", type, text)
	end
end

function M.Info(text)
	if M.IsReady() then
		ConsoleWebUI:CallEvent("info", text)
	end
end

function M.Warn(text)
	if M.IsReady() then
		ConsoleWebUI:CallEvent("warn", text)
	end
end

function M.Error(text)
	if M.IsReady() then
		ConsoleWebUI:CallEvent("error", text)
	end
end

function M.Debug(text)
	if M.IsReady() then
		ConsoleWebUI:CallEvent("debug", text)
	end
end

function M.Success(text)
	if M.IsReady() then
		ConsoleWebUI:CallEvent("success", text)
	end
end

-- Console control
function M.Clear()
	if M.IsReady() then
		ConsoleWebUI:CallEvent("clear")
	end
end

function M.Toggle(show)
	if M.IsReady() then
		ConsoleWebUI:CallEvent("toggle", show)
	end
end

function M.SetTheme(theme)
	if M.IsReady() then
		ConsoleWebUI:CallEvent("setTheme", theme)
	end
end

function M.RegisterCommand(name, desc, handler)
	commands[name] = { desc = desc, handler = handler }
	if M.IsReady() then
		ConsoleWebUI:CallEvent("registerCommand", name, desc)
	end
end

-- Autocomplete provider functions
function M.RegisterAutocomplete(name, desc, type, category)
	if M.IsReady() then
		ConsoleWebUI:CallEvent("registerAutocomplete", name, desc, type or "command", category)
	end
end

function M.UnregisterAutocomplete(name)
	if M.IsReady() then
		ConsoleWebUI:CallEvent("unregisterAutocomplete", name)
	end
end

function M.ClearAutocomplete()
	if M.IsReady() then
		ConsoleWebUI:CallEvent("clearAutocomplete")
	end
end

-- Caret position functions
function M.GetCaretPosition()
	if M.IsReady() then
		ConsoleWebUI:CallEvent("getCaretPosition")
	end
end

function M.SetCaretPositionCallback(callback)
	caretPositionCallback = callback
end

-- Export
return M
