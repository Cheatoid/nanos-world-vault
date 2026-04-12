-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Convenient utility for loading scripts from a directory

-- Localized global functions for better performance
local next = next
local string = string
local string_find = string.find
local string_match = string.match
local string_gsub = string.gsub
local string_sub = string.sub
local Package_GetFiles = Package.GetFiles
local Package_GetDirectories = Package.GetDirectories
local Package_Require = Package and Package.Require or require

-- VFS-aware require function (will be set per-instance)
local _require_fn

-- Default require function
local function _require(...)
	--print("[RequireFolder.require]", ...)
	if _require_fn then
		return _require_fn(...)
	end
	return Package_Require(...)
end

-- Simple path normalization function (replaces backslashes with forward slashes)
local function normalize_path(path)
	return (string_gsub(path, "[\\/]+", "/"))
end

--- Recursively collects all Lua files from the specified path.
---@param path string The directory path to collect files from.
---@param out table Array to append collected file paths to (modified in-place).
---@param recursive boolean|nil If true, recursively collects files from subfolders.
---@param vfs table|nil Optional VFS interface with list_files, list_directories, is_directory methods.
local function collect_files(path, out, recursive, vfs)
	path = normalize_path(path)
	out = out or {}

	-- Ensure trailing slash for proper path filtering
	if string_sub(path, -1) ~= "/" then
		path = path .. "/"
	end

	-- Collect lua files using VFS or Package.GetFiles
	local files
	if vfs and vfs.list_files then
		files = vfs.list_files(path, ".lua")
	else
		files = Package_GetFiles(path, ".lua")
	end
	--print("# files (raw):", #files)

	-- Helper to check if file should be included based on filters
	local function should_include_file(file)
		-- Skip .d.lua declaration files (LuaLS type definitions)
		if string_match(file, "%.[Dd]%.[Ll][Uu][Aa]$") then
			return false
		end
		-- When not recursive, filter out files in subdirectories
		if not recursive then
			local relative = string_sub(file, #path + 1)
			if string_find(relative, "/", nil, true) then
				--print("skipping nested:", file)
				return false
			end
		end
		return true
	end

	for _, file in next, files do
		if should_include_file(file) then
			out[#out + 1] = normalize_path(file)
		end
	end
	-- Recurse into subfolders if enabled
	if recursive then
		local subfolders
		if vfs and vfs.list_directories then
			subfolders = vfs.list_directories(path)
		else
			subfolders = Package_GetDirectories(path)
		end
		for _, sub in next, subfolders do
			collect_files(path .. sub .. "/", out, true, vfs)
		end
	end
	return out
end

-- Helper to detect if a string is a Lua pattern
local function is_pattern(s)
	return string_match(s, "[%%^%$%(%)%[%]%.%*%+%-%?]") ~= nil
end

-- Helper to check if a file matches any pattern
local function matches_pattern(file, patterns)
	for _, pattern in next, patterns do
		if string_match(file, pattern) then
			--print("[RequireFolder] Pattern matched:", pattern, "against", file)
			return true
		end
	end
	return false
end

-- Helper to check if a path is a directory
local function is_directory(path, vfs)
	if vfs and vfs.is_directory then
		return vfs.is_directory(path)
	end
	-- Fallback: check if it has files
	local files = Package_GetFiles(path, ".lua")
	return next(files) ~= nil
end

--- Helper function to load a single file if not already loaded
---@param file string The file path to load
---@param loaded_files table Table tracking which files have been loaded
---@param priority_lookup table Lookup table for priority and skip (exact paths)
---@param skip_patterns table List of patterns for files to skip
---@param include_patterns table List of patterns for files to explicitly include
---@param require_fn function Function to use for requiring files
local function load_file(file, loaded_files, priority_lookup, skip_patterns, include_patterns, require_fn)
	if loaded_files[file] then
		return
	end

	local mark = priority_lookup[file]
	if mark == nil then
		-- Check skip patterns
		if matches_pattern(file, skip_patterns) then
			-- Explicit skip via pattern
			--print("[RequireFolder] Skipping file (pattern):", file)
			return
		elseif matches_pattern(file, include_patterns) then
			-- Explicit include via pattern
			require_fn(file)
			loaded_files[file] = true
		else
			-- No pattern match, load by default
			--print("[RequireFolder] Loading file (default):", file)
			require_fn(file)
			loaded_files[file] = true
		end
	elseif mark == false then
		-- Explicit skip via exact path
		return
	else
		-- Explicit include via exact path
		require_fn(file)
		loaded_files[file] = true
	end
end

--- Helper function to load a priority path (file or directory)
---@param path string The path to load (file or directory)
---@param all_files table List of all files to load from
---@param file_exists table Lookup table for file existence
---@param priority_lookup table Lookup table for priority and skip (exact paths)
---@param skip_patterns table List of patterns for files to skip
---@param load_file_fn function Function to use for loading individual files
---@param vfs table|nil Optional VFS interface
local function load_priority_path(path, all_files, file_exists, priority_lookup, skip_patterns, load_file_fn, vfs)
	-- Check if it's a directory (even if not in file_exists)
	if is_directory(path, vfs) then
		-- Load all files in this directory first
		for _, file in next, all_files do
			if string_match(file, "^" .. normalize_path(path) .. "/") then
				local mark = priority_lookup[file]
				if mark == nil or mark == true then
					-- Skip if matched by skip patterns
					if not matches_pattern(file, skip_patterns) then
						load_file_fn(file)
					end
				end
			end
		end
	elseif file_exists[path] then
		-- It's a file, load it directly
		load_file_fn(path)
	end
end

--- Requires all Lua files from the specified folder with optional priority ordering and ignore list.<br>
--- Supports currying: calling with just a folder returns a function that takes load_priority, recursive, and vfs.
---@param folder string The folder path to load Lua files from.
---@param load_priority table|nil Optional table defining:<br>
--- Keyed entries with Lua patterns (e.g., `"%.tests%.lua$"`) will be matched against file paths.
--- - special index `[0]` can be used to pass a VFS instance
--- - array entries = priority load order (e.g. `"file1.lua"`)
--- - keyed entries = false to skip, or true to force include (e.g. `["file2.lua"] = false`)
---@param recursive boolean|nil If true, recursively collects files from subfolders (default: true).
---@param vfs table|nil Optional VFS interface with list_files, list_directories, is_directory, load methods.
local function RequireFolder(folder, load_priority, recursive, vfs)
	--print("[RequireFolder] Called with:", "folder=", folder, "load_priority=", type(load_priority), "recursive=", recursive, "vfs=", vfs)
	folder = normalize_path(folder)

	-- Support currying: if load_priority and recursive and vfs are nil, return a function
	-- NOTE: This check must happen BEFORE setting defaults!
	if load_priority == nil and recursive == nil and vfs == nil then
		--print("[RequireFolder] Currying - returning function for folder:", folder)
		return function(load_priority_arg, recursive_arg, vfs_arg)
			--print("[RequireFolder] Curried function called with:", type(load_priority_arg), type(recursive_arg), type(vfs_arg))
			return RequireFolder(folder, load_priority_arg, recursive_arg, vfs_arg)
		end
	end

	if recursive == nil then recursive = true end

	-- Check for VFS in load_priority[0] if not passed directly
	if not vfs and load_priority and type(load_priority[0]) == "table" then
		vfs = load_priority[0]
	end

	-- Set up VFS-aware require if VFS provides a load method
	if vfs and vfs.load then
		_require_fn = vfs.load
	elseif vfs and vfs.get then
		-- Fallback: use vfs.get and load the content
		_require_fn = function(name, ...)
			local content = vfs.get(name)
			if content then
				local chunk, err = load(content, "vfs:" .. name)
				if chunk then
					return chunk(...)
				end
				return error("failed to load " .. name .. ": " .. err, 2)
			end
			return Package_Require(name, ...)
		end
	else
		_require_fn = nil
	end

	-- Gather all files
	local all_files = {}
	collect_files(folder, all_files, recursive, vfs)

	-- Fast lookup for existence
	local file_exists = {}
	for _, file in next, all_files do
		file_exists[file] = true
	end

	-- Priority order (array part)
	local priority_order = {}

	-- Lookup table for priority and skip (exact paths)
	local priority_lookup = {}

	-- Pattern list for skip/override (Lua patterns)
	local skip_patterns = {}
	local include_patterns = {}

	if load_priority then
		--print("[RequireFolder] load_priority is present, processing...")
		-- Array entries => priority load order
		for key, entry in next, load_priority do
			if type(key) == "number" then
				local entry = normalize_path(entry) -- intentionally shadowing to avoid reassigning loop variable
				-- Prepend folder path if entry doesn't start with it
				if not string_match(entry, "^" .. folder) then
					-- Check if entry overlaps with last folder component (e.g., folder="Shared/@cheatoid", entry="@cheatoid/standard")
					local last_component = string_match(folder, "([^/]+)$")
					if last_component and string_match(entry, "^" .. last_component .. "/") then
						-- Entry already includes the folder's last component, just append rest
						entry = folder .. entry:sub(#last_component + 1)
					else
						entry = folder .. "/" .. entry
					end
				end
				priority_order[#priority_order + 1] = entry
				priority_lookup[entry] = true
			end
		end

		-- Keyed entries => skip or override
		--print("[RequireFolder] Processing keyed entries, load_priority is:", type(load_priority))
		for key, value in next, load_priority do
			--print("[RequireFolder] Keyed entry:", type(key), key, "=", value)
			if type(key) == "string" then
				local cleaned_key = normalize_path(key)
				--print("[RequireFolder] Checking if pattern:", key, "is_pattern:", is_pattern(key))
				if is_pattern(key) then
					-- Store as pattern
					if value == false then
						--print("[RequireFolder] Registering skip pattern:", key)
						skip_patterns[#skip_patterns + 1] = key
					else
						include_patterns[#include_patterns + 1] = key
					end
				else
					-- Store as exact path
					priority_lookup[cleaned_key] = value ~= false
				end
			end
		end
	end

	-- Debug: print all skip patterns
	--for i, p in next, skip_patterns do
	--	print("[RequireFolder] Skip pattern", i, ":", p)
	--end

	-- Track which files have been loaded to avoid duplicates
	local loaded_files = {}

	-- Create a closure for load_file with the necessary state
	local function load_file_closure(file)
		return load_file(file, loaded_files, priority_lookup, skip_patterns, include_patterns, _require)
	end

	-- 1. Load priority files/directories first
	for _, path in next, priority_order do
		load_priority_path(path, all_files, file_exists, priority_lookup, skip_patterns, load_file_closure, vfs)
	end

	-- 2. Load remaining files
	--print("[RequireFolder] Found " .. #all_files .. " files to load")
	for _, file in next, all_files do
		--print("[RequireFolder] Loading:", file)
		load_file_closure(file)
	end
end

-- Export the API to be accessed by other packages
return RequireFolder
