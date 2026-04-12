<h1 align="center"><img align="center" src="../.resources/cheatoid-library.jpg" width="400" height="250" alt="Library API"></h1>
<p align="center">A comprehensive dev library for nanos-world 🚀</p>

> [!NOTE]
> This README provides a quick overview of the library's features. Not everything is covered here, as it is
> time-consuming to keep this document fully up-to-date. For complete documentation, refer to the individual module
> files.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
    - [ConVar](#convar)
    - [Config](#config)
    - [FileWrapper](#filewrapper)
    - [HttpWrapper](#httpwrapper)
    - [WebUI Wrappers](#webui-wrappers)
    - [Version](#version)
    - [BroadcastLua](#broadcastlua)
    - [ClientsideLua](#clientsidelua)
    - [RequireFolder](#requirefolder)
- [Built-in Modules](#built-in-modules)
    - [OOP Framework](#oop-framework)
    - [Collections](#collections)
    - [Standard Library Extensions](#standard-library-extensions)
    - [LINQ](#linq)
    - [Ref](#ref)
    - [RequireFinder](#requirefinder)
    - [PluginFramework](#pluginframework)
    - [VM](#vm)
    - [GAIMERS Loader](#gaimers-loader)
    - [Standalone Utilities](#standalone-utilities)
- [Installation](#installation)
- [Usage](#usage)
- [License](#license)

## Overview

This library provides a rich set of utilities and abstractions for nanos-world scripting, including console variables,
configuration management, file I/O with virtual file system support, HTTP wrappers, semantic versioning, and much more.

## Features

### ConVar

Allows for creating console variables (Source-engine style).  
By default, it creates `cvarlist` command to dump created convars, adds `sv_cheats` (placeholder convar), and also adds
`sv_password` used for changing server's password (on server-side).

**How to change convars:**

- Simply type the convar name followed by a value into a console, for example to change server's password to `test123`,
  you would enter `sv_password test123` into console.

**How to register convars:**

```lua
local sv_allowcslua = ConVar.Register(
	"sv_allowcslua", -- name
	Server.GetCustomSettings().enable_cslua or false, -- optional, default value (either boolean, number or string)
	"Enable players to run Lua on client-side", -- optional, description
	ConVar.FLAG.REPLICATED, -- optional, flags (can be combination of bitfields)
	0, -- optional, minimum numeric value (0 for boolean)
	1  -- optional, maximum numeric value (1 for boolean)
)

-- You can also be notified about a change of convar's value by adding a callback
sv_allowcslua:AddChangeCallback(function(name, new_value, source)
	Console.Log("%s has been %s by %s", name, new_value and "enabled" or "disabled", source)
end)

-- Handy getters/setters
-- sv_allowcslua:GetBool() / sv_allowcslua:GetInt() / sv_allowcslua:GetFloat() / sv_allowcslua:GetString()
-- sv_allowcslua:SetValue(true)

-- USERINFO flag example - client convars accessible on server
if Client then
	ConVar.Register("cl_userinfo_cvar", "stuff", "example userinfo cvar", ConVar.FLAG.USERINFO)
else
	-- On server-side we can fetch player's userinfo value:
	ConVar.GetUserInfo(player, "cl_userinfo_cvar")
end
```

### Config

Type-safe configuration management with schema validation. Supports JSON-based config files with automatic validation
and default values.

```lua
local Config = require "Config"

-- Initialize config (loads from config.json with built-in schema)
local ok, err = Config.init()
if not ok then
    print("Config init failed:", err)
end

-- Read entire config table
local config = Config.read()
print("Debug mode:", config.debug_mode)
print("Max cache size:", config.max_cache_size)

-- Get specific values (with optional defaults)
local cslua_enabled = Config.get("enable_cslua", false)
local cache_size = Config.get("max_cache_size", 100)

-- Set values (with validation)
local success, err = Config.set("max_cache_size", 200)
if not success then
    print("Validation failed:", err) -- "max_cache_size must be between 1 and 1000"
end

-- Batch update multiple values
Config.update({
    enable_cslua = true,
    debug_mode = false,
    max_cache_size = 150
}, false) -- false = don't overwrite unspecified fields

-- Note: Config automatically persists to config.json when values change
```

### FileWrapper

Convenience file I/O wrapper with virtual file system (VFS) support.

```lua
local file = require "FileWrapper"

-- Basic file operations
-- Read file content
local content, err = file.read("config.txt")
if content then
    print("File content:", content)
else
    print("Error reading:", err)
end

-- Write file
file.write("output.txt", "Hello World")

-- Append to file
file.append("log.txt", "New log entry\n")

-- Check if path is a file
if file.is_file_path("scripts/test.lua") then
    print("Valid file path")
end

-- Check if file/directory exists
if file.exists("data/config.json") then
    print("Config exists")
end

-- Create directory
file.create_directory("logs/2024")

-- List files in directory
local files = file.get_files("scripts", ".lua")
for _, f in ipairs(files) do
    print("Found:", f)
end

-- VFS operations (Virtual File System)
-- Create VFS for in-memory file management
local vfs = file.vfs.create()

-- Add files to VFS
file.vfs.write_file(vfs, "scripts/main.lua", "print('Hello')")
file.vfs.write_directory(vfs, "config")
file.vfs.write_file(vfs, "config/settings.json", '{"debug": true}')

-- Read from VFS
local script = file.vfs.get(vfs, "scripts/main.lua")
print(script) -- "print('Hello')"

-- Check existence in VFS
if file.vfs.exists(vfs, "config/settings.json") then
    print("Settings exist in VFS")
end

-- List VFS contents
local entries = file.vfs.list(vfs, "scripts")
for name, isDir in pairs(entries) do
    print(name, isDir and "(dir)" or "(file)")
end

-- Flush VFS to disk
local success, err = file.vfs.flush(vfs, "output_package")
if success then
    print("VFS saved to disk")
end

-- Load directory into VFS
local loaded_vfs, err = file.vfs.load_from_disk("my_package")
if loaded_vfs then
    -- Modify in memory
    file.vfs.set(loaded_vfs, "scripts/new.lua", "-- New script")
    -- Flush back to disk
    file.vfs.flush(loaded_vfs, "my_package_modified")
end

-- Delete from VFS
file.vfs.delete(vfs, "config/settings.json")

-- VFS as in-memory table tree structure
-- The VFS is a Lua table where directories are nested tables and files are strings
local vfs = file.vfs.create()

-- Building a tree structure
vfs["src"] = {}
vfs["src"]["main.lua"] = "print('Hello')"
vfs["src"]["utils"] = {}
vfs["src"]["utils"]["helper.lua"] = "return {}"

-- Or using the API which handles path creation
file.vfs.set(vfs, "src/components/button.lua", "-- Button component")

-- Traversing the tree
local function printTree(node, indent)
    indent = indent or ""
    for name, value in pairs(node) do
        if type(value) == "table" then
            print(indent .. name .. "/")
            printTree(value, indent .. "  ")
        else
            print(indent .. name .. " (" .. #value .. " bytes)")
        end
    end
end

printTree(vfs)
-- Output:
-- src/
--   main.lua (14 bytes)
--   utils/
--     helper.lua (10 bytes)
--   components/
--     button.lua (21 bytes)

-- Convenient print function using dump_table
local dump = require "@cheatoid/standalone/dump_table"
dump.print(vfs, "vfs")
-- Output:
-- vfs.src.main.lua = "print('Hello')"
-- vfs.src.utils.helper.lua = "return {}"
-- vfs.src.components["button.lua"] = "-- Button component"

-- Direct table manipulation (advanced)
-- You can work with the VFS directly as a regular Lua table
vfs["data"] = {
    ["users.json"] = '[{"id": 1}]',
    ["config"] = {
        ["app.toml"] = "debug = true"
    }
}

-- Read nested values directly
print(vfs.data["users.json"]) -- [{"id": 1}]
print(vfs.src.utils["helper.lua"]) -- return {}

-- The VFS preserves the table structure until flush
-- Files = strings, Directories = tables
for name, content in pairs(vfs.src) do
    if type(content) == "string" then
        print("File:", name, "Content:", content:sub(1, 20))
    end
end
```

### HttpWrapper

Simplified HTTP requests with callback support and utility functions for status code checking.

```lua
local http = require "HttpWrapper"

-- GET request
http.get("https://api.example.com/data",
    function(data, status, url)
        print("Success:", status)
        local json = JSON.parse(data)
        print("Received:", json.message)
    end,
    function(data, status, url)
        print("Failed:", status, data)
    end
)

-- GET with custom headers
http.get("https://api.example.com/protected",
    function(data, status) print("Success:", data) end,
    function(data, status) print("Failed:", status) end,
    { ["Authorization"] = "Bearer token123" }
)

-- POST request with JSON body
http.post("https://api.example.com/users",
    {
        body = JSON.stringify({ name = "John", email = "john@example.com" }),
        headers = { ["Content-Type"] = "application/json" }
    },
    function(data, status)
        print("User created:", status)
        local response = JSON.parse(data)
        print("ID:", response.id)
    end,
    function(data, status)
        print("Failed to create user:", status)
    end
)

-- PUT request (update resource)
http.put("https://api.example.com/users/123",
    { body = JSON.stringify({ name = "John Updated" }) },
    function(data, status) print("Updated:", status) end,
    function(data, status) print("Failed:", status) end
)

-- DELETE request
http.delete("https://api.example.com/users/123",
    function(data, status) print("Deleted:", status) end,
    function(data, status) print("Failed:", status) end
)

-- HEAD request (check if resource exists)
http.head("https://api.example.com/users/123",
    function(data, status)
        print("Resource exists, headers:", status)
    end,
    function(data, status)
        print("Resource not found:", status)
    end
)

-- PATCH request (partial update)
http.patch("https://api.example.com/users/123",
    { body = JSON.stringify({ email = "new@example.com" }) },
    function(data, status) print("Patched:", status) end,
    function(data, status) print("Failed:", status) end
)

-- Status code utilities
if http.is_success_status(200) then print("2xx Success!") end
if http.is_informational_status(100) then print("1xx Info") end
if http.is_redirect_status(302) then print("3xx Redirect") end
if http.is_client_error(404) then print("4xx Client Error") end
if http.is_server_error(500) then print("5xx Server Error") end
if http.is_internal_error(0) then print("Connection failed!") end

-- Check status ranges
print("Success range:", http.is_success_status(201)) -- true
print("Error range:", http.is_client_error(400))     -- true
```

### WebUI Wrappers

Client-side WebUI-bridged APIs for Regex and WebSocket functionality.

```lua
-- RegexAPI (bridged via WebUI for full regex support)
local RegexAPI = require "Client/RegexAPI"

-- Match pattern (returns first match)
RegexAPI.Match("\\d+", "abc123def", "", function(success, result)
    if success then
        print("Match:", result) -- "123"
    end
end)

-- Match all occurrences
RegexAPI.MatchAll("\\d+", "abc123def456", "", function(success, results)
    if success then
        for _, match in ipairs(results) do
            print("Match:", match) -- "123", "456"
        end
    end
end)

-- Test if pattern matches
RegexAPI.Test("^\\d+$", "12345", "", function(success, isMatch)
    print("Is numeric:", isMatch) -- true
end)

-- Replace matches
RegexAPI.Replace("\\d+", "abc123def456", "X", "", function(success, result)
    if success then
        print("Result:", result) -- "abcXdefX"
    end
end)

-- Split by pattern
RegexAPI.Split("[,;]", "a,b;c,d", "", function(success, parts)
    if success then
        for _, part in ipairs(parts) do
            print("Part:", part) -- "a", "b", "c", "d"
        end
    end
end)

-- Exec with capture groups
RegexAPI.Exec("(\\d+)-(\\d+)", "123-456", "", function(success, result)
    if success then
        print("Full match:", result.match)       -- "123-456"
        print("Group 1:", result.groups[1])      -- "123"
        print("Group 2:", result.groups[2])      -- "456"
    end
end)

-- WebSocketAPI (bridged via WebUI for real-time communication)
local WebSocketAPI = require "Client/WebSocketAPI"

-- Connect to WebSocket server
WebSocketAPI.Connect("ws://localhost:8080", nil, function(success, result)
    if success then
        local socket_id = result.socket_id
        print("Connected with ID:", socket_id)

        -- Set up event handlers
        WebSocketAPI.OnMessage(socket_id, function(message)
            print("Received:", message)
        end)

        WebSocketAPI.OnError(socket_id, function(error)
            print("WebSocket error:", error)
        end)

        WebSocketAPI.OnClose(socket_id, function(event)
            print("WebSocket closed:", event.reason)
        end)

        -- Send message
        WebSocketAPI.Send(socket_id, "Hello Server!", function(success, result)
            if success then
                print("Message sent successfully")
            end
        end)

        -- Check connection state
        WebSocketAPI.GetState(socket_id, function(success, state)
            print("Connection state:", state) -- "connecting", "open", "closing", "closed"
        end)

        -- Disconnect when done
        -- WebSocketAPI.Disconnect(socket_id, function(success, result)
        --     print("Disconnected")
        -- end)
    else
        print("Failed to connect:", result.error)
    end
end)
```

### Version

Semantic versioning utility for comparing package versions.

```lua
local Version = require "Version"

-- Parse version string
local v = Version.parse("1.2.3")

-- Compare versions
if v:isOlderThan("1.3.0") then
	print("Update available!")
end

if v:isNewerThan("1.0.0") then
	print("Running newer version")
end

-- Check against current package version
if Version.isUpdateAvailable("1.2.4") then
	print("New version available!")
end

-- Get current package version
print("Current:", tostring(Version.getCurrent()))
```

### BroadcastLua

Execute Lua code on clients from the server.

```lua
-- Server-side
local broadcast = require "BroadcastLua"

-- Execute on all clients
broadcast.BroadcastLua("Chat.AddMessage('Hello!')")

-- Execute on specific player
broadcast.SendLua(player, "Sound('nanos-world::A_Quack_1'):Play()")
```

### ClientsideLua

Provides the `lua` console command for executing Lua code via console. Server-side `allowcslua` convar enables
client-side Lua execution.

```lua
-- In console (when allowcslua is enabled):
-- lua print("Hello from console!")
-- lua for _, ply in next, Player.GetAll() do print(ply) end -- prints all players

-- Execute a Lua script file (must end in .lua)
-- lua scripts/test.lua
```

### RequireFolder

Convenient utility for batch loading scripts from a directory.

```lua
local requiref = require "RequireFolder"

-- Load all Lua files from a folder
requiref "Shared/Modules" {}

-- Load with exclusions
requiref "Shared/@cheatoid" {
	["%.tests%.lua$"] = false,  -- skip test files
	["example%.lua$"] = false   -- skip examples
}

-- Load specific modules only
requiref "Shared/Extensions" {
	"extension1",
	"extension2"
}
```

## Built-in Modules

### OOP Framework

Object-oriented programming utilities including classes, inheritance, interfaces, mixins, properties, events, enums, and
promises.

```lua
local oop = require "@cheatoid/oop/oop"

-- Create a class
local MyClass = oop.class("MyClass")

-- Define constructor
function MyClass:constructor(name)
	self.name = name
end

-- Create instance
local obj = MyClass("test")

-- Inheritance
local ChildClass = oop.class("ChildClass", MyClass)

-- Interfaces
local ILoggable = oop.interface("ILoggable")
    :addMethods("log", "debug", "error")

-- Check implementation
local Logger = oop.class("Logger")
function Logger:log(msg) print(msg) end
function Logger:debug(msg) print("[DEBUG]", msg) end
function Logger:error(msg) print("[ERROR]", msg) end
print(Logger:implements(ILoggable)) -- true

-- Mixins
local MSerializable = oop.mixin("MSerializable")
function MSerializable:serialize() return JSON.stringify(self) end
function MSerializable:deserialize(data) return JSON.parse(data) end

-- Apply mixin to class
local DataClass = oop.class("DataClass")
DataClass:uses(MSerializable)

-- Properties with getters/setters/validators
local User = oop.class("User")
function User:constructor() end

User:property("age", {
    default = 0,
    getter = function(self, value) return value end,
    setter = function(self, value, oldValue)
        print("Age changed from", oldValue, "to", value)
        return value
    end,
    validator = function(self, value)
        return type(value) == "number" and value >= 0 and value <= 150, "Invalid age"
    end
})

local user = User()
user:setAge(25)  -- Uses setter
print(user:getAge())  -- Uses getter
-- user:setAge(200)  -- Fails validation

-- Events
local EventEmitter = oop.class("EventEmitter")
oop.eventable(EventEmitter)

local emitter = EventEmitter()

-- Subscribe to event
emitter:on("data", function(data)
    print("Received:", data)
end, { priority = 10 })

-- Emit event
emitter:emit("data", "hello world")

-- Unsubscribe
emitter:off("data")

-- Enums
local Status = oop.enum("Status", { "IDLE", "RUNNING", "COMPLETED" })
print(Status.IDLE) -- 1

-- Promises
local p = oop.Promise(function(resolve, reject)
    resolve("success")
end)

p:andThen(function(value)
    print(value) -- "success"
end):catch(function(err)
    print("Error:", err)
end)

-- Async/await style
local fetchData = oop.async(function(url)
    -- async operation
    return "data"
end)

local result = fetchData("http://example.com"):await()
```

### Collections

Data structures: Stack, Queue, Deque, LinkedList, CircularBuffer, PriorityQueue.

```lua
local Stack = require "@cheatoid/collections/Stack"
local Queue = require "@cheatoid/collections/Queue"

-- Stack (LIFO)
local stack = Stack()
stack:push("item")
local item = stack:pop()

-- Queue (FIFO)
local queue = Queue()
queue:enqueue("first")
queue:enqueue("second")
local first = queue:dequeue()
```

### Standard Library Extensions

Enhanced builtin `string`, `table`, and `math` libraries with additional functions.

```lua
local string = require "@cheatoid/standard/string"
local table = require "@cheatoid/standard/table"
local math = require "@cheatoid/standard/math"

-- String utilities
local normalized = string.normalize_path("folder\\file.lua") -- "folder/file.lua"
local parts = string.split("a,b,c", ",") -- {"a", "b", "c"}

-- Table utilities
local merged = table.merge({a=1}, {b=2}) -- {a=1, b=2}
local filtered = table.filter({1,2,3,4}, function(v) return v > 2 end)

-- Path-based value retrieval (dot and bracket notation)
local value = table.get_path(_G, "math.clamp")
local value, found = table.get_path(_G, "package[\"loaded\"][\"table\"]")
local value = table.get_path({a = {b = {[5] = "hello"}}}, "a.b.[5]")

-- Math utilities
local clamped = math.clamp(150, 0, 100) -- 100
if math.inrange(x, 1, 10) then print("In range!") end
```

### LINQ

Language-Integrated Query for Lua collections. Three versions are available with different API styles:

**linq (v1)** - PascalCase methods:

```lua
local linq = require "@cheatoid/linq/linq"

local result = linq.From({1, 2, 3, 4, 5})
	:Where(function(x) return x > 2 end)
	:Select(function(x) return x * 2 end)
	:ToTable()
-- result: {6, 8, 10}
```

**linq2 (v2)** - Alternative implementation with PascalCase:

```lua
local linq = require "@cheatoid/linq/linq2"

local result = linq({1, 2, 3, 4, 5})
	:Where(function(x) return x > 2 end)
	:Select(function(x) return x * 2 end)
	:ToArray()
```

**linq3 (v3)** - camelCase methods:

```lua
local Enumerable = require "@cheatoid/linq/linq3"

local result = Enumerable.from({1, 2, 3, 4, 5})
	:where(function(x) return x > 2 end)
	:select(function(x) return x * 2 end)
	:toTable()
```

### Ref

Reference wrapper with advanced features: scalar operator overloading, readonly refs, weak refs, table-proxy mode, and
safe semantics.

See [Ref module documentation](Shared/@cheatoid/ref/README.md) for more details.

```lua
local Ref = require "@cheatoid/ref/ref"

-- Basic reference
local ref = Ref.new(42)
print(ref:get()) -- 42
ref:set(100)

-- Readonly reference
local readonly = Ref.new("immutable", { readonly = true })
-- readonly:set("new") -- ERROR: cannot modify readonly ref

-- Weak reference (allows GC)
local weak = Ref.new({ data = "test" }, { weak = true })

-- Table proxy mode
local config = Ref.new({ name = "server", port = 7777 }, { proxy = true })
print(config.name) -- "server" (accesses through proxy)
config.port = 8888 -- modifies underlying table

-- Wrap all table fields in refs
local data = { a = 1, b = 2 }
local refs = Ref.from_table(data)
refs.a:set(10) -- Modify through ref

-- Metatable shortcuts
local r = Ref(42) -- same as Ref.new
local ro = -Ref -- creates readonly ref factory
local proxy = Ref * { key = "value" } -- from_table shorthand

-- Reactive operations
-- Update value with a function
local counter = Ref.new(0)
counter:update(function(value) return value + 1 end) -- Increment
print(counter:get()) -- 1

-- Map to create derived reactive values
local price = Ref.new(100)
local discounted = price:map(function(value) return value * 0.9 end)
print(discounted:get()) -- 90

-- Update chain
local total = Ref.new(10)
total
    :update(function(v) return v + 5 end)
    :update(function(v) return v * 2 end)
print(total:get()) -- 30 (10 + 5 = 15, then 15 * 2 = 30)
```

### RequireFinder

Utility for finding `require()` expressions in Lua source code using tokenization. Supports relative, absolute, and
library module detection.

See [RequireFinder module documentation](Shared/@cheatoid/require_finder/README.md) for more details.

```lua
local RequireFinder = require "@cheatoid/require_finder/require_finder"

-- Find requires in source code
local source = 'local json = require("json")\nlocal utils = require(".utils")'
local requires = RequireFinder.findRequires(source)

-- Result includes:
-- {
--   { expression = 'require("json")', moduleName = "json", line = 1, col = 14, ... },
--   { expression = 'require(".utils")', moduleName = ".utils", line = 2, col = 15, ... }
-- }

-- With context (type classification)
local withContext = RequireFinder.findRequiresWithContext(source)
-- Adds: lineContent, requireType ("relative", "absolute", or "library"), pathComponents

-- Format results for display
print(RequireFinder.formatResults(withContext))
```

### PluginFramework

Complete plugin system with dependency injection, lifecycle management (init/start/stop), event system, and service
registration.

See [PluginFramework module documentation](Shared/@cheatoid/plugin_framework/README.md) for complete documentation
including API reference and examples.

```lua
local PluginFramework = require "@cheatoid/plugin_framework/plugin_framework"
local PluginManager = PluginFramework.PluginManager
local Plugin = PluginFramework.Plugin

-- Create manager
local manager = PluginManager.new({ debug = true })

-- Register a service (dependency injection)
manager:register_service("logger", {
	log = function(msg) print("[LOG]", msg) end
})

-- Load plugin from string
local plugin_code = [[
function plugin:init(manager)
	print("[my_plugin] Initializing...")
	self.state.count = 0
end

function plugin:start()
	print("[my_plugin] Starting...")
end

function plugin:stop()
	print("[my_plugin] Stopping...")
end

function plugin:greet(name)
	self.state.count = self.state.count + 1
	print("Hello, " .. name .. "!")
	return self.state.count
end
]]

local my_plugin = manager:loadstring("my_plugin", plugin_code)

-- Create plugin using fluent API
local counter = Plugin("counter")
	:with_config({ max = 100 })
	:with_init(function(self, manager)
		self.state.value = 0
	end)
	:with_start(function(self)
		print("Counter started")
	end)
	:with_stop(function(self)
		print("Counter stopped at:", self.state.value)
	end)

manager:register(counter)

-- Plugin with dependencies
local dependent = Plugin("dependent")
	:depends_on("my_plugin")
	:with_init(function(self, manager)
		local parent = manager:get_plugin("my_plugin")
		print("Dependency count:", parent.state.count)
	end)

manager:register(dependent)

-- Event system
manager:on("my_plugin:custom", function(data)
	print("Event received:", data.message)
end)

-- Lifecycle management
manager:init_all()  -- Initialize all plugins
manager:start_all() -- Start all plugins
my_plugin:greet("World")
manager:stop_all()  -- Stop all plugins

-- List all plugins
for _, name in next, manager:list_plugins() do
	print("Plugin:", name)
end
```

### VM

Cheatoid Virtual Machine (CVM) - A Turing-complete, feature-rich, object-oriented Virtual Machine in pure Lua. Provides
a robust platform for code execution with 16 general-purpose registers, 256KB addressable memory, 70+ opcodes,
floating-point support, SIMD operations, and an interactive debugger.

See [VM module documentation](Shared/@cheatoid/vm/README.md) for complete documentation including architecture, opcode
reference, assembly language, and examples.

```lua
local VM = require "@cheatoid/vm/vm"

-- Create and configure VM
local vm = VM.new()

-- Load and execute assembly
local assembly = [[
MOV R0, #42
MOV R1, #8
ADD R2, R0, R1
SYSCALL #1, R2
HALT
]]

vm:load_asm(assembly)
vm:run()
```

### GAIMERS Loader

Custom module loader (codename: GAIMERS) providing utility functions for module loading and global exports.

```lua
local gaimers = require "@cheatoid/loader/gaimers"

-- Import & export: require module and export it as global
local i = gaimers.i
i"type_check"  -- _G["type_check"] = require("type_check")

-- Export: set a global variable
local e = gaimers.e
local my_value = e("MY_VALUE", 42)  -- _G.MY_VALUE = 42

-- Global require: require a module and export it as a different name
local g = gaimers.g
g("tc", "type_check")  -- _G.tc = require("type_check")

-- Alias: alias a global variable
local a = gaimers.a
_G.MyModule = {}
a("MyModule", "mm")  -- _G.mm = _G.MyModule

-- Module export: export all functions from a module as globals
local m = gaimers.m
m("type_check")  -- All type_check functions become global

-- Standard require
local r = gaimers.r
local xml = r"xml"

-- Sandboxed require: require module in isolated environment
local s = gaimers.s
local isolated = s("some_module", true)  -- deep copy environment
```

### Standalone Utilities

Various standalone utility modules:

| Module                 | Description                               |
|------------------------|-------------------------------------------|
| `try`                  | Exception handling with try/catch/finally |
| `type_check`           | Runtime type checking and validation      |
| `istype`               | Simple type-checking functions            |
| `xml`                  | XML parsing and serialization             |
| `zip`                  | ZIP archive handling                      |
| `util`                 | General utilities (coalesce, iff, etc.)   |
| `patcher`              | Code patching utilities                   |
| `debug_helper`         | Debugging and profiling tools             |
| `to_string_literal`    | Convert values to string literals         |
| `biginteger`           | Arbitrary precision integers              |
| `bits`                 | Bit manipulation utilities                |
| `base_encoder_decoder` | Arbitrary Base encoding/decoding          |
| `cfg_parser`           | Custom CFG file parser                    |
| `class`                | Lightweight class implementation          |
| `readonly`             | Read-only table wrapper                   |
| `curry`                | Function currying utility                 |
| `isolated`             | Lua version compatibility & sandboxing    |
| `runlua`               | Advanced code execution with sandboxing   |
| `pretty_grid`          | Formatted grid/table printing             |
| `pretty_hex_dump`      | Hex dump with ASCII view                  |
| `dump_table`           | Recursive table dumper                    |
| `track_value`          | Value change tracker with callbacks       |

**Extensions** (modify built-in types):

| Module                             | Description                                               |
|------------------------------------|-----------------------------------------------------------|
| `extensions/number`                | Adds time units, data sizes, duration objects to numbers  |
| `extensions/string`                | Adds `+` for concatenation, `*` for repetition to strings |
| `extensions/pretty_print_function` | Pretty-print functions with source info                   |

```lua
-- Base encoding/decoding (Base16, Base58, Base64, custom)
local Base = require "@cheatoid/standalone/base_encoder_decoder"

-- One-shot encoding with built-in alphabets
local hex = Base.encode("Hello World!", Base.BASE16)
print("Hex:", hex) -- 48656C6C6F20576F726C6421
local decoded = Base.decode(hex, Base.BASE16)
print("Decoded:", decoded) -- Hello World!

-- Create reusable encoder instance (faster for repeated calls)
local b58 = Base.new(Base.BASE58)
local address = b58.encode("\x00\x00SomeData")
print("Base58:", address)

-- Custom alphabet (e.g., Base5)
local b5 = Base.new("01234")
print("Base5 of 65:", b5.encode("A")) -- "230"

-- Type checking convenience functions
local istype = require "@cheatoid/standalone/istype"

if istype.string(myVar) then print("It's a string") end
if istype.number(x) and istype.integer(x) then print("It's an integer") end
if istype.callable(fn) then fn() end
if istype.none(...) then print("No arguments passed") end

-- Lua code sandboxing
local isolated = require "@cheatoid/standalone/isolated"

-- Loadstring works in all Lua versions (5.1, 5.2+, LuaJIT)
local f = isolated.loadstring("return 1 + 1")
print(f()) -- 2

-- Run code in sandboxed environment
local ok, result = isolated.safe_run("return 2 * 3")
if ok then print("Result:", result) end

-- Custom sandbox environment
local env = isolated.create_env({
    inject = { foo = 42 },     -- Variables to inject
    allow = { "coroutine" },   -- Globals to allow
    deny  = { "math", "os" }   -- Globals to deny
})
isolated.run_string("return foo * 2", env)

-- Advanced code execution (runlua) - more control over sandboxing
local runlua = require "@cheatoid/standalone/runlua"

-- Run code with custom sandbox
local sandbox = { safe_var = 42 }
setmetatable(sandbox, { __index = _G })  -- Allow global access
local ok, result = runlua.run_isolated("return safe_var * 2", sandbox)
if ok then print(result) else print("Error:", result) end

-- Execute function with isolated environment
local func = function() return math.sqrt(16) end
local ok, result = runlua.run_isolated(func)

-- Run in global environment (no sandbox)
local ok, result = runlua.run("return _VERSION")

-- Load string with custom environment
local env = { x = 10 }
setmetatable(env, { __index = _G })
local f, err = runlua.load_string("return x + 5", "chunk_name", "bt", env)
if f then print(f()) end

-- Set function environment (works across Lua versions)
local fn = function() return _G.myvar end
runlua.set_env(fn, { myvar = "custom" })

-- Monkey patching / hooking library
local patcher = require "@cheatoid/standalone/patcher"

-- Create a patcher instance
local Patcher = patcher.new()

-- Example target module
local myModule = {
    add = function(a, b)
        return a + b
    end
}

-- Before hook (runs before original)
Patcher:target(myModule, "add")
    :before(function(a, b)
        print("Called with args:", a, b)
    end)
    :apply()

-- After hook (runs after original, can modify return value)
Patcher:target(myModule, "add")
    :after(function(result, a, b)
        print("Result was:", result)
        return result * 2  -- Modify the return value
    end)
    :apply()

-- Around wrapper (controls when original is called)
Patcher:target(myModule, "add")
    :around(function(orig, a, b)
        print("Before call")
        local result = orig(a, b)  -- Call original
        print("After call, result:", result)
        return result + 100  -- Modify result
    end)
    :apply()

-- Replacement (complete override)
Patcher:target(myModule, "add")
    :replace(function(orig, a, b)
        print("Original add would have been called")
        return a + b + 1  -- Custom logic
    end)
    :apply()

-- Apply only once (patch auto-removes after first call)
Patcher:target(myModule, "add")
    :before(function() print("One-time patch") end)
    :once()
    :apply()

-- Group patches with IDs for easy restore
Patcher:target(myModule, "add")
    :before(function() print("Debug hook") end)
    :id("debug-hooks")
    :apply()

-- Restore patches by ID
Patcher:restore("debug-hooks")

-- Restore all patches
Patcher:restore_all()

-- Recursive table dumper
local dump = require "@cheatoid/standalone/dump_table"

-- Dump a table with options
local myTable = {
    name = "test",
    nested = {
        value = 42,
        items = {1, 2, 3}
    }
}

-- Get dump as lines
local count, lines = dump.dump(myTable, "myTable")
for i = 1, count do
    print(lines[i])
end
-- Output:
-- myTable.name = "test"
-- myTable.nested.value = 42
-- myTable.nested.items[1] = 1
-- myTable.nested.items[2] = 2
-- myTable.nested.items[3] = 3

-- Print directly with depth limit
dump.print(_G, "_G", { max_depth = 1 })

-- Filter to skip certain keys
local count, lines = dump.dump(_G, "_G", {
    max_depth = 2,
    filter = function(path, k, v)
        -- Skip functions and tables that are too large
        if type(v) == "function" then return false end
        return true
    end
})

-- Try/catch
local try = require("@cheatoid/standalone/try").try
try(function()
	error("Something went wrong")
end):catch(function(err)
	print("Error:", err)
end)

-- Type checking
local tc = require "@cheatoid/standalone/type_check"
tc.check_arg(1, "string", value)

-- XML parsing and serialization
local xml = require "@cheatoid/standalone/xml"

-- Parse XML string
local doc = xml.parse("<root><item>value</item></root>")
print(doc.root.item) -- "value"

-- Build XML from table
local xmlString = xml.stringify({
    person = {
        name = "John",
        age = 30,
        _attr = { id = "123" }
    }
})
print(xmlString) -- <person id="123"><name>John</name><age>30</age></person>

-- String literal conversion (for generating Lua code)
local str_lit = require "@cheatoid/standalone/to_string_literal"

-- Convert string with special characters to Lua literal
local escaped = str_lit.to_string_literal("Hello\nWorld\t!")
print(escaped) -- "Hello\nWorld\t!"

-- Binary-safe string literal
local binary_escaped = str_lit.to_string_literal("\x00\x01\x02")
print(binary_escaped) -- "\x00\x01\x02"

-- Long bracket form for strings with newlines
local multiline = str_lit.to_string_literal("Line 1\nLine 2\nLine 3", { long_bracket = true })
print(multiline) -- [[Line 1\nLine 2\nLine 3]] or with appropriate depth

-- Fast raw literal (no surrounding quotes)
local raw = str_lit.to_raw_literal("special\nchars\ttab")
print(raw) -- special\nchars\ttab

-- Value tracking (monitor changes with callbacks)
local track_value = require "@cheatoid/standalone/track_value"

-- Create a tracker for a counter
local counter = 0
local tracker = track_value(0, function() return counter end, function(new, old)
    print("Counter changed from", old, "to", new)
end)

-- Check for changes
counter = 5
local changed, new_val, old_val = tracker()
if changed then
    print("Value updated!") -- Prints because counter changed
end

-- Manual value update
changed, new_val, old_val = tracker(10)
print("Set to", new_val) -- 10

-- CFG file parser (Source-engine style configs)
local cfg = require "@cheatoid/standalone/cfg_parser"
local cfgContent = [[
// Server configuration
"hostname" "My Server"
"maxplayers" 32
/* Game settings */
"gamemode" "sandbox"
"map" "gm_construct"
"groups" {
    "admin" {
        "inherit" "superadmin"
        "can_target" "%admin%"
    }
}
]]

-- Parse Source-style config
local result = cfg.parse(cfgContent)
if result.ok then
    print("Hostname:", cfg.getString(result.value, "hostname"))
    print("Max players:", cfg.getNumber(result.value, "maxplayers"))
    print("Gamemode:", cfg.getString(result.value, "gamemode"))

    -- Get nested blocks
    local groups = cfg.getBlock(result.value, "groups")
    if groups then
        for name, groupData in pairs(groups.entries) do
            print("Group:", name)
        end
    end
end

-- ZIP archive handling
local zip = require "@cheatoid/standalone/zip"

-- Create a new ZIP writer
local writer, err = zip.new_writer("output.zip")
if not writer then
    error("Failed to create ZIP: " .. tostring(err))
end

-- Add a file entry
local entry, err = writer:add("file.txt", 0) -- 0 = stored (no compression)
if not entry then
    error("Failed to add entry: " .. tostring(err))
end

-- Write data to the entry
entry:write("Hello World")

-- Close the entry (finalizes CRC and sizes)
entry:close()

-- Add another entry
entry = writer:add("data/config.json", 0)
entry:write('{"key": "value"}')
entry:close()

-- Finalize the ZIP file
writer:close()

-- Read ZIP file metadata
local metadata, err = zip.read("output.zip")
if metadata then
    for _, file in ipairs(metadata.files) do
        print(file.name, file.size, file.offset, file.crc)
    end
end

-- DebugHelper and Debugger (inspect stack, locals, upvalues, breakpoints)
local debug_helper = require "@cheatoid/standalone/debug_helper"
local debugger = debug_helper.debugger

-- Stack inspection
local depth = debug_helper.get_stack_depth()
print("Stack depth:", depth)

-- Get structured stack trace
local stack = debug_helper.get_stack()
for i, frame in ipairs(stack) do
    print(i, frame.name, "at", frame.source .. ":" .. frame.currentline)
end

-- Get caller information
local caller = debug_helper.get_caller_name(2)
print("Called by:", caller)

-- Inspect locals with classification
local locals = debug_helper.get_locals(2)
for _, entry in ipairs(locals) do
    print(entry.name, "=", entry.value, "(" .. entry.kind .. ")")
end

-- Inspect upvalues
local function myFunc()
    local x = 10
    return function() return x end
end
local upvalues = debug_helper.list_upvalues(myFunc())
for name, value in pairs(upvalues) do
    print("Upvalue:", name, "=", value)
end

-- Full frame snapshot
local frame = debug_helper.dump_frame(2)
print("Parameters:", frame.parameters)
print("Locals:", frame.locals)
print("Upvalues:", frame.upvalues)

-- Interactive debugger with breakpoints
-- Set a breakpoint
debugger.set_breakpoint("@myfile.lua", 42)

-- Set up break callback
debugger.on_break(function(info, line, event, reason)
    print("Paused at", info.source, "line", line, "reason:", reason)
    -- Continue execution
    debugger.resume()
end)

-- List all breakpoints
local bps = debugger.list_breakpoints()
for source, lines in pairs(bps) do
    print(source .. ":" .. table.concat(lines, ", "))
end

-- Clear breakpoint
debugger.clear_breakpoint("@myfile.lua", 42)
debugger.clear_all_breakpoints()

-- Number extensions (modifies number-type metatable)
require "@cheatoid/extensions/number"
print(5.minutes)        -- 300 (seconds)
print(3.days)           -- 259200 (seconds)
print(10.mb)            -- 10485760 (bytes)
print(42.is_even)       -- true
print(3.14159:round(2)) -- 3.14
print((2.hours + 30.minutes):hms()) -- "2:30:00"
print(Duration.parse_iso("PT1H30M").seconds) -- 5400

-- String extensions (modifies string-type metatable)
require "@cheatoid/extensions/string"
print("Hello " + "World")  -- "Hello World"
print("abc" * 3)           -- "abcabcabc"
print("test"[1])           -- "t" (character access)
```

## Installation

1. Download the package from the nanos-world store/vault,
   or [GitHub releases](https://github.com/Cheatoid/nanos-world-vault/releases)
2. Extract it in your server's `Packages/` folder
3. Add it to your package's requirements in `Package.toml`:

```toml
[game]
packages = [
    "cheatoid-library",
]
```

## Usage

Import modules using `require`:

```lua
-- Core library modules
local ConVar = require "ConVar"
local Config = require "Config"
local file = require "FileWrapper"
local http = require "HttpWrapper"
local Version = require "Version"

-- Built-in @cheatoid modules
local oop = require "@cheatoid/oop/oop"
local string = require "@cheatoid/standard/string"
```

## License

MIT License - See [LICENSE](LICENSE) file for details.
