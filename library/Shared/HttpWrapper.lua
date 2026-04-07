-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Convenience HTTP library wrapper (provides simple callback & case-insensitive options overloads)

-- Import dependencies
local math = require("@cheatoid/standard/math")
local table = require("@cheatoid/standard/table")
--local curry = require("@cheatoid/standalone/curry")
local tc = require("@cheatoid/standalone/type_check")
local util = require("@cheatoid/standalone/util")

-- Localized global functions for better performance
local inrange = math.inrange
local table_upper = table.uppercase
local check_arg, check_string = tc.check_arg, tc.check_string
local either, safe_call = util.either, util.safe_call

local HTTP_RequestAsync = assert(HTTP.RequestAsync, "HTTP.RequestAsync function is missing")

--- @alias HttpSuccessCallback fun(data: string, status: integer, url: string): any
--- @alias HttpFailCallback fun(data: string, status: integer, url: string): any
--- @alias HttpOptions table<string, any>

--- @alias HttpMethod fun(url: string, on_success: HttpSuccessCallback, on_fail: HttpFailCallback?, headers: table?): integer
--- @alias HttpMethod_Options fun(url: string, options: HttpOptions): integer

--- HTTP wrapper
--- @class HttpWrapper
--- @field get HttpMethod|HttpMethod_Options
--- @field post HttpMethod|HttpMethod_Options
--- @field put HttpMethod|HttpMethod_Options
--- @field delete HttpMethod|HttpMethod_Options
--- @field head HttpMethod|HttpMethod_Options
--- @field patch HttpMethod|HttpMethod_Options
--- @field options HttpMethod|HttpMethod_Options
local M = {}

local function is_success_status(code)
	-- 2xx = success
	return inrange(code, 200, 299)
end

M.is_success_status = is_success_status

--- Generic HTTP method wrapper
local function HttpWrapper(method)
	return function(url, on_success, on_fail, headers)
		check_string(1)
		local callback

		-- Overload resolution via type-checker
		-- TODO: Optimize this, use util.create_type_dispatcher (type lookup table)
		if check_arg(2, "function|table") == "table" then
			-- *Options-table overload*
			---@type table
			local options = on_success
			options = table_upper(options or {}) -- uppercase lookup is faster
			if options.ONSUCCESS or options.SUCCESS or options.ONFAIL or options.FAIL then
				callback = function(status, data)
					safe_call(
						either(
							is_success_status(status),
							options.ONSUCCESS or options.SUCCESS,
							options.ONFAIL or options.FAIL
						),
						data,
						status,
						url,
						options
					)
				end
			end

			return HTTP_RequestAsync(
				url,     -- main URI (the base address)
				options.ENDPOINT, -- endpoint
				options.METHOD,
				options.DATA, -- data / body payload
				options.CONTENTTYPE, -- content type
				options.COMPRESS, -- whether or not to compress the content with gzip
				options.HEADERS, -- request headers
				callback
			)
		end

		-- *Function overload*
		callback = function(status, data)
			if is_success_status(status) then
				if on_success then
					return on_success(data, status, url)
				end
			else
				if on_fail then
					return on_fail(data, status, url)
				end
			end
		end
		return HTTP_RequestAsync(
			url, -- main URI (the base address)
			nil, -- endpoint
			method,
			nil, -- data / body payload
			nil, -- content type
			false, -- whether or not to compress the content with gzip
			headers, -- request headers
			callback
		)
	end
end

-- Wrap all available HTTP methods
for method, v in next, HTTPMethod do
	M[string.lower(method)] = HttpWrapper(v)
end

-- Export the API to be accessed by other packages
return M
