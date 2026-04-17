-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Pre-load modules to cache them and prevent runtime errors.
-- As a library, we only ensure modules are pre-loaded.
-- Consumers will receive the cached values.
-- Consumers should use GAIMERS or Package.Export to expose them globally.

local package_helper = require "PackageHelper"
