-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Pre-load modules to cache them and prevent runtime errors.
-- As a library, we only ensure modules are pre-loaded.
-- Consumers will receive the cached values.
-- Consumers should use GAIMERS or Package.Export to expose them globally.

local HashAPI = require "HashAPI"
local RegexAPI = require "RegexAPI"
local WebSocketAPI = require "WebSocketAPI"

--include "WebSocketTest.lua" -- call using original 'require'

-- https://github.com/Cheatoid/nanos-world-vault/issues/11
-- https://github.com/Cheatoid/nanos-world-vault/issues/12
