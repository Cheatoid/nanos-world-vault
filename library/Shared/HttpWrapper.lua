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
local patcher = require "@cheatoid/standalone/patcher"

-- Localized global functions for better performance
local error = error
local next = next
local pcall = pcall
local rawget = rawget
local rawset = rawset
local type = type
local debug_getinfo = debug and debug.getinfo
local debug_getregistry = debug and debug.getregistry
local inrange = math.inrange
local table_upper = table.uppercase
local check_arg, check_string = tc.check_arg, tc.check_string
local either, safe_call = util.either, util.safe_call
local string_find = string.find
local string_split_url = string.split_url

local DISABLED_MESSAGE = "HTTP requests are disabled"

local function noop()
end

local function disabled()
	return error(DISABLED_MESSAGE, 2)
end

-- Stash originals + disabled state somewhere that survives ingame hotreload.
-- Fresh locals reset on reload, but the registry / engine globals (HTTP) persist.
-- Without this, a reload while disabled would capture our own detour as "original".
-- Prefer debug.getregistry() (per-VM, no _G pollution); fall back to _G only
-- when the registry is unavailable, and keep an HTTP mirror so either
-- surviving realm can recover it.
local _STASH_KEY = "__Http__"
local registry
if type(debug_getregistry) == "function" then
	local ok, reg = pcall(debug_getregistry)
	if ok and type(reg) == "table" then
		registry = reg
	end
end
local stash
if registry then
	local ok, v = pcall(rawget, registry, _STASH_KEY)
	if ok and type(v) == "table" then
		stash = v
	end
end
if type(stash) ~= "table" and type(HTTP) == "table" then
	local ok, v = pcall(rawget, HTTP, _STASH_KEY)
	if ok and type(v) == "table" then
		stash = v
	end
end
if type(stash) ~= "table" then
	-- Legacy fallback for stashes written before the registry migration.
	local ok, v = pcall(rawget, _G, _STASH_KEY)
	if ok and type(v) == "table" then
		stash = v
	end
end
if type(stash) ~= "table" then
	stash = {}
end
-- Mirror stash so either surviving realm can recover it.
if type(HTTP) == "table" then
	pcall(rawset, HTTP, _STASH_KEY, stash)
end
if registry then
	pcall(rawset, registry, _STASH_KEY, stash)
	-- Drop legacy _G entry once the registry owns the stash.
	pcall(rawset, _G, _STASH_KEY, nil)
else
	pcall(rawset, _G, _STASH_KEY, stash)
end

local function is_c_function(fn)
	if type(fn) ~= "function" then
		return false
	end
	if not debug_getinfo then
		return false
	end
	local ok, info = pcall(debug_getinfo, fn, "S")
	return ok and type(info) == "table" and info.what == "C"
end

local function is_httpwrapper_detour(fn)
	if type(fn) ~= "function" then
		return false
	end
	-- Same-generation fast path (fails after hotreload, new identities).
	if fn == noop or fn == disabled then
		return true
	end
	if not debug_getinfo then
		return false
	end
	local ok, info = pcall(debug_getinfo, fn, "S")
	if not ok or type(info) ~= "table" then
		return false
	end
	if info.what == "C" then
		return false
	end
	local src = info.source or info.short_src or ""
	return string_find(src, "HttpWrapper", 1, true) ~= nil
end

-- Self-heal stash poisoned by a previous generation without detour checks.
for _, _key in next, { "Request", "RequestAsync" } do
	if is_httpwrapper_detour(stash[_key]) then
		stash[_key] = nil
	end
end

local function resolve_original(key, current)
	local stashed = stash[key]
	-- Without debug info we cannot tell detour apart by source,
	-- so never overwrite a known stash entry (first-seen wins).
	if not debug_getinfo then
		if type(stashed) == "function" then
			return stashed
		end
		if type(current) == "function" then
			stash[key] = current
			return current
		end
		return stashed
	end
	if is_httpwrapper_detour(current) then
		-- Hotreload while disabled: current is previous generation's detour, never capture it.
		return stashed
	end
	if type(current) == "function" then
		if is_c_function(current) then
			stash[key] = current
			return current
		end
		-- External Lua patch: keep known-good C original if we already have one.
		if type(stashed) == "function" and is_c_function(stashed) then
			return stashed
		end
		stash[key] = current
		return current
	end
	-- Current missing (e.g. HTTP.Request absent on client): fall back to stash.
	return stashed
