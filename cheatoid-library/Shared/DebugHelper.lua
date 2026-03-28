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
local GETINFO_ALL = "nSltufrL"

local DebugHelper = {}

--- Get the function object at a given stack level.
--- @param level function|integer The function -or- stack frame level, to inspect.
--- @return function|nil
function DebugHelper.get_function(level)
	local info = debug_getinfo(level, "f")
	if info then
		return info.func
	end
end

--- Get the prefix of the source path up to the first slash.
--- @param level function|integer The function -or- stack frame level, to inspect.
--- @return string|nil prefix The extracted prefix, or nil if unavailable.
function DebugHelper.get_source_prefix(level)
	local info = debug_getinfo(level, "S")
	if not info then
		return
	end
	return (string_match(string_gsub(info.source, "^[@=]", ""), "^([^/]+)"))
end

--- Get all locals at a given stack level, with classification.<br>
--- Each entry:<br>
--- { name  = string, value = any, kind  = "param" | "vararg" | "local" }
--- @param level integer The stack frame level to inspect.
--- @return table|nil array Array of local entries.
function DebugHelper.get_locals(level)
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
			kind = "param"
		elseif is_vararg and name == "(*vararg)" then
			kind = "vararg"
		else
			kind = "local"
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

--- Get locals grouped by kind:<br>
--- {params  = { ... }, varargs = { ... }, locals  = { ... } }<br>
--- Each entry has the same shape as in get_locals().
--- @param level integer The stack frame level to inspect.
--- @return table|nil table
function DebugHelper.get_locals_by_kind(level)
	local all = DebugHelper.get_locals(level)
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
		if kind == "param" then
			params[#params + 1] = entry
		elseif kind == "vararg" then
			varargs[#varargs + 1] = entry
		else
			locals[#locals + 1] = entry
		end
	end

	return out
end

--- Get only declared parameters at a given level.
--- @param level integer The stack frame level to inspect.
--- @return table|nil array Array of { name, value }
function DebugHelper.get_parameters(level)
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

--- Check if the function at a given level is vararg.
--- @param level function|integer The function -or- stack frame level, to inspect.
--- @return boolean boolean Whether the function is variadic.
function DebugHelper.is_vararg(level)
	local info = debug_getinfo(level, "u")
	if info then
		return info.isvararg
	end

	return false
end

--- Extract ONLY true varargs from a given stack level.<br>
--- Lua 5.4 marks varargs with the name "(*vararg)".
--- @param level integer Stack frame level.
--- @return table|nil array Array of vararg values.
--- @return integer|nil integer Total amount of vararg values.
function DebugHelper.get_varargs(level)
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

--- Count varargs at a given level.
--- @param level integer Stack frame level.
--- @return integer integer Amount of varargs.
function DebugHelper.count_varargs(level)
	return #DebugHelper.get_varargs(level)
end

--- Get the name of a parameter by index.
--- @param level integer Stack frame level.
--- @param index integer The argument index (1-based).
--- @return string|nil name Parameter name, or nil if not found.
function DebugHelper.get_param_name(level, index)
	local name = debug_getlocal(level, index)
	return name
end

--- Get the value of a parameter by index.
--- @param level integer Stack frame level.
--- @param index integer The argument index (1-based).
--- @return any any Parameter value.
function DebugHelper.get_param_value(level, index)
	local _, value = debug_getlocal(level, index)
	return value
end

--- Get upvalues of the function at a given level.<br>
--- Returns array of: { name = string, value = any }
--- @param level integer Stack frame level.
--- @return table|nil array
function DebugHelper.get_upvalues(level)
	local func = DebugHelper.get_function(level)
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

--- Get a structured stack trace (table, not string).
--- @return table array Array of debug.getinfo tables.
function DebugHelper.get_stack()
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

--- Get the name of the caller function.
--- @param level integer|nil Defaults to 2.
--- @return string|nil
function DebugHelper.get_caller_name(level)
	local info = debug_getinfo(level or 2, "n")
	if info then
		return info.name
	end
end

--- Dump a full frame snapshot:<br>
--- • parameters<br>
--- • varargs<br>
--- • locals (with kind)<br>
--- • upvalues<br>
--- • debug info
---
--- @param level integer|nil Defaults to 2.
--- @return table
function DebugHelper.dump_frame(level)
	level = level or 2
	return {
		parameters = DebugHelper.get_parameters(level),
		varargs = DebugHelper.get_varargs(level),
		locals = DebugHelper.get_locals(level),
		upvalues = DebugHelper.get_upvalues(level),
		info = debug_getinfo(level, GETINFO_ALL),
	}
end

-- Export the API to be accessed by other packages
_G.DebugHelper = DebugHelper
Package.Export("DebugHelper", DebugHelper)
return DebugHelper
