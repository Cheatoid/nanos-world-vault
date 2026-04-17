-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Localized global functions for better performance
local table_insert = table.insert
local table_unpack = table.unpack

-- WebSocket (client) API - bridged via WebUI
local WebSocketAPI = {}

--- Enqueue until ready
local send
do
	local WebSocketWebUI = WebUI(
		Package.GetName() .. ":websocket.api",
		"file:///UI/WebSocketAPI.html",
		WidgetVisibility.Hidden, true, false, 0, 0
	)
	local pending = {} ---@type table<integer, function|nil>
	local queued = {} ---@type table<integer, {event:string, args:table, callback:function, req_id:integer}|nil>
	local req_id = math.mininteger or 0
	local is_ready = false

	-- Receive results from JS
	WebSocketWebUI:Subscribe("WebSocketResult", function(id, success, payload)
		-- this is called from JS in response to our WebSocket request
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
		WebSocketWebUI:CallEvent(event, table_unpack(args))
		-- liftoff! 🚀
		return id
	end

	WebSocketWebUI:Subscribe("WebSocketReady", function()
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

--- Creates a WebSocket connection to the specified URL.<br>
--- Establishes a WebSocket connection that can be used for real-time communication.
---@param url string The WebSocket server URL (e.g., "ws://localhost:8080").
---@param protocols string|nil Optional WebSocket protocols array or single protocol string.
---@param callback function Callback function to receive the connection result (function(success, payload)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- WebSocketAPI.Connect("ws://localhost:8080", nil, function(success, result)
---   if success then
---     print("Connected:", result.socket_id)
---   end
--- end)
--- ```
function WebSocketAPI.Connect(url, protocols, callback)
	-- Handle optional protocols parameter
	if type(protocols) == "function" then
		callback = protocols
		protocols = nil
	end
	return send("DoConnect", { url, protocols }, callback)
end

--- Disconnects a WebSocket connection.<br>
--- Closes the specified WebSocket connection gracefully.
---@param socket_id string The socket ID returned from Connect.
---@param callback function Callback function to receive the disconnection result (function(success, payload)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- WebSocketAPI.Disconnect(socket_id, function(success, result)
---   if success then
---     print("Disconnected:", result.message)
---   end
--- end)
--- ```
function WebSocketAPI.Disconnect(socket_id, callback)
	return send("DoDisconnect", { socket_id }, callback)
end

--- Sends a message through the WebSocket connection.<br>
--- Transmits data to the WebSocket server.
---@param socket_id string The socket ID returned from Connect.
---@param data string|table The data to send (will be JSON stringified if table).
---@param callback function Callback function to receive the send result (function(success, payload)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- WebSocketAPI.Send(socket_id, "Hello Server!", function(success, result)
---   if success then
---     print("Message sent:", result.message)
---   end
--- end)
--- ```
function WebSocketAPI.Send(socket_id, data, callback)
	return send("DoSend", { socket_id, data }, callback)
end

--- Sets up a message event handler for the WebSocket connection.<br>
--- Registers a callback function to handle incoming messages.
---@param socket_id string The socket ID returned from Connect.
---@param callback function Callback function to handle incoming messages (function(message)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- WebSocketAPI.OnMessage(socket_id, function(message)
---   print("Received:", message)
--- end)
--- ```
function WebSocketAPI.OnMessage(socket_id, callback)
	return send("DoOnMessage", { socket_id }, callback)
end

--- Sets up an error event handler for the WebSocket connection.<br>
--- Registers a callback function to handle WebSocket errors.
---@param socket_id string The socket ID returned from Connect.
---@param callback function Callback function to handle errors (function(error)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- WebSocketAPI.OnError(socket_id, function(error)
---   print("WebSocket error:", error)
--- end)
--- ```
function WebSocketAPI.OnError(socket_id, callback)
	return send("DoOnError", { socket_id }, callback)
end

--- Sets up a close event handler for the WebSocket connection.<br>
--- Registers a callback function to handle connection close events.
---@param socket_id string The socket ID returned from Connect.
---@param callback function Callback function to handle close events (function(event)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- WebSocketAPI.OnClose(socket_id, function(event)
---   print("WebSocket closed:", event.reason)
--- end)
--- ```
function WebSocketAPI.OnClose(socket_id, callback)
	return send("DoOnClose", { socket_id }, callback)
end

--- Gets the current connection state of the WebSocket.<br>
--- Returns the ready state of the WebSocket connection.
---@param socket_id string The socket ID returned from Connect.
---@param callback function Callback function to receive the state result (function(success, payload)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- WebSocketAPI.GetState(socket_id, function(success, state)
---   if success then
---     print("State:", state) -- "connecting", "open", "closing", "closed"
---   end
--- end)
--- ```
function WebSocketAPI.GetState(socket_id, callback)
	return send("DoGetState", { socket_id }, callback)
end

--- Sets up a connection event handler for the WebSocket connection.<br>
--- Registers a callback function to handle connection open events.
---@param socket_id string The socket ID returned from Connect.
---@param callback function Callback function to handle connection open (function(event)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- WebSocketAPI.OnOpen(socket_id, function(event)
---   print("WebSocket opened")
--- end)
--- ```
function WebSocketAPI.OnOpen(socket_id, callback)
	return send("DoOnOpen", { socket_id }, callback)
end

-- Export the API to be accessed by other packages
return WebSocketAPI
