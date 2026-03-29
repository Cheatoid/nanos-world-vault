-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- TODO: Build DSL for dependency graph & automatic loader for loading modules/packages/dependencies...
-- TODO: HTTP/GitHub package importing (for dynamic/zipped modules, etc.)

--for _, f in next, Package.GetFiles(nil, ".lua") do
--	print("[package file]", f)
--end

local select = select
-- Compatibility fallback for unpack/table.unpack
local table_unpack = table.unpack or unpack

--- Curries a function to allow partial application.
---@param func function The function to curry.
---@param arity integer|nil The number of arguments required (default: 2).
---@return function function A curried version of the input function.
---@usage local add = function(a, b) return a + b end<br>
---local curriedAdd = curry(add, 2)<br>
---local add5 = curriedAdd(5) -- returns a function<br>
---local result = add5(3) -- returns 8<br>
local function curry(func, arity) -- TODO: Move to Lua lib
	arity = arity or 2
	if arity == 1 then
		return func -- No point currying single-argument functions
	end
	return function(...)
		local argc = select("#", ...)
		if argc >= arity then
			return func(...)
		end
		local args = { ... }
		return function(...)
			return curry(func, arity)(table_unpack(args, 1, argc), ...)
		end
	end
end

-- ==========================================
-- G.A.(I.)M.E.R.
-- ==========================================
local g, a, i, m, e, r

r = Package and Package.Require or require --function(name) print("[require]", name) return name end
e = function(name, value)
	_G[name] = value
	Package.Export(name, value)
	return value
end

-- Global require: require [target] and export it as global [name].
g = curry(
	function(name, target)
		if type(target) == "table" then
			-- TODO: Implement real module support
			target = target[1]
		end
		assert(type(target) == "string", "target must be a string or table")
		return e(name, r(target .. ".lua"))
	end)

-- Get global [name] and alias it as [alias].
a = curry(
	function(name, alias)
		local v = _G[name]
		if alias and v ~= nil then
			_G[alias] = v
		end
		return v
	end)

-- Get global [name] and treat it as module (table with functions) that should be exported as globals.
-- For example: m"TypeCheck" will require the TypeCheck package and export all its functions as global variables.
m = function(name)
	local mod = r(name .. ".lua")
	if mod == nil then
		return
	end
	assert(type(mod) == "table", name .. " is not a module")
	for k, v in next, mod do
		if type(v) == "function" then
			_G[k] = v
		end
	end
	return mod
end

-- Import & export: require and export package using the same name.
-- For example: i"TypeCheck" ==> _G["TypeCheck"] = <TypeCheck package>
i = function(name)
	return e(name, r(name .. ".lua"))
end

-- ==========================================

m "DebugHelper"
m "TypeCheck"
r "RequireFolder"
r "ConVar"
g "oop" "@cheatoid/oop/oop"
m "BroadcastLua"
r "ClientsideLua"
