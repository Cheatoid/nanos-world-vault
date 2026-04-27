<h1 align="center"><a href="https://api.nanos-world.com/store/packages/cheatoid-library"><img align="center" src="../.resources/cheatoid-library.webp" width="400" height="250" alt="Library API"></a></h1>
<p align="center">A comprehensive development toolkit of handy libraries designed to supercharge your scripting workflow and let you focus on building great nanos-world gameplay... 🚀</p>

> [!NOTE]
> This README provides a quick overview of the library's features. Not everything is covered here, as it is
> time-consuming to keep this document fully up-to-date. For complete documentation, refer to the individual module
> files.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
    - [WebBrowser](#webbrowser)
    - [Bind](#bind)
    - [ConVar](#convar)
    - [Chat Commander](#chat-commander)
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
    - [StackVM](#stackvm)
    - [GAIMERS Loader](#gaimers-loader)
    - [Reflection](#reflection)
    - [Permission](#permission)
    - [Standalone Utilities](#standalone-utilities)
    - [Benchmark](#benchmark)
    - [Rate Limiter](#rate-limiter)
    - [Load Balancer & Matchmaking](#load-balancer--matchmaking)
- [Installation](#installation)
- [Usage](#usage)
- [License](#license)

## Overview

This library provides a rich set of utilities and abstractions for nanos-world scripting, including console variables,
configuration management, file I/O with virtual file system support, HTTP wrappers, semantic versioning, and much more.

## Features

### WebBrowser

A *functional* client-side multi-tab Chrome web browser for all your internet surfing needs while playing nanos world.  
Open it by entering `browser_open` console command.  
Alternatively, you can make a keybind: `bind F9 browser_open` and then simply press <kbd>F9</kbd>.  
To open developer tools for the current tab, you can run `browser_devtools` console command (or bind it to key).  
Enjoy a beautiful New Tab experience, you can customize the background gradient, or use an image and much more...

Module file: [Client/WebBrowser.lua](https://github.com/Cheatoid/nanos-world-vault/blob/main/library/Client/WebBrowser.lua)

### Bind

You can bind a console command to a key by using `bind` console command.  
For example, to bind <kbd>F7</kbd> to `disconnect` console command, you would enter `bind F7 disconnect` into console.

Module file: [Client/Bind.lua](https://github.com/Cheatoid/nanos-world-vault/blob/main/library/Client/Bind.lua)

Programatically, you can use the `Bind` library to register an action (a specific function to be executed). For example,

```lua
local Bind = require "Bind"

Bind.RegisterAction("do_something", function()
    print("Doing something!")
end)
-- Now you can execute this action by entering `action do_something` into console
```

But, typically, you want to register a command + action at the same time, like this:

```lua
Bind.RegisterCommand("do_other_thing", function()
    print("Doing something else!")
end, "Command description...")
-- Now you can execute this action by entering `action do_other_thing`
-- and also through keybind: `bind F6 do_other_thing` into console and then press F6
```

### ConVar

Allows for creating console variables (Source-engine style).  
By default, it creates `cvarlist` command to dump created convars, adds `sv_cheats` (placeholder convar), and also adds
`sv_password` used for changing server's password (on server-side).

Module file: [Shared/ConVar.lua](https://github.com/Cheatoid/nanos-world-vault/blob/main/library/Shared/ConVar.lua)

**How to change convars:**

- Simply type the convar name followed by a value into a console, for example to change server's password to `test123`,
  you would enter `sv_password test123` into console.

**How to register convars:**

```lua
local ConVar = require "ConVar"

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
    ConVar.GetPlayerInfo(player, "cl_userinfo_cvar")
end
```

### Chat Commander

Command parser and dispatcher for in-game chat commands with autocompletion support, type coercion, and flexible
validation.

See [Chat Commander documentation](https://github.com/Cheatoid/Lua.Scripts/tree/develop/chat_commander) for complete
details.

```lua
local chat_commander = require "chat_commander"

-- Standard API
chat_commander.register_command("teleport", {
    description = "Teleport to coordinates",
    args = {
        { "x", "number" },
        { "y", type = "number" },
        { name = "z", type = "number", default = 0 },
    },
    handler = function(ctx, args)
        print("Teleporting to:", args.x, args.y, args.z)
    end,
})

local ok, err = chat_commander.handle_line({ player = player }, "/teleport 10 20 30")

-- Fluent API
chat_commander.register_command("kick")
    :description("Kick a player")
    :arg("player", "string")
    :permission(function(ctx, args)
        return ctx.player.is_admin, "admin only"
    end)
    :handler(function(ctx, args)
        -- Kick logic
    end)
    :register()
```

### Config

Type-safe configuration management with schema validation. Supports JSON-based config files with automatic validation
and default values.

Module file: [Shared/Config.lua](https://github.com/Cheatoid/nanos-world-vault/blob/main/library/Shared/Config.lua)

```lua
local Config = require "Config"

-- Initialize config (loads from <package-name>.json with built-in schema)
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

-- Note: Config automatically persists to <package-name>.json when values change
```

### FileWrapper

Convenience file I/O wrapper with virtual file system (VFS) support.

Module file: [Shared/FileWrapper.lua](https://github.com/Cheatoid/nanos-world-vault/blob/main/library/Shared/FileWrapper.lua)

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
local files = file.list_files("scripts", ".lua")
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
local entries = file.vfs.get(vfs, "scripts")
for name, value in pairs(entries or {}) do
    local isDir = type(value) == "table"
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
--local dump = require "@cheatoid/standalone/dump_table"
--dump.print(vfs, "vfs")
table.dump_print(vfs, "vfs") -- Shorthand
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

Module file: [Shared/HttpWrapper.lua](https://github.com/Cheatoid/nanos-world-vault/blob/main/library/Shared/HttpWrapper.lua)

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

Client-side WebUI-bridged APIs for 
[Hash](https://github.com/Cheatoid/nanos-world-vault/blob/main/library/Client/HashAPI.lua), 
[Regex](https://github.com/Cheatoid/nanos-world-vault/blob/main/library/Client/RegexAPI.lua), 
[WebSocket](https://github.com/Cheatoid/nanos-world-vault/blob/main/library/Client/WebSocketAPI.lua), 
and [WebAudio](https://github.com/Cheatoid/nanos-world-vault/blob/main/library/Client/WebAudioAPI.lua) functionality.

```lua
-- HashAPI (bridged via WebUI for hashing/checksums)
local HashAPI = require "Client/HashAPI"

HashAPI.SHA256("hello world", function(success, result)
    if success then
        print("SHA-256:", result)
    else
        print("Hash failed")
    end
end)

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

-- WebAudioAPI (bridged via WebUI for audio playback and spatial audio)
local WebAudioAPI = require "Client/WebAudioAPI"

-- Initialize the Web Audio engine
WebAudioAPI.Init(function(success, result)
    if success then
        print("WebAudio engine initialized")
    end
end)

-- Set listener (player) transform for spatial audio
WebAudioAPI.SetListenerTransform(0, 0, 0, 0, 0, -1, 0, 1, 0, function(success, result)
    if success then
        print("Listener transform set")
    end
end)

-- Set master volume
WebAudioAPI.SetMainGain(1.0, function(success, result)
    if success then
        print("Master gain set")
    end
end)

-- Set ambience volume
WebAudioAPI.SetAmbienceGain(0.5, function(success, result)
    if success then
        print("Ambience gain set")
    end
end)

-- Set lowpass filter for underwater/muffled effects
WebAudioAPI.SetLowpassFilter(20000, function(success, result)
    if success then
        print("Lowpass filter set")
    end
end)
```

### Version

Semantic versioning utility for comparing package versions.

Module file: [Shared/Version.lua](https://github.com/Cheatoid/nanos-world-vault/blob/main/library/Shared/Version.lua)

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

Module file: [Shared/BroadcastLua.lua](https://github.com/Cheatoid/nanos-world-vault/blob/main/library/Shared/BroadcastLua.lua)

```lua
-- Server-side
local broadcast = require "BroadcastLua"

-- Execute on all clients
broadcast.BroadcastLua("Chat.AddMessage('Hello!')")

-- Execute on specific player
broadcast.SendLua(player, "Chat.AddMessage('Hello!')")
```

### ClientsideLua

Provides the `lua` console command for executing Lua code (or script) via console.  
But, server-side must enable `allowcslua` convar to allow client-side Lua execution (it is disabled by default).  
Enter `allowcslua 1` into server console if you are server operator and want to allow client-side `lua` console command.

Module file: [Shared/ClientsideLua.lua](https://github.com/Cheatoid/nanos-world-vault/blob/main/library/Shared/ClientsideLua.lua)

```lua
-- In console (when allowcslua is enabled):
-- lua print("Hello from console!")
-- lua for _, ply in next, Player.GetAll() do print(ply) end -- prints all players

-- Execute a Lua script file (must end in .lua)
-- lua @cheatoid/plugin_framework/example.lua
```

### RequireFolder

Convenient utility for batch loading scripts from a directory.

Module file: [Shared/RequireFolder.lua](https://github.com/Cheatoid/nanos-world-vault/blob/main/library/Shared/RequireFolder.lua)

```lua
local requiref = require "RequireFolder"

-- Load all Lua files from a folder
requiref "Shared/Modules" {}

-- Load with priority and exclusions
requiref "Shared/@cheatoid" {
    "load_first/",  -- highest priority
    "load_second/",
    ["%.tests%.lua$"] = false,  -- skip *.tests.lua files
    ["example%.lua$"] = false   -- skip example.lua
}

-- Load specific modules only
requiref "Shared/Extensions" {
    "extension1",
    "extension2"
}
```

## Built-in Modules

### OOP Framework

Object-oriented programming utilities including classes, inheritance, interfaces, mixins, properties, events, enums,
promises, and integrated profiler.

Module file: [Shared/@cheatoid/oop/oop.lua](https://github.com/Cheatoid/Lua.Scripts/blob/develop/oop/oop.lua)

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

[View all collections](https://github.com/Cheatoid/Lua.Scripts/tree/develop/collections)

Data structures:

- [(OOP) ArrayPool](https://github.com/Cheatoid/Lua.Scripts/blob/develop/oop/collections/ArrayPool.lua)
- [BiMap](https://github.com/Cheatoid/Lua.Scripts/blob/develop/collections/BiMap.lua)
- [CircularBuffer](https://github.com/Cheatoid/Lua.Scripts/blob/develop/collections/CircularBuffer.lua)
- [Deque](https://github.com/Cheatoid/Lua.Scripts/blob/develop/collections/Deque.lua)
- [Heap](https://github.com/Cheatoid/Lua.Scripts/blob/develop/collections/Heap.lua)
- [LinkedList](https://github.com/Cheatoid/Lua.Scripts/blob/develop/collections/LinkedList.lua)
- [PriorityQueue](https://github.com/Cheatoid/Lua.Scripts/blob/develop/collections/PriorityQueue.lua)
- [Queue](https://github.com/Cheatoid/Lua.Scripts/blob/develop/collections/Queue.lua)
- [Set](https://github.com/Cheatoid/Lua.Scripts/blob/develop/collections/Set.lua)
- [SlotMap](https://github.com/Cheatoid/Lua.Scripts/blob/develop/collections/SlotMap.lua)
- [SparseArray](https://github.com/Cheatoid/Lua.Scripts/blob/develop/collections/SparseArray.lua)
- [Stack](https://github.com/Cheatoid/Lua.Scripts/blob/develop/collections/Stack.lua)

```lua
local Stack = require "@cheatoid/collections/Stack"
local Queue = require "@cheatoid/collections/Queue"
local Set = require "@cheatoid/collections/Set"
local ArrayPool = require "@cheatoid/oop/collections/ArrayPool"

-- Stack (LIFO)
local stack = Stack()
stack:push("item")
local item = stack:pop()

-- Queue (FIFO)
local queue = Queue()
queue:enqueue("first")
queue:enqueue("second")
local first = queue:dequeue()

-- Set (unique elements)
local set = Set()
set:add("apple")
set:add("banana")
print(set:contains("apple")) -- true

-- ArrayPool (reusable array pool to reduce GC pressure)
local pool = ArrayPool.shared()
local arr = pool:rent(100) -- Rent array with at least 100 elements
arr[1] = "first"
arr[100] = "last"
pool:release(arr) -- Return to pool for reuse
```

### Standard Library Extensions

Enhanced
builtin [string](https://github.com/Cheatoid/Lua.Scripts/blob/develop/standard/string.lua),
[table](https://github.com/Cheatoid/Lua.Scripts/blob/develop/standard/table.lua),
and [math](https://github.com/Cheatoid/Lua.Scripts/blob/develop/standard/math.lua) libraries with additional functions.  
And they are also fully documented (see .d.lua files in the same directory for LuaDoc annotations).

```lua
local string = require "@cheatoid/standard/string"
local table = require "@cheatoid/standard/table"
local math = require "@cheatoid/standard/math"

-- String utilities
local normalized = string.normalize_path("folder\\file.lua") -- "folder/file.lua"
local parts = string.split("a,b,c", ",") -- {"a", "b", "c"}

-- Table utilities
local merged = table.merge({a=1}, {b=2}) -- {a=1, b=2}
local unique = table.unique({1,2,2,3,3,3}) -- {1,2,3}
local filtered = table.filter({1,2,3,4,5}, function(v) return v > 2 end) -- {3,4,5}

-- Path-based value retrieval (dot and bracket notation)
local value = table.get_path(_G, "math.clamp")
local value = table.get_path(_G, "package[\"loaded\"][\"table\"]")
local value = table.get_path({a = {b = {[5] = "hello"}}}, "a.b.[5]")

-- Math utilities
local clamped = math.clamp(150, 0, 100) -- 100
if math.inrange(x, 1, 10) then print("In range!") end
```

### LINQ

Language-Integrated Query for Lua collections. Three versions are available with different API styles:

**[linq (v1)](https://github.com/Cheatoid/Lua.Scripts/blob/develop/linq/linq.lua)** - PascalCase methods:

```lua
local linq = require "@cheatoid/linq/linq"

local result = linq.From({1, 2, 3, 4, 5})
    :Where(function(x) return x > 2 end)
    :Select(function(x) return x * 2 end)
    :ToTable()
-- result: {6, 8, 10}
```

**[linq2 (v2)](https://github.com/Cheatoid/Lua.Scripts/blob/develop/linq/linq2.lua)** - Alternative implementation with PascalCase:

```lua
local linq = require "@cheatoid/linq/linq2"

local result = linq({1, 2, 3, 4, 5})
    :Where(function(x) return x > 2 end)
    :Select(function(x) return x * 2 end)
    :ToArray()
```

**[linq3 (v3)](https://github.com/Cheatoid/Lua.Scripts/blob/develop/linq/linq3.lua)** - camelCase methods:

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

See [Ref module documentation](https://github.com/Cheatoid/Lua.Scripts/tree/develop/ref#ref-module---a-powerful-reference-wrapper-for-lua)
for more details.

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

See [RequireFinder module documentation](https://github.com/Cheatoid/Lua.Scripts/tree/develop/require_finder#require-finder-utility)
for more details.

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

See [PluginFramework module documentation](https://github.com/Cheatoid/Lua.Scripts/tree/develop/plugin_framework#plugin-framework)
for complete documentation including API reference and examples.

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

See [VM module documentation](https://github.com/Cheatoid/Lua.Scripts/tree/develop/vm#cheatoid-virtual-machine-cvm) for
complete documentation including architecture, opcode reference, assembly language, and examples.

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

### StackVM

Small stack-based VM with a Lua-C-API-like stack surface. Provides a simple stack-based virtual machine with an API
similar to Lua's C API. Supports bytecode compilation, execution, and a Lua-like stack manipulation interface.

See [StackVM implementation](https://github.com/Cheatoid/Lua.Scripts/blob/develop/vm/stackvm.lua) for more details.

```lua
local StackVM = require "@cheatoid/vm/stackvm"

-- Create a new VM state with max stack size
local L = StackVM.new(256)

-- Push values onto the stack
L:pushnumber(42)
L:pushstring("hello")
L:pushboolean(true)

-- Get stack top
print(L:gettop()) -- 3

-- Pop values
L:pop(2)
print(L:gettop()) -- 1

-- Compile and run bytecode
local chunk = {
    code = {
        { op = "PUSHK", 1 },  -- Push constant at index 1
        { op = "PUSHK", 2 },  -- Push constant at index 2
        { op = "ADD" },       -- Add top two values
    },
    k = { 10, 20 }  -- Constants
}

local proto = StackVM.compile(chunk)
StackVM.run(L, proto)
```

### GAIMERS Loader

Custom module loader (codename: GAIMERS) providing utility functions for module loading and global exports.

Module file: [Shared/@cheatoid/loader/gaimers.lua](https://github.com/Cheatoid/Lua.Scripts/blob/develop/loader/gaimers.lua)

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

### Reflection

Runtime reflection utilities for inspecting nanos-world's game engine internals. Provides access to registered classes
and enum tables from the debug registry.

Module file: [Shared/Reflection.lua](https://github.com/Cheatoid/nanos-world-vault/blob/main/library/Shared/Reflection.lua)

```lua
local Reflection = require "Reflection"

-- Get all enum tables from the global environment
-- Returns a table where keys are enum names and values are enum tables
local enums = Reflection.GetEnums()
for name, enum in next, enums do
    print(name) -- Prints enum names like "EColor", "EInputKey", "EControlMode", etc.
end

-- Get all registered classes from the debug registry
-- Returns a table mapping numeric IDs to class tables
local classes = Reflection.GetClasses()
for id, class in next, classes do
    print("Class ID:", id, "Name:", class.Name or "Unknown")
end
```

### Permission

Modular permission system combining simplicity with performance. Provides a clean API for managing permissions with
bit-packed storage for efficiency. Supports category-level overrides, multi-registry support, and freeze concept for
immutable registries.

Module file: [Shared/@cheatoid/permission/permission.lua](https://github.com/Cheatoid/Lua.Scripts/blob/develop/permission/permission.lua)

```lua
local perm = require "@cheatoid/permission/permission"

-- Define a permission category with permissions
perm.define_category("chat", {
    { name = "send", default = true, description = "Send messages" },
    { name = "read", default = true },
    "mute"  -- shorthand: name only, default=false
})

-- Create a permission context for a player
local ctx = perm.new_context()

-- Grant/deny permissions
perm.deny(ctx, "chat.mute")

-- Check permissions
if perm.is_allowed(ctx, "chat.send") then
    -- allow action
end

-- Require permission (throws error if not allowed)
perm.require_permission(ctx, "chat.send")

-- Category operations
perm.grant_category(ctx, "admin")  -- Grant all admin permissions
perm.set_category_state(ctx, "chat", perm.STATE_DENY)  -- Override category

-- Serialization for storage/transmission
local data = perm.to_table(ctx)  -- Human-readable format
local wire = perm.to_wire(ctx)   -- Compact bit-packed format

-- Multi-registry support
local reg = perm.new_registry(perm.STATE_DENY)
perm.define_category_on(reg, "admin", { "kick", "ban" })
local ctx2 = perm.new_context_on(reg)
```

### BigInteger

Arbitrary-precision integer arithmetic for handling numbers that exceed Lua's number precision. Perfect for SteamIDs,
large database IDs, and cryptographic calculations.

Module file: [Shared/@cheatoid/standalone/biginteger.lua](https://github.com/Cheatoid/Lua.Scripts/blob/develop/standalone/biginteger.lua)

```lua
local BigInteger = require "@cheatoid/standalone/biginteger"

-- Create from string (recommended for large numbers)
local steamid64 = BigInteger("76561198000000000")
print("SteamID64:", steamid64:to_string())

-- Arithmetic operations
local a = BigInteger("76561198000000000")
local b = BigInteger("1000000000000000")
local sum = a + b
local diff = a - b
local product = a * b
print("Sum:", sum:to_string())         -- 76561199000000000
print("Difference:", diff:to_string()) -- 75561198000000000
print("Product:", product:to_string()) -- Very large number

-- Power operation (exponentiation)
local large = BigInteger("2")
local result = large ^ 100
print("2^100:", result:to_string())

-- Modulo operation (useful for SteamID calculations)
local account_id = BigInteger("76561198000000000") % BigInteger("10000000000")
print("Account ID:", account_id:to_string())

-- Expression evaluator (Shunting-yard algorithm)
local expr = BigInteger.eval("(76561198000000000 + 1000000000000000) * 2")
print("Evaluated:", expr:to_string())

-- Convert to Lua number (caution: may lose precision for very large numbers)
local small = BigInteger("12345")
local num = small:to_number()
print("As number:", num) -- 12345

-- Zero and one constants
local zero = BigInteger.zero
local one = BigInteger.one
```

### Console

Interactive command console with fuzzy completion, history tracking, and IntelliSense. Perfect for admin panels, debug
interfaces, or in-game command systems.

Module file: [Shared/@cheatoid/standalone/console.lua](https://github.com/Cheatoid/Lua.Scripts/blob/develop/standalone/console.lua)

```lua
local Console = require "@cheatoid/standalone/console"

-- Create a new console instance
local console = Console.new({
  suggestion_limit = 10,
  history_limit = 100,
  case_sensitive = false
})

-- Register commands with typed arguments
console:register({
  name = "kick",
  aliases = { "ban" },
  desc = "Kick a player from the server",
  args = {
    { name = "player", type = "string", desc = "Player name or ID" },
    { name = "reason", type = "string", optional = true, desc = "Kick reason" }
  },
  handler = function(ctx, args)
    return "Kicked " .. args.player .. (args.reason and (" for " .. args.reason) or "")
  end
})

console:register({
  name = "set",
  desc = "Set a configuration value",
  args = {
    { name = "key", type = "string", desc = "Config key" },
    { name = "value", type = "string", desc = "Config value" },
    { name = "permanent", type = "bool", optional = true, default = false, desc = "Save permanently" }
  },
  handler = function(ctx, args)
    return "Set " .. args.key .. " = " .. args.value .. (args.permanent and " (saved)" or "")
  end
})

console:register({
  name = "gamemode",
  desc = "Set the game mode",
  args = {
    { name = "mode", type = "enum", choices = { "deathmatch", "ctf", "tdm", "sandbox" }, desc = "Game mode" }
  },
  handler = function(ctx, args)
    return "Game mode set to: " .. args.mode
  end
})

-- Register built-in commands (help, echo)
console:register_defaults()

-- Parse and execute commands
local result, err = console:input_line('kick "Player123" "griefing"')
if err then print("Error:", err) else print(result) end

-- Get fuzzy suggestions for completion
local suggestions = console:suggest("k", 10)
for _, s in ipairs(suggestions) do
  print(s.key, s.desc)
end

-- Tab completion
local completion = console:complete("ki") -- returns "kick"

-- History navigation
local prev = console:history_prev()
local next = console:history_next()

-- Get help
print(console:help()) -- List all commands
print(console:help("kick")) -- Detailed help for kick command

-- Save/load state (for persistence)
local state = console:save_state()
-- Later: console:load_state(state)
```

### Benchmark

Benchmarking toolkit for measuring code performance with statistical analysis, comparison tools, and multiple timing
modes (with high-precision timer on LuaJIT)...

See [Benchmark example](https://github.com/Cheatoid/Lua.Scripts/blob/develop/benchmark/example.lua) for complete usage examples.

```lua
local bench = require "@cheatoid/benchmark/init"

-- Quick one-shot timing
local elapsed = bench.time(function()
    -- Code to measure
    local x = 0
    for i = 1, 1e6 do
        x = x + i
    end
    return x
end)
print(string.format("Elapsed: %s", bench.formatter.time(elapsed)))

-- Run benchmark with default settings
bench(function()
    local x = 0
    for i = 1, 1e6 do
        x = x + i
    end
end, "loop addition")

-- Create a benchmark suite for comparison
local suite = bench.createSuite({
    iterations = 500,
    warmup = 20,
    precision = 3,
    show_percentiles = { 50, 95, 99 },
})

suite:add("table.insert", function()
    local t = {}
    for i = 1, 5000 do
        t[#t + 1] = i
    end
end)

suite:add("table.insert (pre-alloc)", function()
    local t = {}
    for i = 1, 5000 do
        t[i] = i
    end
end)

suite:run()
suite:compare()
```

### Standalone Utilities

Various standalone utility modules:

| Module                                                                         | Description                                  |
|--------------------------------------------------------------------------------|----------------------------------------------|
| [`base_encoder_decoder`](Shared/@cheatoid/standalone/base_encoder_decoder.lua) | Arbitrary Base encoding/decoding             |
| [`benchmark`](Shared/@cheatoid/benchmark/init.lua)                             | Performance benchmarking toolkit             |
| [`biginteger`](Shared/@cheatoid/standalone/biginteger.lua)                     | Arbitrary precision integers                 |
| [`bit`](Shared/@cheatoid/standalone/bit.lua)                                   | 32-bit bitwise operations (with folding)     |
| [`bits`](Shared/@cheatoid/standalone/bits.lua)                                 | Portable 32-bit bitwise operations utilities |
| [`bitwise`](Shared/@cheatoid/standalone/bitwise.lua)                           | Portable 32-bit bitwise operations (masked)  |
| [`cfg_parser`](Shared/@cheatoid/standalone/cfg_parser.lua)                     | Custom CFG file parser                       |
| [`class`](Shared/@cheatoid/standalone/class.lua)                               | Lightweight class implementation             |
| [`console`](Shared/@cheatoid/standalone/console.lua)                           | Interactive console with fuzzy completion    |
| [`curry`](Shared/@cheatoid/standalone/curry.lua)                               | Function currying utility                    |
| [`debug_helper`](Shared/@cheatoid/standalone/debug_helper.lua)                 | Debugger and debugging utilities             |
| [`dump_table`](Shared/@cheatoid/standalone/dump_table.lua)                     | Recursive table dumper                       |
| [`fold`](Shared/@cheatoid/standalone/fold.lua)                                 | Generic left-fold utility for vararg         |
| [`isolated`](Shared/@cheatoid/standalone/isolated.lua)                         | Lua version compatibility & sandboxing       |
| [`istype`](Shared/@cheatoid/standalone/istype.lua)                             | Simple type-checking functions               |
| [`patcher`](Shared/@cheatoid/standalone/patcher.lua)                           | Code patching utilities                      |
| [`pretty_grid`](Shared/@cheatoid/standalone/pretty_grid.lua)                   | Formatted grid/table printing                |
| [`pretty_hex_dump`](Shared/@cheatoid/standalone/pretty_hex_dump.lua)           | Hex dump with ASCII view                     |
| [`readonly`](Shared/@cheatoid/standalone/readonly.lua)                         | Read-only table wrapper                      |
| [`runlua`](Shared/@cheatoid/standalone/runlua.lua)                             | Advanced code execution with sandboxing      |
| [`to_string_literal`](Shared/@cheatoid/standalone/to_string_literal.lua)       | Convert values to string literals            |
| [`track_value`](Shared/@cheatoid/standalone/track_value.lua)                   | Value change tracker with callbacks          |
| [`try`](Shared/@cheatoid/standalone/try.lua)                                   | Exception handling with try/catch/finally    |
| [`type_check`](Shared/@cheatoid/standalone/type_check.lua)                     | Runtime type checking and validation         |
| [`util`](Shared/@cheatoid/standalone/util.lua)                                 | General utilities (coalesce, iff, etc.)      |
| [`xml`](Shared/@cheatoid/standalone/xml.lua)                                   | XML parsing and serialization                |
| [`zip`](Shared/@cheatoid/standalone/zip.lua)                                   | ZIP archive handling                         |

**Extensions** (modify built-in types):

| Module                             | Description                                                                       |
|------------------------------------|-----------------------------------------------------------------------------------|
| `extensions/number`                | Adds time units, data sizes, duration objects to numbers                          |
| `extensions/string`                | Adds `+` for concatenation, `*` for repetition, `<<`/`>>` for rotation to strings |
| `extensions/pretty_print_function` | Pretty-print functions with source info                                           |

```lua
-- 32-bit bitwise operations (bit32 API compatible)
local bit = require "@cheatoid/standalone/bit"

-- Core operations (vararg support)
local result = bit.band(0xFF00FF00, 0x0F0F0F0F) -- 0x00000000
local result = bit.bor(0xFF00, 0x00FF) -- 0x0000FFFF
local result = bit.bxor(0xF0, 0xFF) -- 0x0F

-- Shift operations
local result = bit.lshift(1, 8) -- 0x00000100
local result = bit.rshift(0x100, 8) -- 1
local result = bit.arshift(0x80000000, 31) -- 0xFFFFFFFF (sign-extending)

-- Rotate operations
local result = bit.rol(0x80000000, 1) -- 1
local result = bit.ror(1, 1) -- 0x80000000

-- Count operations
local count = bit.popcount(0xFF00FF00) -- 16
local lz = bit.countlz(0x80000000) -- 0
local tz = bit.countrz(1) -- 0

-- Byte operations
local swapped = bit.bswap(0x11223344) -- 0x44332211
local byte = bit.getbyte(0x11223344, 0) -- 0x44 (LSB)
local result = bit.setbyte(0x00000000, 0xFF, 0) -- 0x000000FF

-- Hex conversion
local hex = bit.tohex(0xDEADBEEF) -- "0xDEADBEEF"
local value = bit.fromhex("DEADBEEF") -- 0xDEADBEEF

-- Binary I/O (little-endian, big-endian)
local packed = bit.pack_le(0x11223344) -- 4-byte string
local value = bit.unpack_le(packed) -- 0x11223344

-- Portable 32-bit bitwise operations (auto-detects best implementation)
local bitwise = require "@cheatoid/standalone/bitwise"

-- Core operations
local result = bitwise.band(0xFF, 0x0F) -- 0x0F
local result = bitwise.bor(0xF0, 0x0F) -- 0xFF
local result = bitwise.bxor(0xF0, 0xFF) -- 0x0F
local result = bitwise.bnot(0x00) -- 0xFFFFFFFF

-- Shift operations
local result = bitwise.lshift(1, 8) -- 0x00000100
local result = bitwise.rshift(0x100, 8) -- 1
local result = bitwise.arshift(0x80000000, 31) -- 0xFFFFFFFF (sign-extending)

-- Rotate operations
local result = bitwise.rol(0x80000000, 1) -- 1
local result = bitwise.ror(1, 1) -- 0x80000000

-- Byte swap
local result = bitwise.bswap(0x11223344) -- 0x44332211

-- Conversion utilities
local masked = bitwise.tobit(0x123456789) -- 0x3456789 (masked to 32-bit)
local signed = bitwise.toint(0xFFFFFFFF) -- -1 (unsigned to signed)

-- Interactive console with fuzzy completion
local Console = require "@cheatoid/standalone/console"

local console = Console.new({
  suggestion_limit = 10,
  history_limit = 100,
  case_sensitive = false
})

-- Register commands with typed arguments
console:register({
  name = "kick",
  aliases = { "ban" },
  desc = "Kick a player from the server",
  args = {
    { name = "player", type = "string", desc = "Player name or ID" },
    { name = "reason", type = "string", optional = true, desc = "Kick reason" }
  },
  handler = function(ctx, args)
    return "Kicked " .. args.player .. (args.reason and (" for " .. args.reason) or "")
  end
})

-- Register built-in commands (help, echo)
console:register_defaults()

-- Parse and execute commands
local result, err = console:input_line('kick "Player123" "griefing"')
if err then print("Error:", err) else print(result) end

-- Get fuzzy suggestions for completion
local suggestions = console:suggest("k", 10)
for _, s in ipairs(suggestions) do
  print(s.key, s.desc)
end

-- Tab completion
local completion = console:complete("ki") -- returns "kick"

-- History navigation
local prev = console:history_prev()
local next = console:history_next()

-- Get help
print(console:help()) -- List all commands
print(console:help("kick")) -- Detailed help for kick command

-- Save/load state (for persistence)
local state = console:save_state()
-- Later: console:load_state(state)

-- Generic left-fold utility for vararg operations
local fold = require "@cheatoid/standalone/fold"

-- Sum of multiple values
local sum = fold(function(a, b) return a + b end, 1, 2, 3, 4) -- 10

-- Product of multiple values
local product = fold(function(a, b) return a * b end, 2, 3, 4) -- 24

-- Custom reduction
local concatenated = fold(function(a, b) return a .. b end, "a", "b", "c") -- "abc"

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
print("hello" << 2)        -- "llohe" (rotate left)
print("hello" >> 2)        -- "lohel" (rotate right)

```

### Rate Limiter

Simple rate limiting primitives supporting multiple strategies (Fixed Window, Sliding Window Log, Token Bucket, and
Leaky Bucket).

Doumentation: [Shared/@cheatoid/rate_limiter](https://github.com/Cheatoid/Lua.Scripts/tree/develop/rate_limiter)

```lua
local RateLimiter = require "@cheatoid/rate_limiter/rate_limiter"

-- 10 requests per second (fixed window)
local limiter = RateLimiter(RateLimiter.strategy.FixedWindow.new(10, 1))

if limiter:consume() then
    -- allowed
else
    -- rate limited
end

-- Token bucket: 5 tokens/sec, burst up to 20
local tb = RateLimiter(RateLimiter.strategy.TokenBucket.new(5, 20))
if tb:check() then
    tb:consume()
end
```

### Load Balancer & Matchmaking

Utilities for distributing work across backends (load balancing) and building matchmaking queues/strategies.

Examples: [Shared/@cheatoid/load_balancer/examples.lua](https://github.com/Cheatoid/Lua.Scripts/blob/develop/load_balancer/examples.lua)

## Installation

1. Download the package from the nanos-world store/vault,
   or [automated GitHub releases](https://github.com/Cheatoid/nanos-world-vault/releases)
2. Extract it in your server's `Packages/` folder
3. Add it to your package's requirements in `Package.toml` (preferably keep it first in the list):

```toml
[game]
packages = [
    "cheatoid-library",
]
```

4. In your server's gamemode `Shared/Index.lua`, add the following line at the top:

```lua
require "cheatoid-library/Shared/Index.lua"
```

## Usage

It is up to you to wire the *cheatoid-library* modules in your game.  
Import modules using `require` (or use GAIMERS for convenience):

```lua
local GAIMERS = require "cheatoid-library/Shared/@cheatoid/loader/gaimers"

-- Core library modules
local ConVar = require "cheatoid-library/Shared/ConVar"
local Config = require "cheatoid-library/Shared/Config"
local file = require "cheatoid-library/Shared/FileWrapper"
local http = require "cheatoid-library/Shared/HttpWrapper"
local Version = require "cheatoid-library/Shared/Version"

-- Built-in @cheatoid modules
local oop = require "cheatoid-library/Shared/@cheatoid/oop/oop"
local ref = require "cheatoid-library/Shared/@cheatoid/ref/ref"
local plugin_framework = require "cheatoid-library/Shared/@cheatoid/plugin_framework/plugin_framework"
-- etc.
```

## License

MIT License - See [LICENSE](LICENSE) file for details.
