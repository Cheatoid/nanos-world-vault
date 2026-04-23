-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

require "cheatoid-library/Shared/Index.lua"

local MainWebUI = WebUI(
	Package.GetName() .. ":ui",
	"file:///UI/2036.html",
	WidgetVisibility.Visible, false, true, 0, 0
)

Input.SetInputEnabled(false)
Input.SetMouseCursor(CursorType.Default)
Input.SetMouseEnabled(true)

Steam.SetRichPresence("NEO WARS")

do
	local state = "In Main Menu"
	local details = "Level 27"
	local large_text = "NEO WARS"
	local large_image = "nanos-world-full-world"
	Discord.SetActivity(state, details, large_image, large_text, true)
end

Input.Register("Server, please reload packages", "F5", "Reload Packages")
Input.Bind("Server, please reload packages", InputEvent.Pressed, function()
	Events.CallRemote("Server, please reload packages")
end)

Input.Register("DevCon", "F2", "Toggle DevCon")
Input.Bind("DevCon", InputEvent.Pressed, function()
	MainWebUI:CallEvent("ToggleDevCon")
	MainWebUI:ExecuteJavaScript([[toggleCon();]])
	--MainWebUI:SendKeyEvent(WebUIKeyType.Down, 0x0029, WebUIModifier.None)
end)

MainWebUI:Subscribe("Ready", function()
	print("MainWebUI ready")
	MainWebUI:OpenDevTools()
end)

MainWebUI:Subscribe("Client.Disconnect", Client.Disconnect)
