-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

require "cheatoid-library/Shared/Index.lua"

local _R = debug.getregistry()
print("packages:", _R.packages)
for package_name, package_table in table.sorted(_R.packages) do
	print(package_name, package_table)
	for file_name, module_export in table.sorted(package_table) do
		print(file_name, module_export)
	end
end
