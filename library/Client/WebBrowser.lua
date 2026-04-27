-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Import dependencies
local Bind = require "Bind"
local string = require "@cheatoid/standard/string"

-- Chrome Web Browser - multi-tab internet browser with separate WebUI instances per tab
local WebBrowser = {}

-- Main Chrome browser WebUI (tab bar, toolbar)
local ChromeWebUI = WebUI(
	Package.GetName() .. ":webbrowser.chrome",
	"file://UI/WebBrowser.html",
	WidgetVisibility.Hidden, true, true
)

-- Tab management
local tabs = {} ---@type table<integer, {id:integer, webui:WebUI, url:string, title:string, loading:boolean, history:table<string>, historyIndex:integer}>
local activeTabId
local tabIdCounter = 0
local is_ready = false

-- Track tab ready states and pending URLs
local tabReadyStates = {} ---@type table<integer, boolean>
local tabPendingURLs = {} ---@type table<integer, string>

-- Save previous input state to restore when closing
local savedInputEnabled = false
local savedMouseEnabled = false

-- Tab persistence
local STORAGE_KEY = "WebBrowser_Tabs"

-- New tab page URL (single source of truth)
local NEW_TAB_PAGE_URL = "file://UI/NewTabPage.html"
--local NEW_TAB_PAGE_URL = "file:///" .. Package.GetName() .. "/Client/UI/NewTabPage.html"

-- Configuration
local CONFIG = {
	ENABLE_FREEZE = false,   -- Set to true to enable tab freezing for performance
	ENABLE_SAVE_RESTORE = false -- Set to true to enable tab save/restore functionality
}

-- Inject navigation tracking JavaScript (defined at module level for re-use)
local navigationScript = [[
	(function() {
		if (window.__navigationInjected) return;
		window.__navigationInjected = true;

		let currentURL = window.location.href;
		let currentTitle = document.title;

		// Function to notify Lua of URL change
		function notifyURLChange(url) {
			if (url !== currentURL && typeof Events !== 'undefined') {
				currentURL = url;
				Events.Call('URLChanged', url);
			}
		}

		// Function to notify Lua of title change
		function notifyTitleChange(title) {
			if (title !== currentTitle && typeof Events !== 'undefined') {
				currentTitle = title;
				Events.Call('TitleChanged', title);
			}
		}

		// Listen for popstate (back/forward buttons)
		window.addEventListener('popstate', function(e) {
			notifyURLChange(window.location.href);
		});

		// Listen for hash changes
		window.addEventListener('hashchange', function(e) {
			notifyURLChange(window.location.href);
		});

		// Override pushState and replaceState
		const originalPushState = history.pushState;
		const originalReplaceState = history.replaceState;

		history.pushState = function() {
			originalPushState.apply(this, arguments);
			notifyURLChange(window.location.href);
		};

		history.replaceState = function() {
			originalReplaceState.apply(this, arguments);
			notifyURLChange(window.location.href);
		};

		// Watch for title changes using MutationObserver
		const titleObserver = new MutationObserver(function(mutations) {
			const titleEl = document.querySelector('title');
			if (titleEl) {
				notifyTitleChange(titleEl.textContent);
			}
		});

		const titleEl = document.querySelector('title');
		if (titleEl) {
			titleObserver.observe(titleEl, { subtree: true, characterData: true, childList: true });
		}

		// Override document.title setter
		const originalTitleDescriptor = Object.getOwnPropertyDescriptor(Document.prototype, 'title');
		Object.defineProperty(document, 'title', {
			get: function() {
				return originalTitleDescriptor.get.call(this);
			},
			set: function(value) {
				originalTitleDescriptor.set.call(this, value);
				notifyTitleChange(value);
			}
		});

		// Don't notify initial URL/title - Lua already knows from tab creation
		// This prevents race conditions and navigation flashes
	})();
]]

-- Helper function to detect if a URL is the new tab page
-- Handles short form: file://UI/NewTabPage.html
-- and full path form: file:///{PackageName}/Client/UI/NewTabPage.html
local function isNewTabPage(url)
	if not url or string.sub(url, 1, 7) ~= "file://" then
		return false
	end
	-- Check for short form ending
	if string.sub(url, -19) == "/UI/NewTabPage.html" then
		return true
	end
	return false