end

local _original_Request = resolve_original("Request", either(HTTP, HTTP.Request))
local _original_RequestAsync = resolve_original("RequestAsync", either(HTTP, HTTP.RequestAsync))

-- Wrapper fast path always targets the true original, never a detour.
local HTTP_Request = _original_Request
local HTTP_RequestAsync = _original_RequestAsync

local _disabled = stash.disabled == true
local _throw_on_disabled = stash.throw_on_disabled == true
-- Stash poisoned (originals lost): don't stay "disabled" with nil targets.
if _disabled and _original_Request == nil and _original_RequestAsync == nil then
	_disabled = false
	_throw_on_disabled = false
	stash.disabled = false
	stash.throw_on_disabled = false
end
-- Re-install current generation's detour over any stale previous-generation one.
if _disabled then
	local detour = _throw_on_disabled and disabled or noop
	if HTTP then
		if _original_Request then
			HTTP.Request = detour
		end
		if _original_RequestAsync then
			HTTP.RequestAsync = detour
		end
	end
end

--- Disables global HTTP requests.<br>
--- Silent no-op by default, throws when true, re-enabled when false.
---@param flag? boolean Throw on request instead of no-op (default: nil).
---@usage <br>
--- ```
--- http.disable()
--- http.disable(true)
--- ```
local function disable(flag)
	if flag == false then
		return M.enable()
	end
	_disabled = true
	_throw_on_disabled = flag == true
	stash.disabled = true
	stash.throw_on_disabled = _throw_on_disabled
	if HTTP then
		if _original_Request then
			HTTP.Request = _throw_on_disabled and disabled or noop
		end
		if _original_RequestAsync then
			HTTP.RequestAsync = _throw_on_disabled and disabled or noop
		end
	end
end

M.disable = disable
M.Disable = disable

--- Enables global HTTP requests.<br>
--- Restores original `HTTP.Request` and `HTTP.RequestAsync`.
---@usage <br>
--- ```
--- http.enable()
--- ```
local function enable()
	_disabled = false
	_throw_on_disabled = false
	stash.disabled = false
	stash.throw_on_disabled = false
	if HTTP then
		if _original_Request then
			HTTP.Request = _original_Request
		end
		if _original_RequestAsync then
			HTTP.RequestAsync = _original_RequestAsync
		end
	end
end

M.enable = enable
M.Enable = enable

--- Checks if HTTP requests are disabled.<br>
--- Returns true while `disable` is active.
---@return boolean disabled True while HTTP requests are disabled.
---@usage <br>
--- ```
--- if http.is_disabled() then print("offline") end
--- ```
local function is_disabled()
	return _disabled
end

M.is_disabled = is_disabled
M.IsDisabled = is_disabled

---@alias HttpSuccessCallback fun(data: string, status: integer, url: string)
---@alias HttpFailCallback fun(data: string, status: integer, url: string)
---@alias HttpOptions table<string, any>

local function is_internal_error(code)
	-- Failed before HTTP request is even being made (e.g. invalid URL, or firewall issue)
	return code == 0
end

M.is_internal_error = is_internal_error
M.IsInternalError = is_internal_error

local function is_informational_status(code)
	-- 1xx = informational
	return inrange(code, 100, 199)
end

M.is_informational_status = is_informational_status
M.IsInformationalStatus = is_informational_status

local function is_success_status(code)
	-- 2xx = success
	return inrange(code, 200, 299)
end

M.is_success_status = is_success_status
M.IsSuccessStatus = is_success_status

local function is_redirect_status(code)
	-- 3xx = redirection
	return inrange(code, 300, 399)
end

M.is_redirect_status = is_redirect_status
M.IsRedirectStatus = is_redirect_status

local function is_client_error_status(code)
	-- 4xx = client error
	return inrange(code, 400, 499)
