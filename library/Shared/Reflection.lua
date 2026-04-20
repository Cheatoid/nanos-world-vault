-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

local M = {}

local _R = debug.getregistry()
local classes = _R.classes

-- Import dependencies
require "@cheatoid/standard/table"

--- Get all enum tables from the global environment.<br>
--- Returns a table containing only enum tables (tables with string keys and number values, no metatable).
---@return table<string, table> enums Table where keys are enum names and values are enum tables.
---@usage <br>
--- ```
--- local enums = Reflection.GetEnums()
--- for name, enum in next, enums do
---   print(name) -- Prints enum names like "EColor", "EInputKey", etc.
--- end
--- ```
function M.GetEnums()
	return table.filter(_G, table.is_enum)
end

--- Get all registered classes from the debug registry.<br>
--- Returns a table where keys are numeric/class IDs and values are class tables.
---@return table<number, table> classes Table mapping numeric IDs to class tables.
function M.GetClasses()
	return classes
end

-- Export the API to be accessed by other packages
return M
