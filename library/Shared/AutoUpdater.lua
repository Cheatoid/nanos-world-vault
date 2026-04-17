-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Auto-update engine

-- Localized global functions for better performance
local pcall = pcall
local setmetatable = setmetatable
local string_find = string.find
local string_format = string.format
local string_match = string.match
local string_sub = string.sub

-- Import dependencies
local Version = require "Version"
local http = require "HttpWrapper"
local tsl = require "@cheatoid/standalone/to_string_literal"

--- Configuration options for the AutoUpdater.<br>
--- All fields are optional and will fall back to values from metadata_gen.lua or sensible defaults.
---@class AutoUpdaterConfig
---@field owner string|nil GitHub repository owner (default: from metadata_gen)
---@field repo string|nil GitHub repository name (default: from metadata_gen)
---@field branch string|nil Branch to check for updates (default: from metadata_gen or "main")
---@field package_path string|nil Path in repo to metadata_gen.lua (default: from metadata_gen)
---@field package_name string|nil Package name for zip download (default: Package.GetName())
---@field check_asset_store boolean|nil Whether to check nanos-world asset store API (default: true)
---@field auto_download boolean|nil Whether to automatically download updates (default: false)
---@field debug boolean|nil Enable debug logging (default: false)
---@field on_update_available fun(remote_version: string, current_version: string, metadata: table)|nil Callback when update is available
---@field on_no_update fun(current_version: string)|nil Callback when no update is available
---@field on_download_complete fun(zip_data: string, version: string)|nil Callback when zip download completes
---@field on_error fun(err: string, context: string)|nil Callback on errors
---@field on_check_start fun()|nil Callback when update check starts
---@field on_check_complete fun()|nil Callback when update check completes

--- Auto-update engine for GitHub-based packages using metadata_gen.lua.<br>
--- This module provides a clean API for checking for updates, downloading release zips,<br>
--- and handling version comparisons without callback hell.
---@class AutoUpdater
---@field config AutoUpdaterConfig Configuration options for the updater
---@field current_metadata table Local metadata_gen.lua data
---@field current_version string Current package version
---@field remote_metadata table|nil Remote metadata_gen.lua data (after fetch)
---@field remote_version string|nil Remote package version (after fetch)
---@field latest_version string|nil Latest release version (after fetch)
---@field is_preview boolean Whether running a preview version
local AutoUpdater = {}
AutoUpdater.__index = AutoUpdater

--- Creates a new AutoUpdater instance with the specified configuration.<br>
--- If config fields are nil, they will be automatically populated from metadata_gen.lua.
---@usage <br>
--- ```
--- local updater = AutoUpdater.new({
---   debug = true,
---   auto_download = false,
---   on_update_available = function(remote, current, meta)
---     print("Update available: " .. remote)
---   end
--- })
--- updater:checkForUpdates()
--- ```
---@param config AutoUpdaterConfig|nil Configuration options (uses defaults if nil)
---@return AutoUpdater updater The configured AutoUpdater instance
function AutoUpdater.new(config)
	local metadata = require "metadata_gen" ---@type metadata_gen
	return setmetatable({
		config = {
			owner = config and config.owner or metadata.owner,
			repo = config and config.repo or metadata.repo,
			branch = config and config.branch or metadata.branch_name or "main",
			package_path = config and config.package_path or metadata.path,
			package_name = config and config.package_name or Package.GetName(),
			check_asset_store = config and config.check_asset_store ~= false,
			auto_download = config and config.auto_download or false,
			debug = config and config.debug or false,
			on_update_available = config and config.on_update_available,
			on_no_update = config and config.on_no_update,
			on_download_complete = config and config.on_download_complete,
			on_error = config and config.on_error,
			on_check_start = config and config.on_check_start,
			on_check_complete = config and config.on_check_complete,
		},
		current_metadata = metadata,
		current_version = metadata.package_version,
		remote_metadata = nil,
		remote_version = nil,
		latest_version = nil,
		is_preview = string_find(metadata.tag, "-", nil, true) ~= nil,
	}, AutoUpdater)
end

