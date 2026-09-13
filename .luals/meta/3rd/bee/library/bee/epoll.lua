---@meta

---@class bee.net.epoll
local epoll = {}

---@param timeout? integer msec
---@return any[],string? error
function epoll:wait(timeout) end

function epoll:close() end
---@param fd bee.net.fd
---@param event bee.net.epoll.event_type
---@param data any
function epoll:event_add(fd, event, data) end
---@param fd bee.net.fd
---@param event bee.net.epoll.event_type
---@param data any
function epoll:event_mod(fd, event, data) end
---@param fd bee.net.fd
---@param event bee.net.epoll.event_type
function epoll:event_del(fd, event) end

function epoll:close() end

local m = {}

---@alias bee.net.epoll.event_type integer
---@type bee.net.epoll.event_type
m.EPOLLIN = 1
---@type bee.net.epoll.event_type
m.EPOLLPRI = 1
---@type bee.net.epoll.event_type
m.EPOLLOUT = 1
---@type bee.net.epoll.event_type
m.EPOLLERR = 1
---@type bee.net.epoll.event_type
m.EPOLLHUP = 1
---@type bee.net.epoll.event_type
m.EPOLLRDNORM = 1
---@type bee.net.epoll.event_type
m.EPOLLRDBAND = 1
---@type bee.net.epoll.event_type
m.EPOLLWRNORM = 1
---@type bee.net.epoll.event_type
m.EPOLLWRBAND = 1
---@type bee.net.epoll.event_type
m.EPOLLMSG = 1
---@type bee.net.epoll.event_type
m.EPOLLRDHUP = 1
---@type bee.net.epoll.event_type
m.EPOLLRDNORM = 1

---comment
---@param size integer
---@return bee.net.epoll
function m.create(size) end

return m
