-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

local string_match = string.match
local package_version = Package.GetVersion()

--- Version utility class for semantic versioning (major.minor.build)
---@class Version
---@field major integer The major version number.
---@field minor integer The minor version number.
---@field build integer The build version number.
local Version = {}
Version.__index = Version

--- Parses a version string into a Version object.
---@param version_string string Version in format "major.minor.build".
---@return Version Version object with major, minor, build fields.
function Version.parse(version_string)
	local major, minor, build = string_match(version_string, "^(%d+)%.(%d+)%.(%d+)$")
	if not major then
		return error("Invalid version format. Expected 'major.minor.build', got: " .. tostring(version_string), 2)
	end
	return setmetatable({
		major = tonumber(major),
		minor = tonumber(minor),
		build = tonumber(build)
	}, Version)
end

--- Compares this version with another version.
---@param other table|string Version object or string to compare against.
---@return integer integer -1 if this < other, 0 if equal, 1 if this > other.
function Version:compare(other)
	if type(other) == "string" then
		other = Version.parse(other)
	end
	if self.major ~= other.major then
		return self.major < other.major and -1 or 1
	end
	if self.minor ~= other.minor then
		return self.minor < other.minor and -1 or 1
	end
	if self.build ~= other.build then
		return self.build < other.build and -1 or 1
	end
	return 0
end

--- Checks if this version is older than another version.
---@param other table|string Version object or string to compare against.
---@return boolean boolean True if this version is older (update available).
function Version:isOlderThan(other)
	return self:compare(other) < 0
end

--- Checks if this version is newer than another version.
---@param other table|string Version object or string to compare against.
---@return boolean boolean True if this version is newer.
function Version:isNewerThan(other)
	return self:compare(other) > 0
end

--- Checks if versions are equal.
---@param other table|string Version object or string to compare against.
---@return boolean boolean True if versions are equal.
function Version:equals(other)
	return self:compare(other) == 0
end

--- Returns string representation of the version.
---@return string string Version in format "major.minor.build".
function Version:__tostring()
	return string.format("%d.%d.%d", self.major, self.minor, self.build)
end

--- Returns the current package version as a Version object.
---@return Version version Version object representing `Package.GetVersion()`.
function Version.getCurrent()
	return Version.parse(package_version)
end

--- Checks if an update is available compared to a remote version.
---@param remote_version string The remote version string to check against.
---@return boolean boolean True if remote version is newer (update available).
function Version.isUpdateAvailable(remote_version)
	return Version.getCurrent():isOlderThan(remote_version)
end

-- Export the API to be accessed by other packages
return Version
