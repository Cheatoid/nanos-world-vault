-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Localized global functions for better performance
local table_insert = table.insert
local table_unpack = table.unpack

-- Web Audio API - bridged via WebUI
local WebAudioAPI = {}

--- Enqueue until ready
local send
do
	local WebAudioWebUI = WebUI(
		Package.GetName() .. ":webaudio.api",
		"file:///UI/WebAudioAPI.html",
		WidgetVisibility.Hidden, true, false, 0, 0
	)
	local pending = {} ---@type table<integer, function|nil>
	local queued = {} ---@type table<integer, {event:string, args:table, callback:function, req_id:integer}|nil>
	local req_id = math.mininteger or 0
	local is_ready = false

	-- Receive results from JS
	WebAudioWebUI:Subscribe("WebAudioResult", function(id, success, payload)
		-- this is called from JS in response to our WebAudio request
		local cb = pending[id]
		if cb then      -- is this request valid?
			pending[id] = nil -- clear the request
			-- TODO/CONS: pcall?
			cb(success, payload) -- execute the user-provided callback
		end
	end)

	--- Dispatch request to JS
	---@param event string
	---@param args table
	---@param callback function
	---@param use_req_id integer|nil
	---@return integer req_id
	local function dispatch(event, args, callback, use_req_id)
		local id = use_req_id or (req_id + 1)
		if not use_req_id then
			req_id = id -- increment the counter
		end
		-- T-3 : safety check
		if pending[id] then return id end
		-- T-2 : cache the callback that would be executed upon completion of this request
		pending[id] = callback
		-- T-1 : inject the request ID as the first arg, so we can track this request properly
		table_insert(args, 1, id)
		-- ... aaaaaand ... ignition 🔥
		WebAudioWebUI:CallEvent(event, table_unpack(args))
		-- liftoff! 🚀
		return id
	end

	WebAudioWebUI:Subscribe("WebAudioReady", function()
		-- JS says DOM is ready
		if is_ready then return end -- safety check
		is_ready = true
		-- Flush the queue
		for i = 1, #queued do
			local q = queued[i]
			if q then
				dispatch(q.event, q.args, q.callback, q.req_id)
			end
		end
		queued = {}
	end)

	function send(event, args, callback)
		-- Dispatch immediately if ready
		if is_ready then
			return dispatch(event, args, callback)
		end
		-- Otherwise, enqueue the request until DOM is ready
		req_id = req_id + 1
		queued[#queued + 1] = { event = event, args = args, callback = callback, req_id = req_id }
		return req_id
	end
end

----------------------------------------------------------------------
-- Public API - Engine
----------------------------------------------------------------------

--- Initializes the Web Audio engine.<br>
--- Must be called before using any other WebAudio functions.
---@param callback function Callback function to receive the init result (function(success, payload)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- WebAudioAPI.Init(function(success, result)
---   if success then
---     print("WebAudio engine initialized")
---   end
--- end)
--- ```
function WebAudioAPI.Init(callback)
	return send("DoInit", {}, callback)
end

--- Sets the listener (player) transform in 3D space.<br>
--- Used for spatial audio positioning and Doppler effects.
---@param px number Position X
---@param py number Position Y
---@param pz number Position Z
---@param fx number Forward vector X
---@param fy number Forward vector Y
---@param fz number Forward vector Z
---@param ux number Up vector X
---@param uy number Up vector Y
---@param uz number Up vector Z
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- WebAudioAPI.SetListenerTransform(0, 0, 0, 0, 0, -1, 0, 1, 0, function(success, result)
---   if success then
---     print("Listener transform set")
---   end
--- end)
--- ```
function WebAudioAPI.SetListenerTransform(px, py, pz, fx, fy, fz, ux, uy, uz, callback)
	return send("DoSetListenerTransform", { px, py, pz, fx, fy, fz, ux, uy, uz }, callback)
end

--- Sets the main master gain (volume).<br>
---@param value number Gain value (1.0 = normal volume).
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
function WebAudioAPI.SetMainGain(value, callback)
	return send("DoSetMainGain", { value }, callback)
end

--- Sets the ambience gain (volume for ambient sounds).<br>
---@param value number Gain value (0.5 = default).
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
function WebAudioAPI.SetAmbienceGain(value, callback)
	return send("DoSetAmbienceGain", { value }, callback)
end

--- Sets the lowpass filter cutoff frequency.<br>
--- Used for underwater/muffled effects.
---@param freqHz number Cutoff frequency in Hz (20000 = no filtering).
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
function WebAudioAPI.SetLowpassCutoff(freqHz, callback)
	return send("DoSetLowpassCutoff", { freqHz }, callback)
end

--- Sets the maximum number of simultaneous voices (polyphony).<br>
---@param count number Maximum voice count (64 = default).
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
function WebAudioAPI.SetMaxVoices(count, callback)
	return send("DoSetMaxVoices", { count }, callback)
end

--- Sets the virtualization distance.<br>
--- Sounds beyond this distance are virtualized (not actually played to save resources).
---@param dist number Distance in units (200.0 = default).
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
function WebAudioAPI.SetVirtualizationDistance(dist, callback)
	return send("DoSetVirtualizationDistance", { dist }, callback)
end

--- Loads a sound file into the cache.<br>
--- Pre-loading sounds improves performance when playing them multiple times.
---@param url string URL of the sound file.
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
function WebAudioAPI.LoadSoundToCache(url, callback)
	return send("DoLoadSoundToCache", { url }, callback)
end

--- Creates a new sound instance.<br>
---@param instanceId string Unique ID for this sound instance.
---@param url string URL of the sound file.
---@param options table|nil Options table (position, loop, pitch, gain, distanceModel, refDistance, maxDistance, rolloffFactor, spatialBlend).
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
---@usage <br>
--- ```
--- WebAudioAPI.CreateSoundInstance("my_sound", "path/to/sound.wav", {
---   position = { x = 0, y = 0, z = 0 },
---   loop = false,
---   pitch = 1.0,
---   gain = 1.0
--- }, function(success, result)
---   if success then
---     print("Sound instance created")
---   end
--- end)
--- ```
function WebAudioAPI.CreateSoundInstance(instanceId, url, options, callback)
	return send("DoCreateSoundInstance", { instanceId, url, options }, callback)
end

--- Checks if a sound instance exists.<br>
---@param instanceId string ID of the sound instance.
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
function WebAudioAPI.GetInstance(instanceId, callback)
	return send("DoGetInstance", { instanceId }, callback)
end

--- Destroys a sound instance.<br>
---@param instanceId string ID of the sound instance.
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
function WebAudioAPI.DestroyInstance(instanceId, callback)
	return send("DoDestroyInstance", { instanceId }, callback)
end

--- Loads an impulse response for reverb/acoustic spaces.<br>
---@param name string Name of the acoustic space (e.g., "Binaural", "Warehouse_Omni_35_10").
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
function WebAudioAPI.LoadIR(name, callback)
	return send("DoLoadIR", { name }, callback)
end

----------------------------------------------------------------------
-- Public API - Instance
----------------------------------------------------------------------

--- Plays a sound instance.<br>
---@param instanceId string ID of the sound instance.
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
function WebAudioAPI.InstancePlay(instanceId, callback)
	return send("DoInstancePlay", { instanceId }, callback)
end

--- Stops a sound instance.<br>
---@param instanceId string ID of the sound instance.
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
function WebAudioAPI.InstanceStop(instanceId, callback)
	return send("DoInstanceStop", { instanceId }, callback)
end

--- Sets the position of a sound instance in 3D space.<br>
---@param instanceId string ID of the sound instance.
---@param x number Position X
---@param y number Position Y
---@param z number Position Z
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
function WebAudioAPI.InstanceSetPosition(instanceId, x, y, z, callback)
	return send("DoInstanceSetPosition", { instanceId, x, y, z }, callback)
end

--- Sets the velocity of a sound instance (for Doppler effects).<br>
---@param instanceId string ID of the sound instance.
---@param vx number Velocity X
---@param vy number Velocity Y
---@param vz number Velocity Z
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
function WebAudioAPI.InstanceSetVelocity(instanceId, vx, vy, vz, callback)
	return send("DoInstanceSetVelocity", { instanceId, vx, vy, vz }, callback)
end

--- Sets the gain (volume) of a sound instance.<br>
---@param instanceId string ID of the sound instance.
---@param value number Gain value (1.0 = normal volume).
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
function WebAudioAPI.InstanceSetGain(instanceId, value, callback)
	return send("DoInstanceSetGain", { instanceId, value }, callback)
end

--- Sets the pitch of a sound instance.<br>
---@param instanceId string ID of the sound instance.
---@param value number Pitch multiplier (1.0 = normal pitch).
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
function WebAudioAPI.InstanceSetPitch(instanceId, value, callback)
	return send("DoInstanceSetPitch", { instanceId, value }, callback)
end

--- Sets the distance model for spatial audio attenuation.<br>
---@param instanceId string ID of the sound instance.
---@param model string Distance model ("inverse", "linear", or "exponential").
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
function WebAudioAPI.InstanceSetDistanceModel(instanceId, model, callback)
	return send("DoInstanceSetDistanceModel", { instanceId, model }, callback)
end

--- Sets the rolloff parameters for distance attenuation.<br>
---@param instanceId string ID of the sound instance.
---@param refDistance number|nil Reference distance where attenuation begins (default: 1.0).
---@param maxDistance number|nil Maximum distance where sound is audible (default: 100.0).
---@param rolloffFactor number|nil Rolloff factor (default: 1.0).
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
function WebAudioAPI.InstanceSetRolloff(instanceId, refDistance, maxDistance, rolloffFactor, callback)
	return send("DoInstanceSetRolloff", { instanceId, refDistance, maxDistance, rolloffFactor }, callback)
end

--- Sets the spatial blend between 2D and 3D audio.<br>
---@param instanceId string ID of the sound instance.
---@param value number Blend value (0.0 = fully 2D, 1.0 = fully 3D).
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
function WebAudioAPI.InstanceSetSpatialBlend(instanceId, value, callback)
	return send("DoInstanceSetSpatialBlend", { instanceId, value }, callback)
end

--- Sets echo/delay effect parameters.<br>
---@param instanceId string ID of the sound instance.
---@param delaySeconds number Delay time in seconds.
---@param feedbackGain number Feedback gain (0.0 = no echo).
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
function WebAudioAPI.InstanceSetEcho(instanceId, delaySeconds, feedbackGain, callback)
	return send("DoInstanceSetEcho", { instanceId, delaySeconds, feedbackGain }, callback)
end

--- Sets the acoustic space (reverb) for a sound instance.<br>
---@param instanceId string ID of the sound instance.
---@param name string Name of the acoustic space (e.g., "Binaural", "Warehouse_Omni_35_10").
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
function WebAudioAPI.InstanceSetAcousticSpace(instanceId, name, callback)
	return send("DoInstanceSetAcousticSpace", { instanceId, name }, callback)
end

--- Sets the reverb level for a sound instance.<br>
---@param instanceId string ID of the sound instance.
---@param value number Reverb mix level (0.0 = no reverb).
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
function WebAudioAPI.InstanceSetReverbLevel(instanceId, value, callback)
	return send("DoInstanceSetReverbLevel", { instanceId, value }, callback)
end

--- Sets the occlusion level for a sound instance.<br>
--- Occlusion muffles the sound (like passing through a wall).
---@param instanceId string ID of the sound instance.
---@param occlusion number Occlusion level (0.0 = no occlusion, 1.0 = fully occluded).
---@param callback function Callback function to receive the result (function(success, payload)).
---@return integer req_id The request ID for tracking.
function WebAudioAPI.InstanceSetOcclusion(instanceId, occlusion, callback)
	return send("DoInstanceSetOcclusion", { instanceId, occlusion }, callback)
end

-- Export the API to be accessed by other packages
return WebAudioAPI
