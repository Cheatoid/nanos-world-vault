-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Localized global functions for better performance
local next = next
local pcall = pcall
local select = select
local type = type
local string_find = string.find
--local string_match = string.match
local string_sub = string.sub
local File_Exists = File.Exists
local Client_GetPackages = Client and Client.GetPackages
local Server_GetPackages = Server and Server.GetPackages

--- Package management utility library for Nanos World.<br>
--- Provides console commands & functions for loading, unloading, and reloading packages with pattern matching support.
---@class PackageHelper
---@field PatternPrefix string
local self = {
	--- Prefix for pattern matching mode
	---@type string
	PatternPrefix = ":"
}

--- Validates if a package name is properly formatted.
---@param name string The package name to validate.
---@return boolean boolean True if the name is valid, false otherwise.
local function IsPackageNameValid(name)
	return name and type(name) == "string" --and (string_match(name, "^[%w%-%._]*$")) or false
end

self.HasValidName = IsPackageNameValid

---@alias PackageInfoTable { title: string, name: string, type: PackageType, version: string, author: string }

--- Retrieves all available packages as a lookup table.
---@param onlyLoaded? boolean (Server only) Whether to only consider loaded packages (default: true).
---@return table<string, PackageInfoTable> packages A table with package names as keys and package objects as values.
local function GetAllPackages(onlyLoaded)
	local lookup = {}
	if Server_GetPackages then
		for _, p in next, Server_GetPackages(onlyLoaded ~= false) do
			lookup[p.name] = p
		end
	elseif Client_GetPackages then
		for _, p in next, Client_GetPackages() do
			lookup[p.name] = p
		end
	end
	return lookup
end

self.GetAll = GetAllPackages

--- Retrieves all packages' names (from filesystem).
---@return string[] names
local function GetPackageNames()
	local names = {}
	for _, path in next, File.GetDirectories("Packages", 0) do
		local name = string.basename(path)
		local packagePath = Server and (path .. "Package.toml") or ("../" .. name .. "/Package.toml")
		if File_Exists(packagePath) then
			names[#names + 1] = name
		end
	end
	return names
end

self.GetPackageNames = GetPackageNames

--- Checks if a package with the given name exists.
---@param name string The package name to check.
---@return boolean boolean True if the package exists, false otherwise.
local function PackageExists(name)
	return GetAllPackages()[name] ~= nil
end

self.Exists = PackageExists

--- Finds packages matching a name or pattern.<br>
--- Supports exact name matching and pattern matching (when name starts with `PatternPrefix`).
---@param name string The package name or pattern to match.
---@return string[] names A table of matching package names.
local function GetMatchingPackages(name)
	local matches = {}
	if type(name) == "string" then
		-- Check if we should use pattern matching mode
		if string_sub(name, 1, 1) == (self.PatternPrefix or ":") then
			local searchPattern = string_sub(name, 2) -- Remove the pattern prefix char
			for packageName in next, GetAllPackages(false) do
				if string_find(packageName, searchPattern, nil, true) then
					matches[#matches + 1] = packageName
				end
			end
			return matches
		end
		-- Exact name match
		if PackageExists(name) then
			return { name }
		end
	end
	return matches
end

self.Match = GetMatchingPackages

--- Reloads all packages with optional filtering.
---@param onlyLoaded? boolean Whether to only reload loaded packages (default: true).
---@param typeFilter? integer Package type filter (default: -1 for all types).
local function ReloadAllPackages(onlyLoaded, typeFilter)
	--if typeFilter == nil then typeFilter = -1 end -- PackageType.* or -1 for all
	for _, p in next, Server.GetPackages(onlyLoaded ~= false, typeFilter) do
		--Console.RunCommand("package reload " .. p.name)
		pcall(Server.ReloadPackage, p.name)
	end
end

self.ReloadAll = ReloadAllPackages

--- Reloads specified packages or all packages if none specified.<br>
--- Supports pattern matching for multiple packages.
---@param ... string Variable number of package names or patterns to reload.
local function ReloadPack(...)
	if select("#", ...) == 0 then
		--Console_RunCommand("package reload all")
		ReloadAllPackages()
	else
		for _, name in next, { ... } do
			local matches = GetMatchingPackages(name)
			for _, match in next, matches do
				--Console_RunCommand("package reload " .. match)
				if Server.IsPackageLoaded(match) then
					pcall(Server.ReloadPackage, match)
				else
					pcall(Server.LoadPackage, match)
				end
			end
		end
	end
end

self.Reload = ReloadPack

--- Loads specified packages or all packages if none specified.<br>
--- Supports pattern matching for multiple packages.
---@param ... string Variable number of package names or patterns to load.
local function LoadPack(...)
	if select("#", ...) == 0 then
		--Console.RunCommand("package load all")
		for _, p in next, Server.GetPackages(false) do
			--if not Server.IsPackageLoaded(p.name) then
			pcall(Server.LoadPackage, p.name)
			--end
		end
	else
		for _, name in next, { ... } do
			local matches = GetMatchingPackages(name)
			for _, match in next, matches do
				--Console.RunCommand("package load " .. match)
				--if not Server.IsPackageLoaded(match) then
				pcall(Server.LoadPackage, match)
				--end
			end
		end
	end
end

self.Load = LoadPack

--- Unloads specified packages or all loaded packages if none specified.<br>
--- Supports pattern matching for multiple packages.
---@param ... string Variable number of package names or patterns to unload.
local function UnloadPack(...)
	if select("#", ...) == 0 then
		--Console_RunCommand("package unload all")
		local result = Server.GetPackages(true)
		for _, p in next, result do
			--Console.RunCommand("package unload " .. p.name)
			pcall(Server.UnloadPackage, p.name)
		end
	else
		for _, name in next, { ... } do
			local matches = GetMatchingPackages(name)
			for _, match in next, matches do
				--Console.RunCommand("package unload " .. match)
				--if Server.IsPackageLoaded(match) then
				pcall(Server.UnloadPackage, match)
				--end
			end
		end
	end
end

self.Unload = UnloadPack

local PackageName = Package.GetName()

--- Reload the cheatoid-library package itself.<br>
--- Useful for development to quickly reload changes during development.
local function ReloadLib()
	Server.ReloadPackage(PackageName)
end

self.ReloadLib = ReloadLib

-- Register console commands
Console.RegisterCommand("reloadlib", ReloadLib,
	"Reload " .. PackageName)
Console.RegisterCommand("reload", ReloadPack,
	"Reload a specific package or all, use colon (:) prefix for pattern-matching mode")
Console.RegisterCommand("load", LoadPack,
	"Load a specific package or all, use colon (:) prefix for pattern-matching mode")
Console.RegisterCommand("unload", UnloadPack,
	"Unload a specific package or all, use colon (:) prefix for pattern-matching mode")

-- Export the API to be accessed by other packages
return self
