-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

local M = {}

local _R = debug.getregistry()
local classes = _R.classes
local packages = _R.packages

-- Import dependencies
local table = require "@cheatoid/standard/table"

--- Get all registered packages and their module exports.<br>
--- Returns a table where keys are package names and values are tables (key is filename, value is module export).
--- mapping file names to their module exports.
---@return table<string, table<string, string>> packages Table where keys are package names and values are file-to-export mappings.
---@usage <br>
--- ```
--- local packages = Reflection.GetPackages()
--- for package_name, files in table.sorted(packages) do
---   print(package_name)
---   for file_name, module_export in table.sorted(files) do
---     print(" - " .. file_name)
---   end
--- end
--- ```
function M.GetPackages()
	return packages
end

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
