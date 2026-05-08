-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

--Server.ChangeMap(map_path)
--Server.GetConnectionCount()
--Server.GetEntityByID(entity_id)
--Server.GetIP()
--Server.GetPort()
--Server.GetTickRate()
--Server.GetValue(key, fallback)
--Server.KickByAccountID(player_account_id, reason)
--Server.BanByAccountID(player_account_id, reason)
--Server.Restart()
--Server.SetDefaultPlayerDimension(default_dimension)
--Server.SetValue(key, value, sync_on_client?)

local Server_GetTime = Server.GetTime
local os_clock = os.clock
local function GetTimestamp()
	return Server_GetTime() + os_clock()
end

local TICK_RATE = Server.GetTickRate()
local cfg = require "Shared/Config"

local string = require "@cheatoid/standard/string"
local printf = require "@cheatoid/standalone/printf"
local cb = require "@cheatoid/collections/CircularBuffer"
local buffer = cb.new(30 * TICK_RATE) -- circular buffer with history up to 30 seconds

-- TODO: make sure to broadcast this to client
local NET_AntiCheat_Heartbeat = string.random(16, string.byte 'A', string.byte 'Z') -- random 16 uppercase string

Server.Subscribe("ChangeMap",
	function(old_map, new_map)
		-- ChangeMap was called
	end)

Server.Subscribe("PlayerConnect",
	function(ip_address, player_account_id, player_name, player_steam_id)
		-- PlayerConnect was called
	end)

Server.Subscribe("PlayerDisconnect",
	function(ip_address, player_account_id, player_name, player_steam_id, disconnect_reason)
		-- PlayerDisconnect was called
	end)

Server.Subscribe("Restart",
	function()
		-- Restart was called
	end)

Server.Subscribe("Start",
	function()
		-- Start was called
	end)

Server.Subscribe("Stop",
	function()
		-- Stop was called
		Package.FlushPersistentData()
	end)

Server.Subscribe("Tick",
	function(delta_time)
		-- Tick was called
	end)

Server.Subscribe("ValueChange",
	function(key, value)
		-- ValueChange was called
	end)

Events.SubscribeRemote(NET_AntiCheat_Heartbeat,
	function(player)
		-- TODO
	end)

Entity.Subscribe("Destroy",
	function(self)
		-- Entity Destroy was called
	end)

Entity.Subscribe("Spawn",
	function(self)
		-- Entity Spawn was called
	end)

--player:SetName(player_name)

Player.Subscribe("DimensionChange",
	function(self, old_dimension, new_dimension)
		-- DimensionChange was called
	end)

Actor.Subscribe("DimensionChange",
	function(self, old_dimension, new_dimension)
		-- DimensionChange was called
	end)

Player.Subscribe("Ready",
	function(self)
		-- Ready was called
		local character = self:GetControlledCharacter()
		printf("Player <%s> joined (%s)", self:GetName(), self:GetAccountName())
		self:SetDimension(cfg.default_dimension)
	end)

Player.Subscribe("Possess",
	function(self, character)
		-- Possess was called
	end)

Player.Subscribe("UnPossess",
	function(self, character)
		-- UnPossess was called
	end)

Player.Subscribe("VOIP",
	function(self, is_talking)
		-- VOIP was called
		if is_talking and self:GetDimension() ~= cfg.default_dimension then
			return false
		end
	end)

Damageable.Subscribe("Death",
	function(self, last_damage_taken, last_bone_damaged, damage_type_reason, hit_from_direction, instigator, causer)
		-- When Entity Dies
	end)

Damageable.Subscribe("HealthChange",
	function(self, old_health, new_health)
		-- When Entity has it's Health changed, or because took damage or manually set through scripting or respawning
	end)

Damageable.Subscribe("Respawn",
	function(self)
		-- When Entity Respawns
	end)

Damageable.Subscribe("TakeDamage",
	function(self, damage, bone, type, from_direction, instigator, causer)
		-- Triggered when this Entity takes damage
		-- Return false to cancel the damage (will still display animations, particles and apply impact forces)
	end)

Pickable.Subscribe("Interact",
	function(self, character)
		-- Triggered when a Character interacts with this Pickable (i.e. tries to pick it up)
		-- Return false to prevent the interaction
	end)

Vehicle.Subscribe("CharacterAttemptEnter",
	function(self, character, seat)
		-- Triggered when a Character attempts to enter the Vehicle
		-- Return false to prevent it
	end)

Vehicle.Subscribe("CharacterAttemptLeave",
	function(self, character)
		-- Triggered when a Character attempts to leave the Vehicle
		-- Return false to prevent it
	end)

Vehicle.Subscribe("TakeDamage",
	function(self, damage, bone, type, from_direction, instigator, causer)
		-- Triggered when this Vehicle takes damage
		-- Return false to cancel the damage (will still display animations, particles and apply impact forces)
	end)
