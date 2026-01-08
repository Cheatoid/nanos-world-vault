# Library API
Currrently featuring... more coming soon™ 🚀

## ConVar
Exposed as `ConVar`; used for creating console variables (Source-engine style).
By default, it creates `cvarlist` conmmand to dump created convars, adds `sv_cheats` (placeholder convar), and also adds `sv_password` used for changing server's password.
How to change convars? Simply type the convar name followed by a value into a console, for example to change server's password to `test123`, you would enter `sv_password test123` into console.
You can register your own convars, for example:
```lua
local sv_allowcslua = ConVar.Register(
	"sv_allowcslua", -- name
	Server.GetCustomSettings().enable_cslua or false, -- optional, default value (either boolean, number or string)
	"Enable players to run Lua on client-side", -- optional, description
	ConVar.FLAG.REPLICATED, -- optional, flags (can be combination of bitfields)
	0, -- optional, minimum numeric value (0 for boolean)
	1  -- optional, maximum numeric value (1 for boolean)
)

-- You can also be notified about a change of convar's value by adding a callback like this:
-- Note: If you specify NEVER_AS_STRING in convar flags, then `new_value` argument will be empty in callback.
sv_allowcslua:AddChangeCallback(function(name, new_value, source)
	Console.Log("%s has been %s by %s", name, new_value and "enabled" or "disabled", source)
end)
-- You can remove previously added change-callback by calling RemoveChangeCallback and passing the function.

-- Handy getters are available also:
-- sv_allowcslua:GetBool() /  sv_allowcslua:GetInt() / sv_allowcslua:GetFloat() / sv_allowcslua:GetString()
-- sv_allowcslua:SetValue(true) -- setter (must respect convar's type, will do loose conversion)

-- There are several convar bit-flags available (they can be combined using bitwise-OR), they allow you to control how convar behaves.
-- For example: USERINFO flag is useful when you want to provide a convar on client and fetch it's value on the server side:
if Client then
	ConVar.Register("cl_userinfo_cvar", "stuff", "example userinfo cvar", ConVar.FLAG.USERINFO)
else
	-- On server-side we can fetch player's userinfo value:
	ConVar.GetUserInfo(player, "cl_userinfo_cvar")
end

-- For more information, open package source code and read the code, its fairly documented 😇
```
