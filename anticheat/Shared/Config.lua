-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Import reference wrapper
local ref = require "@cheatoid/ref/ref"

---@class anticheat.config
---@field default_dimension integer Default dimension to use (this becomes the default, instead of 1)

local function FlushToDisk(key, value)
	Package.SetPersistentData(key, value)
	Package.FlushPersistentData()
end

-- A reactive Config reference, which will automatically flush to disk upon changing a field
local cfg ---@type anticheat.config
local default_cfg = {
	default_dimension = 1337, -- must be between [1..65535]
} ---@type anticheat.config

---@return anticheat.config
local function ResetToDefault()
	if cfg then
		for k, v in next, default_cfg do
			rawset(cfg, k, v)
			Package.SetPersistentData(k, v)
		end
		Package.FlushPersistentData()
	else
		cfg = ref.reactive(default_cfg, FlushToDisk)
	end
	return cfg
end

---@return anticheat.config
local function Reload()
	cfg = ref.reactive(Package.GetPersistentData(), FlushToDisk)
	return cfg
end

---@return anticheat.config
local function Get()
	return cfg
end

Reload()

-- Export
return setmetatable({
	Get = Get,
	Reload = Reload,
	ResetToDefault = ResetToDefault,
}, {
	__call = Reload,
	__index = function(_, key)
		return cfg[key]
	end,
	__newindex = function(_, key, value)
		cfg[key] = value
	end,
})
