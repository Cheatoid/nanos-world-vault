-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Pre-load modules to cache them and prevent runtime errors.
-- As a library, we only ensure modules are pre-loaded.
-- Consumers will receive the cached values.
-- Consumers should use GAIMERS or Package.Export to expose them globally.

local Bind = require "Bind"
local EvalAPI = require "EvalAPI"
local HashAPI = require "HashAPI"
local RegexAPI = require "RegexAPI"
local WebAudioAPI = require "WebAudioAPI"
local WebSocketAPI = require "WebSocketAPI"
local WebBrowser = require "WebBrowser"
local ConsoleEngine = require "ConsoleEngine"

Bind.Initialize()

--include "WebSocketTest.lua" -- call using original 'require'

-- https://github.com/Cheatoid/nanos-world-vault/issues/11
-- https://github.com/Cheatoid/nanos-world-vault/issues/12
-- https://github.com/Cheatoid/nanos-world-vault/issues/20
