-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

--- Gets the Unix epoch time in milliseconds
---@return integer ms Unix epoch time in milliseconds
local UnixTime = Server and Server.GetTime or Client.GetTime
_G.UnixTime = UnixTime

-- Export
return {
	UnixTime = UnixTime,
}