end

M.is_client_error_status = is_client_error_status
M.IsClientErrorStatus = is_client_error_status

local function is_server_error_status(code)
	-- 5xx = server error
	return inrange(code, 500, 599)
end

M.is_server_error_status = is_server_error_status
M.IsServerErrorStatus = is_server_error_status

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
	---@overload fun(url: string, on_success: HttpSuccessCallback, on_fail?: HttpFailCallback, headers?: HttpOptions)
	---@overload fun(url: string, options: HttpOptions)
	return function(url, on_success, on_fail, headers)
		if _disabled then
			if _throw_on_disabled then
				return error(DISABLED_MESSAGE, 2)
			end
			return
		end

		check_string(1)
		local callback

		-- Split URL into base URL and endpoint
		local base_url, url_endpoint = string_split_url(url)

		-- Overload resolution via type-checker
		-- TODO: Optimize this, use util.create_type_dispatcher (type lookup table)
		if check_arg(2, "function|table") == "table" then
			-- *Options-table overload*

			local options = on_success ---@cast options HttpOptions
			options = table_upper(options) -- uppercase lookup is faster

			-- Use provided endpoint if available, otherwise use extracted endpoint
			local endpoint = options.ENDPOINT or url_endpoint ---@cast endpoint string
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
---@param on_success? HttpSuccessCallback Callback function called on success with (data, status, url).
---@param on_fail? HttpFailCallback Callback function called on failure with (data, status, url).
---@param headers? HttpOptions Optional request headers table.
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
M.Get = M.get
M.GET = M.get

--- Perform an HTTP POST request.<br>
--- The POST method submits an entity to the specified resource, often causing a change in state or side effects on the server.
---@param url string The URL to request.
---@param on_success? HttpSuccessCallback Callback function called on success with (data, status, url).
---@param on_fail? HttpFailCallback Callback function called on failure with (data, status, url).
---@param headers? HttpOptions Optional request headers table.
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
M.Post = M.post
M.POST = M.post

--- Perform an HTTP PUT request.<br>
--- The PUT method replaces all current representations of the target resource with the request payload.
---@param url string The URL to request.
---@param on_success? HttpSuccessCallback Callback function called on success with (data, status, url).
---@param on_fail? HttpFailCallback Callback function called on failure with (data, status, url).
---@param headers? HttpOptions Optional request headers table.
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
M.Put = M.put
M.PUT = M.put

--- Perform an HTTP DELETE request.<br>
--- The DELETE method deletes the specified resource.
---@param url string The URL to request.
---@param on_success? HttpSuccessCallback Callback function called on success with (data, status, url).
---@param on_fail? HttpFailCallback Callback function called on failure with (data, status, url).
---@param headers? HttpOptions Optional request headers table.
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
M.Delete = M.delete
M.DELETE = M.delete

--- Perform an HTTP HEAD request.<br>
--- The HEAD method asks for a response identical to a GET request, but without the response body.
---@param url string The URL to request.
---@param on_success? HttpSuccessCallback Callback function called on success with (data, status, url).
---@param on_fail? HttpFailCallback Callback function called on failure with (data, status, url).
---@param headers? HttpOptions Optional request headers table.
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
M.Head = M.head
M.HEAD = M.head

--- Perform an HTTP PATCH request.<br>
--- The PATCH method applies partial modifications to a resource.
---@param url string The URL to request.
---@param on_success? HttpSuccessCallback Callback function called on success with (data, status, url).
---@param on_fail? HttpFailCallback Callback function called on failure with (data, status, url).
---@param headers? HttpOptions Optional request headers table.
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
M.Patch = M.patch
M.PATCH = M.patch

--- Perform an HTTP OPTIONS request.<br>
--- The OPTIONS method describes the communication options for the target resource.
---@param url string The URL to request.
---@param on_success? HttpSuccessCallback Callback function called on success with (data, status, url).
---@param on_fail? HttpFailCallback Callback function called on failure with (data, status, url).
---@param headers? HttpOptions Optional request headers table.
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
M.Options = M.options
M.OPTIONS = M.options

-- Export the API to be accessed by other packages
return M
