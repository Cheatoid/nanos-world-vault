-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- TODO: Intercept & Protect:
-- Chat.AddMessage(message)
-- Client.SetDebugEnabled(false)
-- Client.SetHighlightColor(highlight_color, index, mode?)
-- Client.SetOutlineColor(outline_color, index?, thickness?)
-- Console.RegisterCommand(command, callback, description?, parameters?)
-- Console.RunCommand(command)
-- Canvas (class) API
-- Debug API
-- Character.GetAll()
-- Player.GetAll()
-- Paintable:SetMaterialFromCanvas(canvas, index?)
-- Paintable:SetMaterialFromSceneCapture(scene_capture, index?)
-- Paintable:SetMaterialFromWebUI(webui, index?)

--local input_enabled = Input.IsInputEnabled()
--local is_mouse_enabled = Input.IsMouseEnabled()
--local scripting_key_bindings = Input.GetScriptingKeyBindings()
--local screen_position = Viewport.ProjectWorldToScreen(world_position)
--local world_position = Viewport.DeprojectScreenToWorld(screen_position)
--local viewport_size = Viewport.GetViewportSize()
--local mouse_pos = Viewport.GetMousePosition()
--local values_keys = Client.GetAllValuesKeys()
--local local_player = Client.GetLocalPlayer()
--local camera_location = local_player:GetCameraLocation()
--local camera_rotation = local_player:GetCameraRotation()
--local direction = camera_rotation:GetForwardVector()
--local entity = Client.GetEntityByID(entity_id)
--local frame_time = Client.GetFrameTime()

-- TODO: figure out how to capture post-render game screenshot
--Steam.TriggerScreenshot()

-- Localization
local WebUI = WebUI

local Client_GetTime = Client.GetTime
local os_clock = os.clock
local function GetTimestamp()
	return Client_GetTime() + os_clock()
end

local web ---@type WebUI|nil
local function InitializeWebUI()
	web = WebUI("", "", WidgetVisibility.Hidden, true, false, 0, 0)
	web:Subscribe("Ready", function()
		web:CallEvent("", "AntiCheat WebUI is Ready")
	end)
	web:Subscribe("", function(param1)
		print("Received response: " .. tostring(param1))
	end)
	--web:LoadHTML([[]])
	web:LoadURL("https://cheatoid.github.io/nanos-world-vault/anticheat/index.html")
end

-- TODO: will be set dynamically
local JS_AntiCheat_Heartbeat ---@type string|nil

function _G.IsAntiCheatLoaded() -- intentionally global (honeypot)
	return JS_AntiCheat_Heartbeat ~= nil
end

Client.Subscribe("LanguageChange",
	function(language)
		-- Called when the Client language changes
	end)

Client.Subscribe("SpawnLocalPlayer",
	function(local_player)
		-- Called when the local player spawns (just after the game has loaded)
		InitializeWebUI()
	end)

Client.Subscribe("Tick",
	function(delta_time)
		-- Called every frame
	end)

Client.Subscribe("ValueChange",
	function(key, value)
		-- Triggered when a value is changed with Client.SetValue or Server.SetValue (for synced values)
	end)

Client.Subscribe("WindowFocusChange",
	function(is_focused)
		-- Called when the game is focused/unfocused
	end)

Chat.Subscribe("ChatEntry",
	function(message, player)
		-- Called when a new Chat Message is received,
		-- this is also triggered when new messages are sent programatically
	end)

Chat.Subscribe("Close",
	function()
		-- When player closes the Chat
	end)

Chat.Subscribe("Open",
	function()
		-- When player opens the Chat
	end)

Console.Subscribe("Close",
	function()
		-- Console Close was called
	end)

Console.Subscribe("LogEntry",
	function(text, type)
		-- Console LogEntry was called
	end)

Console.Subscribe("Open",
	function()
		-- Console Open was called
	end)

Console.Subscribe("PlayerSubmit",
	function(text)
		-- Console PlayerSubmit was called
	end)

Input.Subscribe("KeyDown",
	function(key_name, delta)
		-- KeyDown was called
	end)

Input.Subscribe("KeyPress",
	function(key_name, delta)
		-- KeyPress was called
	end)

Input.Subscribe("KeyUp",
	function(key_name, delta)
		-- KeyUp was called
	end)

Input.Subscribe("MouseDown",
	function(key_name, mouse_x, mouse_y)
		-- MouseDown was called
	end)

Input.Subscribe("MouseMove",
	function(cursor_delta_x, cursor_delta_y, mouse_x, mouse_y)
		-- MouseMove was called
	end)

Input.Subscribe("MouseScroll",
	function(mouse_x, mouse_y, delta)
		-- MouseScroll was called
	end)

Input.Subscribe("MouseUp",
	function(key_name, mouse_x, mouse_y)
		-- MouseUp was called
	end)

Viewport.Subscribe("Resize",
	function(new_size)
		-- Viewport Resize was called
	end)

local TimerHeartbeat, TimerHeartbeatCallback
do
	local math_random = math.random
	function TimerHeartbeatCallback()
		if IsAntiCheatLoaded() then
			-- TODO: request heartbeat from JS
			web:CallEvent(JS_AntiCheat_Heartbeat, GetTimestamp())
			Timer.ClearInterval(TimerHeartbeat)
			TimerHeartbeat = Timer.SetInterval(TimerHeartbeatCallback, math_random(100, 5000))
		end
	end

	TimerHeartbeat = Timer.SetInterval(TimerHeartbeatCallback, math_random(1000, 5000))
end

Events.SubscribeRemote("AntiCheat::Init", function()
	-- TODO
end)

--debug.sethook()

collectgarbage()
collectgarbage()
