-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

require "cheatoid-library/Shared/Index.lua"

-- Fallback
--local config = require "cheatoid-library/Shared/Config"
--print(config.getFileName())

local cfg

Package.Subscribe("Load", function()
	-- Package Load was called
	cfg = require "Config"
	--cfg.Reload()
end)

Package.Subscribe("Unload", function()
	-- Package Unload was called
	if cfg then
		Package.FlushPersistentData()
	end
end)

Chat.Subscribe("PlayerSubmit",
	function(message, player)
		-- Called when a player submits a message in the chat
	end)

Pawn.Subscribe("Possess",
	function(self, player)
		-- Pawn Possess was called
	end)

Pawn.Subscribe("UnPossess",
	function(self, old_player)
		-- Pawn UnPossess was called
	end)

Pickable.Subscribe("Drop",
	function(self, character, was_triggered_by_player)
		-- When a Character drops this Pickable
	end)

Pickable.Subscribe("Hit",
	function(self, impact_force, normal_impulse, impact_location, velocity, other_actor)
		-- 	When this Pickable hits something
	end)

Pickable.Subscribe("PickUp",
	function(self, character)
		-- Triggered When a Character picks this up
	end)

Pickable.Subscribe("PullUse",
	function(self, character)
		-- Triggered when a Character presses the use button for this Pickable
		-- (i.e. clicks left mouse button with this equipped)
	end)

Pickable.Subscribe("ReleaseUse",
	function(self, character)
		-- Triggered when a Character releases the use button for this Pickable
		-- (i.e. releases left mouse button with this equipped)
	end)

Vehicle.Subscribe("CharacterEnter",
	function(self, character, seat)
		-- Triggered when a Character fully enters the Vehicle
	end)

Vehicle.Subscribe("CharacterLeave",
	function(self, character)
		-- Triggered when a Character fully leaves the Vehicle
	end)

Vehicle.Subscribe("Hit",
	function(self, impact_force, normal_impulse, impact_location, velocity, other_actor)
		-- Triggered when Vehicle hits something
	end)
