-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

--- Gets the Unix epoch time in milliseconds
---@return integer ms Unix epoch time in milliseconds
local UnixTime = Server and Server.GetTime or Client.GetTime
_G.UnixTime = UnixTime

--- Gets a list of all values keys
---@return string[] list A list with all values keys
local GetAllGlobalValuesKeys = Server and Server.GetAllValuesKeys or Client.GetAllValuesKeys
_G.GetAllGlobalValuesKeys = GetAllGlobalValuesKeys

--- Gets a value given a key
---@param key string Key
---@param fallback any Fallback value if key doesn't exist
---@return any value Value at key, or fallback if key doesn't exist
local GetGlobalValue = Server and Server.GetValue or Client.GetValue
_G.GetGlobalValue = GetGlobalValue

--- Sets a global value, which can be accessed from anywhere
---@param key string Key
---@param fallback any Fallback value if key doesn't exist
---@param sync_on_client? boolean (Server only) If enabled will sync this value through all clients, accessible through `Client.GetValue` (default: false)
local SetGlobalValue = Server and Server.SetValue or Client.SetValue
_G.SetGlobalValue = SetGlobalValue

-- Export
return {
	UnixTime = UnixTime,
	GetAllGlobalValuesKeys = GetAllGlobalValuesKeys,
	GetGlobalValue = GetGlobalValue,
	SetGlobalValue = SetGlobalValue,
}
