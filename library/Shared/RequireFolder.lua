-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Localized global functions for better performance
local next = next
local string_gsub = string.gsub
local Package_GetFiles = Package.GetFiles
local Package_GetDirectories = Package.GetDirectories
local Package_Require = Package.Require -- _G.require

--- Normalizes a path by converting backslashes to forward slashes and removing redundant slashes.
---@param path string The path to normalize.
---@return string string The normalized path.
local function normalize_path(path)
	-- Replace backslashes with forward slashes
	path = string_gsub(path, "\\", "/")
	-- Collapse multiple slashes into one
	path = string_gsub(path, "/+", "/")
	-- Remove trailing slash unless it's the root
	if #path > 1 then
		path = string_gsub(path, "/$", "")
	end
	return path
end

--- Recursively collects all Lua files from the specified path.
---@param path string The directory path to collect files from.
---@param out table Array to append collected file paths to (modified in-place).
---@param recursive boolean|nil If true, recursively collects files from subfolders.
local function collect_files(path, out, recursive)
	path = normalize_path(path)
	-- Collect lua files in this folder
	local files = Package_GetFiles(path, ".lua")
	for _, file in next, files do
		out[#out + 1] = normalize_path(file)
	end
	-- Recurse into subfolders if enabled
	if recursive then
		local subfolders = Package_GetDirectories(path)
		for _, sub in next, subfolders do
			collect_files(sub, out, true)
		end
	end
end

--- Requires all Lua files from the specified folder with optional priority ordering.
---@param folder string The folder path to load Lua files from.
---@param load_priority table|nil Optional table defining load priority (array entries = load order, keyed entries = skip/override).
---@param recursive boolean|nil If true, recursively collects files from subfolders.
local function RequireFolder(folder, load_priority, recursive)
	folder = normalize_path(folder)

	-- Gather all files
	local all_files = {}
	collect_files(folder, all_files, recursive)

	-- Fast lookup for existence
	local file_exists = {}
	for _, file in next, all_files do
		file_exists[file] = true
	end

	-- Priority order (array part)
	local priority_order = {}

	-- Lookup table for priority and skip
	local priority_lookup = {}

	if load_priority then
		-- Array entries => priority load order
		for key, entry in next, load_priority do
			if type(key) == "number" then
				local entry = normalize_path(entry) -- intentionally shadowing to avoid reassigning loop variable
				priority_order[#priority_order + 1] = entry
				priority_lookup[entry] = true
			end
		end

		-- Keyed entries => skip or override
		for key, value in next, load_priority do
			if type(key) == "string" then
				priority_lookup[normalize_path(key)] = value ~= false
			end
		end
	end

	-- 1. Load priority files first
	for _, path in next, priority_order do
		if file_exists[path] then
			Package_Require(path)
		end
	end

	-- 2. Load remaining files
	for _, file in next, all_files do
		local mark = priority_lookup[file]
		if mark == nil then
			Package_Require(file)
		elseif mark == false then
			-- Explicit skip
		end
	end
end

-- Export the API to be accessed by other packages
return RequireFolder
