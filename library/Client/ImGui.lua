-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Localized global functions for better performance
local table_insert = table.insert
local table_unpack = table.unpack

-- ImGui API - bridged via WebUI
-- Drives the ImGui demo page (UI/ImGui.html) through its window.UI facade,
-- so user interfaces can be built from Lua without touching JavaScript.
-- Results arrive as UI.call envelopes: { ok = boolean, result = any }.
local ImGui = {}

--- Enqueue until ready
local send
local is_ready
local is_imgui_ready
local when_ready
local ImGuiWebUI ---@type WebUI?
local example_visible = false

--- Creates the transparent overlay WebUI and wires the eval bridge.
--- Accepts an optional options table to override the defaults.
---@param options? table Optional overrides: { name = string, url = string, visibility = WidgetVisibility }.
function ImGui.Initialize(options)
	options = options or {}
	local ImGuiUI = WebUI(
		options.name or (Package.GetName() .. ":imgui.api"),
		options.url or "file://UI/ImGui.html",
		options.visibility or WidgetVisibility.Visible, true, false, 0, 0
	)
	ImGuiWebUI = ImGuiUI
	local pending = {} ---@type table<integer, function?>
	local queued = {} ---@type table<integer, {event:string, args:table, callback:function, req_id:integer}?>
	local ready_cbs = {} ---@type table<integer, function>
	local req_id = math.mininteger or 0
	local dom_ready = false
	local wasm_ready = false

	-- Receive results from JS
	ImGuiUI:Subscribe("EvalResult", function(id, success, payload)
		-- this is called from JS in response to our Eval request
		local cb = pending[id]
		if cb then      -- is this request valid?
			pending[id] = nil -- clear the request
			-- TODO/CONS: pcall?
			cb(success, payload) -- execute the user-provided callback
		end
	end)

	--- Dispatch request to JS
	---@param event string
	---@param args table
	---@param callback function
	---@param use_req_id? integer
	---@return integer req_id
	local function dispatch(event, args, callback, use_req_id)
		local id = use_req_id or (req_id + 1)
		if not use_req_id then
			req_id = id -- increment the counter
		end
		-- T-3 : safety check
		if pending[id] then return id end
		-- T-2 : cache the callback that would be executed upon completion of this request
		pending[id] = callback
		-- T-1 : inject the request ID as the first arg, so we can track this request properly
		table_insert(args, 1, id)
		-- ... aaaaaand ... ignition 🔥
		ImGuiUI:CallEvent(event, table_unpack(args))
		-- liftoff! 🚀
		return id
	end

	ImGuiUI:Subscribe("EvalReady", function()
		-- JS says DOM is ready
		if dom_ready then return end -- safety check
		dom_ready = true
		-- Flush the queue
		for i = 1, #queued do
			local q = queued[i]
			if q then
				dispatch(q.event, q.args, q.callback, q.req_id)
			end
		end
		queued = {}
	end)

	ImGuiUI:Subscribe("ImGuiReady", function(info)
		-- JS says the WASM runtime is ready (fired on DOM load, then again on init)
		if not (info and info.imguiReady) then return end -- wait for the runtime, not just the DOM
		if wasm_ready then return end               -- safety check
		wasm_ready = true
		-- Flush ready callbacks
		for i = 1, #ready_cbs do
			local cb = ready_cbs[i]
			if cb then cb() end
		end
		ready_cbs = {}
	end)

	function send(event, args, callback)
		-- Dispatch immediately if ready
		if dom_ready then
			return dispatch(event, args, callback)
		end
		-- Otherwise, enqueue the request until DOM is ready
		req_id = req_id + 1
		queued[#queued + 1] = { event = event, args = args, callback = callback, req_id = req_id }
		return req_id
	end

	function is_ready()
		return dom_ready
	end

	function is_imgui_ready()
		return wasm_ready
	end

	function when_ready(callback)
		-- Run immediately when the runtime is already up
		if wasm_ready then
			callback()
			return true
		end
		ready_cbs[#ready_cbs + 1] = callback
		return false
	end

	ImGui.Initialize = function() end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

--- Returns the underlying WebUI instance (nil before Initialize).
---@return WebUI? webui The underlying WebUI instance (nil before Initialize).
function ImGui.GetWebUI()
	return ImGuiWebUI
end

--- Reports whether the page DOM is ready (queued evals have been flushed).
---@return boolean ready True when the bridge accepts requests immediately.
function ImGui.IsReady()
	if not is_ready then return false end -- Initialize not called yet
	return is_ready()
end

--- Reports whether the ImGui WASM runtime is initialized.
---@return boolean ready True when ImGui widgets can be rendered.
function ImGui.IsImGuiReady()
	if not is_imgui_ready then return false end -- Initialize not called yet
	return is_imgui_ready()
end

--- Runs the callback once the ImGui runtime is ready.<br>
--- Executes immediately when already ready.
---@param callback function Called with no arguments when ready.
---@return boolean was_ready True when already ready (callback ran inline).
---@usage <br>
--- ```
--- ImGui.WhenReady(function()
---   ImGui.RegisterView("hud", [[ ImGui.Begin("HUD"); ImGui.Text("hi"); ImGui.End(); ]])
--- end)
--- ```
function ImGui.WhenReady(callback)
	if not when_ready then return false end -- Initialize not called yet
	return when_ready(callback)
end

--- Evaluates JavaScript code and returns the result.<br>
--- The code is executed in a sandboxed environment within the WebUI context.
---@param code string The JavaScript code to evaluate.
---@param callback? function Callback function to receive the eval result (function(success, payload)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- ImGui.Eval("1 + 1", function(success, result)
---   if success then
---     print("Result:", result) -- 2
---   end
--- end)
--- ```
function ImGui.Eval(code, callback)
	return send("DoEval", { code }, callback)
end

--- Evaluates JavaScript code with additional context variables.<br>
--- The provided context object will be available as variables in the evaluated code.
---@param code string The JavaScript code to evaluate.
---@param context table A table of key-value pairs to be available as variables in the JS context.
---@param callback? function Callback function to receive the eval result (function(success, payload)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- ImGui.EvalWithContext("a + b", { a = 5, b = 10 }, function(success, result)
---   if success then
---     print("Result:", result) -- 15
---   end
--- end)
--- ```
function ImGui.EvalWithContext(code, context, callback)
	return send("DoEvalWithContext", { code, context }, callback)
end

--- Invokes a window.UI facade method and returns its envelope.<br>
--- The payload is { ok = boolean, result = any } - check res.ok before using res.result.
---@param method string UI facade method name (e.g. "snapshot", "registerView").
---@param args? table Positional arguments forwarded to the method.
---@param callback? function Callback function to receive the call result (function(success, res)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- ImGui.Call("snapshot", {}, function(success, res)
---   if success and res.ok then
---     print("Speed:", res.result.float.gal_speed)
---   end
--- end)
--- ```
function ImGui.Call(method, args, callback)
	return send("DoEvalWithContext", { "UI.call(method, args)", { method = method, args = args or {} } }, callback)
end

--- Invokes several window.UI facade methods in one round-trip.<br>
--- Each entry is { method, arg1, arg2, ... }; the payload is an array of envelopes.
---@param calls table Array of { method:string, ...args } entries.
---@param callback? function Callback function to receive the batch results (function(success, results)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- ImGui.Batch({ { "set", "gal_speed", 7.5 }, { "get", "gal_speed" } }, function(success, results)
---   if success and results[2].ok then
---     print("Speed:", results[2].result.value) -- 7.5
---   end
--- end)
--- ```
function ImGui.Batch(calls, callback)
	return send("DoEvalWithContext", { "UI.batch(calls)", { calls = calls } }, callback)
end

--- Registers a custom render view from a JS function body.<br>
--- The body receives (ImGui, UI, fps); it must Begin/End its own windows.
---@param id string Unique view id (re-registering the same id replaces it).
---@param source string JS function body, e.g. 'ImGui.Begin("HUD"); ImGui.Text("hi"); ImGui.End();'.
---@param callback? function Callback function to receive the registration result (function(success, res)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- ImGui.RegisterView("hud", [[
---   ImGui.Begin("HUD");
---   ImGui.Text("hello from Lua!");
---   if (ImGui.Button("Ping")) console.log("ping");
---   ImGui.End();
--- ]])
--- ```
function ImGui.RegisterView(id, source, callback)
	return ImGui.Call("registerView", { id, source }, callback)
end

--- Unregisters a custom render view.
---@param id string View id passed to RegisterView.
---@param callback? function Callback function to receive the result (function(success, res)).
---@return integer req_id The request ID for tracking.
function ImGui.UnregisterView(id, callback)
	return ImGui.Call("unregisterView", { id }, callback)
end

--- Removes all custom render views.
---@param callback? function Callback function to receive the result (function(success, res)).
---@return integer req_id The request ID for tracking.
function ImGui.ClearViews(callback)
	return ImGui.Call("clearViews", {}, callback)
end

--- Lists registered custom view ids.
---@param callback? function Callback function to receive the id array (function(success, res)).
---@return integer req_id The request ID for tracking.
function ImGui.ListViews(callback)
	return ImGui.Call("listViews", {}, callback)
end

--- Returns per-view render errors for failing custom views.
---@param callback? function Callback function to receive the error array (function(success, res)).
---@return integer req_id The request ID for tracking.
function ImGui.ViewErrors(callback)
	return ImGui.Call("viewErrors", {}, callback)
end

--- Shows or hides the built-in demo windows (Widget Gallery, etc).
---@param enabled boolean False hides the demo so only custom views render.
---@param callback? function Callback function to receive the result (function(success, res)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- ImGui.SetShowDemo(false) -- custom views only
--- ```
function ImGui.SetShowDemo(enabled, callback)
	return ImGui.Call("setShowDemo", { enabled }, callback)
end

--- Reads one widget state value by key.
---@param key string State key used by the widget wrappers (e.g. "gal_speed").
---@param callback? function Callback function to receive { found, value } (function(success, res)).
---@return integer req_id The request ID for tracking.
function ImGui.Get(key, callback)
	return ImGui.Call("get", { key }, callback)
end

--- Writes one widget state value by key.<br>
--- Accepts boolean/number/string/number-array values.
---@param key string State key used by the widget wrappers (e.g. "gal_speed").
---@param value boolean|number|string|table Value to store (arrays must hold numbers only).
---@param callback? function Callback function to receive { found, value } (function(success, res)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- ImGui.Set("gal_speed", 7.5)
--- ```
function ImGui.Set(key, value, callback)
	return ImGui.Call("set", { key, value }, callback)
end

--- Reads several widget state values at once.
---@param keys table Array of state keys.
---@param callback? function Callback function to receive the key-value map (function(success, res)).
---@return integer req_id The request ID for tracking.
function ImGui.GetMany(keys, callback)
	return ImGui.Call("getMany", { keys }, callback)
end

--- Writes several widget state values at once.
---@param values table Map of state keys to values (see Set for accepted types).
---@param callback? function Callback function to receive { updated } (function(success, res)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- ImGui.SetMany({ gal_speed = 7.5, gal_count = 3 })
--- ```
function ImGui.SetMany(values, callback)
	return ImGui.Call("setMany", { values }, callback)
end

--- Reads the whole widget state (bool/float/int/string maps plus frame).
---@param callback? function Callback function to receive the snapshot (function(success, res)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- -- poll widget values every tick:
--- ImGui.Snapshot(function(success, res)
---   if success and res.ok then
---     print("Speed:", res.result.float.gal_speed)
---   end
--- end)
--- ```
function ImGui.Snapshot(callback)
	return ImGui.Call("snapshot", {}, callback)
end

--- Drains one-frame widget interaction events.<br>
--- Each event is { type, frame, ... } where type is one of:<br>
--- button, checkbox, selectable, combo, listbox, menu, radio, flags.
---@param callback? function Callback function to receive the event array (function(success, res)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- -- poll interactions every tick:
--- ImGui.PollEvents(function(success, res)
---   if success and res.ok then
---     for _, e in ipairs(res.result) do
---       print(e.type, e.id or e.key)
---     end
---   end
--- end)
--- ```
function ImGui.PollEvents(callback)
	return ImGui.Call("pollEvents", {}, callback)
end

--- Reports bridge and runtime status.
---@param callback? function Callback function to receive the status (function(success, res)).
---@return integer req_id The request ID for tracking.
function ImGui.Status(callback)
	return ImGui.Call("status", {}, callback)
end

--- Shows the Lua example window, proving Lua-to-JS interop.<br>
--- Hides the built-in demo, registers the "lua_example" view, seeds a
--- value, and starts polling interaction events every tick (see ExampleTick).
---@usage <br>
--- ```
--- ImGui.Example() -- a "Lua Example" window appears; click its button and watch the console
--- ```
function ImGui.Example()
	ImGui.SetShowDemo(false)
	ImGui.RegisterView("lua_example", [[
		ImGui.Begin("Lua Example");
		ImGui.Text("Built entirely from Lua via ImGui.RegisterView");
		ImGui.LabelText("FPS", fps.toFixed(1));
		ImGui.Separator();
		if (ImGui.Button("Click me!")) console.log("Lua example button pressed");
		ImGui.Checkbox("Enable feature", "ex_enabled", true);
		const speed = ImGui.SliderFloat("Speed", "ex_speed", 0.0, 10.0, "%.2f", 0, 3.5);
		ImGui.ProgressBar(speed.value / 10, 0, 0, speed.value.toFixed(2));
		ImGui.Combo("Fruit", "ex_fruit", ["Apple", "Banana", "Cherry"], -1, 0, 0);
		ImGui.InputText("Name", "ex_name", 0, "Ada");
		ImGui.ColorEdit3("Color", "ex_color", 0, [0.45, 0.55, 0.60]);
		ImGui.End();
	]])
	ImGui.Set("ex_speed", 7.5)
	if not example_visible then
		example_visible = true
		Client.Subscribe("Tick", ImGui.ExampleTick)
	end
end

--- Hides the Lua example window and restores the built-in demo.
function ImGui.HideExample()
	ImGui.UnregisterView("lua_example")
	ImGui.SetShowDemo(true)
	if example_visible then
		example_visible = false
		Client.Unsubscribe("Tick", ImGui.ExampleTick)
	end
end

--- Polls widget interaction events and prints them, proving JS-to-Lua interop.<br>
--- Subscribed to Tick by Example (unsubscribed by HideExample).
---@return integer req_id The request ID for tracking.
function ImGui.ExampleTick()
	return ImGui.PollEvents(function(success, res)
		if success and res.ok then
			for _, e in ipairs(res.result) do
				print(string.format("[ImGui] event: %s %s", e.type, e.id or e.key or ""))
			end
		end
	end)
end

-- Export the API to be accessed by other packages
return ImGui
