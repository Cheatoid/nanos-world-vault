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
local initialized = false
local ImGuiWebUI ---@type WebUI?
local example_visible = false
local example_views = {} ---@type table<string, boolean>

--- Fails with a actionable message when the bridge was never initialized.
--- Without this every Eval/Call crashes with cryptic
--- `attempt to call a nil value (upvalue 'send')` at Call().
local function assert_initialized(what)
	if not send then
		error(string.format(
			"ImGui.%s failed: ImGui not initialized. Run `lua imgui.Initialize()` first (creates the file://UI/ImGui.html overlay). Do NOT use the WebBrowser tab for this.",
			tostring(what or "Call")), 3)
	end
end

--- Creates the transparent overlay WebUI and wires the eval bridge.
--- Accepts an optional options table to override the defaults.
--- Do NOT open the demo via WebBrowser (New Tab -> ImGui link): that tab has
--- no Lua bridge. This overlay (file://UI/ImGui.html + postMessage relay to
--- the embedded imgui_web_demo iframe) is the only path Example* can drive.
---@param options? table Optional overrides: { name = string, url = string, visibility = WidgetVisibility }.
function ImGui.Initialize(options)
	if initialized then return end
	initialized = true
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
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

--- Reports whether Initialize has created the overlay WebUI.
---@return boolean initialized True after Initialize ran.
function ImGui.IsInitialized()
	return initialized
end

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
	assert_initialized("Eval")
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
	assert_initialized("EvalWithContext")
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
	assert_initialized("Call")
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
	assert_initialized("Batch")
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

