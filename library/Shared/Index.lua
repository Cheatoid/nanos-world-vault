-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Patch 'require' function like a good boi
if "INTERNAL - Package Lua Implementation" == debug.getinfo(require, "S").source then
	_G.include = require -- preserve original 'require' function as global 'include'
	_ENV.include = require
	require = require "@cheatoid/patch/require.lua"
end

-- Import dependencies
local gaimers = require "@cheatoid/loader/gaimers"
gaimers.r = require

-- Globally export GAIMERS + require for convenience
--_G.GAIMERS = gaimers
--_G.r = require

-- Localized global functions for better performance
--local g, a, i, m, e, r, s = gaimers.g, gaimers.a, gaimers.i, gaimers.m, gaimers.e, gaimers.r, gaimers.s

----------------------------------------------------------------------
-- TODO: Auto initialize modules/packages, add dependency injection...
----------------------------------------------------------------------

local SERVER = type(Server) == "table"
local CLIENT = type(Client) == "table"
--print("SERVER:" .. tostring(SERVER), "CLIENT:" .. tostring(CLIENT))

local package_metadata = require "metadata_gen"
local package_path = package_metadata.path
local is_preview = string.find(package_metadata.tag, "-", nil, true) ~= nil
local function debug_print(...)
	if is_preview then
		print(string.format(...))
	end
end

if is_preview then
	Console.Warn("preview version detected; some features may not work")
end

local Version = require "Version"
local package_name = Package.GetName()
--log("package name: %s", package_name)
--log("local package version: %s", Package.GetVersion())
print("local package version: " .. tostring(Version.getCurrent()))
debug_print("metadata path: %s", package_path)
print("metadata version: " .. package_metadata.package_version)
print("metadata tag: " .. package_metadata.tag)
debug_print("metadata timestamp: %s", package_metadata.timestamp)
debug_print("metadata branch: %s", package_metadata.branch_name)

-- Pre-load modules to cache them and prevent runtime errors.
-- As a library, we only ensure modules are pre-loaded.
-- Consumers will receive the cached values.
-- Consumers should use GAIMERS or Package.Export to expose them globally.

--for _, f in next, Package.GetFiles(nil, ".lua") do
--	debug_print("[package file]", f)
--end

--for f, hash in next, package_metadata.files_hash do
--end

--local dbg = require "@cheatoid/standalone/debug_helper"
--dbg.debugger.on_hook(function(info, line, event)
--	print("Event:", event, "at", info.source .. ":" .. line)
--end)
--dbg.debugger.enable("clr", 0)

local requiref = require "RequireFolder"
requiref "Shared/@cheatoid" {
	-- NOTE: *.d.lua are automatically ignored
	--[0] = require("FileWrapper").vfs, -- pass VFS instance at index 0
	"@cheatoid/standard",
	"@cheatoid/standalone",
	--["@cheatoid/patch/require.lua"] = false, -- ignore; it shouldn't hurt to require it again tho
	["%.tests%.lua$"] = false,                               -- skip all files ending in .tests.lua
	["@cheatoid/extensions/.*"] = false,                     -- ignore; extensions must be explicitly loaded because they modify default Lua types
	["@cheatoid/require_finder/find_requires%.lua$"] = false, -- ignore
	["@cheatoid/plugin_framework/example_usage%.lua$"] = false, -- ignore
	["@cheatoid/plugin_framework/hello_plugin%.lua$"] = false, -- ignore
}

--dbg.debugger.disable()

-- @formatter:off
local dbg     = require "@cheatoid/standalone/debug_helper"
local tc      = require "@cheatoid/standalone/type_check"
local tsl     = require "@cheatoid/standalone/to_string_literal"
local patcher = require "@cheatoid/standalone/patcher"
local util    = require "@cheatoid/standalone/util"
local xml     = require "@cheatoid/standalone/xml"
local zip     = require "@cheatoid/standalone/zip"
local cfg     = require "@cheatoid/standalone/cfg_parser"
local plugins = require "@cheatoid/plugin_framework/plugin_framework"
local oop     = require "@cheatoid/oop/oop"
local ref     = require "@cheatoid/ref/ref"
local vm      = require "@cheatoid/vm/vm"
local config  = require "Config"
local file    = require "FileWrapper"
local vfs     = file.vfs
local http    = require "HttpWrapper"
local ConVar  = require "ConVar"
require "BroadcastLua"
require "ClientsideLua"
--require "@cheatoid/extensions/number"
--require "@cheatoid/extensions/string"
-- @formatter:on

