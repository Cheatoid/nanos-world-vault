-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

local pcall = pcall
local type = type
local string_find = string.find
--local string_match = string.match
local string_sub = string.sub
local Server_GetPackages = Server.GetPackages
local Server_IsPackageLoaded = Server.IsPackageLoaded
local Server_LoadPackage = Server.LoadPackage
local Server_ReloadPackage = Server.ReloadPackage
local Server_UnloadPackage = Server.UnloadPackage

--- @class PackageHelper
--- Package management utility library for Nanos World.
--- Provides console commands & functions for loading, unloading, and reloading packages with pattern matching support.
local self = {
	--- Prefix for pattern matching mode
	--- @type string
	PatternPrefix = ":"
}

--- Validates if a package name is properly formatted.
--- @param name string The package name to validate.
--- @return boolean boolean True if the name is valid, false otherwise.
local function IsPackageNameValid(name)
	return name and type(name) == "string" --and string_match(name, "^[%w%-%._]*$")
end
self.HasValidName = IsPackageNameValid

--- Retrieves all available packages as a lookup table.
--- @return table table A table with package names as keys and package objects as values.
local function GetAllPackages()
	local array = Server_GetPackages(false, -1)
	local lookup = {}
	for _, p in next, array do
		lookup[p.name] = p
	end
	return lookup
end
self.GetAll = GetAllPackages

--- Checks if a package with the given name exists.
--- @param name string The package name to check.
--- @return boolean boolean True if the package exists, false otherwise.
local function PackageExists(name)
	return GetAllPackages()[name] ~= nil
end
self.Exists = PackageExists

--- Finds packages matching a name or pattern.
--- Supports exact name matching and pattern matching (when name starts with PatternPrefix).
--- @param name string The package name or pattern to match.
--- @return table table A table of matching package names.
local function GetMatchingPackages(name)
	local matches = {}
	if type(name) == "string" then
		-- Check if we should use pattern matching mode
		if string_sub(name, 1, 1) == (self.PatternPrefix or ":") then
			local searchPattern = string_sub(name, 2) -- Remove the pattern prefix char
			for _, p in next, Server_GetPackages(false, -1) do
				if string_find(p.name, searchPattern, nil, true) then
					matches[#matches + 1] = p.name
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
--- @param onlyLoaded boolean|nil Whether to only reload loaded packages (default: true).
--- @param typeFilter integer|nil Package type filter (default: -1 for all types).
local function ReloadAllPackages(onlyLoaded, typeFilter)
	if onlyLoaded == nil then onlyLoaded = true end
	if typeFilter == nil then typeFilter = -1 end -- PackageType.* or -1 for all
	for _, p in next, Server_GetPackages(onlyLoaded, typeFilter) do
		--Console_RunCommand("package reload " .. p.name)
		pcall(Server_ReloadPackage, p.name)
	end
end
self.ReloadAll = ReloadAllPackages

--- Reloads specified packages or all packages if none specified.
--- Supports pattern matching for multiple packages.
--- @param ... string Variable number of package names or patterns to reload.
local function ReloadPack(...)
	if select("#", ...) == 0 then
		--Console_RunCommand("package reload all")
		ReloadAllPackages()
	else
		for _, name in next, { ... } do
			local matches = GetMatchingPackages(name)
			for _, match in next, matches do
				--Console_RunCommand("package reload " .. match)
				if Server_IsPackageLoaded(match) then
					pcall(Server_ReloadPackage, match)
				else
					pcall(Server_LoadPackage, match)
				end
			end
		end
	end
end
self.Reload = ReloadPack

--- Loads specified packages or all packages if none specified.
--- Supports pattern matching for multiple packages.
--- @param ... string Variable number of package names or patterns to load.
local function LoadPack(...)
	if select("#", ...) == 0 then
		--Console_RunCommand("package load all")
		for _, p in next, Server_GetPackages(false, -1) do
			--if not Server_IsPackageLoaded(p.name) then
			pcall(Server_LoadPackage, p.name)
			--end
		end
	else
		for _, name in next, { ... } do
			local matches = GetMatchingPackages(name)
			for _, match in next, matches do
				--Console_RunCommand("package load " .. match)
				--if not Server_IsPackageLoaded(match) then
				pcall(Server_LoadPackage, match)
				--end
			end
		end
	end
end
self.Load = LoadPack

--- Unloads specified packages or all loaded packages if none specified.
--- Supports pattern matching for multiple packages.
--- @param ... string Variable number of package names or patterns to unload.
local function UnloadPack(...)
	if select("#", ...) == 0 then
		--Console_RunCommand("package unload all")
		local result = Server_GetPackages(true, -1)
		for _, p in next, result do
			--Console_RunCommand("package unload " .. p.name)
			pcall(Server_UnloadPackage, p.name)
		end
	else
		for _, name in next, { ... } do
			local matches = GetMatchingPackages(name)
			for _, match in next, matches do
				--Console_RunCommand("package unload " .. match)
				--if Server_IsPackageLoaded(match) then
				pcall(Server_UnloadPackage, match)
				--end
			end
		end
	end
end
self.Unload = UnloadPack

-- Register console commands
Console.RegisterCommand("reload", ReloadPack, "reload a specific package or all")
Console.RegisterCommand("load", LoadPack, "load a specific package or all")
Console.RegisterCommand("unload", UnloadPack, "unload a specific package or all")

-- Export the API to be accessed by other packages
_G.PackageHelper = self
Package.Export("PackageHelper", self)
return self
