-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Localize frequently used globals for performance
local debug_getinfo, debug_getlocal, string_gmatch = debug.getinfo, debug.getlocal, string.gmatch

--- Gets a list of parameter names for the function at the given stack level.
--- @param level number: The stack level (1 = current function, 2 = function calling this, etc.)
--- @return table|nil: A list of strings representing the parameter names, or nil if out of bounds.
local function GetParameterNames(level)
	-- Get info about the function at this level.
	-- "u" includes: 'nparams' (number of parameters) and 'isvararg'
	local info = debug_getinfo(level, "u")
	if not info then
		return -- Invalid level
	end

	local params = {}

	-- Iterate strictly from 1 to nparams.
	-- This prevents reading internal locals defined in the function body.
	for i = 1, info.nparams do
		local name = debug_getlocal(level, i)
		params[i] = name
	end

	return params
end

--- Helper to get a specific parameter name by index.
--- @param level number: The stack level.
--- @param index number: The argument index (1-based).
--- @return string|nil: The name of the parameter, or nil if out of bounds.
local function GetParameterName(level, index)
	local info = debug_getinfo(level, "u")
	if info and 1 <= index and index <= info.nparams then
		-- debug.getlocal returns the name as the first return value
		return (debug_getlocal(level, index))
	end
end

--- Helper for strict type checking.
--- @param val any: The value to check.
--- @param expected_type string|table: The expected Lua type (e.g., "string") or a list of types (e.g., {"string", "number"} or "string|number").
--- @param arg_index number|nil: The argument positional index (1, 2, 3...).
--- @param optional boolean|nil: If true, the argument is optional (nil is accepted).
--- @param func_level number|nil: Stack level of the function whose args we describe (defaults to 1).
--- @param error_level number|nil: Stack level for error reporting (defaults to 2).
function TypeCheck(val, expected_type, arg_index, optional, func_level, error_level)
	-- Set default stack level for inspecting arguments.
	func_level = (func_level or 1) + 1

	-- We add 1 to the base level (usually 2) to account for this helper function,
	-- ensuring the error points to the calling library function, not this helper.
	error_level = (error_level or 2) + 1

	-- If optional is true and value is nil, pass immediately
	if optional and val == nil then
		return
	end

	-- Normalize expected_type into a list of allowed types
	local allowed_types = {}
	if type(expected_type) == "table" then
		allowed_types = expected_type
	else
		-- Assume string. Check for union syntax "string|number"
		for t in string_gmatch(expected_type, "([^|]+)") do
			allowed_types[#allowed_types + 1] = t
		end
	end

	-- Perform Type Check
	local actual_type = type(val)
	local is_valid = false

	for _, t in next, allowed_types do
		if actual_type == t or t == "any" or (t == "nil" and val == nil) then
			is_valid = true
			break
		end
	end

	-- Handle Error
	if not is_valid then
		local type_str = ""
		local count = #allowed_types

		for i, t in next, allowed_types do
			if i > 1 then
				type_str = (i == count) and (type_str .. " or ") or (type_str .. ", ")
			end
			type_str = type_str .. t
		end

		local funcInfo = debug_getinfo(func_level, "n")
		local funcName = (funcInfo and funcInfo.name) or "?"
		local prefix = optional and "optional " or ""
		return error(string.format(
				"bad argument #%d%s to '%s' (expected %s%s, got %s)",
				arg_index or "?",
				arg_index and " (" .. (GetParameterName(func_level + 1, arg_index) or "?") .. ")" or "",
				funcName,
				prefix,
				type_str,
				actual_type),
			error_level
		)
	end
end

--- Performs strict type checking on a function argument by automatically retrieving its value from the caller's stack frame.<br>
--- This is a convenience wrapper around `TypeCheck` that:<br>
--- • Fetches the argument value using `debug.getlocal`<br>
--- • Ensures the argument index is within the function's declared parameters<br>
--- • Forwards all type-checking rules to `TypeCheck`<br>
--- @param arg_index number: The 1-based positional index of the argument to validate.
--- @param expected_type string|table: The expected Lua type, or a list/union of types.
--- @param optional boolean|nil: If true, `nil` is accepted as a valid value. Defaults to false.
--- @param func_level number|nul: The stack level of the function whose parameters should be inspected. Defaults to 2.
--- @param error_level number|nil: Stack level used for error attribution. Defaults to 2, and is internally incremented by 1 so that errors point to the calling function, not this helper.
function TypeCheckArg(arg_index, expected_type, optional, func_level, error_level)
	-- The caller function is at level 2
	func_level = func_level or 2

	-- Default stack level for error reporting
	error_level = error_level or 2

	-- Get info about the caller (your function)
	local info = debug_getinfo(func_level, "u")
	local nparams = info and info.nparams or 0

	-- Prevent reading locals beyond declared parameters
	if arg_index < 1 or arg_index > nparams then
		if optional then
			return
		end

		local funcInfo = debug_getinfo(func_level, "n")
		local funcName = funcInfo and funcInfo.name or "?"
		return error(string.format(
			"bad argument #%d to '%s' (no such parameter index %d)",
			1,
			funcName,
			arg_index
		), error_level)
	end

	-- Fetch the argument value (discard the name)
	local _, val = debug_getlocal(func_level, arg_index)

	-- Delegate to TypeCheck
	return TypeCheck(val, expected_type, arg_index, optional, func_level, error_level)
end

--local function test()
--	local function example(a, b, c)
--		TypeCheck(a, "number|boolean", 1)
--		TypeCheckArg(1, "number|boolean")
--		TypeCheck(b, "string|nil", 2)
--		TypeCheckArg(2, "string|nil")
--		TypeCheck(c, "table", 3)
--		TypeCheckArg(3, "table")
--		print(a, b, c)
--	end
--	example(12.34, "foo", { "bar" })
--	example(false, nil, { "bar" })
--	example()
--end
--test()

Package.Export("TypeCheck", TypeCheck)
Package.Export("TypeCheckArg", TypeCheckArg)
return {
	TypeCheck = TypeCheck,
	TypeCheckArg = TypeCheckArg,
}
