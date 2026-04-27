-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Console engine

-- Import dependencies
local console = require "@cheatoid/standalone/console"
local autocompleter = require "@cheatoid/autocompleter/autocompleter"
local permission = require "@cheatoid/permission/permission"
local plugin_framework = require "@cheatoid/plugin_framework/plugin_framework"

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

		ConsoleWebUI:Subscribe("Ready", function()
			-- Initialize with default theme
			ConsoleWebUI:CallEvent("setTheme", "amber")
			M.Toggle(true)
		end)

		-- Handle command execution from JS
		ConsoleWebUI:Subscribe("onCommand", function(name, args)
			local cmd = commands[name]
			if cmd and cmd.handler then
				local result = cmd.handler(args)
				if result then
					M.Log(result.type or "log", result.text)
				end
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
