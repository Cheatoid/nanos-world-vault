-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Localized global functions for better performance
local table_insert = table.insert
local table_unpack = table.unpack

-- Hash API - bridged via WebUI
local HashAPI = {}

--- Enqueue until ready
local send
do
	local HashWebUI = WebUI(
		Package.GetName() .. ":hash.api",
		"file:///UI/HashAPI.html",
		WidgetVisibility.Hidden, true, false, 0, 0
	)
	local pending = {} ---@type table<integer, function|nil>
	local queued = {} ---@type table<integer, {event:string, args:table, callback:function, req_id:integer}|nil>
	local req_id = math.mininteger or 0
	local is_ready = false

	-- Receive results from JS
	HashWebUI:Subscribe("HashResult", function(id, success, payload)
		-- this is called from JS in response to our Hash request
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
		HashWebUI:CallEvent(event, table_unpack(args))
		-- liftoff! 🚀
		return id
	end

	HashWebUI:Subscribe("HashReady", function()
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

--- Computes the SHA-1 hash of the given string.<br>
--- Returns a 40-character hexadecimal string.
---@param str string The string to hash.
---@param callback function Callback function to receive the hash result (function(success, payload)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- HashAPI.SHA1("hello world", function(success, result)
---   if success then
---     print("SHA-1:", result) -- "2aae6c35c94fcfb415dbe95f408b9ce91ee846ed"
---   end
--- end)
--- ```
function HashAPI.SHA1(str, callback)
	return send("DoSHA1", { str }, callback)
end

--- Computes the SHA-256 hash of the given string.<br>
--- Returns a 64-character hexadecimal string.
---@param str string The string to hash.
---@param callback function Callback function to receive the hash result (function(success, payload)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- HashAPI.SHA256("hello world", function(success, result)
---   if success then
---     print("SHA-256:", result) -- "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
---   end
--- end)
--- ```
function HashAPI.SHA256(str, callback)
	return send("DoSHA256", { str }, callback)
end

--- Computes the SHA-384 hash of the given string.<br>
--- Returns a 96-character hexadecimal string.
---@param str string The string to hash.
---@param callback function Callback function to receive the hash result (function(success, payload)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- HashAPI.SHA384("hello world", function(success, result)
---   if success then
---     print("SHA-384:", result)
---   end
--- end)
--- ```
function HashAPI.SHA384(str, callback)
	return send("DoSHA384", { str }, callback)
end

--- Computes the SHA-512 hash of the given string.<br>
--- Returns a 128-character hexadecimal string.
---@param str string The string to hash.
---@param callback function Callback function to receive the hash result (function(success, payload)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- HashAPI.SHA512("hello world", function(success, result)
---   if success then
---     print("SHA-512:", result) -- "309ecc489c12d6eb4cc40f50c902f2b4d0ed77ee511a7c7a9bcd3ca86d4cd86f989dd35bc5ff499670da34255b45b0cfd830e81f605dcf7dc5542e93ae9cd76f"
---   end
--- end)
--- ```
function HashAPI.SHA512(str, callback)
	return send("DoSHA512", { str }, callback)
end

--- Computes the CRC32 checksum of the given string.<br>
--- Returns an 8-character hexadecimal string.
---@param str string The string to checksum.
---@param callback function Callback function to receive the checksum result (function(success, payload)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- HashAPI.CRC32("hello world", function(success, result)
---   if success then
---     print("CRC32:", result)
---   end
--- end)
--- ```
function HashAPI.CRC32(str, callback)
	return send("DoCRC32", { str }, callback)
end

--- Computes the MD5 hash of the given string.<br>
--- Returns a 32-character hexadecimal string.
---@param str string The string to hash.
---@param callback function Callback function to receive the hash result (function(success, payload)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- HashAPI.MD5("hello world", function(success, result)
---   if success then
---     print("MD5:", result) -- "5eb63bbbe01eeed093cb22bb8f5acdc3"
---   end
--- end)
--- ```
function HashAPI.MD5(str, callback)
	return send("DoMD5", { str }, callback)
end

-- Export the API to be accessed by other packages
return HashAPI
