-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

--local pack_name = '"version:' .. Package.GetName() .. '"'
--local pack_version = Package.GetVersion()
--print("cheatoid library pre-check", _G[pack_name])
--if _G[pack_name] == pack_version then return end
--if Package.GetPersistentData(pack_name) == pack_version then return end
--print("cheatoid library pre-check survived", pack_version)

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
	Console.Warn("Preview version detected; some features may not work")
end

local Version = require "Version"
local package_name = Package.GetName()
--log("package name: %s", package_name)
--log("package version: %s", Package.GetVersion())
print("package version: " .. tostring(Version.getCurrent()))
local branch_name = package_metadata.branch_name or "main"
debug_print("metadata path: %s", package_path)
print("metadata version: " .. package_metadata.package_version)
print("metadata tag: " .. package_metadata.tag)
debug_print("metadata timestamp: %s", package_metadata.timestamp)
debug_print("metadata branch: %s", branch_name)

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
	["%.tests%.lua$"] = false,                               -- skip all files ending in .tests.lua
	["@cheatoid/extensions/.*"] = false,                     -- skip; extensions must be explicitly loaded because they modify default Lua types
	["@cheatoid/patch/.*"] = false,                          -- skip; patches must be explicitly loaded
	["/?examples?%.lua$"] = false,                           -- ignore examples
	["@cheatoid/require_finder/find_requires%.lua$"] = false, -- ignore
	["@cheatoid/plugin_framework/example_usage%.lua$"] = false, -- ignore
	["@cheatoid/plugin_framework/hello_plugin%.lua$"] = false, -- ignore
	["@cheatoid/standard/global%.lua$"] = false,             -- ignore (let consumers explicitly load it)
}

--dbg.debugger.disable()

-- @formatter:off
local dbg          = require "@cheatoid/standalone/debug_helper"
local tc           = require "@cheatoid/standalone/type_check"
local istype       = require "@cheatoid/standalone/istype"
local tsl          = require "@cheatoid/standalone/to_string_literal"
local patcher      = require "@cheatoid/standalone/patcher"
local util         = require "@cheatoid/standalone/util"
local xml          = require "@cheatoid/standalone/xml"
local zip          = require "@cheatoid/standalone/zip"
local cfg          = require "@cheatoid/standalone/cfg_parser"
local benchmark    = require "@cheatoid/benchmark/init"
local collections  = require "@cheatoid/collections/init"
local plugins      = require "@cheatoid/plugin_framework/plugin_framework"
local rate_limiter = require "@cheatoid/rate_limiter/rate_limiter"
local oop          = require "@cheatoid/oop/oop"
local ref          = require "@cheatoid/ref/ref"
local vm           = require "@cheatoid/vm/vm"
local config       = require "Config"
local file         = require "FileWrapper"
local vfs          = file.vfs
local http         = require "HttpWrapper"
local ConVar       = require "ConVar"
require "BroadcastLua"
require "ClientsideLua"
--require "@cheatoid/extensions/number"
--require "@cheatoid/extensions/string"
-- @formatter:on

--_G[Package.GetName()] = Package.GetVersion()

--_G[pack_name] = pack_version
--Package.SetPersistentData(pack_name, pack_version)
--Package.FlushSetPersistentData()

local updater = require "AutoUpdater"

if SERVER then
	-- Initialize AutoUpdater
	local update = updater.new {
		debug = is_preview,
		check_asset_store = true,
		auto_download = false,
		on_check_start = function()
			debug_print("Starting update check...")
		end,
		on_update_available = function(remote_version, current_version, metadata)
			print(string.format("[AutoUpdater] Update available: %s -> %s", current_version, remote_version))
			print("[AutoUpdater] Remote commit count: " .. (metadata.commit_count or "unknown"))
			print("[AutoUpdater] Remote tag: " .. (metadata.tag or "unknown"))
		end,
		on_no_update = function(current_version)
			debug_print("[AutoUpdater] Already up to date: %s", current_version)
		end,
		on_download_complete = function(zip_data, version)
			debug_print("[AutoUpdater] Downloaded update %s (%d bytes)", version, #zip_data)
			-- TODO: Save to temporary downloads folder, and then extract via Zip library
			-- TODO/CONS: Use VFS to store/load code instead of extracting zip to disk?
		end,
		on_error = function(err, context)
			Console.Warn(string.format("[AutoUpdater] Error in %s: %s", context, err))
		end,
		on_check_complete = function()
			debug_print("Update check completed")
		end,
	}
	-- Start the update check
	update:checkForUpdates()
end

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

To start a new version simply double-click, or run .\.scripts\ver.ps1
(tag exists to enable locally staged version at this point, it has to exist to have correct versioning)

When ready to release it:
Simply double-click, or run .\.scripts\release.cmd
It will automatically handle everything:
Push changes, make github release, upload packages to store and start a new version... 😎
]]
