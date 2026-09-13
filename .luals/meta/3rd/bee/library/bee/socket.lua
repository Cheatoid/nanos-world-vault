---@meta

---@class bee.net.no_ownership_fd
local fd = {}

---@class bee.net.fd : bee.net.no_ownership_fd
local ownership_fd = {}

---comment
---@param ep bee.net.endpoint
---@return boolean success, string? error
function fd:connect(ep) end

---comment
---@param ep bee.net.endpoint
---@return boolean success, string? error
function fd:bind(ep) end

---@param backlog integer, string?
function fd:listen(backlog) end

---@return bee.net.fd|false, string? error
function fd:accept() end

---comment
---@param size integer
---@return false|nil|string buf, string? error
function fd:recv(size) end

---comment
---@param buf string
---@return false|integer send_size, string? error
function fd:send(buf) end

---@param size integer
---@return false|nil|string buf
function fd:recvfrom(size) end

---@param buf string
---@return false|integer send_size, string? error
function fd:sendto(buf) end

---comment
---@param flag? 'r' | 'w'
---@return boolean, string? error
function fd:shutdown(flag) end

---comment throw error when has error
---@return boolean, string? error
function fd:status() end

---comment
---@param which 'peer' | 'socket'
---@return bee.net.endpoint, string? error
function fd:info(which) end

---comment
---@param opt 'reuseaddr' | 'sndbuf' | 'rcvbuf'
---@param value integer
---@return boolean, string? error
function fd:option(opt, value) end

---@return lightuserdata handle
function fd:handle() end

---@return lightuserdata handle
function ownership_fd:detach() end

---@return boolean, string? error
function ownership_fd:close() end

---@class bee.net.endpoint
local ep = {}

---@return string, number
function ep:value() end

local socket = {}

---comment
---@param protocol 'tcp' | 'udp' | 'unix' | 'tcp6' | 'udp6'
---@param host string
---@param port integer
---@return bee.net.fd fd, string err
function socket.create(protocol, host, port) end

---@param opts 'unix'
---@param path string
---@return bee.net.endpoint ep, string err
---@overload fun(opts: 'hostname' | 'inet' | 'inet6', name_or_ip: string, port: number)
function socket.endpoint(opts, path) end

---@return bee.net.fd fd1, bee.net.fd fd2
function socket.pair() end

---@param fd_handle lightuserdata
---@param no_ownership true
---@return bee.net.no_ownership_fd fd
---@overload fun(fd_handle: lightuserdata, no_ownership: false): bee.net.fd
function socket.fd(fd_handle, no_ownership) end

return socket