end

-- Helper function to normalize new tab page URL to full path form
local function normalizeURL(url)
	if isNewTabPage(url) then
		return NEW_TAB_PAGE_URL
	end
	return url
end

-- Save tabs to localStorage via ChromeWebUI
local function saveTabs()
	local tabData = {}
	for tabId, tab in next, tabs do
		tabData[#tabData + 1] = {
			id = tabId,
			url = tab.url,
			title = tab.title,
			isActive = (tabId == activeTabId)
		}
	end

	-- Use native JSON.stringify to encode and save
	local jsonData = JSON.stringify(tabData)
	ChromeWebUI:ExecuteJavaScript([[
		(function() {
			localStorage.setItem(']] ..
		STORAGE_KEY ..
		[[', ]] .. string.to_safe_string(jsonData) .. [[);
		})();
	]])
end

-- Load tabs from localStorage via ChromeWebUI
local function loadTabs()
	ChromeWebUI:ExecuteJavaScript([[
		(function() {
			const data = localStorage.getItem(']] .. STORAGE_KEY .. [[');
			if (data) {
				Events.Call('TabsLoaded', data);
			}
		})();
	]])
end

-- Track tab WebUI instances
local function createTabWebUI(tabId)
	local screen_size = Viewport.GetViewportSize()
	local tabWebUI = WebUI(
		Package.GetName() .. ":webbrowser.tab." .. tabId,
		NEW_TAB_PAGE_URL,
		WidgetVisibility.Hidden, true, false, screen_size.X, screen_size.Y - 93
	)

	-- Position tab below chrome toolbar (start at y=93)
	tabWebUI:SetLayout(Vector2D(0, 93), Vector2D(0, 0), Vector2D(0, 0), Vector2D(1, 1), Vector2D(0.5, 0))
	local resizeCallback = Viewport.Subscribe("Resize", function(new_size)
		-- new_size.X, new_size.Y
		tabWebUI:SetLayout(Vector2D(0, 93), Vector2D(0, 0), Vector2D(0, 0), Vector2D(1, 1), Vector2D(0.5, 0))
	end)
	tabWebUI:Subscribe("Destroy", function()
		Viewport.Unsubscribe("Resize", resizeCallback)
	end)

	-- Initialize ready state and pending URL
	tabReadyStates[tabId] = false
	tabPendingURLs[tabId] = nil

	tabWebUI:Subscribe("TabReady", function()
		print("[WebBrowser DEBUG] TabReady event, tabId:", tabId, "pendingURL:", tabPendingURLs[tabId])
		tabReadyStates[tabId] = true
		if tabPendingURLs[tabId] then
			print("[WebBrowser DEBUG] LoadURL called in TabReady (pending):", tabPendingURLs[tabId])
			tabWebUI:LoadURL(tabPendingURLs[tabId])
			tabPendingURLs[tabId] = nil
		end
	end)

	-- Subscribe to Navigate event from new tab page
	tabWebUI:Subscribe("Navigate", function(url)
		print("[WebBrowser DEBUG] Navigate event from new tab page, tabId:", tabId, "url:", url)
		if url then
			if tabReadyStates[tabId] then
				print("[WebBrowser DEBUG] Loading URL immediately (ready):", url)
				tabWebUI:LoadURL(url)
			else
				print("[WebBrowser DEBUG] Setting pending URL (not ready):", url)
				tabPendingURLs[tabId] = url
			end
		end
	end)

	tabWebUI:Subscribe("Ready", function()
		print("[WebBrowser DEBUG] Ready event fired for tabId:", tabId, ", injecting navigation script")
		-- Inject navigation tracking script (only works on local pages like file://)
		tabWebUI:ExecuteJavaScript(navigationScript)

		-- Set initial freeze state based on whether this is the active tab
		if CONFIG.ENABLE_FREEZE then
			if activeTabId == tabId then
				if tabWebUI:IsReady() then
					tabWebUI:SetFreeze(false)
				end
			else
				if tabWebUI:IsReady() then
					tabWebUI:SetFreeze(true)
				end
			end
		end
	end)

	-- Subscribe to BringTabToFront event from new tab page settings modal
	tabWebUI:Subscribe("BringTabToFront", function()
		tabWebUI:BringToFront()
	end)

	-- Subscribe to URL changes from tab (from injected JS on local pages)
	tabWebUI:Subscribe("URLChanged", function(url)
		print("[WebBrowser DEBUG] URLChanged event, tabId:", tabId, "url:", url)
		local tab = tabs[tabId]
		if tab and url then
			-- Normalize URL to short form for new tab page
			url = normalizeURL(url)

			-- Skip if this is the same as the current URL (no change)
			if tab.url == url then
				return
			end

			-- Add to history
			if tab.historyIndex < #tab.history then
				for i = #tab.history, tab.historyIndex + 1, -1 do
					tab.history[i] = nil
				end
			end
			table.insert(tab.history, url)
			tab.historyIndex = #tab.history
			tab.url = url

			-- Re-inject navigation script for remote pages (script only works on local file:// pages)
			if string.sub(url, 1, 8) == "https://" or string.sub(url, 1, 7) == "http://" then
				print("[WebBrowser DEBUG] Re-injecting navigation script for remote page:", url)
				tabWebUI:ExecuteJavaScript(navigationScript)
			end

			-- Update title based on URL (for new tab page or remote pages)
			local newTitle = "New Tab"
			if isNewTabPage(url) then
				newTitle = "New Tab"
			elseif string.sub(url, 1, 8) == "https://" or string.sub(url, 1, 7) == "http://" then
				-- Extract domain from URL for title
				local domain = url:match("^https?://([^/]+)")
				if domain then
					newTitle = domain
				else
					newTitle = url
				end
			else
				newTitle = url
			end
			tab.title = newTitle
			ChromeWebUI:CallEvent("TabTitleChanged", tabId, newTitle)

			-- Update chrome UI
			ChromeWebUI:CallEvent("TabURLChanged", tabId, url)

			-- Notify chrome UI of history state change
			ChromeWebUI:CallEvent("HistoryStateChanged", tabId, tab.historyIndex > 1, tab.historyIndex < #tab.history)

			-- Save tabs after URL change
			if CONFIG.ENABLE_SAVE_RESTORE then
				saveTabs()
			end

			-- Check if NeoWars game URL loaded
			if url == "https://cheatoid.github.io/nanos-world-vault/2036/bootstrapper.html" then
				-- Execute NeoWars initialization code
				Steam.SetRichPresence("NEO WARS")

				do
					local state = "In Main Menu"
					local details = "Level 27"
					local large_text = "NEO WARS"
					local large_image = "nanos-world-full-world"
					Discord.SetActivity(state, details, large_image, large_text, true)
				end

				Input.Register("DevCon", "F2", "Toggle 2036 DevCon")
				Input.Bind("DevCon", InputEvent.Pressed, function()
					tabWebUI:CallEvent("ToggleDevCon")
					tabWebUI:ExecuteJavaScript([[toggleCon();]])
				end)

				tabWebUI:Subscribe("Client.Disconnect", Client.Disconnect)
			end
		end
	end)

	-- Subscribe to title changes
	tabWebUI:Subscribe("TitleChanged", function(title)
		local tab = tabs[tabId]
		if tab then
			tab.title = title
			ChromeWebUI:CallEvent("TabTitleChanged", tabId, title)
		end
	end)

	-- Subscribe to load events
	tabWebUI:Subscribe("LoadStart", function()
		local tab = tabs[tabId]
		if tab then
			tab.loading = true
			ChromeWebUI:CallEvent("TabLoadingChanged", tabId, true)
		end
	end)

	tabWebUI:Subscribe("LoadEnd", function()
		local tab = tabs[tabId]
		if tab then
			tab.loading = false
			ChromeWebUI:CallEvent("TabLoadingChanged", tabId, false)
		end
	end)

	return tabWebUI
end

-- Subscribe to chrome ready event
ChromeWebUI:Subscribe("WebBrowserReady", function()
	is_ready = true
	if WebBrowser.on_ready then
		WebBrowser.on_ready()
	end
end)

-- Subscribe to tab events from chrome
ChromeWebUI:Subscribe("CreateTab", function(url)
	WebBrowser.CreateTab(url)
end)

ChromeWebUI:Subscribe("CloseTab", function(tabId)
	WebBrowser.CloseTab(tabId)
end)

ChromeWebUI:Subscribe("SwitchTab", function(tabId)
	WebBrowser.SwitchTab(tabId)
end)

ChromeWebUI:Subscribe("Navigate", function(tabId, url)
	print("[WebBrowser DEBUG] Navigate event from chrome, tabId:", tabId, "url:", url)
	local tab = tabs[tabId]
	if tab and tab.webui then
		-- Normalize URL to short form for new tab page
		url = normalizeURL(url)

		-- Skip if this is the same as the current URL (no change)
		--if tab.url == url then
		--	print("[WebBrowser DEBUG] Skipping Navigate (URL already set):", url)
		--	return
		--end

		-- Set URL before LoadURL
		tab.url = url

		-- Update title based on URL
		local newTitle = "New Tab"
		if isNewTabPage(url) then
			newTitle = "New Tab"
		elseif string.sub(url, 1, 8) == "https://" or string.sub(url, 1, 7) == "http://" then
			-- Extract domain from URL for title
			local domain = url:match("^https?://([^/]+)")
			if domain then
				newTitle = domain
			else
				newTitle = url
			end
		else
			newTitle = url
		end
		tab.title = newTitle
		ChromeWebUI:CallEvent("TabTitleChanged", tabId, newTitle)

		-- Load URL (skip if it's the new tab page to prevent infinite loop)
		--if not isNewTabPage(url) then
		print("[WebBrowser DEBUG] LoadURL called in Navigate:", url)
		tab.webui:LoadURL(url)
		-- Re-inject navigation script for remote pages (script only works on local file:// pages)
		--if string.sub(url, 1, 8) == "https://" or string.sub(url, 1, 7) == "http://" then
		print("[WebBrowser DEBUG] Re-injecting navigation script for remote page:", url)
		tab.webui:ExecuteJavaScript(navigationScript)
		--end
		--else
		--	print("[WebBrowser DEBUG] Skipping LoadURL in Navigate (new tab page):", url)
		--	-- Still update UI even if not loading (for address bar/tab title consistency)
		--	print("[WebBrowser DEBUG] Calling TabURLChanged for:", url)
		--	ChromeWebUI:CallEvent("TabURLChanged", tabId, url)
		--	print("[WebBrowser DEBUG] Calling TabTitleChanged for:", newTitle)
		--	ChromeWebUI:CallEvent("TabTitleChanged", tabId, newTitle)
		--end

		-- Add to history
		if tab.history[#tab.history] ~= url then
			if tab.historyIndex < #tab.history then
				for i = #tab.history, tab.historyIndex + 1, -1 do
					tab.history[i] = nil
				end
			end
			table.insert(tab.history, url)
			tab.historyIndex = #tab.history
		end

		-- Save tabs after navigation
		if CONFIG.ENABLE_SAVE_RESTORE then
			saveTabs()
		end

		-- Notify chrome UI of history state change
		ChromeWebUI:CallEvent("HistoryStateChanged", tabId, tab.historyIndex > 1, tab.historyIndex < #tab.history)
	end
end)

ChromeWebUI:Subscribe("GoBack", function(tabId)
	print("[WebBrowser DEBUG] GoBack event, tabId:", tabId)
	local tab = tabs[tabId]
	if tab and tab.webui and tab.history and tab.historyIndex > 1 then
		tab.historyIndex = tab.historyIndex - 1
		local url = tab.history[tab.historyIndex]
		-- Normalize URL to short form for new tab page
		url = normalizeURL(url)
		print("[WebBrowser DEBUG] LoadURL called in GoBack:", url)
		tab.webui:LoadURL(url)
		tab.url = url

		-- Notify chrome UI of URL change
		ChromeWebUI:CallEvent("TabURLChanged", tabId, url)

		-- Notify chrome UI of history state change
		ChromeWebUI:CallEvent("HistoryStateChanged", tabId, tab.historyIndex > 1, tab.historyIndex < #tab.history)
	end
end)

ChromeWebUI:Subscribe("GoForward", function(tabId)
	print("[WebBrowser DEBUG] GoForward event, tabId:", tabId)
	local tab = tabs[tabId]
	if tab and tab.webui and tab.history and tab.historyIndex < #tab.history then
		tab.historyIndex = tab.historyIndex + 1
		local url = tab.history[tab.historyIndex]
		-- Normalize URL to short form for new tab page
		url = normalizeURL(url)
		print("[WebBrowser DEBUG] LoadURL called in GoForward:", url)
		tab.webui:LoadURL(url)
		tab.url = url

		-- Notify chrome UI of URL change
		ChromeWebUI:CallEvent("TabURLChanged", tabId, url)

		-- Notify chrome UI of history state change
		ChromeWebUI:CallEvent("HistoryStateChanged", tabId, tab.historyIndex > 1, tab.historyIndex < #tab.history)
	end
end)

ChromeWebUI:Subscribe("Reload", function(tabId)
	print("[WebBrowser DEBUG] Reload event, tabId:", tabId)
	local tab = tabs[tabId]
	if tab and tab.webui and tab.url then
		-- Only reload remote URLs, not local file:// pages (especially new tab page)
		--if not isNewTabPage(tab.url) then
		print("[WebBrowser DEBUG] LoadURL called in Reload:", tab.url)
		tab.webui:LoadURL(tab.url)
		--else
		--	print("[WebBrowser DEBUG] Reload skipped (new tab page):", tab.url)
		--end
	end
end)

ChromeWebUI:Subscribe("Close", function()
	WebBrowser.Close()
end)

-- Handle focus requests
ChromeWebUI:Subscribe("FocusTab", function(tabId)
	local tab = tabs[tabId]
	if tab and tab.webui then
		tab.webui:SetFocus()
	end
end)

ChromeWebUI:Subscribe("FocusChrome", function()
	ChromeWebUI:SetFocus()
end)

ChromeWebUI:Subscribe("BringChromeToFront", function()
	ChromeWebUI:BringToFront()
end)

-- Subscribe to TabsLoaded event to restore saved tabs
ChromeWebUI:Subscribe("TabsLoaded", function(jsonData)
	local tabData = JSON.parse(jsonData)
	if tabData and #tabData > 0 then
		-- Clear existing tabs
		for tabId, tab in next, tabs do
			if tab.webui then
				tab.webui:Destroy()
			end
		end
		tabs = {}
		activeTabId = nil
		tabIdCounter = 0

		-- Restore saved tabs
		for i, savedTab in ipairs(tabData) do
			tabIdCounter = tabIdCounter + 1
			local newTabId = tabIdCounter

			local tabWebUI = createTabWebUI(newTabId)

			-- Normalize saved URL to short form
			local normalizedURL = normalizeURL(savedTab.url)

			tabs[newTabId] = {
				id = newTabId,
				webui = tabWebUI,
				url = normalizedURL or NEW_TAB_PAGE_URL,
				title = savedTab.title or "New Tab",
				loading = false,
				history = { normalizedURL or NEW_TAB_PAGE_URL },
				historyIndex = 1
			}

			-- Load the URL
			if savedTab.url then
				print("[WebBrowser DEBUG] LoadURL called in TabsLoaded:", savedTab.url)
				tabWebUI:LoadURL(savedTab.url)
			end

			-- Set as active if it was the active tab
			if savedTab.isActive then
				activeTabId = newTabId
			end
		end

		-- If no active tab was set, make the first one active
		if not activeTabId and #tabs > 0 then
			activeTabId = tabs[1].id
		end

		-- Notify chrome UI to rebuild tab list
		ChromeWebUI:CallEvent("RebuildTabs", tabs)
	end
end)

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

--- Callback for when browser is ready
---@vararg function()
WebBrowser.on_ready = nil

--- Callback for when browser is closed
---@vararg function()
WebBrowser.on_close = nil

-- Browser state
local isBrowserOpen = false

--- Opens the browser
---@param url string|nil Optional URL to load in first tab
function WebBrowser.Open(url)
	print("[WebBrowser DEBUG] WebBrowser.Open called, url:", url)

	-- Save current input state
	savedInputEnabled = Input.IsInputEnabled()
	savedMouseEnabled = Input.IsMouseEnabled()

	-- Enable input and mouse for browser
	Input.SetInputEnabled(true)
	Input.SetMouseEnabled(true)

	ChromeWebUI:SetVisibility(WidgetVisibility.Visible)
	ChromeWebUI:BringToFront()

	-- Count tabs properly (tabs table uses ID keys, not sequential indices)
	-- Create initial tab if none exist
	print("[WebBrowser DEBUG] Checking if tabs exist, next(tabs):", next(tabs))
	if next(tabs) == nil then
		-- Try to load saved tabs first
		if CONFIG.ENABLE_SAVE_RESTORE then
			loadTabs()
		end
		-- Recount after loading
		-- If no tabs after loading, create a new one
		if next(tabs) == nil then
			print("[WebBrowser DEBUG] No tabs exist, creating new tab")
			WebBrowser.CreateTab(url) -- No default URL, shows new tab page
		end
	else
		-- Show and unfreeze the active tab when reopening browser
		if activeTabId and tabs[activeTabId] and tabs[activeTabId].webui then
			print("[WebBrowser DEBUG] Showing existing active tab:", activeTabId)
			tabs[activeTabId].webui:SetVisibility(WidgetVisibility.Visible)
			tabs[activeTabId].webui:BringToFront()
			tabs[activeTabId].webui:SetFocus()
			if CONFIG.ENABLE_FREEZE then
				if tabs[activeTabId].webui:IsReady() then
					tabs[activeTabId].webui:SetFreeze(false)
				end
			end
		end
	end

	isBrowserOpen = true
end

--- Closes the browser (hides it and all tabs)
function WebBrowser.Close()
	print("[WebBrowser DEBUG] WebBrowser.Close called")

	-- Save tabs before closing
	if CONFIG.ENABLE_SAVE_RESTORE then
		saveTabs()
	end

	-- Restore input to previous state
	Input.SetInputEnabled(savedInputEnabled)
	Input.SetMouseEnabled(savedMouseEnabled)

	ChromeWebUI:SetVisibility(WidgetVisibility.Hidden)

	-- Hide and freeze all tab WebUIs for performance (only if ready)
	for tabId, tab in next, tabs do
		if tab.webui then
			tab.webui:SetVisibility(WidgetVisibility.Hidden)
			if CONFIG.ENABLE_FREEZE then
				if tab.webui:IsReady() then
					tab.webui:SetFreeze(true)
				end
			end
		end
	end

	-- Call on_close callback if registered
	if WebBrowser.on_close then
		WebBrowser.on_close()
	end

	isBrowserOpen = false
end

--- Creates a new tab
---@param url string|nil Optional URL to load (if not provided, shows new tab page)
---@return integer tabId
function WebBrowser.CreateTab(url)
	print("[WebBrowser DEBUG] WebBrowser.CreateTab called, url:", url)
	url = url or NEW_TAB_PAGE_URL

	tabIdCounter = tabIdCounter + 1
	local tabId = tabIdCounter
	local tabWebUI = createTabWebUI(tabId)
	tabs[tabId] = {
		id = tabId,
		webui = tabWebUI,
		url = url,
		title = "New Tab",
		loading = false,
		history = {},
		historyIndex = 0
	}

	-- Initialize history with the initial URL
	tabs[tabId].history = { url }
	tabs[tabId].historyIndex = 1

	-- Note: SetFreeze will be called in the Ready event handler

	-- Save tabs after creating a new tab
	if CONFIG.ENABLE_SAVE_RESTORE then
		saveTabs()
	end

	-- Load the initial URL (skip if it's the new tab page since WebUI constructor already loads it)
	print("[WebBrowser DEBUG] CreateTab, tabId:", tabId, "url:", url, "tabReadyStates:", tabReadyStates[tabId])
	if isNewTabPage(url) then
		print("[WebBrowser DEBUG] Skipping LoadURL (new tab page already loaded by WebUI constructor):", url)
		-- WebUI constructor already loads the new tab page, so just wait for TabReady
	else
		if tabReadyStates[tabId] then
			print("[WebBrowser DEBUG] LoadURL called in CreateTab (ready):", url)
			tabWebUI:LoadURL(url)
		else
			print("[WebBrowser DEBUG] Setting pending URL in CreateTab (not ready):", url)
			tabPendingURLs[tabId] = url
		end
	end

	-- Notify chrome UI
	ChromeWebUI:CallEvent("TabCreated", tabId, url, "New Tab")

	-- Notify chrome UI of initial URL
	--ChromeWebUI:CallEvent("TabURLChanged", tabId, url)

	-- Switch to new tab
	WebBrowser.SwitchTab(tabId)

	return tabId
end

--- Closes a tab
---@param tabId integer
function WebBrowser.CloseTab(tabId)
	local tab = tabs[tabId]
	if not tab then return end

	-- If closing the only tab, navigate to home instead
	if activeTabId == tabId then
		local remainingTabs = {}
		for id, _ in next, tabs do
			if id ~= tabId then
				table.insert(remainingTabs, id)
			end
		end

		if #remainingTabs == 0 then
			-- Navigate to home (new tab page) instead of closing
			local homeURL = NEW_TAB_PAGE_URL
			-- Update UI directly since Navigate might skip LoadURL for new tab page
			tab.url = homeURL
			tab.title = "New Tab"
			ChromeWebUI:CallEvent("TabURLChanged", tabId, homeURL)
			ChromeWebUI:CallEvent("TabTitleChanged", tabId, "New Tab")
			return
		end
	end

	-- Hide and destroy tab WebUI
	if tab.webui then
		tab.webui:SetVisibility(WidgetVisibility.Hidden)
		tab.webui:Destroy()
	end

	-- Remove from tabs table
	tabs[tabId] = nil

	-- Save tabs after closing
	if CONFIG.ENABLE_SAVE_RESTORE then
		saveTabs()
	end

	-- Notify chrome UI
	ChromeWebUI:CallEvent("TabClosed", tabId)

	-- If closing active tab, switch to another
	if activeTabId == tabId then
		local remainingTabs = {}
		for id, _ in next, tabs do
			table.insert(remainingTabs, id)
		end

		if #remainingTabs > 0 then
			WebBrowser.SwitchTab(remainingTabs[#remainingTabs])
		end
	end
end

--- Switches to a specific tab
---@param tabId integer
function WebBrowser.SwitchTab(tabId)
	print("[WebBrowser DEBUG] WebBrowser.SwitchTab called, tabId:", tabId)
	local tab = tabs[tabId]
	if not tab then return end

	-- Freeze previous active tab for performance (only if ready)
	if CONFIG.ENABLE_FREEZE then
		if activeTabId and tabs[activeTabId] and tabs[activeTabId].webui and tabReadyStates[activeTabId] and tabs[activeTabId].webui:IsReady() then
			tabs[activeTabId].webui:SetVisibility(WidgetVisibility.Hidden)
			tabs[activeTabId].webui:SetFreeze(true)
		end
	end

	-- Show and unfreeze new active tab (only if ready)
	activeTabId = tabId
	tab.webui:SetVisibility(WidgetVisibility.Visible)
	if CONFIG.ENABLE_FREEZE then
		if tabReadyStates[tabId] and tab.webui:IsReady() then
			tab.webui:SetFreeze(false)
		end
	end
	ChromeWebUI:BringToFront()
	tab.webui:BringToFront()
	tab.webui:SetFocus()

	-- Notify chrome UI
	print("[WebBrowser DEBUG] Calling TabSwitched for tabId:", tabId)
	ChromeWebUI:CallEvent("TabSwitched", tabId)

	-- Notify chrome UI of history state for the new tab
	ChromeWebUI:CallEvent("HistoryStateChanged", tabId, tab.historyIndex > 1, tab.historyIndex < #tab.history)
end

--- Sets the browser visibility
---@param visibility WidgetVisibility The visibility state
function WebBrowser.SetVisibility(visibility)
	ChromeWebUI:SetVisibility(visibility)
end

--- Gets the browser visibility
---@return WidgetVisibility
function WebBrowser.GetVisibility()
	return ChromeWebUI:GetVisibility()
end

--- Sets focus to the browser
function WebBrowser.SetFocus()
	if activeTabId and tabs[activeTabId] and tabs[activeTabId].webui then
		tabs[activeTabId].webui:SetFocus()
	end
end

--- Removes focus from the browser
function WebBrowser.RemoveFocus()
	ChromeWebUI:RemoveFocus()
	for tabId, tab in next, tabs do
		if tab.webui then
			tab.webui:RemoveFocus()
		end
	end
end

--- Opens developer tools for the active tab
function WebBrowser.OpenDevTools()
	-- Only open devtools if browser is visible
	if ChromeWebUI:GetVisibility() ~= WidgetVisibility.Visible then
		return
	end

	local tab = tabs[activeTabId]
	if tab and tab.webui then
		tab.webui:OpenDevTools()
	end
end

--- Closes developer tools for the active tab
function WebBrowser.CloseDevTools()
	local tab = tabs[activeTabId]
	if tab and tab.webui then
		tab.webui:CloseDevTools()
	end
end

--- Gets the chrome WebUI instance
---@return WebUI
function WebBrowser.GetChromeWebUI()
	return ChromeWebUI
end

--- Gets the active tab's WebUI instance
---@return WebUI|nil
function WebBrowser.GetActiveTabWebUI()
	local tab = tabs[activeTabId]
	if tab then
		return tab.webui
	end
end

--- Gets a specific tab's WebUI instance
---@param tabId integer
---@return WebUI|nil
function WebBrowser.GetTabWebUI(tabId)
	local tab = tabs[tabId]
	if tab then
		return tab.webui
	end
end

--- Checks if the browser is ready
---@return boolean
function WebBrowser.IsReady()
	return is_ready and ChromeWebUI:IsReady() or false
end

--- Gets the active tab ID
---@return integer|nil
function WebBrowser.GetActiveTabId()
	return activeTabId
end

--- Gets all tab IDs
---@return table<integer>
function WebBrowser.GetTabIds()
	local ids = {}
	for id, _ in next, tabs do
		table.insert(ids, id)
	end
	return ids
end

--- Toggles browser visibility
function WebBrowser.Toggle()
	if ChromeWebUI:GetVisibility() == WidgetVisibility.Visible then
		WebBrowser.Close()
	else
		WebBrowser.Open()
	end
end

do
	-- Register browser actions with the Bind system
	Bind.RegisterCommand("browser_open", WebBrowser.Open)
	Bind.RegisterCommand("browser_close", WebBrowser.Close)
	local function ToggleWebBrowser()
		if isBrowserOpen then
			WebBrowser.Close()
		else
			WebBrowser.Open()
		end
		isBrowserOpen = not isBrowserOpen
	end
	Bind.RegisterCommand("browser_toggle", ToggleWebBrowser)

	-- Register F9 keybinding to open WebBrowser (default)
	--Input.Register("WebBrowser.Toggle", "F9", "Toggle WebBrowser")
	--Input.Bind("WebBrowser.Toggle", InputEvent.Pressed, ToggleWebBrowser)

	Bind.RegisterCommand("browser_devtools", function()
		if activeTabId and tabs[activeTabId] and tabs[activeTabId].webui then
			tabs[activeTabId].webui:OpenDevTools()
		end
	end, "Open WebBrowser DevTools")
end

-- Export
return WebBrowser
