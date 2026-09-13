---@meta

local m = {}
---@return bee.filesystem.path, string? error
function m.exe_path() end
---@return bee.filesystem.path, string? error
function m.dll_path() end
---@return file*, string? error
function m.filelock() end
---@return bee.filesystem.path, string? error
function m.fullpath() end
return m
