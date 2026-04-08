-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- WebSocket Bridge Test Script
-- This demonstrates how to use the WebSocketAPI

-- Load the WebSocket API
local WebSocketAPI = require("WebSocketAPI")
-- Alternatively, remove the above local completely and it would still work the same,
-- because WebSocketAPI is exported globally in Index.lua via GAIMERS

-- Test WebSocket connection
local function test_websocket()
	print("Testing WebSocket Bridge...")

	-- Connect to a public echo server
	WebSocketAPI.Connect("wss://echo.websocket.org", nil, function(success, result)
		if success then
			print("Connected to WebSocket:", result.socket_id)
			print("Initial state:", result.message)

			-- Set up event handlers
			WebSocketAPI.OnOpen(result.socket_id, function(event)
				print("WebSocket opened!")

				-- Send a test message
				WebSocketAPI.Send(result.socket_id, "Hello from nanos world!", function(success, send_result)
					if success then
						print("Message sent:", send_result.message)
					else
						print("Failed to send message:", send_result)
					end
				end)
			end)

			WebSocketAPI.OnMessage(result.socket_id, function(message)
				print("Received message:", message)

				-- Check connection state
				WebSocketAPI.GetState(result.socket_id, function(success, state_result)
					if success then
						print("Connection state:", state_result.state)
					end
				end)

				-- Disconnect after receiving echo
				WebSocketAPI.Disconnect(result.socket_id, function(success, disconnect_result)
					if success then
						print("Disconnected:", disconnect_result.message)
					else
						print("Failed to disconnect:", disconnect_result)
					end
				end)
			end)

			WebSocketAPI.OnError(result.socket_id, function(error)
				print("WebSocket error:", error)
			end)

			WebSocketAPI.OnClose(result.socket_id, function(event)
				print("WebSocket closed:", event.reason, "(code:", event.code, ")")
			end)
		else
			print("Failed to connect:", result)
		end
	end)
end

-- Run the test
test_websocket()