--- Peeks widget interaction events WITHOUT draining the queue.<br>
--- Same payload as PollEvents; the events remain queued, so the next
--- PollEvents still returns them. Useful for inspecting without consuming
--- (the shared Tick poller, bindings and button routes all consume via PollEvents).
---@param callback? function Callback function to receive the event array (function(success, res)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- ImGui.PeekEvents(function(success, res)
---   if success and res.ok then print("queued:", #res.result) end
--- end)
--- ```
function ImGui.PeekEvents(callback)
	return ImGui.Call("peekEvents", {}, callback)
end

--- Reports bridge and runtime status.<br>
--- Result fields: { domReady, imguiReady, demo, frame, views, viewErrors,
--- queuedEvents, uiVersion }. uiVersion "1.2.0"+ means SetTheme and friends
--- are available (older pages answer those calls with { ok = false }).
---@param callback? function Callback function to receive the status (function(success, res)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- ImGui.Status(function(success, res)
---   if success and res.ok then print("demo ui:", res.result.uiVersion) end
--- end)
--- ```
function ImGui.Status(callback)
	return ImGui.Call("status", {}, callback)
end

----------------------------------------------------------------------
-- Theme & style (global, persistent across frames)
----------------------------------------------------------------------
--- Requires the demo page v1.2.0+ (see Status uiVersion): rebuild
--- imgui_web_demo (build.cmd) and redeploy the hosted page. Calls against an
--- older page fail gracefully with { ok = false } and change nothing.<br>
--- For per-frame styling that works on ANY page version, see ThemeSnippet.

--- ImGuiCol indices. Mirrors imgui.h enum ImGuiCol_ order (Text = 0).
ImGui.Col = {
	Text = 0,
	TextDisabled = 1,
	WindowBg = 2,
	ChildBg = 3,
	PopupBg = 4,
	Border = 5,
	BorderShadow = 6,
	FrameBg = 7,
	FrameBgHovered = 8,
	FrameBgActive = 9,
	TitleBg = 10,
	TitleBgActive = 11,
	TitleBgCollapsed = 12,
	MenuBarBg = 13,
	ScrollbarBg = 14,
	ScrollbarGrab = 15,
	ScrollbarGrabHovered = 16,
	ScrollbarGrabActive = 17,
	CheckMark = 18,
	CheckboxSelectedBg = 19,
	SliderGrab = 20,
	SliderGrabActive = 21,
	Button = 22,
	ButtonHovered = 23,
	ButtonActive = 24,
	Header = 25,
	HeaderHovered = 26,
	HeaderActive = 27,
	Separator = 28,
	SeparatorHovered = 29,
	SeparatorActive = 30,
	ResizeGrip = 31,
	ResizeGripHovered = 32,
	ResizeGripActive = 33,
	InputTextCursor = 34,
	TabHovered = 35,
	Tab = 36,
	TabSelected = 37,
	TabSelectedOverline = 38,
	TabDimmed = 39,
	TabDimmedSelected = 40,
	TabDimmedSelectedOverline = 41,
	DockingPreview = 42,
	DockingEmptyBg = 43,
	PlotLines = 44,
	PlotLinesHovered = 45,
	PlotHistogram = 46,
	PlotHistogramHovered = 47,
	TableHeaderBg = 48,
	TableBorderStrong = 49,
	TableBorderLight = 50,
	TableRowBg = 51,
	TableRowBgAlt = 52,
	TextLink = 53,
	TextSelectedBg = 54,
	TreeLines = 55,
	DragDropTarget = 56,
	DragDropTargetBg = 57,
	UnsavedMarker = 58,
	NavCursor = 59,
	NavWindowingHighlight = 60,
	NavWindowingDimBg = 61,
	ModalWindowDimBg = 62,
}

--- Number of ImGuiCol entries (63 for this Dear ImGui version).<br>
--- Prefer the runtime count via GetStyleColorCount when validating indices.
ImGui.ColCount = 63

--- Returns the runtime ImGuiCol count from the demo page.<br>
--- Use it to validate numeric Col indices instead of trusting ColCount.
---@param callback? function Callback function to receive the count (function(success, res)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- ImGui.GetStyleColorCount(function(success, res)
---   if success and res.ok then print("colors:", res.result) end
--- end)
--- ```
function ImGui.GetStyleColorCount(callback)
	return ImGui.Call("getStyleColorCount", {}, callback)
end

--- Valid SetStyleFloat fields (see the C++ curated setters).
ImGui.StyleFloatFields = { "alpha", "disabledAlpha", "windowRounding", "windowBorderSize",
	"childRounding", "childBorderSize", "popupRounding", "popupBorderSize",
	"frameRounding", "frameBorderSize", "indentSpacing", "scrollbarSize",
	"scrollbarRounding", "grabMinSize", "grabRounding", "tabRounding" }

--- Valid SetStyleVec2 fields.
ImGui.StyleVec2Fields = { "windowPadding", "framePadding", "itemSpacing" }

--- Applies a global theme preset plus optional overrides (one-shot, persistent).<br>
--- Overrides: { colors = { Button = { r, g, b, a } }, floats = { windowRounding = 6 },
--- vec2s = { windowPadding = { 10, 10 } } }. Color keys accept Col names or indices.
---@param name string Preset: "dark", "light" or "classic".
---@param overrides? table Optional { colors = {}, floats = {}, vec2s = {} } tweaks.
---@param callback? function Callback function to receive { theme } (function(success, res)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- ImGui.SetTheme("dark")
--- ImGui.SetTheme("light", { floats = { windowRounding = 8 }, colors = { Button = { 0.2, 0.6, 0.9, 1 } } })
--- ```
function ImGui.SetTheme(name, overrides, callback)
	if type(overrides) == "function" and callback == nil then
		callback = overrides
		overrides = nil
	end
	return ImGui.Call("setTheme", { name or "dark", overrides or {} }, callback)
end

--- Applies the Dear ImGui dark preset (one-shot, persistent).
---@param callback? function Callback function to receive the result (function(success, res)).
---@return integer req_id The request ID for tracking.
function ImGui.StyleColorsDark(callback)
	return ImGui.SetTheme("dark", nil, callback)
end

--- Applies the Dear ImGui light preset (one-shot, persistent).
---@param callback? function Callback function to receive the result (function(success, res)).
---@return integer req_id The request ID for tracking.
function ImGui.StyleColorsLight(callback)
	return ImGui.SetTheme("light", nil, callback)
end

--- Applies the Dear ImGui classic preset (one-shot, persistent).
---@param callback? function Callback function to receive the result (function(success, res)).
---@return integer req_id The request ID for tracking.
function ImGui.StyleColorsClassic(callback)
	return ImGui.SetTheme("classic", nil, callback)
end

--- Overrides one global style color (one-shot, persistent).<br>
--- Accepts a Col name ("Button") or index plus an { r, g, b[, a] } array.
---@param idxOrName string|integer Col name or index (see ImGui.Col).
---@param rgba table { r, g, b[, a] } floats in 0..1.
---@param callback? function Callback function to receive the result (function(success, res)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- ImGui.SetStyleColor("Button", { 0.2, 0.6, 0.9, 1 })
--- ImGui.SetStyleColor(ImGui.Col.Header, { 0.9, 0.3, 0.2, 1 })
--- ```
function ImGui.SetStyleColor(idxOrName, rgba, callback)
	return ImGui.Call("setStyleColor", { idxOrName, rgba }, callback)
end

--- Overrides one global float style var (one-shot, persistent).<br>
--- Field must be one of ImGui.StyleFloatFields.
---@param field string e.g. "windowRounding", "alpha", "frameRounding".
---@param value number New value.
---@param callback? function Callback function to receive the result (function(success, res)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- ImGui.SetStyleFloat("windowRounding", 8)
--- ```
function ImGui.SetStyleFloat(field, value, callback)
	return ImGui.Call("setStyleFloat", { field, value }, callback)
end

--- Overrides one global ImVec2 style var (one-shot, persistent).<br>
--- Field must be one of ImGui.StyleVec2Fields.
---@param field string e.g. "windowPadding", "framePadding", "itemSpacing".
---@param x number New x component.
---@param y number New y component.
---@param callback? function Callback function to receive the result (function(success, res)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- ImGui.SetStyleVec2("windowPadding", 12, 12)
--- ```
function ImGui.SetStyleVec2(field, x, y, callback)
	return ImGui.Call("setStyleVec2", { field, x, y }, callback)
end

--- Convenience: global alpha (one-shot, persistent).
---@param value number 0..1.
---@param callback? function Callback function to receive the result (function(success, res)).
---@return integer req_id The request ID for tracking.
function ImGui.SetStyleAlpha(value, callback)
	return ImGui.SetStyleFloat("alpha", value, callback)
end

--- Convenience: window corner rounding (one-shot, persistent).
---@param value number Pixels, 0 for rectangular windows.
---@param callback? function Callback function to receive the result (function(success, res)).
---@return integer req_id The request ID for tracking.
function ImGui.SetStyleWindowRounding(value, callback)
	return ImGui.SetStyleFloat("windowRounding", value, callback)
end

--- Convenience: frame (widget) corner rounding (one-shot, persistent).
---@param value number Pixels, 0 for rectangular frames.
---@param callback? function Callback function to receive the result (function(success, res)).
---@return integer req_id The request ID for tracking.
function ImGui.SetStyleFrameRounding(value, callback)
	return ImGui.SetStyleFloat("frameRounding", value, callback)
end

--- Builds a per-frame Push/Pop style snippet around JS content.<br>
--- Works on ANY page version (uses only the long-bound Push/PopStyleColor).<br>
--- Colors accept Col names ("Button") or indices; values are { r, g, b[, a] }.
---@param colors table Map of Col name/index to { r, g, b[, a] }.
---@param content string JS statements rendered with the pushed style.
---@return string snippet Balanced PushStyleColor ... content ... PopStyleColor(n).
---@usage <br>
--- ```
--- local inner = ImGui.ThemeSnippet({ Button = { 0.2, 0.6, 0.9, 1 } }, [[
---   if (ImGui.Button("Styled!")) console.log("styled pressed");
--- ]])
--- ImGui.RegisterView("styled", "ImGui.Begin(\"S\");\n" .. inner .. "\nImGui.End();")
--- ```
function ImGui.ThemeSnippet(colors, content)
	local pushes = {}
	local n = 0
	for k, c in next, colors or {} do
		local idx = type(k) == "string" and ImGui.Col[k] or k
		assert(idx ~= nil, "ThemeSnippet: unknown Col " .. tostring(k))
		assert(type(c) == "table" and (#c == 3 or #c == 4), "ThemeSnippet: color must be { r, g, b[, a] }")
		pushes[#pushes + 1] = string.format("ImGui.PushStyleColor(%d, %s, %s, %s, %s);",
			idx, tostring(c[1]), tostring(c[2]), tostring(c[3]), tostring(c[4] or 1.0))
		n = n + 1
	end
	return table.concat(pushes, "\n") .. "\n" .. (content or "") .. string.format("\nImGui.PopStyleColor(%d);", n)
end

----------------------------------------------------------------------
-- Bindings (two-way Lua <-> UI)
----------------------------------------------------------------------

--- Coverage: PollEvents only fires for checkbox, selectable (stateful),
--- combo, listbox, radio (RadioButtonInt) and flags (CheckboxFlags), plus
--- momentary button/menu presses. Sliders, drags, text/number inputs and
--- color editors/pickers update storage SILENTLY, so bindings cover them via
--- a throttled GetMany poll (see ExampleTick). Text/LabelText/ProgressBar/plots
--- are display-only (nothing to bind: drive them from storage, see ExampleLabels).
--- Tooltips (SetTooltip/SetItemTooltip) take static strings likewise: compose
--- them from storage in the view (see ExampleLabels). Buttons/menus use OnButton.
--- Colors are split-key storage (key_r/_g/_b/_a): use BindColor, not Bind.
--- DragFloatRange2 is dual-key (keyMin + keyMax): Bind each key separately.
--- Mirrors: key -> { value = any, on_change: function?, subkeys: string[]? }.
local bindings = {} ---@type table<string, { value: any, on_change: function?, subkeys: string[]? }>

--- Button id -> Lua handler, run from the shared Tick poller.<br>
--- Lets a UI button drive Lua logic (which can then SetBound back to the UI).
local button_routes = {} ---@type table<string, function>

--- Shallow array-aware equality (scalars via ==, number-arrays element-wise).
---@param a any
---@param b any
---@return boolean equal
local function bindings_equal(a, b)
	if a == b then return true end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	if #a ~= #b then return false end
	for i = 1, #a do
		if a[i] ~= b[i] then return false end
	end
	return true
end

--- Shallow array copy (scalars pass through).
---@param v any
---@return any copy
local function bindings_copy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for i = 1, #v do out[i] = v[i] end
	return out
end

--- Ticks between GetMany polls for silent widgets (sliders/drags/inputs/colors).
--- Events stay immediate (every Tick); silent widgets lag at most this many Ticks.
local POLL_EVERY = 10
local tick_frame = 0

--- Ensures the shared Tick poller is subscribed exactly once.<br>
--- Shared by example views and bindings so PollEvents is drained once per frame.
local function ensure_tick()
	if example_visible then return end
	example_visible = true
	Client.Subscribe("Tick", ImGui.ExampleTick)
end

--- Stops the shared Tick poller when no views, bindings or button routes remain.
local function maybe_stop_tick()
	if next(example_views) == nil and next(bindings) == nil and next(button_routes) == nil and example_visible then
		example_visible = false
		Client.Unsubscribe("Tick", ImGui.ExampleTick)
	end
end

--- Tracks a visible example view and ensures Tick polling.
---@param id string View id registered via RegisterView.
local function track_example(id)
	example_views[id] = true
	ensure_tick()
end

--- Untracks one example view, stopping Tick polling when none remain.
---@param id string View id passed to RegisterView.
local function untrack_example(id)
	example_views[id] = nil
	maybe_stop_tick()
end

--- Applies one drained PollEvents envelope to the binding mirrors.<br>
--- Calls each binding's on_change(new_value, old_value) on real changes,
--- then runs any button_routes[id] handlers for button/menu events.
---@param res table UI.call envelope payload ({ ok, result }).
local function sync_bindings(res)
	if not (res and res.ok) then return end
	local events = res.result
	if type(events) ~= "table" then return end
	for _, e in ipairs(events) do
		if type(e) == "table" then
			if e.key then
				local b = bindings[e.key]
				-- checkbox/selectable/combo/listbox/radio/flags all carry key + value
				if b and e.value ~= nil and not bindings_equal(b.value, e.value) then
					local old = b.value
					b.value = e.value
					if b.on_change then
						-- TODO/CONS: pcall?
						b.on_change(e.value, old)
					end
				end
			end
			-- Button/SmallButton/ArrowButton/InvisibleButton/ColorButton emit
			-- { type = "button", id }; MenuItem emits { type = "menu", id }.
			if (e.type == "button" or e.type == "menu") and e.id then
				local route = button_routes[e.id]
				if route then
					-- TODO/CONS: pcall?
					route(e)
				end
			end
		end
	end
end

--- Collects every JS storage key backing the bindings.<br>
--- Normal bindings contribute their own key; color bindings contribute
--- their key_r/_g/_b(/_a) sub-keys.
---@return string[] keys
local function collect_poll_keys()
	local keys = {}
	for k, b in next, bindings do
		if b.subkeys then
			for _, sk in ipairs(b.subkeys) do keys[#keys + 1] = sk end
		else
			keys[#keys + 1] = k
		end
	end
	return keys
end

--- Diffs one GetMany result map into the mirrors (polled UI -> Lua path).<br>
--- Covers sliders, drags, inputs and colors, which never emit PollEvents.
---@param map table Key-value map from getMany (missing keys read as nil and are skipped).
local function sync_polled(map)
	if type(map) ~= "table" then return end
	for k, b in next, bindings do
		if b.subkeys then
			local agg = {}
			local complete = true
			for i, sk in ipairs(b.subkeys) do
				local v = map[sk]
				if v == nil then
					complete = false
					break
				end
				agg[i] = v
			end
			if complete and not bindings_equal(b.value, agg) then
				local old = b.value
				b.value = agg
				if b.on_change then
					-- TODO/CONS: pcall?
					b.on_change(bindings_copy(agg), old)
				end
			end
		else
			local v = map[k]
			if v ~= nil and not bindings_equal(b.value, v) then
				local old = b.value
				b.value = bindings_copy(v)
				if b.on_change then
					-- TODO/CONS: pcall?
					b.on_change(bindings_copy(v), old)
				end
			end
		end
	end
end

--- Routes a UI press to a Lua handler via the shared Tick poller.<br>
--- Covers Button, SmallButton, ArrowButton, InvisibleButton and ColorButton
--- ({ type = "button", id }) as well as MenuItem ({ type = "menu", id }).<br>
--- Buttons are momentary (no value to mirror), so this replaces Bind for them.
---@param button_id string Exact widget label (the emitted event id).
---@param handler function Called as handler(event) on each press.
---@usage <br>
--- ```
--- ImGui.OnButton("Enable from Lua", function() ImGui.SetBound("bind_flag", true) end)
--- ImGui.OnButton("New", function(e) print("menu/button pressed:", e.id, e.type) end)
--- ```
function ImGui.OnButton(button_id, handler)
	button_routes[button_id] = handler
	ensure_tick()
end

--- Removes one button route registered via OnButton.
---@param button_id string Exact Button label.
function ImGui.OffButton(button_id)
	button_routes[button_id] = nil
	maybe_stop_tick()
end

--- Binds a single-key widget to a Lua mirror with two-way sync.<br>
--- Works for checkbox, SelectableState, combo, listbox, RadioButtonInt,
--- CheckboxFlags (via immediate PollEvents) AND sliders, drags, text/number
--- inputs, VSlider, SliderAngle, InputDouble (via throttled GetMany poll).<br>
--- Do NOT use for colors (split-key storage: use BindColor), buttons/menus
--- (momentary: use OnButton) or text labels (display-only).<br>
--- Lua -> UI: use SetBound (or the BindState proxy) to push.<br>
--- UI -> Lua: the shared Tick poller updates the mirror and fires on_change.
---@param key string State key used by the widget (e.g. "bind_flag").
---@param initial boolean|number|string|table Initial value, pushed via Set immediately.
---@param on_change? function Called as on_change(new_value, old_value) when the UI changes the value.
---@return table handle { key = string, get = function, set = function }.
---@usage <br>
--- ```
--- local god = ImGui.Bind("bind_godmode", false, function(new) print("godmode:", new) end)
--- god.set(true)  -- Lua -> UI: checkbox ticks on next frame
--- print(god.get()) -- Lua mirror (also updated when the user clicks)
---
--- local speed = ImGui.Bind("bind_speed", 3.5, function(new) print("speed:", new) end)
--- -- drag the SliderFloat -> mirror updates within ~POLL_EVERY ticks
--- ```
function ImGui.Bind(key, initial, on_change)
	bindings[key] = { value = initial, on_change = on_change }
	ImGui.Set(key, initial)
	ensure_tick()
	return {
		key = key,
		get = function()
			local b = bindings[key]
			return b and b.value
		end,
		set = function(v)
			return ImGui.SetBound(key, v)
		end,
	}
end

--- Pushes a new value for a bound key (Lua -> UI) and updates the mirror.<br>
--- Falls back to a plain Set when the key was never bound.<br>
--- Color base keys (bound via BindColor) accept an { r, g, b[, a] } array here.
---@param key string State key passed to Bind (or color base key from BindColor).
---@param value boolean|number|string|table Value to store (arrays must hold numbers only).
---@param callback? function Optional Set/SetMany callback (function(success, res)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- ImGui.SetBound("bind_godmode", true) -- checkbox ticks, on_change NOT fired (local echo suppressed)
--- ImGui.SetBound("bind_tint", { 1, 0, 0 }) -- ColorEdit3 turns red
--- ```
function ImGui.SetBound(key, value, callback)
	local b = bindings[key]
	if b then
		if b.subkeys then
			return ImGui.SetBoundColor(key, value, callback)
		end
		b.value = bindings_copy(value)
	end
	return ImGui.Set(key, value, callback)
end

--- Binds a color editor/picker (split-key storage key_r/_g/_b/_a) to a Lua array.<br>
--- Covers ColorEdit3/4 and ColorPicker3/4, which never emit PollEvents.
---@param key string Base key used by the widget (e.g. "bind_tint").
---@param initial table { r, g, b } or { r, g, b, a } floats in 0..1, pushed via SetMany immediately.
---@param on_change? function Called as on_change(new_rgb, old_rgb) when the UI changes the color.
---@return table handle { key = string, get = function, set = function }.
---@usage <br>
--- ```
--- local tint = ImGui.BindColor("bind_tint", { 0.45, 0.55, 0.60 }, function(new)
---   print("tint:", new[1], new[2], new[3])
--- end)
--- tint.set({ 1, 0, 0 }) -- Lua -> UI: picker turns red
--- ```
function ImGui.BindColor(key, initial, on_change)
	local suffix = { "_r", "_g", "_b", "_a" }
	local n = #initial
	assert(n == 3 or n == 4, "BindColor: initial must be { r, g, b } or { r, g, b, a }")
	local subkeys = {}
	local seed = {}
	for i = 1, n do
		subkeys[i] = key .. suffix[i]
		seed[subkeys[i]] = initial[i]
	end
	bindings[key] = { value = bindings_copy(initial), on_change = on_change, subkeys = subkeys }
	ImGui.SetMany(seed)
	ensure_tick()
	return {
		key = key,
		get = function()
			local b = bindings[key]
			return b and bindings_copy(b.value)
		end,
		set = function(v)
			return ImGui.SetBoundColor(key, v)
		end,
	}
end

--- Pushes a new { r, g, b[, a] } value for a BindColor key (Lua -> UI).
---@param key string Base key passed to BindColor.
---@param rgb table { r, g, b } or { r, g, b, a } floats in 0..1.
---@param callback? function Optional SetMany callback (function(success, res)).
---@return integer req_id The request ID for tracking.
function ImGui.SetBoundColor(key, rgb, callback)
	local b = bindings[key]
	if b and b.subkeys then
		local copy = {}
		for i = 1, #b.subkeys do copy[i] = rgb[i] end
		b.value = copy
		local seed = {}
		for i, sk in ipairs(b.subkeys) do seed[sk] = rgb[i] end
		return ImGui.SetMany(seed, callback)
	end
	return nil
end

--- Reads the Lua mirror for a bound key (no round-trip).<br>
--- This is the value to treat as truth in game logic.<br>
--- Table (array) mirrors are returned as copies: mutate via SetBound, not in place.
---@param key string State key passed to Bind (or base key from BindColor).
---@param fallback? any Returned when the key was never bound.
---@return any value The Lua mirror (or fallback).
---@usage <br>
--- ```
--- if ImGui.GetBound("bind_godmode", false) then print("godmode ON") end
--- local tint = ImGui.GetBound("bind_tint") -- { r, g, b } copy
--- ```
function ImGui.GetBound(key, fallback)
	local b = bindings[key]
	if b then return bindings_copy(b.value) end
	return fallback
end

--- Reports whether a key currently has a Lua binding.
---@param key string State key.
---@return boolean bound True when Bind was called and Unbind was not.
function ImGui.IsBound(key)
	return bindings[key] ~= nil
end

--- Removes one binding (mirror only; the JS-side value is left as-is).
---@param key string State key passed to Bind.
function ImGui.Unbind(key)
	bindings[key] = nil
	maybe_stop_tick()
end

--- Removes all bindings (mirrors only).
function ImGui.UnbindAll()
	for k, _ in next, bindings do
		bindings[k] = nil
	end
	maybe_stop_tick()
end

--- Binds a whole table of single-key widgets and returns a proxy where assignment syncs.<br>
--- Reading proxy.key returns the Lua mirror; writing proxy.key = v pushes via SetBound.<br>
--- This is the closest to "whenever we change Lua boolean value, it syncs to UI".<br>
--- Note: color base keys need BindColor first; afterwards proxy.key = { r, g, b } works.
---@param initial table Map of state keys to initial values (e.g. { bind_flag = true }).
---@param on_change? function Called as on_change(key, new_value, old_value) for UI-driven changes.
---@return table proxy Proxy table with __index/__newindex wired to the bindings.
---@usage <br>
--- ```
--- local state = ImGui.BindState({ bind_flag = false }, function(k, new) print(k, new) end)
--- state.bind_flag = true -- Lua -> UI: checkbox ticks on next frame, no manual Set needed
--- if state.bind_flag then print("ON") end -- reads the Lua mirror
--- ```
function ImGui.BindState(initial, on_change)
	for k, v in next, initial or {} do
		bindings[k] = {
			value = v,
			on_change = on_change and function(new_value, old_value)
				on_change(k, new_value, old_value)
			end or nil,
		}
		ImGui.Set(k, v)
	end
	ensure_tick()
	local proxy = {}
	setmetatable(proxy, {
		__index = function(_, k)
			local b = bindings[k]
			if b then return bindings_copy(b.value) end
			return nil
		end,
		__newindex = function(_, k, v)
			ImGui.SetBound(k, v)
		end,
	})
	return proxy
end

----------------------------------------------------------------------
-- Examples
----------------------------------------------------------------------

--- Shows the Lua example window, proving Lua-to-JS interop.<br>
--- Hides the built-in demo, registers the "lua_example" view, seeds a
--- value, and starts polling interaction events every tick (see ExampleTick).
---@usage <br>
--- ```
--- ImGui.Example() -- a "Lua Example" window appears; click its button and watch the console
--- ```
function ImGui.Example()
	ImGui.SetShowDemo(false)
	ImGui.RegisterView("lua_example", [==[
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
	]==])
	ImGui.Set("ex_speed", 7.5)
	track_example("lua_example")
end

--- Hides the Lua example window and restores the built-in demo.
function ImGui.HideExample()
	ImGui.UnregisterView("lua_example")
	untrack_example("lua_example")
	if next(example_views) == nil then
		ImGui.SetShowDemo(true)
	end
end

--- Shows buttons, checkboxes, radios, flags, selectables, trees.<br>
--- Covers Button/SmallButton/ArrowButton, Checkbox/CheckboxFlags,
--- RadioButtonInt, SelectableState, TreeNode, CollapsingHeader, Bullets.
---@usage <br>
--- ```
--- ImGui.ExampleBasic() -- "Lua Basic" window with buttons, radios, selectables
--- ```
function ImGui.ExampleBasic()
	ImGui.SetShowDemo(false)
	ImGui.RegisterView("lua_basic", [==[
		ImGui.Begin("Lua Basic");
		ImGui.Text("Buttons, checkboxes, radios, selectables");
		ImGui.Separator();
		if (ImGui.Button("Click Me!")) console.log("basic: Click Me!");
		ImGui.SameLine();
		if (ImGui.SmallButton("Small")) console.log("basic: Small");
		ImGui.SameLine();
		ImGui.ArrowButton("bx_arrow", ImGui.Dir.Right);
		if (ImGui.IsItemHovered()) ImGui.SetTooltip("ArrowButton tooltip");
		ImGui.SeparatorText("Checkboxes");
		ImGui.Checkbox("Enable feature", "bx_enable", true);
		ImGui.Checkbox("Show details", "bx_details", false);
		ImGui.CheckboxFlags("Flag A (1)", "bx_flags", 1, 0);
		ImGui.CheckboxFlags("Flag B (2)", "bx_flags", 2, 0);
		ImGui.CheckboxFlags("Flag C (4)", "bx_flags", 4, 0);
		ImGui.SeparatorText("Radios");
		ImGui.RadioButtonInt("Mode 0", "bx_mode", 0, 0);
		ImGui.SameLine();
		ImGui.RadioButtonInt("Mode 1", "bx_mode", 1, 0);
		ImGui.SameLine();
		ImGui.RadioButtonInt("Mode 2", "bx_mode", 2, 0);
		ImGui.SeparatorText("Selectable");
		const fruits = ["Apple", "Banana", "Cherry"];
		for (let i = 0; i < fruits.length; i++) {
			ImGui.PushID("bx_sel" + i);
			const st = ImGui.SelectableState(fruits[i], "bx_selfruit" + i, 0, 0, 0, i === 0);
			if (st.clicked) console.log("basic selectable:", fruits[i], st.value);
			ImGui.PopID();
		}
		ImGui.SeparatorText("Tree");
		if (ImGui.TreeNode("Advanced Options")) {
			ImGui.BulletText("Option 1");
			ImGui.BulletText("Option 2");
			ImGui.TreePop();
		}
		if (ImGui.CollapsingHeader("Collapsible section", 0)) {
			ImGui.TextWrapped("Wrapped text inside a collapsing header.");
			ImGui.Indent();
			ImGui.TextDisabled("indented note");
			ImGui.Unindent();
		}
		ImGui.End();
	]==])
	ImGui.SetMany({ bx_enable = true, bx_details = false, bx_flags = 0, bx_mode = 0 })
	track_example("lua_basic")
end

--- Hides the "Lua Basic" example window.
function ImGui.HideExampleBasic()
	ImGui.UnregisterView("lua_basic")
	untrack_example("lua_basic")
end

--- Shows sliders, drags, vertical slider and progress bar.<br>
--- Covers SliderFloat/Int, SliderFloat2/3/4, SliderInt2, SliderAngle,
--- VSliderFloat, DragFloat/Int, DragFloat2/3/4, DragInt2, DragFloatRange2.
---@usage <br>
--- ```
--- ImGui.ExampleSliders() -- "Lua Sliders/Drags" window
--- ImGui.Snapshot(function(ok, res) print(res.result.float.sl_speed) end)
--- ```
function ImGui.ExampleSliders()
	ImGui.SetShowDemo(false)
	ImGui.RegisterView("lua_sliders", [==[
		ImGui.Begin("Lua Sliders/Drags");
		ImGui.SeparatorText("Sliders");
		ImGui.SliderFloat("Speed", "sl_speed", 0.0, 10.0, "%.2f", 0, 3.5);
		ImGui.SliderInt("Count", "sl_count", 0, 100, "%d", 0, 42);
		ImGui.SliderFloat2("Offset XY", "sl_off2", -1.0, 1.0, "%.3f", 0, [0.2, -0.4]);
		ImGui.SliderFloat3("Rotation", "sl_rot3", -180.0, 180.0, "%.1f", 0, [0, 90, 180]);
		ImGui.SliderFloat4("RGBA weights", "sl_w4", 0.0, 1.0, "%.2f", 0, [1, 0.5, 0.25, 1]);
		ImGui.SliderInt2("Grid", "sl_grid", 1, 16, "%d", 0, [4, 4]);
		ImGui.SliderAngle("Angle", "sl_angle", -360, 360, "%.0f deg", 0, 45.0);
		const v = ImGui.VSliderFloat("##sl_v", "sl_v", 24, 80, 0.0, 1.0, "%.2f", 0, 0.65);
		ImGui.SameLine();
		ImGui.ProgressBar(v.value, 0, 0, v.value.toFixed(2));
		ImGui.SeparatorText("Drags");
		ImGui.DragFloat("Throttle", "sl_thr", 0.01, 0, 1, "%.3f", 0, 0.5);
		ImGui.DragInt("Lives", "sl_lives", 1, 0, 9, "%d", 0, 3);
		ImGui.DragFloat2("Position", "sl_pos2", 0.05, -10, 10, "%.2f", 0, [1.0, 2.0]);
		ImGui.DragFloat3("Scale", "sl_scl3", 0.02, 0.1, 5, "%.2f", 0, [1, 1, 1]);
		ImGui.DragFloat4("Bounds", "sl_bnd4", 0.1, 0, 100, "%.1f", 0, [0, 0, 64, 64]);
		ImGui.DragInt2("Tile", "sl_tile", 1, 0, 32, "%d", 0, [5, 7]);
		ImGui.DragFloatRange2("Range", "sl_rmin", "sl_rmax", 0.01, 0, 1, "%.2f", "", 0, 0.25, 0.75);
		ImGui.End();
	]==])
	ImGui.SetMany({ sl_speed = 3.5, sl_count = 42, sl_v = 0.65, sl_thr = 0.5, sl_lives = 3 })
	track_example("lua_sliders")
end

--- Hides the "Lua Sliders/Drags" example window.
function ImGui.HideExampleSliders()
	ImGui.UnregisterView("lua_sliders")
	untrack_example("lua_sliders")
end

--- Shows color editors, pickers and swatch buttons.<br>
--- Covers ColorEdit3/4, ColorPicker3/4 and ColorButton.
---@usage <br>
--- ```
--- ImGui.ExampleColors() -- "Lua Colors" window with editors, pickers, swatches
--- ```
function ImGui.ExampleColors()
	ImGui.SetShowDemo(false)
	ImGui.RegisterView("lua_colors", [==[
		ImGui.Begin("Lua Colors");
		ImGui.SeparatorText("Editors");
		ImGui.ColorEdit3("Base", "co_base", 0, [0.45, 0.55, 0.60]);
		ImGui.ColorEdit4("Tint", "co_tint", 0, [0.45, 0.55, 0.60, 1.0]);
		ImGui.SeparatorText("Pickers");
		ImGui.ColorPicker3("Picker", "co_pick3", 0, [0.45, 0.55, 0.60]);
		ImGui.ColorPicker4("Picker+A", "co_pick4", ImGui.ColorEditFlags.AlphaBar, [0.8, 0.3, 0.2, 1.0]);
		ImGui.SeparatorText("Swatches");
		if (ImGui.ColorButton("co_sw1", [0.9, 0.2, 0.2, 1.0], 0, 0, 0)) console.log("colors: red swatch");
		ImGui.SameLine();
		if (ImGui.ColorButton("co_sw2", [0.2, 0.8, 0.3, 1.0], 0, 0, 0)) console.log("colors: green swatch");
		ImGui.SameLine();
		if (ImGui.ColorButton("co_sw3", [0.25, 0.5, 0.95, 1.0], 0, 0, 0)) console.log("colors: blue swatch");
		ImGui.SameLine();
		ImGui.TextDisabled("click a swatch");
		ImGui.End();
	]==])
	track_example("lua_colors")
end

--- Hides the "Lua Colors" example window.
function ImGui.HideExampleColors()
	ImGui.UnregisterView("lua_colors")
	untrack_example("lua_colors")
end

--- Shows combos, list boxes and a bordered table.<br>
--- Covers Combo, ListBox, BeginTable/TableSetupColumn/TableHeadersRow/
--- TableNextRow/TableSetColumnIndex/Text/EndTable.
---@usage <br>
--- ```
--- ImGui.ExampleLists() -- pick a fruit, the LabelText mirrors the polled index
--- ImGui.PollEvents(function(ok, res) print(NanosTable.Dump(res)) end)
--- ```
function ImGui.ExampleLists()
	ImGui.SetShowDemo(false)
	ImGui.RegisterView("lua_lists", [==[
		ImGui.Begin("Lua Lists/Tables");
		const fruits = ["Apple", "Banana", "Cherry", "Orange", "Mango", "Papaya"];
		ImGui.SeparatorText("Combo");
		const cb = ImGui.Combo("Fruit", "li_fruit", fruits, -1, 0, 0);
		ImGui.LabelText("Picked", fruits[cb.value] + " (#" + cb.value + ")");
		ImGui.SeparatorText("ListBox");
		const lb = ImGui.ListBox("Fruits", "li_fruitlb", fruits, 4, 2);
		ImGui.LabelText("Row", fruits[lb.value] + " (#" + lb.value + ")");
		ImGui.SeparatorText("Table");
		if (ImGui.BeginTable("li_table", 3, ImGui.TableFlags.Borders | ImGui.TableFlags.RowBg, 0, 0, 0)) {
			ImGui.TableSetupColumn("Name", 0, 0, 0);
			ImGui.TableSetupColumn("Role", 0, 0, 0);
			ImGui.TableSetupColumn("Lvl", 0, 0, 0);
			ImGui.TableHeadersRow();
			const rows = [["Alice", "Mage", "12"], ["Bob", "Warrior", "9"], ["Cid", "Ranger", "15"]];
			for (let r = 0; r < rows.length; r++) {
				ImGui.TableNextRow(0, 0);
				for (let c = 0; c < 3; c++) { ImGui.TableSetColumnIndex(c); ImGui.Text(rows[r][c]); }
			}
			ImGui.EndTable();
		}
		ImGui.End();
	]==])
	ImGui.SetMany({ li_fruit = 0, li_fruitlb = 2 })
	track_example("lua_lists")
end

--- Hides the "Lua Lists/Tables" example window.
function ImGui.HideExampleLists()
	ImGui.UnregisterView("lua_lists")
	untrack_example("lua_lists")
end

--- Shows text/number inputs, progress bars and plots.<br>
--- Covers InputText/WithHint/Multiline, InputFloat/Int (+N variants),
--- InputDouble, ProgressBar, PlotLines, PlotHistogram.
---@usage <br>
--- ```
--- ImGui.ExampleInputs() -- type a name, watch it via Snapshot("in_name")
--- ImGui.Get("in_name", function(ok, res) print(res.value) end)
--- ```
function ImGui.ExampleInputs()
	ImGui.SetShowDemo(false)
	ImGui.RegisterView("lua_inputs", [==[
		ImGui.Begin("Lua Inputs/Plots");
		ImGui.SeparatorText("Text");
		ImGui.InputText("Name", "in_name", 0, "Ada");
		ImGui.InputTextWithHint("Search", "type to filter...", "in_search", 0, "");
		ImGui.InputTextMultiline("Notes", "in_notes", 0, 60, 0, "line1\nline2");
		ImGui.SeparatorText("Numbers");
		ImGui.InputFloat("Gravity", "in_grav", 0.1, 1.0, "%.2f", 0, 9.81);
		ImGui.InputInt("Ammo", "in_ammo", 1, 10, 0, 30);
		ImGui.InputFloat2("UV", "in_uv", "%.3f", 0, [0.0, 1.0]);
		ImGui.InputFloat3("Spawn", "in_spawn", "%.1f", 0, [10.0, 0.0, 5.0]);
		ImGui.InputFloat4("Rect", "in_rect", "%.1f", 0, [0, 0, 128, 64]);
		ImGui.InputInt2("Cell", "in_cell", 0, [3, 7]);
		ImGui.InputInt3("RGB int", "in_rgbint", 0, [255, 128, 0]);
		ImGui.InputDouble("Pi", "in_pi", 0.01, 0.1, "%.6f", 0, 3.141593);
		ImGui.SeparatorText("Plots");
		ImGui.ProgressBar(0.65, 0, 0, "65%");
		ImGui.PlotLines("Signal", [0.1, 0.4, 0.2, 0.8, 0.5, 0.9, 0.3, 0.6], "avg", 0, 1, 0, 55);
		ImGui.PlotHistogram("Levels", [1, 3, 2, 5, 4, 6, 3, 2], "", 0, 6, 0, 55);
		ImGui.End();
	]==])
	ImGui.SetMany({ in_name = "Ada", in_grav = 9.81, in_ammo = 30 })
	track_example("lua_inputs")
end

--- Hides the "Lua Inputs/Plots" example window.
function ImGui.HideExampleInputs()
	ImGui.UnregisterView("lua_inputs")
	untrack_example("lua_inputs")
end

--- Shows layout helpers: tooltips, disabled state, child, popup, columns.<br>
--- Covers BeginDisabled/EndDisabled, IsItemHovered, SetTooltip/SetItemTooltip,
--- BeginChild/EndChild, OpenPopup/BeginPopup/EndPopup, Dummy, SameLine,
--- SetNextItemWidth, GetContentRegionAvailWidth, Columns/NextColumn.
---@usage <br>
--- ```
--- ImGui.ExampleLayout() -- hover the buttons to see tooltips, open the popup
--- ```
function ImGui.ExampleLayout()
	ImGui.SetShowDemo(false)
	ImGui.RegisterView("lua_layout", [==[
		ImGui.Begin("Lua Panels");
		ImGui.SeparatorText("Disabled + tooltip");
		ImGui.BeginDisabled(true);
		ImGui.Button("Disabled button");
		ImGui.EndDisabled();
		ImGui.Button("Hover me");
		if (ImGui.IsItemHovered()) ImGui.SetTooltip("Tooltip via IsItemHovered + SetTooltip");
		ImGui.SameLine();
		ImGui.Button("Hover me 2");
		ImGui.SetItemTooltip("Tooltip via SetItemTooltip");
		ImGui.SeparatorText("Child window");
		if (ImGui.BeginChild("lo_child", 0, 90, true, 0)) {
			ImGui.Text("Child region content");
			ImGui.Dummy(0, 4);
			if (ImGui.SmallButton("Child action")) console.log("layout: child action");
		}
		ImGui.EndChild();
		ImGui.SeparatorText("Popup");
		if (ImGui.Button("Open popup")) ImGui.OpenPopup("lo_popup", 0);
		if (ImGui.BeginPopup("lo_popup", 0)) {
			ImGui.Text("Popup content here");
			ImGui.Checkbox("Popup option", "lo_popopt", true);
			ImGui.EndPopup();
		}
		ImGui.SeparatorText("Width");
		ImGui.Text("Avail width: " + ImGui.GetContentRegionAvailWidth().toFixed(1));
		ImGui.SetNextItemWidth(180);
		ImGui.SliderFloat("Narrow slider", "lo_narrow", 0, 1, "%.2f", 0, 0.3);
		ImGui.SeparatorText("Columns");
		ImGui.Columns(2, "lo_cols", true);
		ImGui.Text("Column 1");
		ImGui.NextColumn();
		ImGui.Text("Column 2");
		ImGui.NextColumn();
		ImGui.Columns(1);
		ImGui.End();
	]==])
	ImGui.Set("lo_narrow", 0.3)
	track_example("lua_layout")
end

--- Hides the "Lua Panels" example window.
function ImGui.HideExampleLayout()
	ImGui.UnregisterView("lua_layout")
	untrack_example("lua_layout")
end

--- Shows a menu bar plus a reorderable tab bar.<br>
--- Covers Begin (with MenuBar flag), BeginMenuBar/BeginMenu/MenuItem/EndMenu/
--- EndMenuBar, BeginTabBar/BeginTabItem/EndTabItem/EndTabBar.
---@usage <br>
--- ```
--- ImGui.ExampleTabs() -- File/Edit menus log to console, Tab 2 owns a checkbox
--- ```
function ImGui.ExampleTabs()
	ImGui.SetShowDemo(false)
	ImGui.RegisterView("lua_tabs", [==[
		ImGui.Begin("Lua Tabs/Menu", null, ImGui.WindowFlags.MenuBar);
		if (ImGui.BeginMenuBar()) {
			if (ImGui.BeginMenu("File")) {
				if (ImGui.MenuItem("New")) console.log("tabs: New");
				if (ImGui.MenuItem("Open")) console.log("tabs: Open");
				ImGui.Separator();
				if (ImGui.MenuItem("Exit")) console.log("tabs: Exit");
				ImGui.EndMenu();
			}
			if (ImGui.BeginMenu("Edit")) {
				if (ImGui.MenuItem("Undo")) console.log("tabs: Undo");
				if (ImGui.MenuItem("Redo")) console.log("tabs: Redo");
				ImGui.EndMenu();
			}
			ImGui.EndMenuBar();
		}
		if (ImGui.BeginTabBar("lua_tabbar", ImGui.TabBarFlags.Reorderable)) {
			if (ImGui.BeginTabItem("Tab 1", null, 0)) {
				ImGui.Text("Content of Tab 1");
				if (ImGui.Button("Tab 1 Button")) console.log("tabs: tab1 button");
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("Tab 2", null, 0)) {
				ImGui.Text("Content of Tab 2");
				ImGui.Checkbox("Tab 2 Checkbox", "ta_check", false);
				ImGui.EndTabItem();
			}
			ImGui.EndTabBar();
		}
		ImGui.End();
	]==])
	track_example("lua_tabs")
end

--- Hides the "Lua Tabs/Menu" example window.
function ImGui.HideExampleTabs()
	ImGui.UnregisterView("lua_tabs")
	untrack_example("lua_tabs")
end

--- Shows a minimal always-on-top style HUD with FPS and progress.<br>
--- Demonstrates SetNextWindowPos/SetNextWindowSize with Cond.FirstUseEver,
--- Text, Separator, ProgressBar and LabelText without extra state keys.
---@usage <br>
--- ```
--- ImGui.ExampleHUD() -- small "Lua HUD" window, no Tick spam beyond PollEvents
--- ```
function ImGui.ExampleHUD()
	ImGui.SetShowDemo(false)
	ImGui.RegisterView("lua_hud", [==[
		ImGui.SetNextWindowPos(10, 10, ImGui.Cond.FirstUseEver);
		ImGui.SetNextWindowSize(280, 130, ImGui.Cond.FirstUseEver);
		ImGui.Begin("Lua HUD");
		ImGui.LabelText("FPS", fps.toFixed(1));
		ImGui.Separator();
		ImGui.Text("Hello from Lua HUD!");
		const t = (Date.now() % 2000) / 2000;
		ImGui.ProgressBar(t, 0, 0, (t * 100).toFixed(0) + "%");
		if (ImGui.SmallButton("Ping console")) console.log("hud: ping fps=" + fps.toFixed(1));
		ImGui.End();
	]==])
	track_example("lua_hud")
end

--- Hides the "Lua HUD" example window.
function ImGui.HideExampleHUD()
	ImGui.UnregisterView("lua_hud")
	untrack_example("lua_hud")
end

--- Shows two-way bindings across every stateful widget family.<br>
--- Immediate path (PollEvents, same Tick): checkboxes, SelectableState, combo,
--- listbox, RadioButtonInt, CheckboxFlags.<br>
--- Polled path (GetMany every POLL_EVERY Ticks): sliders, drags, text/number
--- inputs, color editors/pickers, which never emit events.<br>
--- The Lua-side buttons prove the Lua -> UI direction without touching the widgets.
---@usage <br>
--- ```
--- ImGui.ExampleBinding()
--- -- click/drag/type/pick -> console prints "[Bind] <key> changed to ..."
--- -- or drive it from Lua:
--- ImGui.SetBound("bind_flag", true) -- checkbox ticks on next frame
--- ImGui.SetBound("bind_fruit", 2) -- combo jumps to Cherry on next frame
--- ImGui.SetBound("bind_fruitlb", 0) -- listbox jumps to Apple on next frame
--- ImGui.SetBound("bind_mode", 1) -- radio group switches on next frame
--- ImGui.SetBound("bind_flags", 3) -- flags A+B tick on next frame
--- ImGui.SetBound("bind_sel", true) -- selectable highlights on next frame
--- ImGui.SetBound("bind_speed", 9.0) -- slider jumps on next frame
--- ImGui.SetBound("bind_name", "Ada") -- text field updates on next frame
--- ImGui.SetBound("bind_tint", { 1, 0, 0 }) -- picker turns red (BindColor key)
--- print(ImGui.GetBound("bind_flag")) -- Lua mirror, the value game logic should read
---
--- -- reactive table form (plain assignment auto-pushes):
--- -- local state = ImGui.BindState({ bind_flag = false })
--- -- state.bind_flag = true -- same as SetBound, checkbox ticks
--- ```
function ImGui.ExampleBinding()
	ImGui.SetShowDemo(false)
	-- One bound key per widget family. Event widgets report same-Tick,
	-- silent widgets report via the throttled poll; both land in on_change.
	local function bp(key, initial)
		return ImGui.Bind(key, initial, function(new_value, _old)
			if type(new_value) == "table" then
				local parts = {}
				for i, v in ipairs(new_value) do parts[i] = tostring(v) end
				print(string.format("[Bind] %s changed to {%s}", key, table.concat(parts, ", ")))
			else
				print(string.format("[Bind] %s changed to %s", key, tostring(new_value)))
			end
		end)
	end
	-- Checkboxes (bool, event)
	bp("bind_flag", false)
	bp("bind_details", true)
	-- Lists / choice (int/bool, event)
	bp("bind_fruit", 0) -- Combo index
	bp("bind_fruitlb", 2) -- ListBox index
	bp("bind_mode", 0)  -- RadioButtonInt group value
	bp("bind_flags", 0) -- CheckboxFlags bitmask (A=1+B=2+C=4)
	bp("bind_sel", true) -- SelectableState selected
	-- Numbers (float/int/array, polled)
	bp("bind_speed", 3.5) -- SliderFloat
	bp("bind_count", 42) -- SliderInt
	bp("bind_thr", 0.5) -- DragFloat
	bp("bind_grav", 9.81) -- InputFloat
	bp("bind_ammo", 30) -- InputInt
	bp("bind_name", "Ada") -- InputText
	-- Color (split-key storage, polled)
	ImGui.BindColor("bind_tint", { 0.45, 0.55, 0.60 }, function(new_value, _old)
		print(string.format("[Bind] bind_tint changed to %.2f,%.2f,%.2f (polled)", new_value[1], new_value[2],
			new_value[3]))
	end)
	-- UI button -> Lua -> UI round-trip: proves the Lua -> UI direction live.
	-- Pressing the button emits a button event; the shared Tick poller routes
	-- it here, and SetBound pushes the checkbox state for the next frame.
	ImGui.OnButton("Enable from Lua", function()
		ImGui.SetBound("bind_flag", true)
		print("[Bind] forced ON from Lua (button round-trip)")
	end)
	ImGui.OnButton("Disable from Lua", function()
		ImGui.SetBound("bind_flag", false)
		print("[Bind] forced OFF from Lua (button round-trip)")
	end)
	ImGui.RegisterView("lua_binding", [==[
		ImGui.Begin("Lua Binding");
		ImGui.Text("Two-way: Lua <-> every stateful widget");
		ImGui.SeparatorText("Checks (event)");
		ImGui.Checkbox("Godmode", "bind_flag", false);
		ImGui.Checkbox("Show details", "bind_details", true);
		ImGui.CheckboxFlags("Flag A (1)", "bind_flags", 1, 0);
		ImGui.SameLine();
		ImGui.CheckboxFlags("Flag B (2)", "bind_flags", 2, 0);
		ImGui.SameLine();
		ImGui.CheckboxFlags("Flag C (4)", "bind_flags", 4, 0);
		ImGui.SeparatorText("Choice (event)");
		const fruits = ["Apple", "Banana", "Cherry", "Orange", "Mango", "Papaya"];
		ImGui.Combo("Fruit", "bind_fruit", fruits, -1, 0, 0);
		ImGui.ListBox("Fruits", "bind_fruitlb", fruits, 4, 2);
		ImGui.RadioButtonInt("Mode 0", "bind_mode", 0, 0);
		ImGui.SameLine();
		ImGui.RadioButtonInt("Mode 1", "bind_mode", 1, 0);
		ImGui.SameLine();
		ImGui.RadioButtonInt("Mode 2", "bind_mode", 2, 0);
		ImGui.SelectableState("Pinned item", "bind_sel", 0, 0, 0, true);
		ImGui.SeparatorText("Numbers (polled)");
		ImGui.SliderFloat("Speed", "bind_speed", 0.0, 10.0, "%.2f", 0, 3.5);
		ImGui.SliderInt("Count", "bind_count", 0, 100, "%d", 0, 42);
		ImGui.DragFloat("Throttle", "bind_thr", 0.01, 0, 1, "%.3f", 0, 0.5);
		ImGui.InputText("Name", "bind_name", 0, "Ada");
		ImGui.InputFloat("Gravity", "bind_grav", 0.1, 1.0, "%.2f", 0, 9.81);
		ImGui.InputInt("Ammo", "bind_ammo", 1, 10, 0, 30);
		ImGui.SeparatorText("Color (polled)");
		ImGui.ColorEdit3("Tint", "bind_tint", 0, [0.45, 0.55, 0.60]);
		// Live reads of the JS-side storage (mirror Lua after Set):
		ImGui.SeparatorText("Live storage");
		ImGui.Text("flag: " + (ImGui.GetBool("bind_flag", false) ? "ON" : "OFF"));
		ImGui.Text("fruit: " + UI.get("bind_fruit").value + " row: " + UI.get("bind_fruitlb").value);
		ImGui.Text("mode: " + UI.get("bind_mode").value + " flags: " + UI.get("bind_flags").value);
		ImGui.Text("speed: " + UI.get("bind_speed").value + " name: " + UI.get("bind_name").value);
		ImGui.SeparatorText("Drive from Lua");
		ImGui.Button("Enable from Lua");
		ImGui.SameLine();
		ImGui.Button("Disable from Lua");
		ImGui.SeparatorText("Mirror");
		ImGui.TextWrapped("Read ImGui.GetBound(key) in Lua - that is the truth for game logic.");
		ImGui.End();
	]==])
	track_example("lua_binding")
end

--- Hides the "Lua Binding" example window and removes its bindings.
function ImGui.HideExampleBinding()
	ImGui.UnregisterView("lua_binding")
	for _, k in next, { "bind_flag", "bind_details", "bind_fruit", "bind_fruitlb",
		"bind_mode", "bind_flags", "bind_sel", "bind_speed", "bind_count",
		"bind_thr", "bind_grav", "bind_ammo", "bind_name", "bind_tint" } do
		ImGui.Unbind(k)
	end
	ImGui.OffButton("Enable from Lua")
	ImGui.OffButton("Disable from Lua")
	untrack_example("lua_binding")
end

--- Shows dynamic labels and tooltips driven by string bindings.<br>
--- LabelText/Text/SetTooltip take static strings, so the view reads the live
--- storage (UI.get(key).value) while Lua pushes via Bind/SetBound on the same
--- keys. Typing in the inputs updates the labels and tooltips next frame.
---@usage <br>
--- ```
--- ImGui.ExampleLabels() -- type a name: LabelText + tooltip follow it
--- ImGui.SetBound("bind_title", "Cid") -- labels update without touching UI code
--- ```
function ImGui.ExampleLabels()
	ImGui.SetShowDemo(false)
	local function bs(key, initial)
		return ImGui.Bind(key, initial, function(new_value, _old)
			print(string.format("[Bind] %s changed to %s", key, tostring(new_value)))
		end)
	end
	bs("bind_title", "Ada")
	bs("bind_score", "1250 pts")
	bs("bind_tip", "Follow me anywhere!")
	ImGui.RegisterView("lua_labels", [==[
		ImGui.Begin("Lua Labels/Tooltips");
		ImGui.Text("Static text vs storage-backed labels");
		ImGui.SeparatorText("Labels mirror Lua strings");
		ImGui.LabelText("Name", String(UI.get("bind_title").value));
		ImGui.LabelText("Score", String(UI.get("bind_score").value));
		ImGui.Text("Hello, " + UI.get("bind_title").value + "!");
		ImGui.SeparatorText("Edit them (labels follow)");
		ImGui.InputText("Edit name", "bind_title", 0, "Ada");
		ImGui.InputText("Edit score", "bind_score", 0, "1250 pts");
		ImGui.InputText("Edit tip", "bind_tip", 0, "Follow me anywhere!");
		ImGui.SeparatorText("Dynamic tooltips");
		ImGui.Button("Hover me");
		if (ImGui.IsItemHovered()) ImGui.SetTooltip("Tip: " + UI.get("bind_tip").value);
		ImGui.SameLine();
		ImGui.Button("Hover me 2");
		ImGui.SetItemTooltip(String(UI.get("bind_title").value) + " scores " + UI.get("bind_score").value);
		ImGui.End();
	]==])
	track_example("lua_labels")
end

--- Hides the "Lua Labels/Tooltips" example window and removes its bindings.
function ImGui.HideExampleLabels()
	ImGui.UnregisterView("lua_labels")
	ImGui.Unbind("bind_title")
	ImGui.Unbind("bind_score")
	ImGui.Unbind("bind_tip")
	untrack_example("lua_labels")
end

--- Shows global theming plus a per-frame styled section.<br>
--- Preset buttons call SetTheme (one-shot, needs demo v1.2.0+; the uiVersion
--- is printed for diagnosis). The rounding slider drives SetStyleFloat live,
--- and the "Styled!" button is wrapped in ThemeSnippet (works everywhere).
---@usage <br>
--- ```
--- ImGui.ExampleTheme()
--- ImGui.SetTheme("light", { floats = { windowRounding = 8 } })
--- ```
function ImGui.ExampleTheme()
	ImGui.SetShowDemo(false)
	ImGui.Status(function(ok, res)
		if ok and res.ok then
			print(string.format("[Theme] demo uiVersion: %s", tostring(res.result.uiVersion)))
		end
	end)
	ImGui.Bind("bind_round", 6.0, function(new_value, _old)
		ImGui.SetStyleFloat("windowRounding", new_value)
	end)
	ImGui.OnButton("Theme: Dark", function() ImGui.SetTheme("dark") end)
	ImGui.OnButton("Theme: Light", function() ImGui.SetTheme("light") end)
	ImGui.OnButton("Theme: Classic", function() ImGui.SetTheme("classic") end)
	local styled = ImGui.ThemeSnippet({ Button = { 0.2, 0.6, 0.9, 1 }, ButtonHovered = { 0.3, 0.7, 1.0, 1 } }, [==[
		if (ImGui.Button("Styled!")) console.log("theme: styled button pressed");
	]==])
	ImGui.RegisterView("lua_theme", [==[
		ImGui.Begin("Lua Theme");
		ImGui.Text("Global presets (one-shot, v1.2.0+)");
		ImGui.Button("Theme: Dark");
		ImGui.SameLine();
		ImGui.Button("Theme: Light");
		ImGui.SameLine();
		ImGui.Button("Theme: Classic");
		ImGui.SeparatorText("Live style var");
		ImGui.SliderFloat("Window rounding", "bind_round", 0.0, 12.0, "%.1f", 0, 6.0);
		ImGui.SeparatorText("Per-frame snippet");
	]==] .. "\n" .. styled .. [==[
		ImGui.End();
	]==])
	track_example("lua_theme")
end

--- Hides the "Lua Theme" example window and removes its bindings.
function ImGui.HideExampleTheme()
	ImGui.UnregisterView("lua_theme")
	ImGui.Unbind("bind_round")
	ImGui.OffButton("Theme: Dark")
	ImGui.OffButton("Theme: Light")
	ImGui.OffButton("Theme: Classic")
	untrack_example("lua_theme")
end

--- Shows every Lua example window at once (hides the built-in demo).<br>
--- Convenience wrapper around Example/Basic/Sliders/Colors/Lists/Inputs/
--- Layout/Tabs/HUD/Binding/Labels/Theme. Pair with HideExamples when done.
---@usage <br>
--- ```
--- ImGui.ExampleAll()  -- opens the full Lua gallery
--- ImGui.HideExamples() -- closes everything, restores the demo
--- ```
function ImGui.ExampleAll()
	ImGui.Example()
	ImGui.ExampleBasic()
	ImGui.ExampleSliders()
	ImGui.ExampleColors()
	ImGui.ExampleLists()
	ImGui.ExampleInputs()
	ImGui.ExampleLayout()
	ImGui.ExampleTabs()
	ImGui.ExampleHUD()
	ImGui.ExampleBinding()
	ImGui.ExampleLabels()
	ImGui.ExampleTheme()
end

--- Hides every Lua example window and restores the built-in demo.<br>
--- Unregisters all tracked "lua_*" views, drops their bindings and button
--- routes, restores the demo, and stops Tick polling unless foreign (non-example)
--- bindings or routes still exist.
---@usage <br>
--- ```
--- ImGui.HideExamples() -- clean slate, demo windows return
--- ```
function ImGui.HideExamples()
	local had_binding = example_views["lua_binding"]
	local had_labels = example_views["lua_labels"]
	local had_theme = example_views["lua_theme"]
	for id, _ in next, example_views do
		ImGui.UnregisterView(id)
	end
	example_views = {}
	if had_binding then
		for _, k in next, { "bind_flag", "bind_details", "bind_fruit", "bind_fruitlb",
			"bind_mode", "bind_flags", "bind_sel", "bind_speed", "bind_count",
			"bind_thr", "bind_grav", "bind_ammo", "bind_name", "bind_tint" } do
			bindings[k] = nil
		end
		button_routes["Enable from Lua"] = nil
		button_routes["Disable from Lua"] = nil
	end
	if had_labels then
		bindings["bind_title"] = nil
		bindings["bind_score"] = nil
		bindings["bind_tip"] = nil
	end
	if had_theme then
		bindings["bind_round"] = nil
		button_routes["Theme: Dark"] = nil
		button_routes["Theme: Light"] = nil
		button_routes["Theme: Classic"] = nil
	end
	ImGui.SetShowDemo(true)
	maybe_stop_tick()
end

--- Shared Tick poller: drains PollEvents once, syncs bindings, then prints.<br>
--- Subscribed by examples and bindings (unsubscribed when none remain).<br>
--- UI -> Lua flows through sync_bindings (immediate events) plus a throttled
--- GetMany poll (sliders/drags/inputs/colors, which never emit events).<br>
--- Lua -> UI flows through Set/SetBound/SetBoundColor.
---@return integer req_id The request ID for tracking.
function ImGui.ExampleTick()
	tick_frame = tick_frame + 1
	local frame = tick_frame
	return ImGui.PollEvents(function(success, res)
		if success and res.ok then
			sync_bindings(res)
			if next(example_views) ~= nil then
				for _, e in ipairs(res.result) do
					print(string.format("[ImGui] event: %s %s", e.type, e.id or e.key or ""))
				end
			end
		end
		if next(bindings) ~= nil and frame % POLL_EVERY == 0 then
			local keys = collect_poll_keys()
			if #keys > 0 then
				ImGui.GetMany(keys, function(ok2, res2)
					if ok2 and res2.ok then
						sync_polled(res2.result)
					end
				end)
			end
		end
	end)
end

--- Alias kept for readability: bindings share the same single-drain Tick poller.
---@return integer req_id The request ID for tracking.
function ImGui.BindTick()
	return ImGui.ExampleTick()
end

_G.imgui = ImGui
_G.ImGui = ImGui -- alias: console is case-sensitive, accept both `imgui.*` and `ImGui.*`

do
	-- Console ergonomics: `imgui_init`, `imgui_demo`, `imgui_hide`, `imgui_status`.
	-- Guarded: ImGui.lua must stay loadable even when Bind/Console are unavailable.
	local Bind = require "Bind"
	local function must_init()
		if not initialized then ImGui.Initialize() end
	end
	Bind.RegisterCommand("imgui_init", function()
		must_init()
		print("[ImGui] initialized:", ImGui.IsInitialized(), "ready:", ImGui.IsReady())
	end, "Create ImGui overlay WebUI")
	Bind.RegisterCommand("imgui_demo", function()
		must_init()
		ImGui.ExampleAll()
	end, "Open full ImGui Lua gallery")
	Bind.RegisterCommand("imgui_hide", function()
		if initialized then ImGui.HideExamples() end
	end, "Close all ImGui Lua examples")
	Bind.RegisterCommand("imgui_status", function()
		if not initialized then
			print("[ImGui] not initialized")
			return
		end
		ImGui.Status(function(success, res)
			if success and res and res.ok then
				print(string.format("[ImGui] dom=%s wasm=%s demo=%s views=%d ui=%s",
					tostring(ImGui.IsReady()), tostring(ImGui.IsImGuiReady()),
					tostring(res.result.demo), #(res.result.views or {}),
					tostring(res.result.uiVersion)))
			else
				print("[ImGui] status failed")
			end
		end)
	end, "Print ImGui bridge status")
end

-- Export the API to be accessed by other packages
return ImGui