--- Internal debug logging function.<br>
--- Only logs if debug mode is enabled or running a preview version.
---@param self AutoUpdater The AutoUpdater instance
---@param format string The format string for the log message
---@param ... any Additional arguments for string.format
local function debugLog(self, format, ...)
	if self.config.debug or self.is_preview then
		print(string_format("[AutoUpdater] " .. format, ...))
	end
end

--- Internal error handler that calls the configured error callback or logs to console.<br>
--- If on_error callback is configured, it will be invoked with the error and context.<br>
--- Otherwise, logs a warning to the console.
---@param self AutoUpdater The AutoUpdater instance
---@param err string The error message
---@param context string The context where the error occurred
local function handleError(self, err, context)
	if self.config.on_error then
		self.config.on_error(err, context)
	else
		Console.Warn(string_format("[AutoUpdater] Error in %s: %s", context, err))
	end
end

--- Checks the nanos-world asset store API for the current package version.<br>
--- This is used to detect if the current version is a preview/delayed version.<br>
--- The callback receives the store version string, or nil if the check fails.
---@param self AutoUpdater The AutoUpdater instance
---@param callback fun(store_version: string|nil) Callback invoked with the store version
local function checkAssetStore(self, callback)
	local target_url = string_format("https://api.nanos-world.com/store/packages/%s", self.config.package_name)
	debugLog(self, "Checking asset store: %q", target_url)

	http.get(
		target_url,
		function(data, status, url)
			debugLog(self, "[asset store] status: %s, url: %q, size: %d", status, url, #data)
			local success, parsed = pcall(function()
				local parsed_json = JSON.parse(data)
				return parsed_json.payload.version.version
			end)

			if success and parsed then
				debugLog(self, "Asset store version: %s", parsed)
				callback(parsed)
			else
				debugLog(self, "Failed to parse asset store response")
				callback()
			end
		end,
		function(data, status, url)
			debugLog(self, "[asset store] error - status: %s, url: %q, data: %s", status, url,
				tsl.to_string_literal(data))
			callback()
		end
	)
end

--- Fetches the remote metadata_gen.lua file from GitHub.<br>
--- This retrieves version information, commit counts, tags, and other metadata from the remote repository.<br>
--- The callback receives the parsed metadata table, or nil if the fetch fails.
---@param self AutoUpdater The AutoUpdater instance
---@param callback fun(metadata: table|nil) Callback invoked with the remote metadata
local function fetchRemoteMetadata(self, callback)
	local target_url = string_format(
		"https://raw.github.com/%s/%s/%s/%s/Shared/metadata_gen.lua",
		self.config.owner,
		self.config.repo,
		self.config.branch,
		self.config.package_path
	)
	debugLog(self, "Fetching remote metadata: %q", target_url)

	http.get(
		target_url,
		function(data, status, url)
			debugLog(self, "[remote metadata] status: %s, url: %q, size: %d", status, url, #data)
			local success, metadata = pcall(function()
				return load(data)()
			end)

			if success and metadata then
				self.remote_metadata = metadata
				self.remote_version = metadata.package_version
				debugLog(self, "Remote metadata version: %s", self.remote_version)
				debugLog(self, "Remote commit count: %s", metadata.commit_count)
				debugLog(self, "Remote tag count: %s", metadata.tag_count)
				debugLog(self, "Remote tag: %s", metadata.tag)
				callback(metadata)
			else
				handleError(self, "Failed to load remote metadata", "fetchRemoteMetadata")
				callback()
			end
		end,
		function(data, status, url)
			debugLog(self, "[remote metadata] error - status: %s, url: %q, data: %s", status, url,
				tsl.to_string_literal(data))
			handleError(self, string_format("HTTP %d", status), "fetchRemoteMetadata")
			callback()
		end
	)
end

--- Fetches the VERSION file from the GitHub repository.<br>
--- This file contains the latest stable release version tag.<br>
--- If the VERSION file cannot be fetched, falls back to the tag from remote metadata.<br>
--- The callback receives the version string (with "v" prefix), or nil if unavailable.
---@param self AutoUpdater The AutoUpdater instance
---@param callback fun(version: string|nil) Callback invoked with the latest version
local function fetchRepoVersion(self, callback)
	local version_url = string_format(
		"https://raw.github.com/%s/%s/%s/VERSION",
		self.config.owner,
		self.config.repo,
		self.config.branch
	)
	debugLog(self, "Fetching repo version: %q", version_url)

	http.get(
		version_url,
		function(version_data, version_status, version_url)
			debugLog(self, "[repo version] status: %s, data: %s", version_status, tsl.to_string_literal(version_data))
			local latest_version = version_status == 200 and (string_match(version_data, "^(v?[%d%.]+)")) or false

			if not latest_version then
				debugLog(self, "Failed to fetch repo version, falling back to metadata tag: %s",
					self.remote_metadata.tag)
				latest_version = self.remote_metadata.tag
			end

			if latest_version and string_sub(latest_version, 1, 1) ~= "v" then
				latest_version = "v" .. latest_version
			end

			debugLog(self, "Latest repo version: %s", latest_version)
			self.latest_version = latest_version
			callback(latest_version)
		end,
		function(data, status, url)
			debugLog(self, "[repo version] error - status: %s, url: %s, data: %s", status, url,
				tsl.to_string_literal(data))
			-- Fallback to metadata tag
			debugLog(self, "Falling back to metadata tag: %s", self.remote_metadata.tag)
			self.latest_version = self.remote_metadata.tag
			callback(self.remote_metadata.tag)
		end
	)
end

--- Downloads the release zip file from GitHub for the specified version.<br>
--- The zip file contains the full package for that release.<br>
--- The callback receives the raw zip data as a string, or nil if the download fails.
---@param self AutoUpdater The AutoUpdater instance
---@param version string The version tag to download (e.g., "v0.0.27")
---@param callback fun(zip_data: string|nil) Callback invoked with the zip data
local function downloadZip(self, version, callback)
	local zip_url = string_format(
		"https://github.com/%s/%s/releases/download/%s/%s.zip",
		self.config.owner,
		self.config.repo,
		version,
		self.config.package_name
	)
	debugLog(self, "Downloading zip: %q", zip_url)

	http.get(
		zip_url,
		function(zip_data, zip_status, zip_url)
			debugLog(self, "[zip download] status: %s, size: %d bytes", zip_status, #zip_data)
			if zip_status == 200 and #zip_data > 0 then
				callback(zip_data)
			else
				handleError(self, string_format("HTTP %d", zip_status), "downloadZip")
				callback()
			end
		end,
		function(data, status, url)
			debugLog(self, "[zip download] error - status: %s, url: %q, data: %s", status, url,
				tsl.to_string_literal(data))
			handleError(self, string_format("HTTP %d", status), "downloadZip")
			callback()
		end
	)
end

--- Performs a complete update check including asset store and GitHub checks.<br>
--- This is the main entry point for checking for updates. It will:
--- 1. Check the nanos-world asset store/vault if enabled
--- 2. Fetch remote metadata from GitHub
--- 3. Fetch the latest VERSION file
--- 4. Compare versions and trigger appropriate callbacks
---@usage <br>
--- ```
--- updater:checkForUpdates(function(has_update, remote, latest)
---   if has_update then
---     print("Update available: " .. remote)
---   end
--- end)
--- ```
---@param callback fun(has_update: boolean, remote_version: string|nil, latest_version: string|nil)|nil Optional callback with update status
function AutoUpdater:checkForUpdates(callback)
	if self.config.on_check_start then
		self.config.on_check_start()
	end

	-- Check asset store if enabled
	if self.config.check_asset_store then
		checkAssetStore(self, function(store_version)
			if store_version then
				local parsed_store = Version.parse(store_version)
				if parsed_store:isOlderThan(Version.getCurrent()) then
					self.is_preview = true
					Console.Warn("Preview version detected (delayed); some features may not work")
				end
				debugLog(self, "Asset store version: %s", store_version)
			end

			-- Continue with GitHub check
			self:checkGithubUpdates(callback)
		end)
	else
		self:checkGithubUpdates(callback)
	end
end

--- Checks GitHub for updates without checking the asset store.<br>
--- This method fetches remote metadata and compares versions directly.<br>
--- Use this if you want to skip the asset store check.<br>
--- The callback receives the update status and version information.
---@param callback fun(has_update: boolean, remote_version: string|nil, latest_version: string|nil)|nil Optional callback with update status
function AutoUpdater:checkGithubUpdates(callback)
	fetchRemoteMetadata(self, function(metadata)
		if not metadata then
			if callback then callback(false) end
			if self.config.on_check_complete then self.config.on_check_complete() end
			return
		end

		fetchRepoVersion(self, function(latest_version)
			if not latest_version then
				if callback then callback(false) end
				if self.config.on_check_complete then self.config.on_check_complete() end
				return
			end

			-- Compare versions
			local current = Version.parse(self.current_version)
			local remote = Version.parse(self.remote_version)
			local has_update = remote:isNewerThan(current)

			debugLog(self, "Current version: %s, Remote version: %s, Latest: %s, Has update: %s",
				self.current_version, self.remote_version, latest_version, tostring(has_update))

			if has_update then
				if self.config.on_update_available then
					self.config.on_update_available(self.remote_version, self.current_version, metadata)
				end

				-- Auto-download if enabled
				if self.config.auto_download then
					self:downloadUpdate(latest_version)
				end
			else
				if self.config.on_no_update then
					self.config.on_no_update(self.current_version)
				end
			end

			if callback then callback(has_update, self.remote_version, latest_version) end
			if self.config.on_check_complete then self.config.on_check_complete() end
		end)
	end)
end

--- Downloads the update zip for the specified version.<br>
--- If version is nil, uses the latest_version from the last check.
---@usage <br>
--- ```
--- updater:downloadUpdate("v0.0.28", function(zip_data, version)
---   if zip_data then
---     print("Downloaded " .. version .. ": " .. #zip_data .. " bytes")
---   end
--- end)
--- ```
---@param version string|nil Version to download (defaults to latest_version)
---@param callback fun(zip_data: string|nil, version: string)|nil Optional callback with zip data and version
function AutoUpdater:downloadUpdate(version, callback)
	version = version or self.latest_version
	if not version then
		handleError(self, "No version available for download", "downloadUpdate")
		if callback then callback(nil, "") end
		return
	end

	downloadZip(self, version, function(zip_data)
		if zip_data and self.config.on_download_complete then
			self.config.on_download_complete(zip_data, version)
		end
		if callback then callback(zip_data, version) end
	end)
end

--- Gets the current package version from local metadata.<br>
--- This is the version of the currently running package.
---@return string version The current package version
function AutoUpdater:getCurrentVersion()
	return self.current_version
end

--- Gets the remote package version from the last metadata fetch.<br>
--- Returns nil if no remote check has been performed yet.
---@return string|nil version The remote package version, or nil if not checked
function AutoUpdater:getRemoteVersion()
	return self.remote_version
end

--- Gets the latest release version from the last VERSION file fetch.<br>
--- Returns nil if no version check has been performed yet.
---@return string|nil version The latest release version, or nil if not checked
function AutoUpdater:getLatestVersion()
	return self.latest_version
end

--- Gets the remote metadata table from the last metadata fetch.<br>
--- This contains commit counts, tags, and other information from the remote repository.<br>
--- Returns nil if no remote check has been performed yet.
---@return table|nil metadata The remote metadata table, or nil if not fetched
function AutoUpdater:getRemoteMetadata()
	return self.remote_metadata
end

--- Checks if the current version is a preview version.<br>
--- Preview versions are detected by the presence of a hyphen in the tag (e.g., "v0.0.28-alpha").
---@usage <br>
--- ```
--- if updater:isPreviewVersion() then
---     Console.Warn("Running preview version")
--- end
--- ```
---@return boolean is_preview True if running a preview version
function AutoUpdater:isPreviewVersion()
	return self.is_preview
end

--- Convenience method for a one-shot update check with optional configuration.<br>
--- Creates a temporary AutoUpdater instance, performs the check, and invokes the callback.<br>
--- Useful for simple update checks without managing an instance.
---@usage <br>
--- ```
--- AutoUpdater.check({ debug = true }, function(has_update, remote, latest)
---   if has_update then
---     print("Update available: " .. remote)
---   end
--- end)
--- ```
---@param options AutoUpdaterConfig|nil Optional configuration overrides
---@param callback fun(has_update: boolean, remote_version: string|nil, latest_version: string|nil) Callback with update status
function AutoUpdater.check(options, callback)
	local updater = AutoUpdater.new(options or {})
	updater:checkForUpdates(callback)
end

return AutoUpdater
