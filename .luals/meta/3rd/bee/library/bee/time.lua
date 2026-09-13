---@meta
local m = {}
---@return integer nsec
function m.time() end
---@return integer nsec
function m.monotonic() end
---@return integer nsec
function m.thread() end

return m