if SERVER then
	local target_url = string.format("https://api.nanos-world.com/store/packages/%s", package_name)
	debug_print("asset store url: %q", target_url)
	-- TODO: use async/await from oop to avoid callback hell
	http.get(
		target_url,
		function(data, status, url)
			debug_print("[asset store] status: %s, url: %q, size: %d", status, url, #data)
			pcall(function()
				local parsedJson = JSON.parse(data)
				local storeVersion = parsedJson.payload.version.version
				print("vault/store version: " .. storeVersion)
				if Version.parse(storeVersion):isOlderThan(Version.getCurrent()) then
					is_preview = true
					Console.Warn("preview version detected; some features may not work")
				end
			end)
		end,
		function(data, status, url)
			debug_print("[asset store] status: %s, url: %q, data: %q", status, url, data)
		end
	)
	-- "https://raw.github.com/%s/%s/main/VERSION" -- latest repo release version
	--target_url = "https://raw.github.com/Cheatoid/nanos-world-vault/main/VERSION"
	-- "https://github.com/%s/%s/releases.atom" -- release feed xml
	--target_url = "https://github.com/Cheatoid/nanos-world-vault/releases.atom"
	target_url = string.format(
	--"https://github.com/%s/%s/raw/refs/heads/%s/%s/Shared/metadata_gen.lua",
		"https://raw.github.com/%s/%s/%s/%s/Shared/metadata_gen.lua", -- shorter
		package_metadata.owner,
		package_metadata.repo,
		package_metadata.branch_name,
		package_path
	)
	debug_print("github metadata url: %q", target_url)
	http.get(
		target_url,
		function(data, status, url)
			debug_print("[github metadata] status: %s, url: %q, size: %d", status, url, #data)
			pcall(function()
				local githubMetadata = load(data)() ---@type metadata_gen
				local githubVersion, githubCommitCount, githubTagCount, githubTag, githubPrevHash =
					githubMetadata.package_version, githubMetadata.commit_count, githubMetadata.tag_count,
					githubMetadata.tag, githubMetadata.prev_hash
				print("github metadata version: " .. githubVersion)
				debug_print("github tag count: %s", githubTagCount)
				debug_print("github prev hash: %s", githubPrevHash)
				print("github metadata tag: " .. githubTag)
				-- Fetch the actual latest version from VERSION file
				local versionUrl = string.format(
					"https://raw.github.com/%s/%s/main/VERSION",
					githubMetadata.owner or "Cheatoid",
					githubMetadata.repo or "nanos-world-vault"
				)
				debug_print("fetching latest repo version: %q", versionUrl)
				http.get(
					versionUrl,
					function(versionData, versionStatus, versionUrl)
						debug_print("[repo version] status: %s, data: %q", versionStatus, versionData)
						local latestVersion = versionStatus == 200 and
							versionData:match("^v?([%d%.]+)") -- NOTE: repo version should always be stable
						if not latestVersion then
							print("failed to fetch repo version, falling back to metadata tag: " .. githubTag)
							latestVersion = githubTag
						else
							print("latest repo version: " .. latestVersion)
						end
						http.get(
							string.format(
								"https://github.com/%s/%s/releases/download/%s/%s.zip",
								githubMetadata.owner or "Cheatoid",
								githubMetadata.repo or "nanos-world-vault",
								latestVersion,
								package_name
							),
							function(zipData, zipStatus, zipUrl)
								debug_print("latest zip status: %s", zipStatus)
								debug_print("latest zip size: %d bytes", #zipData)
								-- TODO: save to temporary downloads folder, and then extract via zip library
								-- TODO/CONS: use vfs to store/load code instead of extracting zip to disk?
							end,
							function(data, status, url)
								debug_print("[github zip] status: %s, url: %q, data: %q", status, url, data)
							end
						)
					end,
					function(data, status, url)
						debug_print("[github version] failed - status: %s, url: %q", status, url)
						-- Fallback: use githubTag from metadata
						http.get(
							string.format(
								"https://github.com/%s/%s/releases/download/%s/%s.zip",
								githubMetadata.owner or "Cheatoid",
								githubMetadata.repo or "nanos-world-vault",
								githubTag,
								package_name
							),
							function(zipData, zipStatus, zipUrl)
								debug_print("latest zip status: %s", zipStatus)
								debug_print("latest zip size: %d bytes", #zipData)
							end,
							function(data, status, url)
								debug_print("[github zip] status: %s, url: %q, data: %q", status, url, data)
							end
						)
					end
				)
			end)
		end,
		function(data, status, url)
			debug_print("[github metadata] status: %s, url: %q, data: %q", status, url, data)
		end
	)
end

-- TODO: Automatic updates, because "upload to store" is a painful process

--do
--	local filename = string.format("test_%s.txt", Server and "server" or "client")
--	print("Creating " .. filename)
--	local testfile = File(filename, true)
--	testfile:Write(string.format("Hello %s\n", Server and "Server" or "Client"))
--	testfile:Flush()
--	testfile:Close()
--	print("Created " .. filename)
--end

--[[
Reminder to myself: Package-Release cycle

0. for simplicity: run .\.scripts\ver.ps1 -next

1. increase version in `Package.toml`
2. create a version commit `v{version from Package.toml}`, and locally tag the commit
3. make code changes and commit all staged changes
4. run packager (regenerates `metadata_gen.lua`), stage all `metadata_gen.lua` files

(tag exists to enable locally staged version at this point, it has to exist to have correct versioning)

when ready to release it:
(make sure all changes are committed and pushed)
5. remove the previously created local tag (created in step 2.)
6. run packager again (regenerates `metadata_gen.lua`), stage all `metadata_gen.lua` files, and then commit+push
7. create a tag on the pushed commit from previous step 6 (use the same version as in step 2.)
8. push the tag
]]
