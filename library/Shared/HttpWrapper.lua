-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Convenience HTTP library wrapper (provides simple callback & case-insensitive options overloads)
local M = {}

-- TODO: async/await support (with promises from oop)

-- Import dependencies
local math = require "@cheatoid/standard/math"
local string = require "@cheatoid/standard/string"
local table = require "@cheatoid/standard/table"
--local curry = require "@cheatoid/standalone/curry"
local tc = require "@cheatoid/standalone/type_check"
local util = require "@cheatoid/standalone/util"

-- Localized global functions for better performance
local inrange = math.inrange
local table_upper = table.uppercase
local check_arg, check_string = tc.check_arg, tc.check_string
local either, safe_call = util.either, util.safe_call
local string_split_url = string.split_url

local HTTP_RequestAsync = assert(HTTP.RequestAsync, "HTTP.RequestAsync function is missing")

---@alias HttpSuccessCallback fun(data: string, status: integer, url: string): unknown
---@alias HttpFailCallback fun(data: string, status: integer, url: string): unknown
---@alias HttpOptions table<string, any>

local function is_internal_error(code)
	-- Failed before HTTP request is even being made (e.g. invalid URL, or firewall issue)
	return code == 0
end

M.is_internal_error = is_internal_error

local function is_informational_status(code)
	-- 1xx = informational
	return inrange(code, 100, 199)
end

M.is_informational_status = is_informational_status

local function is_success_status(code)
	-- 2xx = success
	return inrange(code, 200, 299)
end

M.is_success_status = is_success_status

local function is_redirect_status(code)
	-- 3xx = redirection
	return inrange(code, 300, 399)
end

M.is_redirect_status = is_redirect_status

local function is_client_error_status(code)
	-- 4xx = client error
	return inrange(code, 400, 499)
end

M.is_client_error_status = is_client_error_status
M.is_error_status = is_client_error_status

local function is_server_error_status(code)
	-- 5xx = server error
	return inrange(code, 500, 599)
end

M.is_server_error_status = is_server_error_status

--- Common MIME types / Content-Type values for convenience
---@class ContentTypes
M.CONTENT_TYPES = table.make_case_insensitive {
	-- Text types
	TEXT_PLAIN = "text/plain",
	TEXT_HTML = "text/html",
	TEXT_CSS = "text/css",
	TEXT_JAVASCRIPT = "text/javascript",
	TEXT_XML = "text/xml",
	TEXT_CSV = "text/csv",
	TEXT_MARKDOWN = "text/markdown",

	-- Application types
	APPLICATION_JSON = "application/json",
	APPLICATION_XML = "application/xml",
	APPLICATION_X_WWW_FORM_URLENCODED = "application/x-www-form-urlencoded",
	APPLICATION_OCTET_STREAM = "application/octet-stream",
	APPLICATION_PDF = "application/pdf",
	APPLICATION_ZIP = "application/zip",
	APPLICATION_RTF = "application/rtf",
	APPLICATION_JAVASCRIPT = "application/javascript",

	-- Multipart types
	MULTIPART_FORM_DATA = "multipart/form-data",
	MULTIPART_MIXED = "multipart/mixed",

	-- Image types
	IMAGE_JPEG = "image/jpeg",
	IMAGE_PNG = "image/png",
	IMAGE_GIF = "image/gif",
	IMAGE_SVG_XML = "image/svg+xml",
	IMAGE_WEBP = "image/webp",
	IMAGE_ICO = "image/x-icon",

	-- Audio types
	AUDIO_MPEG = "audio/mpeg",
	AUDIO_WAV = "audio/wav",
	AUDIO_OGG = "audio/ogg",

	-- Video types
	VIDEO_MP4 = "video/mp4",
	VIDEO_WEBM = "video/webm",
	VIDEO_OGG = "video/ogg",

	-- Font types
	FONT_WOFF = "font/woff",
	FONT_WOFF2 = "font/woff2",
	FONT_TTF = "font/ttf",
	FONT_OTF = "font/otf",
}

M.ContentTypes = M.CONTENT_TYPES
M.MEDIA_TYPES = M.CONTENT_TYPES
M.MediaTypes = M.CONTENT_TYPES

--- Generic HTTP method wrapper
---@param method integer Specify HTTPMethod
local function HttpWrapper(method)
	---@overload fun(url: string, on_success: HttpSuccessCallback, on_fail: HttpFailCallback?, headers: HttpOptions?): unknown
	---@overload fun(url: string, options: HttpOptions): unknown
	return function(url, on_success, on_fail, headers)
		check_string(1)
		local callback

		-- Split URL into base URL and endpoint
		local base_url, url_endpoint = string_split_url(url)

		-- Overload resolution via type-checker
		-- TODO: Optimize this, use util.create_type_dispatcher (type lookup table)
		if check_arg(2, "function|table") == "table" then
			-- *Options-table overload*

			-- Use provided endpoint if available, otherwise use extracted endpoint
			local endpoint = options.ENDPOINT or url_endpoint

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
				base_url, -- main URI (the base address)
				endpoint, -- endpoint
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
			base_url, -- main URI (the base address)
			url_endpoint, -- endpoint
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
--for method, v in next, HTTPMethod do
--	M[string.lower(method)] = HttpWrapper(v)
--end

