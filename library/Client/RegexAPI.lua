-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Localized global functions for better performance
local table_insert = table.insert
local table_unpack = table.unpack

local RegexAPI = {}

--- Enqueue until ready
local send
do
	local RegexWebUI =
		WebUI("cheatoid-library.regex.api", "file:///UI/RegexAPI.html", WidgetVisibility.Hidden, true, false, 0, 0)
	local pending = {} ---@type table<integer, function|nil>
	local queued = {} ---@type table<integer, {event:string, args:table, callback:function, req_id:integer}|nil>
	local req_id = math.mininteger or 0
	local is_ready = false

	-- Receive results from JS
	RegexWebUI:Subscribe("RegexResult", function(id, success, payload)
		-- this is called from JS in response to our Regex request
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
		RegexWebUI:CallEvent(event, table_unpack(args))
		-- liftoff! 🚀
		return id
	end

	RegexWebUI:Subscribe("RegexReady", function()
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

--- Performs a regex match on the given text.<br>
--- Returns the first match of the pattern in the text.
--- @param pattern string The regular expression pattern to match.
--- @param text string The text to search within.
--- @param flags string|nil Optional regex flags (e.g., "i" for case-insensitive, "m" for multiline).
--- @param callback function Callback function to receive the match result (function(success, payload)).
--- @return integer req_id The request ID for tracking.
--- @usage <br>
--- ```
--- RegexAPI.Match("HELLO", "hello world", "i", function(success, result)
---     if success then
---         print("Matched:", result) -- "hello"
---     end
--- end)
--- ```
function RegexAPI.Match(pattern, text, flags, callback)
	-- Handle optional flags parameter
	if type(flags) == "function" then
		callback = flags
		flags = nil
	end
	return send("DoMatch", { pattern, text, flags }, callback)
end

--- Performs a regex match to find all occurrences in the given text.<br>
--- Returns all non-overlapping matches of the pattern in the text.
--- @param pattern string The regular expression pattern to match.
--- @param text string The text to search within.
--- @param flags string|nil Optional regex flags (e.g., "i" for case-insensitive, "m" for multiline).
--- @param callback function Callback function to receive all matches (function(success, payload)).
--- @return integer req_id The request ID for tracking.
--- @usage <br>
--- ```
--- RegexAPI.MatchAll("\\d+", "abc123def456", "", function(success, results)
---     if success then
---         for _, match in ipairs(results) do
---             print("Match:", match) -- "123", "456"
---         end
---     end
--- end)
--- ```
function RegexAPI.MatchAll(pattern, text, flags, callback)
	-- Handle optional flags parameter
	if type(flags) == "function" then
		callback = flags
		flags = nil
	end
	return send("DoMatchAll", { pattern, text, flags }, callback)
end

--- Tests if a regex pattern matches the given text.<br>
--- Returns a boolean indicating whether the pattern matches anywhere in the text.
--- @param pattern string The regular expression pattern to test.
--- @param text string The text to test against.
--- @param flags string|nil Optional regex flags (e.g., "i" for case-insensitive, "m" for multiline).
--- @param callback function Callback function to receive the test result (function(success, payload)).
--- @return integer req_id The request ID for tracking.
--- @usage <br>
--- ```
--- RegexAPI.Test("^\\d+$", "12345", "", function(success, matches)
---     print("Is numeric:", matches) -- true
--- end)
--- ```
function RegexAPI.Test(pattern, text, flags, callback)
	-- Handle optional flags parameter
	if type(flags) == "function" then
		callback = flags
		flags = nil
	end
	return send("DoTest", { pattern, text, flags }, callback)
end

--- Replaces matches of a regex pattern in the given text.<br>
--- Replaces all occurrences of the pattern with the specified replacement string.
--- @param pattern string The regular expression pattern to search for.
--- @param text string The text to perform replacements in.
--- @param replacement string The replacement string (can use $& for matched text, $1 for capture groups, etc.).
--- @param flags string|nil Optional regex flags (e.g., "i" for case-insensitive). Note: "g" is always applied.
--- @param callback function Callback function to receive the replaced result (function(success, payload)).
--- @return integer req_id The request ID for tracking.
--- @usage <br>
--- ```
--- RegexAPI.Replace("\\d+", "abc123def456", "X", "", function(success, result)
---     if success then
---         print(result) -- "abcXdefX"
---     end
--- end)
--- ```
function RegexAPI.Replace(pattern, text, replacement, flags, callback)
	-- Handle optional flags parameter
	if type(flags) == "function" then
		callback = flags
		flags = nil
	end
	return send("DoReplace", { pattern, text, replacement, flags }, callback)
end

--- Splits a string using a regex pattern as the delimiter.<br>
--- Returns an array of strings split by the pattern.
--- @param pattern string The regular expression pattern to use as delimiter.
--- @param text string The text to split.
--- @param flags string|nil Optional regex flags (e.g., "i" for case-insensitive).
--- @param callback function Callback function to receive the split result (function(success, payload)).
--- @return integer req_id The request ID for tracking.
--- @usage <br>
--- ```
--- RegexAPI.Split("[,;]", "a,b;c,d", "", function(success, parts)
---     if success then
---         for _, part in ipairs(parts) do
---             print(part) -- "a", "b", "c", "d"
---         end
---     end
--- end)
--- ```
function RegexAPI.Split(pattern, text, flags, callback)
	-- Handle optional flags parameter
	if type(flags) == "function" then
		callback = flags
		flags = nil
	end
	return send("DoSplit", { pattern, text, flags }, callback)
end

--- Executes a regex pattern on the given text.<br>
--- Similar to match but returns detailed match information including capture groups.
--- @param pattern string The regular expression pattern to execute.
--- @param text string The text to execute against.
--- @param flags string|nil Optional regex flags (e.g., "i" for case-insensitive, "m" for multiline).
--- @param callback function Callback function to receive the exec result (function(success, payload)).
--- @return integer req_id The request ID for tracking.
--- @usage <br>
--- ```
--- RegexAPI.Exec("(\\d+)-(\\d+)", "123-456", "", function(success, result)
---     if success then
---         print("Full match:", result.match) -- "123-456"
---         print("Group 1:", result.groups and result.groups[1]) -- "123"
---         print("Group 2:", result.groups and result.groups[2]) -- "456"
---     end
--- end)
--- ```
function RegexAPI.Exec(pattern, text, flags, callback)
	-- Handle optional flags parameter
	if type(flags) == "function" then
		callback = flags
		flags = nil
	end
	return send("DoExec", { pattern, text, flags }, callback)
end

-- Export the API to be accessed by other packages
return RegexAPI
