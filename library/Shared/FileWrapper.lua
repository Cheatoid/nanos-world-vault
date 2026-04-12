-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Convenience file I/O wrapper and virtual file system (VFS) library
local M = {}

-- Localized global functions for better performance
local assert = assert
local next = next
local type = type
local string = require("@cheatoid/standard/string")
local string_gmatch = string.gmatch
local string_match = string.match
local string_normalize_path = string.normalize_path
local string_path_file = string.path_file

local File = assert(_G.File, "File function is missing")

-- Localized File API methods for better performance
local File_IsRegularFile = File.IsRegularFile
local File_IsDirectory = File.IsDirectory
local File_Exists = File.Exists
local File_Time = File.Time
local File_Remove = File.Remove
local File_GetFiles = File.GetFiles
local File_GetDirectories = File.GetDirectories
local File_CreateDirectory = File.CreateDirectory
local File_GetFullPath = File.GetFullPath

--- Check if input looks like a file path.<br>
--- Detects common file path patterns and rejects paths with invalid characters.<br>
--- Invalid characters include Windows invalid chars (< > : " | ? *) and control characters.
---@param input string The input string to check.
---@return boolean is_file_path True if the input looks like a file path, false otherwise.
---@usage <br>
--- ```
--- -- Check if input is a file path
--- if file.is_file_path("my_script.lua") then
---   print("Looks like a file path")
--- end
---
--- -- Check with path separators
--- if file.is_file_path("scripts/my_script.lua") then
---   print("Looks like a file path")
--- end
--- ```
local function is_file_path(input) -- TODO: Move to Lua lib (string)
	-- Reject paths with invalid characters
	-- Windows invalid chars: < > : " | ? *
	-- Also reject null and control characters
	if string_match(input, '[<>:"%|%?%*%c\0]') then
		return false
	end
	-- Check for common file path patterns
	-- Ends with .lua extension
	if string_match(input, "%.[Ll][Uu][Aa]$") then
		return true
	end
	-- Has path separators (Windows or Unix)
	if string_match(input, "[/\\]") then
		return true
	end
	return false
end

M.is_file_path = is_file_path

--- Check if a path exists as a file.<br>
--- Uses File.IsRegularFile to check if the path is a regular file.
---@param path string The path to check.
---@return boolean is_file True if the path is a file, false otherwise.
---@usage <br>
--- ```
--- if file.is_file("my_script.lua") then
---   print("This is a file")
--- end
--- ```
local function is_file(path)
	return File_IsRegularFile(path)
end

M.is_file = is_file

--- Check if a path exists as a directory.<br>
--- Uses File.IsDirectory to check if the path is a directory.
---@param path string The path to check.
---@return boolean is_dir True if the path is a directory, false otherwise.
---@usage <br>
--- ```
--- if file.is_dir("scripts/") then
---   print("This is a directory")
--- end
--- ```
local function is_dir(path)
	return File_IsDirectory(path)
end

M.is_dir = is_dir

--- Check if a path exists (as a file or directory).<br>
--- Uses File.Exists to check if the path exists.
---@param path string The path to check.
---@return boolean exists True if the path exists, false otherwise.
---@usage <br>
--- ```
--- if file.exists("my_script.lua") then
---   print("Path exists")
--- end
--- ```
local function exists(path)
	return File_Exists(path)
end

M.exists = exists

--- Get file modification time in Unix time.<br>
--- Uses File.Time to get the last modification time.
---@param path string The file path to get information for.
---@return integer|nil time The last modification time in Unix time, or nil on failure.
---@usage <br>
--- ```
--- local time = file.time("my_script.lua")
--- if time then
---   print("Last modified:", time)
--- end
--- ```
local function file_time(path)
	return File_Time(path)
end

M.time = file_time

--- Read file content from the given path.<br>
--- Opens the file using File API and reads its content.<br>
--- Returns nil and an error message if the file cannot be opened or read.
---@param path string The file path to read.
---@return string|nil content The file content, or nil on failure.
---@return string|nil error Error message if the operation failed.
---@usage <br>
--- ```
--- local content, err = file.read("my_script.lua")
--- if content then
---   print("File content:", content)
--- else
---   print("Error:", err)
--- end
--- ```
local function read_file(path)
	-- TODO: Import @cheatoid standard string library and automatically normalize path string
	-- Try to open and read the file
	local file = File(path)
	if not (file and file:IsGood()) then
		return nil, "failed to open file: " .. path
	end
	local content = file:Read()
	file:Close()
	if not content then
		return nil, "failed to read file: " .. path
	end
	return content
end

M.read = read_file

--- Write content to a file at the given path.<br>
--- Creates or overwrites the file using File API.<br>
--- Returns nil and an error message if the file cannot be opened or written.
---@param path string The file path to write.
---@param content string The content to write to the file.
---@return boolean|nil success True on success, nil on failure.
---@return string|nil error Error message if the operation failed.
---@usage <br>
--- ```
--- local success, err = file.write("my_script.lua", "print('Hello, World!')")
--- if success then
---   print("File written successfully")
--- else
---   print("Error:", err)
--- end
--- ```
local function write_file(path, content)
	-- Try to open and write to the file
	local file = File(path)
	if not (file and file:IsGood()) then
		return nil, "failed to open file for writing: " .. path
	end
	local success = file:Write(content)
	file:Close()
	if not success then
		return nil, "failed to write to file: " .. path
	end
	return true
end

M.write = write_file

--- Append content to a file at the given path.<br>
--- Reads existing content, appends new content, and writes back.<br>
--- Creates the file if it doesn't exist.<br>
--- Returns nil and an error message if the operation fails.
---@param path string The file path to append to.
---@param content string The content to append to the file.
---@return boolean|nil success True on success, nil on failure.
---@return string|nil error Error message if the operation failed.
---@usage <br>
--- ```
--- -- Append to existing file
--- local success, err = file.append("log.txt", "\\nNew log entry")
--- if success then
---   print("Content appended successfully")
--- else
---   print("Error:", err)
--- end
--- ```
local function append_file(path, content)
	-- Read existing content if file exists
	local existing_content, err = read_file(path)
	if existing_content then
		content = existing_content .. content
	elseif err and not string_match(err, "failed to open file") then
		-- Error other than file not found
		return nil, err
	end
	-- Write the combined content
	return write_file(path, content)
end

M.append = append_file

--- Delete a file or directory at the given path.<br>
--- Uses File.Remove to remove the file or directory.<br>
--- Returns the number of files deleted.
---@param path string The file or directory path to remove.
---@return integer count Number of files deleted.
---@usage <br>
--- ```
--- local count = file.remove("old_file.lua")
--- print("Deleted", count, "files")
--- ```
local function remove_file(path)
	return File_Remove(path)
end

M.remove = remove_file
M.delete = remove_file -- alias

--- Rename a file from old_path to new_path.<br>
--- Copies content from old_path to new_path and deletes the original.<br>
--- Returns nil and an error message if the operation fails.
---@param old_path string The current file path.
---@param new_path string The new file path.
---@return boolean|nil success True on success, nil on failure.
---@return string|nil error Error message if the operation failed.
---@usage <br>
--- ```
--- local success, err = file.rename("old_name.lua", "new_name.lua")
--- if success then
---   print("File renamed successfully")
--- else
---   print("Error:", err)
--- end
--- ```
local function rename_file(old_path, new_path)
	-- Read content from old file
	local content, err = read_file(old_path)
	if not content then
		return nil, err
	end
	-- Write content to new file
	local success, write_err = write_file(new_path, content)
	if not success then
		return nil, write_err
	end
	-- Delete old file
	local success, delete_err = remove_file(old_path)
	if not success then
		return nil, delete_err
	end
	return true
end

M.rename = rename_file
M.move = rename_file -- alias

--- Copy a file from source to destination.<br>
--- Reads content from source and writes it to destination.<br>
--- Returns nil and an error message if the operation fails.
---@param source string The source file path.
---@param destination string The destination file path.
---@return boolean|nil success True on success, nil on failure.
---@return string|nil error Error message if the operation failed.
---@usage <br>
--- ```
--- local success, err = file.copy("source.lua", "destination.lua")
--- if success then
---   print("File copied successfully")
--- else
---   print("Error:", err)
--- end
--- ```
local function copy_file(source, destination)
	-- Read content from source
	local content, err = read_file(source)
	if not content then
		return nil, err
	end
	-- Write content to destination
	return write_file(destination, content)
end

M.copy = copy_file

--- List all files in the package with optional filters.<br>
--- Uses File.GetFiles to get a list of file paths.<br>
--- Returns a table of file paths matching the filters.
---@param path_filter string|nil Path filter (default: "").
---@param extension_filter string|nil Extension filter (e.g., ".lua", default: "").
---@param max_depth integer|nil Maximum depth to search (-1 for unlimited, default: -1).
---@return string[] files Table of file paths.
---@usage <br>
--- ```
--- -- List all .lua files
--- local files = file.list_files("", ".lua")
--- for i, file_path in next, files do
---   print(file_path)
--- end
---
--- -- List all files in a specific directory
--- local files = file.list_files("scripts/")
--- ```
local function list_files(path_filter, extension_filter, max_depth)
	return File_GetFiles(path_filter or "", extension_filter or "", max_depth or -1)
end

M.list_files = list_files

--- Iterate over files in the package with optional filters.<br>
--- Returns an iterator function that yields file paths one at a time.<br>
--- Useful for processing large numbers of files without loading them all into memory.
---@param path_filter string|nil Path filter (default: "").
---@param extension_filter string|nil Extension filter (e.g., ".lua", default: "").
---@return fun() iterator Iterator function that yields file paths.
---@usage <br>
--- ```
--- -- Iterate over all .lua files
--- for file_path in file.iterate_files("", ".lua") do
---   print(file_path)
--- end
--- ```
local function iterate_files(path_filter, extension_filter)
	local files = list_files(path_filter, extension_filter)
	local index = 0
	return function()
		index = index + 1
		return files[index]
	end
end

M.iterate_files = iterate_files

--- List all directories in the package with optional path filter.<br>
--- Uses File.GetDirectories to get a list of directory paths.<br>
--- Returns a table of directory paths matching the filter.
---@param path_filter string|nil Path filter (default: "").
---@param max_depth integer|nil Maximum depth to search (-1 for unlimited, default: -1).
---@return string[] directories Table of directory paths.
---@usage <br>
--- ```
--- -- List all directories
--- local dirs = file.list_directories()
--- for i, dir_path in next, dirs do
---   print(dir_path)
--- end
---
--- -- List directories in a specific path
--- local dirs = file.list_directories("scripts/")
--- ```
local function list_directories(path_filter, max_depth)
	return File_GetDirectories(path_filter or "", max_depth or -1)
end

M.list_directories = list_directories

--- Iterate over directories in the package with optional path filter.<br>
--- Returns an iterator function that yields directory paths one at a time.<br>
--- Useful for processing large directory structures without loading them all into memory.
---@param path_filter string|nil Path filter (default: "").
---@return fun() iterator Iterator function that yields directory paths.
---@usage <br>
--- ```
--- -- Iterate over all directories
--- for dir_path in file.iterate_directories() do
---   print(dir_path)
--- end
--- ```
local function iterate_directories(path_filter)
	local dirs = list_directories(path_filter)
	local index = 0
	return function()
		index = index + 1
		return dirs[index]
	end
end

M.iterate_directories = iterate_directories

--- Create a directory at the given path.<br>
--- Uses File.CreateDirectory to create the directory.<br>
--- Returns true on success, false on failure.
---@param path string The directory path to create.
---@return boolean success True on success, false on failure.
---@usage <br>
--- ```
--- if file.create_directory("scripts/my_folder") then
---   print("Directory created successfully")
--- end
--- ```
local function create_directory(path)
	return File_CreateDirectory(path)
end

M.create_directory = create_directory
M.mkdir = create_directory -- alias

--- Get the full path given a relative path.<br>
--- Uses File.GetFullPath to resolve the full path based on the current side.<br>
--- Returns the full path or nil on failure.
---@param path string The relative path to resolve.
---@return string|nil full_path The full path, or nil on failure.
---@usage <br>
--- ```
--- local full_path = file.get_full_path("my_script.lua")
--- if full_path then
---   print("Full path:", full_path)
--- end
--- ```
local function get_full_path(path)
	-- Normalize path using string library
	path = string_normalize_path(path)
	return File_GetFullPath(path)
end

M.get_full_path = get_full_path

----------------------------------------------------------------------
-- Virtual File System (VFS) Module
-- Allows constructing files in-memory using tables and flushing to disk
----------------------------------------------------------------------

--- Create a new empty VFS instance.<br>
--- Returns a table representing a virtual file system structure.<br>
--- Files can be added to this structure and then flushed to disk.
---@return table vfs The VFS instance
---@usage <br>
--- ```
--- local vfs = file.vfs.create()
--- ```
local function vfs_create()
	return {}
end

--- Write a file to the VFS structure.<br>
--- Creates the file at the specified path within the VFS.<br>
--- Automatically creates parent directories if they don't exist.<br>
--- Returns nil and an error message if the operation fails.
---@param vfs table The VFS instance
---@param path string The file path within the VFS (e.g., "scripts/main.lua")
---@param content string The file content
---@return boolean|nil success True on success, nil on failure
---@return string|nil error Error message if the operation failed
---@usage <br>
--- ```
--- local vfs = file.vfs.create()
--- local success, err = file.vfs.write_file(vfs, "scripts/main.lua", "print('Hello')")
--- if success then
---   print("File written")
--- else
---   print("Error:", err)
--- end
--- ```
local function vfs_write_file(vfs, path, content)
	-- Normalize path using string library
	path = string_normalize_path(path)

	-- Split path into components
	local parts = {}
	for part in string_gmatch(path, "[^/\\]+") do
		parts[#parts + 1] = part
	end

	if #parts == 0 then
		return nil, "invalid path"
	end

	-- Navigate/create directory structure
	local current = vfs
	for i = 1, #parts - 1 do
		local dir_name = parts[i]
		if not current[dir_name] then
			current[dir_name] = {}
		elseif type(current[dir_name]) ~= "table" then
			-- Path component is a file, cannot traverse
			return nil, "path component '" .. dir_name .. "' is a file, not a directory"
		end
		current = current[dir_name]
	end

	-- Set the file content
	current[parts[#parts]] = content
	return true
end

--- Write a directory to the VFS structure.<br>
--- Creates the directory at the specified path within the VFS.<br>
--- Automatically creates parent directories if they don't exist.<br>
--- Returns nil and an error message if the operation fails.
---@param vfs table The VFS instance
---@param path string The directory path within the VFS (e.g., "scripts/utils")
---@return boolean|nil success True on success, nil on failure
---@return string|nil error Error message if the operation failed
---@usage <br>
--- ```
--- local vfs = file.vfs.create()
--- local success, err = file.vfs.write_directory(vfs, "scripts/utils")
--- if success then
---   print("Directory created")
--- else
---   print("Error:", err)
--- end
--- ```
local function vfs_write_directory(vfs, path)
	-- Normalize path using string library
	path = string_normalize_path(path)

	-- Split path into components
	local parts = {}
	for part in string_gmatch(path, "[^/\\]+") do
		parts[#parts + 1] = part
	end

	if #parts == 0 then
		return nil, "invalid path"
	end

	-- Navigate/create directory structure
	local current = vfs
	for i = 1, #parts do
		local dir_name = parts[i]
		if not current[dir_name] then
			current[dir_name] = {}
		elseif type(current[dir_name]) ~= "table" then
			-- Path component is a file, cannot traverse
			return nil, "path component '" .. dir_name .. "' is a file, not a directory"
		end
		current = current[dir_name]
	end

	return true
end

--- Get a value at the specified path in the VFS.<br>
--- Navigates the VFS table structure and returns the value at the given path.<br>
--- Returns nil if the path does not exist.
---@param vfs table The VFS instance
---@param path string The path to get the value from (e.g., "scripts/config")
---@return any value The value at the path, or nil if not found
---@usage <br>
--- ```
--- local vfs = file.vfs.create()
--- file.vfs.set(vfs, "scripts/config", { enabled = true })
--- local config = file.vfs.get(vfs, "scripts/config")
--- print(config.enabled) -- true
--- ```
local function vfs_get(vfs, path)
	-- Normalize path
	path = string_normalize_path(path)

	-- Split path into components
	local parts = {}
	for part in string_gmatch(path, "[^/\\]+") do
		parts[#parts + 1] = part
	end

	if #parts == 0 then
		return vfs
	end

	-- Navigate to the target
	local current = vfs
	for i = 1, #parts do
		local key = parts[i]
		if current[key] == nil then
			return nil
		end
		current = current[key]
	end

	return current
end

--- Set a value at the specified path in the VFS.<br>
--- Creates the table structure as needed if intermediate paths don't exist.<br>
--- If the final path component is a table, it will be replaced with the new value.<br>
--- Returns nil and an error message if the operation fails.
---@param vfs table The VFS instance
---@param path string The path to set the value at (e.g., "scripts/config")
---@param value any The value to set (string for files, table for directories, or any other value)
---@return boolean|nil success True on success, nil on failure
---@return string|nil error Error message if the operation failed
---@usage <br>
--- ```
--- local vfs = file.vfs.create()
--- local success, err = file.vfs.set(vfs, "scripts/config", { enabled = true })
--- if success then
---   print("Value set")
--- else
---   print("Error:", err)
--- end
--- ```
local function vfs_set(vfs, path, value)
	-- Normalize path
	path = string_normalize_path(path)

	-- Split path into components
	local parts = {}
	for part in string_gmatch(path, "[^/\\]+") do
		parts[#parts + 1] = part
	end

	if #parts == 0 then
		return nil, "invalid path"
	end

	-- Navigate/create directory structure (except for last part)
	local current = vfs
	for i = 1, #parts - 1 do
		local key = parts[i]
		if not current[key] then
			current[key] = {}
		elseif type(current[key]) ~= "table" then
			-- Path component is a file, cannot traverse
			return nil, "path component '" .. key .. "' is a file, not a directory"
		end
		current = current[key]
	end

	-- Set the value at the final path component
	current[parts[#parts]] = value
	return true
end

--- Check if a path exists in the VFS.<br>
--- Returns true if the path exists (file or directory), false otherwise.
---@param vfs table The VFS instance
---@param path string The path to check (e.g., "scripts/main.lua")
---@return boolean exists True if the path exists
---@usage <br>
--- ```
--- local vfs = file.vfs.create()
--- file.vfs.write_file(vfs, "scripts/main.lua", "content")
--- if file.vfs.exists(vfs, "scripts/main.lua") then
---   print("File exists")
--- end
--- ```
local function vfs_exists(vfs, path)
	return vfs_get(vfs, path) ~= nil
end

--- Check if a path is a directory in the VFS.<br>
--- Returns true if the path exists and is a directory (table), false otherwise.
---@param vfs table The VFS instance
---@param path string The path to check (e.g., "scripts/utils")
---@return boolean is_directory True if the path is a directory
---@usage <br>
--- ```
--- local vfs = file.vfs.create()
--- file.vfs.write_directory(vfs, "scripts/utils")
--- if file.vfs.is_directory(vfs, "scripts/utils") then
---   print("It's a directory")
--- end
--- ```
local function vfs_is_directory(vfs, path)
	local value = vfs_get(vfs, path)
	return value ~= nil and type(value) == "table"
end

--- Check if a path is a file in the VFS.<br>
--- Returns true if the path exists and is a file (string), false otherwise.
---@param vfs table The VFS instance
---@param path string The path to check (e.g., "scripts/main.lua")
---@return boolean is_file True if the path is a file
---@usage <br>
--- ```
--- local vfs = file.vfs.create()
--- file.vfs.write_file(vfs, "scripts/main.lua", "content")
--- if file.vfs.is_file(vfs, "scripts/main.lua") then
---   print("It's a file")
--- end
--- ```
local function vfs_is_file(vfs, path)
	local value = vfs_get(vfs, path)
	return value ~= nil and type(value) == "string"
end

--- Delete a key at the specified path in the VFS.<br>
--- Removes the key and its value from the VFS structure.<br>
--- If the path is a directory, deletes it recursively including all contents.<br>
--- Returns nil and an error message if the operation fails.
---@param vfs table The VFS instance
---@param path string The path to delete (e.g., "scripts/old_file.lua" or "scripts/old_folder")
---@return boolean|nil success True on success, nil on failure
---@return string|nil error Error message if the operation failed
---@usage <br>
--- ```
--- local vfs = file.vfs.create()
--- file.vfs.write_file(vfs, "scripts/old.lua", "content")
--- local success, err = file.vfs.delete(vfs, "scripts/old.lua")
--- if success then
---   print("Deleted")
--- else
---   print("Error:", err)
--- end
--- -- Delete entire folder recursively
--- file.vfs.delete(vfs, "scripts/old_folder")
--- ```
local function vfs_delete(vfs, path)
	-- Normalize path
	path = string_normalize_path(path)

	-- Split path into components
	local parts = {}
	for part in string_gmatch(path, "[^/\\]+") do
		parts[#parts + 1] = part
	end

	if #parts == 0 then
		return nil, "invalid path"
	end

	-- Navigate to parent directory
	local current = vfs
	for i = 1, #parts - 1 do
		local key = parts[i]
		if not current[key] then
			-- Parent path doesn't exist
			return nil, "path component '" .. key .. "' does not exist"
		elseif type(current[key]) ~= "table" then
			-- Path component is a file, cannot traverse
			return nil, "path component '" .. key .. "' is a file, not a directory"
		end
		current = current[key]
	end

	-- Delete the final key
	local final_key = parts[#parts]
	if not current[final_key] then
		return nil, "path does not exist"
	end

	-- Recursively delete if it's a directory (table)
	if type(current[final_key]) == "table" then
		-- Delete all contents recursively
		for key in next, current[final_key] do
			current[final_key][key] = nil
		end
	end

	current[final_key] = nil
	return true
end

--- Recursive helper to flush a VFS node to disk.
---@param node table The VFS node (file content or directory table)
---@param current_path string The current disk path
---@param created_dirs table Set of already created directories to avoid redundant calls
local function vfs_flush_recursive(node, current_path, created_dirs)
	if type(node) == "string" then
		-- It's a file, write it
		write_file(current_path, node)
	elseif type(node) == "table" then
		-- It's a directory, create it and recurse
		if not created_dirs[current_path] then
			create_directory(current_path)
			created_dirs[current_path] = true
		end
		for name, child in next, node do
			local child_path = current_path .. "/" .. name
			vfs_flush_recursive(child, child_path, created_dirs)
		end
	end
end

--- Flush the VFS structure to disk.<br>
--- Writes all files and directories from the VFS to the actual file system.<br>
--- Uses the existing file API functions (create_directory, write_file).<br>
--- Returns nil and an error message if the operation fails.
---@param vfs table The VFS instance
---@param base_path string The base directory path on disk where to write the VFS
---@return boolean|nil success True on success, nil on failure
---@return string|nil error Error message if the operation failed
---@usage <br>
--- ```
--- local vfs = file.vfs.create()
--- file.vfs.write_file(vfs, "scripts/main.lua", "print('Hello')")
--- local success, err = file.vfs.flush(vfs, "my_package")
--- if success then
---   print("Flushed to disk")
--- else
---   print("Error:", err)
--- end
--- ```
local function vfs_flush(vfs, base_path)
	-- Ensure base path exists
	if not exists(base_path) then
		if not create_directory(base_path) then
			return nil, "failed to create base directory: " .. base_path
		end
	end

	local created_dirs = { [base_path] = true }
	vfs_flush_recursive(vfs, base_path, created_dirs)
	return true
end

--- Load a VFS from a real filesystem path.<br>
--- Reads files and directories from disk and populates a VFS structure.<br>
--- Uses the existing file API functions to recursively load the directory structure.
---@param base_path string The base directory path on disk to load from
---@return table|nil vfs The populated VFS instance, or nil on failure
---@return string|nil error Error message if the operation failed
---@usage <br>
--- ```
--- local vfs, err = file.vfs.load_from_disk("my_package")
--- if vfs then
---   print("Loaded VFS from disk")
---   -- Modify VFS in memory
---   file.vfs.set(vfs, "scripts/new.lua", "content")
---   -- Flush back to disk
---   file.vfs.flush(vfs, "my_package_modified")
--- else
---   print("Error:", err)
--- end
--- ```
local function vfs_load_from_disk(base_path)
	-- Check if base path exists
	if not exists(base_path) then
		return nil, "path does not exist: " .. base_path
	end

	-- Normalize base path
	base_path = string_normalize_path(base_path)

	-- Create VFS instance
	local vfs = {}

	-- Recursive helper to load from disk
	local function load_recursive(disk_path, vfs_node)
		-- Get all files in the directory
		local files = list_files(disk_path, "", -1)
		for i, file_path in next, files do
			-- Get the relative filename
			local filename = string_path_file(file_path)
			if filename and filename ~= "" then
				-- Read file content
				local content, err = read_file(file_path)
				if content then
					vfs_node[filename] = content
				elseif err then
					-- Log error but continue
					-- Could accumulate errors if needed
				end
			end
		end

		-- Get all directories and recurse
		local dirs = list_directories(disk_path, -1)
		for i, dir_path in next, dirs do
			local dirname = string_path_file(dir_path)
			if dirname and dirname ~= "" then
				-- Create directory node
				vfs_node[dirname] = {}
				-- Recurse into subdirectory
				load_recursive(dir_path, vfs_node[dirname])
			end
		end
	end

	-- Load the directory structure
	load_recursive(base_path, vfs)

	return vfs
end

-- VFS API
M.vfs = {
	create = vfs_create,
	write_file = vfs_write_file,
	write_directory = vfs_write_directory,
	flush = vfs_flush,
	load_from_disk = vfs_load_from_disk,
	get = vfs_get,
	set = vfs_set,
	exists = vfs_exists,
	is_directory = vfs_is_directory,
	is_file = vfs_is_file,
	delete = vfs_delete,
}

-- Export the API to be accessed by other packages
return M