--- Perform an HTTP GET request.<br>
--- The GET method requests a representation of the specified resource. Requests using GET should only retrieve data.
---@param url string The URL to request.
---@param on_success HttpSuccessCallback|nil Callback function called on success with (data, status, url).
---@param on_fail HttpFailCallback|nil Callback function called on failure with (data, status, url).
---@param headers HttpOptions|nil Optional request headers table.
---@return unknown unknown The result of the HTTP request.
---@usage <br>
--- ```
--- -- Simple GET with callbacks
--- Http.get("https://api.example.com/data",
---   function(data, status, url) print("Success:", status) end,
---   function(data, status, url) print("Error:", status) end
--- )
---
--- -- GET with headers
--- Http.get("https://api.example.com/data",
---   function(data, status, url) print("Success:", status) end,
---   function(data, status, url) print("Error:", status) end,
---   { ["Authorization"] = "Bearer token" }
--- )
--- ```
M.get = HttpWrapper(HTTPMethod.GET)

--- Perform an HTTP POST request.<br>
--- The POST method submits an entity to the specified resource, often causing a change in state or side effects on the server.
---@param url string The URL to request.
---@param on_success HttpSuccessCallback|nil Callback function called on success with (data, status, url).
---@param on_fail HttpFailCallback|nil Callback function called on failure with (data, status, url).
---@param headers HttpOptions|nil Optional request headers table.
---@return unknown unknown The result of the HTTP request.
---@usage <br>
--- ```
--- -- Simple POST with callbacks
--- Http.post("https://api.example.com/data",
---   function(data, status, url) print("Success:", status) end,
---   function(data, status, url) print("Error:", status) end
--- )
--- ```
M.post = HttpWrapper(HTTPMethod.POST)

--- Perform an HTTP PUT request.<br>
--- The PUT method replaces all current representations of the target resource with the request payload.
---@param url string The URL to request.
---@param on_success HttpSuccessCallback|nil Callback function called on success with (data, status, url).
---@param on_fail HttpFailCallback|nil Callback function called on failure with (data, status, url).
---@param headers HttpOptions|nil Optional request headers table.
---@return unknown unknown The result of the HTTP request.
---@usage <br>
--- ```
--- -- Simple PUT with callbacks
--- Http.put("https://api.example.com/data",
---   function(data, status, url) print("Success:", status) end,
---   function(data, status, url) print("Error:", status) end
--- )
--- ```
M.put = HttpWrapper(HTTPMethod.PUT)

--- Perform an HTTP DELETE request.<br>
--- The DELETE method deletes the specified resource.
---@param url string The URL to request.
---@param on_success HttpSuccessCallback|nil Callback function called on success with (data, status, url).
---@param on_fail HttpFailCallback|nil Callback function called on failure with (data, status, url).
---@param headers HttpOptions|nil Optional request headers table.
---@return unknown unknown The result of the HTTP request.
---@usage <br>
--- ```
--- -- Simple DELETE with callbacks
--- Http.delete("https://api.example.com/data",
---   function(data, status, url) print("Success:", status) end,
---   function(data, status, url) print("Error:", status) end
--- )
--- ```
M.delete = HttpWrapper(HTTPMethod.DELETE)

--- Perform an HTTP HEAD request.<br>
--- The HEAD method asks for a response identical to a GET request, but without the response body.
---@param url string The URL to request.
---@param on_success HttpSuccessCallback|nil Callback function called on success with (data, status, url).
---@param on_fail HttpFailCallback|nil Callback function called on failure with (data, status, url).
---@param headers HttpOptions|nil Optional request headers table.
---@return unknown unknown The result of the HTTP request.
---@usage <br>
--- ```
--- -- Simple HEAD with callbacks
--- Http.head("https://api.example.com/data",
---   function(data, status, url) print("Success:", status) end,
---   function(data, status, url) print("Error:", status) end
--- )
--- ```
M.head = HttpWrapper(HTTPMethod.HEAD)

--- Perform an HTTP PATCH request.<br>
--- The PATCH method applies partial modifications to a resource.
---@param url string The URL to request.
---@param on_success HttpSuccessCallback|nil Callback function called on success with (data, status, url).
---@param on_fail HttpFailCallback|nil Callback function called on failure with (data, status, url).
---@param headers HttpOptions|nil Optional request headers table.
---@return unknown unknown The result of the HTTP request.
---@usage <br>
--- ```
--- -- Simple PATCH with callbacks
--- Http.patch("https://api.example.com/data",
---   function(data, status, url) print("Success:", status) end,
---   function(data, status, url) print("Error:", status) end
--- )
--- ```
M.patch = HttpWrapper(HTTPMethod.PATCH)

--- Perform an HTTP OPTIONS request.<br>
--- The OPTIONS method describes the communication options for the target resource.
---@param url string The URL to request.
---@param on_success HttpSuccessCallback|nil Callback function called on success with (data, status, url).
---@param on_fail HttpFailCallback|nil Callback function called on failure with (data, status, url).
---@param headers HttpOptions|nil Optional request headers table.
---@return unknown unknown The result of the HTTP request.
---@usage <br>
--- ```
--- -- Simple OPTIONS with callbacks
--- Http.options("https://api.example.com/data",
---   function(data, status, url) print("Success:", status) end,
---   function(data, status, url) print("Error:", status) end
--- )
--- ```
M.options = HttpWrapper(HTTPMethod.OPTIONS)

-- Export the API to be accessed by other packages
return M
