-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Localized global functions for better performance
local table_insert = table.insert
local table_unpack = table.unpack

-- Eval API - bridged via WebUI
local EvalAPI = {}

--- Enqueue until ready
local send
do
	local EvalWebUI = WebUI(
		Package.GetName() .. ":eval.api",
		"file:///UI/EvalAPI.html",
		WidgetVisibility.Hidden, true, false, 0, 0
	)
	local pending = {} ---@type table<integer, function|nil>
	local queued = {} ---@type table<integer, {event:string, args:table, callback:function, req_id:integer}|nil>
	local req_id = math.mininteger or 0
	local is_ready = false

	-- Receive results from JS
	EvalWebUI:Subscribe("EvalResult", function(id, success, payload)
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
	---@param use_req_id integer|nil
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
		EvalWebUI:CallEvent(event, table_unpack(args))
		-- liftoff! 🚀
		return id
	end

	EvalWebUI:Subscribe("EvalReady", function()
		-- JS says DOM is ready
		if is_ready then return end -- safety check
		is_ready = true
		-- Flush the queue
		for i = 1, #queued do
			local q = queued[i]
			if q then
				dispatch(q.event, q.args, q.callback, q.req_id)
			end
		end
		queued = {}
	end)

	function send(event, args, callback)
		-- Dispatch immediately if ready
		if is_ready then
			return dispatch(event, args, callback)
		end
		-- Otherwise, enqueue the request until DOM is ready
		req_id = req_id + 1
		queued[#queued + 1] = { event = event, args = args, callback = callback, req_id = req_id }
		return req_id
	end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

--- Evaluates JavaScript code and returns the result.<br>
--- The code is executed in a sandboxed environment within the WebUI context.<br>
--- Returns the result of the evaluation, or an error message if execution fails.
---@param code string The JavaScript code to evaluate.
---@param callback function Callback function to receive the eval result (function(success, payload)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- EvalAPI.Eval("1 + 1", function(success, result)
---   if success then
---     print("Result:", result) -- 2
---   end
--- end)
---
--- EvalAPI.Eval("Math.sqrt(16)", function(success, result)
---   if success then
---     print("Result:", result) -- 4
---   end
--- end)
--- ```
function EvalAPI.Eval(code, callback)
	return send("DoEval", { code }, callback)
end

--- Evaluates JavaScript code with additional context variables.<br>
--- The provided context object will be available as variables in the evaluated code.
---@param code string The JavaScript code to evaluate.
---@param context table A table of key-value pairs to be available as variables in the JS context.
---@param callback function Callback function to receive the eval result (function(success, payload)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- EvalAPI.EvalWithContext("a + b", { a = 5, b = 10 }, function(success, result)
---   if success then
---     print("Result:", result) -- 15
---   end
--- end)
--- ```
function EvalAPI.EvalWithContext(code, context, callback)
	return send("DoEvalWithContext", { code, context }, callback)
end

-- Export the API to be accessed by other packages
return EvalAPI
