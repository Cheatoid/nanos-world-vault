-- Lua 5.4 debug utilities for inspecting:
-- • parameters
-- • varargs
-- • locals (with kind classification)
-- • upvalues
-- • stack frames

-- All global functions are localized for speed.
local next       = next
local getinfo    = debug.getinfo
local getlocal   = debug.getlocal
local getupvalue = debug.getupvalue

DebugHelper      = {}

--- Get the function object at a given stack level.
--- @param level number: Stack frame level.
--- @return function|nil:
function DebugHelper.get_function(level)
	local info = getinfo(level, "f")
	return info and info.func
end

--- Get all locals at a given stack level, with classification.<br>
--- Each entry:<br>
--- { name  = string, value = any, kind  = "param" | "vararg" | "local" }
--- @param level number: Stack frame level.
--- @return table: Array of local entries.
function DebugHelper.get_locals(level)
	local info        = getinfo(level, "u")
	local locals      = {}

	local param_count = info.nparams
	local is_vararg   = info.isvararg

	local i           = 1
	while true do
		local name, value = getlocal(level, i)
		if not name then break end

		local kind
		if i <= param_count then
			kind = "param"
		elseif is_vararg and name == "(*vararg)" then
			kind = "vararg"
		else
			kind = "local"
		end

		locals[i] = {
			name  = name,
			value = value,
			kind  = kind
		}

		i = i + 1
	end

	return locals
end

--- Get locals grouped by kind:<br>
--- {params  = { ... }, varargs = { ... }, locals  = { ... } }<br>
--- Each entry has the same shape as in get_locals().
--- @param level number: Stack frame level.
--- @return table:
function DebugHelper.get_locals_by_kind(level)
	local all     = DebugHelper.get_locals(level)

	local out     = {
		params  = {},
		varargs = {},
		locals  = {}
	}

	local params  = out.params
	local varargs = out.varargs
	local locals  = out.locals

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
--- @param level number: Stack frame level.
--- @return table: Array of { name, value }
function DebugHelper.get_parameters(level)
	local info = getinfo(level, "u")
	local params = {}

	for i = 1, info.nparams do
		local name, value = getlocal(level, i)
		params[i] = { name = name, value = value }
	end

	return params
end

--- Check if the function at a given level is vararg.
--- @param level number: Stack frame level.
--- @return boolean:
function DebugHelper.is_vararg(level)
	local info = getinfo(level, "u")
	return info.isvararg
end

--- Extract ONLY true varargs from a given stack level.<br>
--- Lua 5.4 marks varargs with the name "(*vararg)".
--- @param level number: Stack frame level.
--- @return table: Array of vararg values.
--- @return number: Total amount of vararg values.
function DebugHelper.get_varargs(level)
	local info = getinfo(level, "u")
	local varargs = {}

	if not info.isvararg then
		return varargs
	end

	local index = info.nparams + 1
	local i = 0

	while true do
		local name, value = getlocal(level, index)
		if not name then break end

		if name == "(*vararg)" then
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
--- @param level number: Stack frame level.
--- @return number:
function DebugHelper.count_varargs(level)
	return #DebugHelper.get_varargs(level)
end

--- Get the name of a parameter by index.
--- @param level number: Stack frame level.
--- @param index number:
--- @return string|nil:
function DebugHelper.get_param_name(level, index)
	local name = getlocal(level, index)
	return name
end

--- Get the value of a parameter by index.
--- @param level number: Stack frame level.
--- @param index number:
--- @return any:
function DebugHelper.get_param_value(level, index)
	local _, value = getlocal(level, index)
	return value
end

--- Get upvalues of the function at a given level.<br>
--- Returns array of: { name = string, value = any }
--- @param level number: Stack frame level.
--- @return table:
function DebugHelper.get_upvalues(level)
	local func = DebugHelper.get_function(level)
	if not func then return {} end

	local ups = {}
	local i = 1

	while true do
		local name, value = getupvalue(func, i)
		if not name then break end
		ups[i] = { name = name, value = value }
		i = i + 1
	end

	return ups
end

--- Get a structured stack trace (table, not string).
--- @return table: Array of debug.getinfo tables.
function DebugHelper.get_stack()
	local frames = {}
	local level = 1

	while true do
		local info = getinfo(level, "nSltufrL")
		if not info then break end
		frames[level] = info
		level = level + 1
	end

	return frames
end

--- Get the name of the caller function.
--- @param level number|nil: Defaults to 2.
--- @return string|nil
function DebugHelper.get_caller_name(level)
	level = level or 2
	local info = getinfo(level, "n")
	return info and info.name
end

--- Dump a full frame snapshot:<br>
--- • parameters<br>
--- • varargs<br>
--- • locals (with kind)<br>
--- • upvalues<br>
--- • debug info<br>
--- @param level number|nil: Defaults to 2.
--- @return table
function DebugHelper.dump_frame(level)
	level = level or 2
	return {
		parameters = DebugHelper.get_parameters(level),
		varargs    = DebugHelper.get_varargs(level),
		locals     = DebugHelper.get_locals(level),
		upvalues   = DebugHelper.get_upvalues(level),
		info       = getinfo(level, "nSltufrL")
	}
end

Package.Export("DebugHelper", DebugHelper)
return DebugHelper
