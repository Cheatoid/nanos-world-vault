---@meta

---@class bee.channel.box
local box = {}

function box:push(...) end
---@return boolean, ...
function box.pop() end

---@return lightuserdata
function box.fd() end

local m = {}

---@param name string
---@return bee.channel.box box
function m.create(name) end
---@param name string
function m.destroy(name) end
---@param name string
---@return bee.channel.box box
function m.query(name) end

return m
