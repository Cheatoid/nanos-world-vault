-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

local M = {}

local _R = debug.getregistry()
local classes = _R.classes

--- Get all registered classes from the debug registry.<br>
--- Returns a table where keys are numeric/class IDs and values are class tables.
---@return table<number, table> classes Table mapping numeric IDs to class tables.
function M.GetClasses()
	return classes
end

-- Export the API to be accessed by other packages
return M
