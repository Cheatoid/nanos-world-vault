-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Import dependencies
r "@cheatoid/standard/table"

local oop = require("@cheatoid/oop/oop")
local try = require("@cheatoid/standalone/try").try
local ref = require("@cheatoid/ref/ref").new -- TODO: use this for managing config state externally (+ auto-save on field write)

local File = File
local JSON = JSON

--- @class cheatoidlib.config.field
--- @field type "boolean"|"string"|"number"|"integer"|"table"
--- @field default any
--- @field required boolean
--- @field validate nil|fun(value: any): boolean, string|nil

--- @class cheatoidlib.config.schema
--- @field [string] cheatoidlib.config.field

--- @class cheatoidlib.config
--- @field enable_cslua boolean Enable client-side Lua execution
--- @field debug_mode boolean Enable debug logging
--- @field max_cache_size integer Maximum cache size in MB

--- Configuration field types
local FieldType = oop.Enum("FieldType", {
	"boolean",
	"string",
	"number",
	"integer",
	"table",
	"array",
})

--- @type cheatoidlib.config.schema
local SCHEMA = {
	enable_cslua = {
		type = "boolean",
		default = false,
		required = false,
	},
	debug_mode = {
		type = "boolean",
		default = false,
		required = false,
	},
	max_cache_size = {
		type = "integer",
		default = 100,
		required = false,
		validate = function(v)
			if v < 1 or v > 1000 then
				return false, "max_cache_size must be between 1 and 1000"
			end
			return true
		end,
	},
}

--- @type cheatoidlib.config
local DEFAULTS = {
	enable_cslua = false,
	debug_mode = false,
	max_cache_size = 100,
}
local FILE_NAME = "config.json"

-- Module state
local is_dirty = false
local is_initialized = false
local config_data ---@type cheatoidlib.config|nil
local file_handle ---@type File|nil

--- Validates a value against a field schema
--- @param key string
--- @param value any
--- @param schema cheatoidlib.config.field
--- @return boolean valid
--- @return string|nil error
local function validate_field(key, value, schema)
	if value == nil then
		if schema.required then
			return false, string.format("Field '%s' is required", key)
		end
		return true
	end

	local value_type = type(value)
	local expected_type = schema.type

	-- Type validation
	if expected_type == "integer" then
		if value_type ~= "number" or value % 1 ~= 0 then
			return false, string.format("Field '%s' must be an integer, got %s", key, value_type)
		end
	elseif expected_type == "array" then
		if value_type ~= "table" or (value[1] == nil and next(value) ~= nil) then
			return false, string.format("Field '%s' must be an array", key)
		end
	elseif value_type ~= expected_type and expected_type ~= "any" then
		return false, string.format("Field '%s' must be of type '%s', got '%s'", key, expected_type, value_type)
	end

	-- Custom validation
	if schema.validate then
		local ok, err = schema.validate(value)
		if not ok then
			return false, err or string.format("Field '%s' failed validation", key)
		end
	end

	return true
end

--- Validates entire config against schema
--- @param data table
--- @return boolean valid
--- @return string? error
local function validate_config(data)
	for key, field_schema in next, SCHEMA do
		local value = data[key]
		local valid, err = validate_field(key, value, field_schema)
		if not valid then
			return false, err
		end
	end
	return true
end

--- Merges source table into target recursively
--- @param target table
--- @param source table
--- @param overwrite boolean
local function merge_tables(target, source, overwrite)
	for k, v in next, source do
		if type(v) == "table" and type(target[k]) == "table" then
			merge_tables(target[k], v, overwrite)
		elseif overwrite or target[k] == nil then
			target[k] = v
		end
	end
	return target
end

--- Applies defaults to missing fields
--- @param data table|nil
--- @return cheatoidlib.config
local function apply_defaults(data)
	local result = {}
	for k, v in next, DEFAULTS do
		result[k] = v
	end
	if data then
		merge_tables(result, data, true)
	end
	return result
end

local init, read, get, set, update, write, reset, isDirty, getSchema, getDefaults, registerField

