-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

--for _, f in next, Package.GetFiles(nil, ".lua") do
--	print("[package file]", f)
--end

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

local Version = require "Version"
local packageName = Package.GetName()
--print("package name: " .. packageName)
--print("local package version: " .. Package.GetVersion())
print("local package version: " .. tostring(Version.getCurrent()))

local packageMetadata = require "metadata_gen"
local packagePath = packageMetadata.path
print("metadata path: " .. packagePath)
print("metadata version: " .. packageMetadata.package_version)
print("metadata tag: " .. packageMetadata.tag)
print("metadata timestamp: " .. packageMetadata.timestamp)
print("metadata branch: " .. packageMetadata.branch_name)

local SERVER = type(Server) == "table"
local CLIENT = type(Client) == "table"
--print(SERVER, CLIENT)

if SERVER then
	local http = require "HttpWrapper"
	local xml = require "@cheatoid/standalone/xml"
	local zip = require "@cheatoid/standalone/zip"
	local tsl = require "@cheatoid/standalone/to_string_literal"
	local target_url = string.format("https://api.nanos-world.com/store/packages/%s", packageName)
	print("asset store url: " .. target_url)
	http.get(
		target_url,
		function(data, status, url)
			print("[asset store http]", status, url, "size: " .. #data)
			pcall(function()
				local parsedJson = JSON.parse(data)
				local storeVersion = parsedJson.payload.version.version
				print("vault/store version: " .. storeVersion)
			end)
		end,
		function(data, status, url)
			print("[asset store http]", status, url, data)
		end
	)
	-- "https://raw.github.com/%s/%s/main/VERSION" -- latest repo release version
	--target_url = "https://raw.github.com/Cheatoid/nanos-world-vault/main/VERSION"
	-- "https://github.com/%s/%s/releases.atom" -- release feed xml
	--target_url = "https://github.com/Cheatoid/nanos-world-vault/releases.atom"
	target_url = string.format(
	--"https://github.com/%s/%s/raw/refs/heads/%s/%s/Shared/metadata_gen.lua",
		"https://raw.github.com/%s/%s/%s/%s/Shared/metadata_gen.lua", -- shorter
		packageMetadata.owner,
		packageMetadata.repo,
		packageMetadata.branch_name,
		packagePath
	)
	print("github url: " .. target_url)
	http.get(
		target_url,
		function(data, status, url)
			print("[github repo http]", status, url, "size: " .. #data)
			pcall(function()
				local githubMetadata = load(data)() ---@type metadata_gen
				local githubVersion, githubCommitCount, githubTagCount, githubTag, githubPrevHash =
					githubMetadata.package_version, githubMetadata.commit_count, githubMetadata.tag_count,
					githubMetadata.tag, githubMetadata.prev_hash
				print("github version: " .. githubVersion)
				print("github tag count: " .. githubTagCount)
				print("github prev hash: " .. githubPrevHash)
				print("github latest tag: " .. githubTag)
				http.get(
					string.format(
						"https://github.com/%s/%s/releases/download/%s/%s.zip",
						githubMetadata.owner or "Cheatoid",
						githubMetadata.repo or "nanos-world-vault",
						githubTag, -- TODO/FIXME: this should be using repo VERSION
						packageName
					),
					function(zipData, zipStatus, zipUrl)
						print("latest zip status: " .. zipStatus)
						print("latest zip size: " .. #zipData .. " bytes")
					end
				)
			end)
		end,
		function(data, status, url)
			print("[github repo http]", status, url, data)
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

-- Pre-load modules to cache them and prevent runtime errors.
-- As a library, we only ensure modules are pre-loaded.
-- Consumers will receive the cached values.
-- Consumers should use GAIMERS or Package.Export to expose them globally.

local requiref = require "RequireFolder"
requiref "@cheatoid/standard"

require "@cheatoid/standalone/debug_helper"
require "@cheatoid/standalone/type_check"
require "@cheatoid/oop/oop"
require "Config"
require "ConVar"
require "BroadcastLua"
require "ClientsideLua"
require "HttpWrapper"

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
