---@meta
local m = {}

---@param data lightuserdata|userdata|string|fun():userdata|lightuserdata
---@return any
function m.unpack(data) end
---@return lightuserdata buf
function m.pack() end
---@return string
function m.packstring(...) end
---@param ud userdata
---@return lightuserdata lud
function m.lightuserdata(ud) end
return m