--- Initializes the config module
--- @return boolean success
--- @return string|nil error
function init()
	if is_initialized then
		return true
	end

	local success, err = pcall(function()
		-- Check if config file exists
		if not File.Exists(FILE_NAME) then
			-- Create a default config file
			config_data = apply_defaults()
			local json_str = JSON.stringify(config_data)
			local file = File(FILE_NAME, true)
			file:Write(json_str)
			file:Flush()
			file:Close()
			is_initialized = true
			is_dirty = false
			return
		end

		-- Read the existing config
		file_handle = File(FILE_NAME)
		if not file_handle:IsGood() then
			return error("Failed to open config file", 2)
		end

		local content = file_handle:Read(0) -- Read whole file
		file_handle:Close()
		file_handle = nil

		if not content or content == "" then
			config_data = apply_defaults()
		else
			local ok, parsed = pcall(JSON.parse, content)
			if not ok or type(parsed) ~= "table" then
				return error("Failed to parse config file as JSON", 2)
			end

			-- Validate against schema
			local valid, err = validate_config(parsed)
			if not valid then
				-- Log warning but still use defaults for invalid fields
				print(string.format("[Config] Validation warning: %s", err))
			end

			config_data = apply_defaults(parsed)
		end

		is_initialized = true
		is_dirty = false
	end)

	if not success then
		-- Fallback to defaults on error
		config_data = apply_defaults()
		is_initialized = true
		is_dirty = false
		return false, tostring(err)
	end

	return true
end

--- Reads current config
--- @return cheatoidlib.config|nil
function read()
	if not is_initialized then
		local ok, err = init()
		if not ok then
			print(string.format("[Config] Init failed: %s", err))
		end
	end
	return config_data
end

--- Gets a specific config value
--- @param key string
--- @param default any
--- @return any
function get(key, default)
	if not is_initialized then
		init()
	end
	if config_data then
		return config_data[key] ~= nil and config_data[key] or default
	end
	return default
end

--- Sets a specific config value
--- @param key string
--- @param value any
--- @return boolean success
--- @return string|nil error
function set(key, value)
	if not is_initialized then
		local ok, err = init()
		if not ok then
			return false, err
		end
	end

	-- Validate if schema exists for this key
	local field_schema = SCHEMA[key]
	if field_schema then
		local valid, err = validate_field(key, value, field_schema)
		if not valid then
			return false, err
		end
	end

	config_data[key] = value
	is_dirty = true
	return true
end

--- Updates config with new values (partial update)
--- @param updates table
--- @param overwrite boolean
--- @return boolean success
--- @return string|nil error
function update(updates, overwrite)
	if type(updates) ~= "table" then
		return false, "updates must be a table"
	end

	if not is_initialized then
		local ok, err = init()
		if not ok then
			return false, err
		end
	end

	-- Validate updates
	for k, v in next, updates do
		local field_schema = SCHEMA[k]
		if field_schema then
			local valid, err = validate_field(k, v, field_schema)
			if not valid then
				return false, err
			end
		end
	end

	merge_tables(config_data, updates, overwrite ~= false)
	is_dirty = true
	return true
end

--- Writes current config to file
--- @param force boolean|nil
--- @return boolean success
--- @return string|nil error
function write(force)
	if not is_initialized then
		return false, "Config not initialized"
	end

	if not is_dirty and not force then
		return true -- Nothing to write
	end

	local success, err = pcall(function()
		local json_str = JSON.stringify(config_data or DEFAULTS)
		local file = File(FILE_NAME, true)
		if not file:IsGood() then
			return error("Failed to open config file for writing", 2)
		end
		file:Write(json_str)
		file:Flush()
		file:Close()
		is_dirty = false
	end)

	if not success then
		return false, tostring(err)
	end

	return true
end

--- Resets config to defaults and optionally deletes the file
--- @param delete_file boolean
function reset(delete_file)
	if file_handle then
		file_handle:Close()
		file_handle = nil
	end

	if delete_file then
		File.Remove(FILE_NAME)
	end

	config_data = apply_defaults()
	is_dirty = true
	is_initialized = true

	if delete_file then
		write()
	end
end

--- Checks if config has unsaved changes
--- @return boolean
function isDirty()
	return is_dirty
end

--- Gets the schema definition
--- @return cheatoidlib.config.schema
function getSchema()
	local copy = {}
	for k, v in next, SCHEMA do
		copy[k] = v
	end
	return copy
end

--- Gets default values
--- @return cheatoidlib.config
function getDefaults()
	local copy = {}
	for k, v in next, DEFAULTS do
		copy[k] = v
	end
	return copy
end

--- Registers a new field in the schema (for extensibility)
--- @param key string
--- @param field_schema cheatoidlib.config.field
function registerField(key, field_schema)
	if not field_schema or not field_schema.type then
		return error("Field schema must have a 'type' property", 2)
	end
	SCHEMA[key] = field_schema
	if field_schema.default ~= nil and config_data then
		if config_data[key] == nil then
			config_data[key] = field_schema.default
			is_dirty = true
		end
	end
end

-- Export
return {
	init = init,
	read = read,
	get = get,
	set = set,
	update = update,
	write = write,
	reset = reset,
	isDirty = isDirty,
	getSchema = getSchema,
	getDefaults = getDefaults,
	registerField = registerField,
}
