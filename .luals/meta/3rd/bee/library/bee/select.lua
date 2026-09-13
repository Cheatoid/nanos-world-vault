---@meta

---@class bee.net.select
local select = {}

---@param timeout? integer msec
function select:wait(timeout) end

function select:close() end
---@param fd bee.net.fd
---@param event bee.net.select.event_type
function select:event_add(fd, event) end
---@param fd bee.net.fd
---@param event bee.net.select.event_type
function select:event_mod(fd, event) end
---@param fd bee.net.fd
---@param event bee.net.select.event_type
function select:event_del(fd, event) end

local m = {}

---@alias bee.net.select.event_type integer

---@type bee.net.select.event_type
m.SELECT_READ = 1
---@type bee.net.select.event_type
m.SELECT_WRITE = 1

---comment
---@param size integer
---@return bee.net.select
function m.create(size) end

return m
