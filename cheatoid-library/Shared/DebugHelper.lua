-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Lua debug utilities for inspecting:
-- • parameters
-- • varargs
-- • locals (with kind classification)
-- • upvalues
-- • stack frames

-- Localize global functions for better performance.
local next, debug_getinfo, debug_getlocal, debug_getupvalue, string_gsub, string_match =
		next, debug.getinfo, debug.getlocal, debug.getupvalue, string.gsub, string.match

local VARARG_TEMP = "(*vararg)"
local LOCAL_PARAM, LOCAL_VARARG, LOCAL_LOCAL = "param", "vararg", "local"
local GETINFO_ALL = "nSltufrL"

local DebugHelper = {}

--- Get the current stack depth by counting all available stack frames.
--- @return integer depth The total number of stack frames in the call stack.
local function get_stack_depth()
	local i = 0
	while debug_getinfo(i) do
		i = i + 1
	end
	return i
end
DebugHelper.get_stack_depth = get_stack_depth

--- Get the function object at a given stack level.
--- @param func_level function|integer The function -or- stack frame level, to inspect.
--- @return function|nil
local function get_function(func_level)
	local info = debug_getinfo(func_level, "f")
	if info then
		return info.func
	end
end
DebugHelper.get_function = get_function

--- Get the prefix of the source path up to the first slash.
--- @param func_level function|integer The function -or- stack frame level, to inspect.
--- @return string|nil prefix The extracted prefix, or nil if unavailable.
local function get_source_prefix(func_level)
	local info = debug_getinfo(func_level, "S")
	if not info then
		return
	end
	return (string_match(string_gsub(info.source, "^[@=]", ""), "^([^/]+)"))
end
DebugHelper.get_source_prefix = get_source_prefix

--- Get all locals at a given stack level, with classification.<br>
--- Each entry:<br>
--- { name  = string, value = any, kind  = "param" | "vararg" | "local" }
--- @param level integer The stack frame level to inspect.
--- @return table|nil array Array of local entries.
local function get_locals(level)
	local info = debug_getinfo(level, "u")
	if not info then
		return
	end

	local locals = {}
	local param_count = info.nparams
	local is_vararg = info.isvararg

	local i = 1
	while true do
		local name, value = debug_getlocal(level, i)
		if not name then
			break
		end

		local kind
		if i <= param_count then
			kind = LOCAL_PARAM
		elseif is_vararg and name == VARARG_TEMP then
			kind = LOCAL_VARARG
		else
			kind = LOCAL_LOCAL
		end

		locals[i] = {
			name = name,
			value = value,
			kind = kind,
		}

		i = i + 1
	end

	return locals
end
DebugHelper.get_locals = get_locals

--- Get locals grouped by kind:<br>
--- { params  = { ... }, varargs = { ... }, locals  = { ... } }<br>
--- Each entry has the same shape as in get_locals().
--- @param level integer The stack frame level to inspect.
--- @return table|nil table
local function get_locals_by_kind(level)
	local all = get_locals(level)
	if not all then
		return
	end

	local out = {
		params = {},
		varargs = {},
		locals = {},
	}

	local params = out.params
	local varargs = out.varargs
	local locals = out.locals

	for _, entry in next, all do
		local kind = entry.kind
		if kind == LOCAL_PARAM then
			params[#params + 1] = entry
		elseif kind == LOCAL_VARARG then
			varargs[#varargs + 1] = entry
		else
			locals[#locals + 1] = entry
		end
	end

	return out
end
DebugHelper.get_locals_by_kind = get_locals_by_kind

--- Get only declared parameters at a given level.
--- @param level integer The stack frame level to inspect.
--- @return table|nil array Array of { name, value }
local function get_parameters(level)
	local info = debug_getinfo(level, "u")
	if not info then
		return
	end

	local params = {}
	for i = 1, info.nparams do
		local name, value = debug_getlocal(level, i)
		params[i] = { name = name, value = value }
	end

	return params
end
DebugHelper.get_parameters = get_parameters

--- Check if the function at a given level is vararg.
--- @param level function|integer The function -or- stack frame level, to inspect.
--- @return boolean boolean Whether the function is variadic.
local function is_vararg(level)
	local info = debug_getinfo(level, "u")
	if info then
		return info.isvararg
	end

	return false
end
DebugHelper.is_vararg = is_vararg

--- Extract ONLY true varargs from a given stack level.<br>
--- Lua marks varargs with the name "(*vararg)".
--- @param level integer Stack frame level.
--- @return table|nil array Array of vararg values.
--- @return integer|nil integer Total amount of vararg values.
local function get_varargs(level)
	local info = debug_getinfo(level, "u")
	if not info or not info.isvararg then
		return
	end

	local varargs = {}

	local index = info.nparams + 1
	local i = 0

	while true do
		local name, value = debug_getlocal(level, index)
		if not name then
			break
		end

		if name == VARARG_TEMP then
			i = i + 1
			varargs[i] = value
		else
			break
		end

		index = index + 1
	end

	return varargs, i
end
DebugHelper.get_varargs = get_varargs

--- Count varargs at a given level.
--- @param level integer Stack frame level.
--- @return integer integer Amount of varargs.
local function count_varargs(level)
	return #get_varargs(level)
end
DebugHelper.count_varargs = count_varargs

--- Get the name of a parameter by index.
--- @param level integer Stack frame level.
--- @param index integer The argument index (1-based).
--- @return string|nil name Parameter name, or nil if not found.
local function get_param_name(level, index)
	local name = debug_getlocal(level, index)
	return name
end
DebugHelper.get_param_name = get_param_name

--- Get the value of a parameter by index.
--- @param level integer Stack frame level.
--- @param index integer The argument index (1-based).
--- @return any any Parameter value.
local function get_param_value(level, index)
	local _, value = debug_getlocal(level, index)
	return value
end
DebugHelper.get_param_value = get_param_value

--- Get upvalues of the function at a given level.<br>
--- Returns array of: { name = string, value = any }
--- @param level integer Stack frame level.
--- @return table|nil array
local function get_upvalues(level)
	local func = get_function(level)
	if not func then
		return
	end

	local ups = {}
	local i = 1

	while true do
		local name, value = debug_getupvalue(func, i)
		if not name then
			break
		end
		ups[i] = { name = name, value = value }
		i = i + 1
	end

	return ups
end
DebugHelper.get_upvalues = get_upvalues

--- Get a structured stack trace (table, not string).
--- @return table array Array of debug.getinfo tables.
local function get_stack()
	local frames = {}
	local level = 1

	while true do
		local info = debug_getinfo(level, GETINFO_ALL)
		if not info then
			break
		end
		frames[level] = info
		level = level + 1
	end

	return frames
end
DebugHelper.get_stack = get_stack

--- Get the name of the caller function.
--- @param level integer|nil Defaults to 2.
--- @return string|nil
local function get_caller_name(level)
	local info = debug_getinfo(level or 2, "n")
	if info then
		return info.name
	end
end
DebugHelper.get_caller_name = get_caller_name

--- Dump a full frame snapshot:<br>
--- • parameters<br>
--- • varargs<br>
--- • locals (with kind)<br>
--- • upvalues<br>
--- • debug info
---
--- @param level integer The stack frame level to inspect (default: 2).
--- @return table
local function dump_frame(level)
	level = level or 2
	return {
		parameters = get_parameters(level),
		varargs = get_varargs(level),
		locals = get_locals(level),
		upvalues = get_upvalues(level),
		info = debug_getinfo(level, GETINFO_ALL),
	}
end
DebugHelper.dump_frame = dump_frame

-- Export the API to be accessed by other packages
return DebugHelper
