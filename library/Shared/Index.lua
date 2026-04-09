-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- TODO: Build DSL for dependency graph & automatic loader for loading modules/packages/dependencies...
-- TODO: HTTP/GitHub package importing (for dynamic/zipped modules, etc.)

--for _, f in next, Package.GetFiles(nil, ".lua") do
--	print("[package file]", f)
--end

-- Patch 'require' function like a good boi
if "INTERNAL - Package Lua Implementation" == debug.getinfo(require, "S").source then
	require = require("@cheatoid/patch/require.lua")
end

-- Import dependencies
local gaimers = require("@cheatoid/loader/gaimers")
gaimers.r = require

-- Globally export GAIMERS + require for convenience
_G.GAIMERS = gaimers
_G.r = require

-- Localized global functions for better performance
local g, a, i, m, e, r, s = gaimers.g, gaimers.a, gaimers.i, gaimers.m, gaimers.e, gaimers.r, gaimers.s

----------------------------------------------------------------------
-- TODO: Auto initialize modules/packages, add dependency injection...
----------------------------------------------------------------------

-- As much as I like my custom loader GAIMERS, it is not fully cooperative with LuaLS...
-- So I am rethinking my approach and will use the standard require function instead;
-- Most likely, I will end up making a custom script that will "compile" the dependency graph,
-- use the standard require function to load them, in order to have proper editor navigation...

local Version = require("Version")
local packageName = Package.GetName()
--print("package name: " .. packageName)
--print("local package version: " .. Package.GetVersion())
print("local package version: " .. tostring(Version.getCurrent()))

local packageMetadata = require("metadata_gen")
local packagePath = packageMetadata.path
print("metadata path: " .. packagePath)
print("metadata numver: " .. packageMetadata.num_version)
print("metadata tag: " .. packageMetadata.tag)
print("metadata timestamp: " .. packageMetadata.timestamp)

if Server then
	local http = require("HttpWrapper")
	local zip = require("@cheatoid/standalone/zip")
	local tsl = require("@cheatoid/standalone/to_string_literal")
	http.get(
		string.format("https://api.nanos-world.com/store/packages/%s", packageName),
		function(data, status, url)
			print("vault/store status: " .. status)
			print("vault/store data:")
			print(tsl.to_string_literal(data))
			pcall(function()
				local parsedJson = JSON.parse(data)
				local storeVersion = parsedJson.payload.version.version
				print("vault/store version: " .. storeVersion)
			end)
		end
	)
	http.get(
		string.format(
		--"https://github.com/%s/%s/raw/refs/heads/main/%s/Shared/metadata_gen.lua",
			"https://raw.github.com/%s/%s/main/%s/Shared/metadata_gen.lua", -- shorter
			packageMetadata.owner,
			packageMetadata.repo,
			packagePath
		),
		function(data, status, url)
			print("github status: " .. status)
			print("github data:")
			print(tsl.to_string_literal(data))
			pcall(function()
				local githubMetadata = load(data)() ---@type metadata_gen
				local githubNumVer, githubPrevHash, githubTag =
					githubMetadata.num_version, githubMetadata.prev_hash, githubMetadata.tag
				print("github latest numver: " .. githubNumVer)
				print("github prev hash: " .. githubPrevHash)
				print("github latest tag: " .. githubTag)
				http.get(
					string.format(
						"https://github.com/%s/%s/releases/download/%s/%s.zip",
						githubMetadata.owner or "Cheatoid",
						githubMetadata.repo or "nanos-world-vault",
						githubTag,
						packageName
					),
					function(zipData, zipStatus, zipUrl)
						print("latest zip status: " .. zipStatus)
						print("latest zip size: " .. #zipData .. " bytes")
					end
				)
			end)
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

r "Config"
m "@cheatoid/standalone/debug_helper"
m "@cheatoid/standalone/type_check"
r "RequireFolder"
i "ConVar"
g "oop" "@cheatoid/oop/oop"
m "BroadcastLua"
r "ClientsideLua"

--[[
Reminder to myself: Package-Release cycle

0. for simplicity: run .\.scripts\ver.ps1 -next

1. increase version in `Package.toml`
2. create a version commit `v{version from Package.toml}`, and locally tag the commit
3. make code changes and commit all staged changes
4. run packager (regenerates `metadata_gen.lua`), stage all `metadata_gen.lua` files

(tag exists to enable locally staged version at this point, it has to exist to have correct versioning)

when ready to release it:
5. remove the previously created local tag (created in step 2.)
6. run packager again (regenerates `metadata_gen.lua`), stage all `metadata_gen.lua` files, and then commit+push
7. create a tag on the pushed commit from previous step 6 (use the same version as in step 2.)
8. push the tag
]]
