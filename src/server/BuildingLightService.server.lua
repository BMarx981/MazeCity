-- BuildingLightService (Script) -> ServerScriptService
-- Persists which towers a player has topped out and lets that player clear the
-- visual record without changing tower progress, score, or the maze itself.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Profiles = require(ServerScriptService:WaitForChild("PlayerProfiles"))

local function findOrCreate(parent, className, name)
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local made = Instance.new(className)
	made.Name = name
	made.Parent = parent
	return made
end

local remote = findOrCreate(ReplicatedStorage, "RemoteEvent", "BuildingLightUpdate")
local intents = findOrCreate(ReplicatedStorage, "RemoteEvent", "BuildingLightIntent")
local progress = findOrCreate(ServerScriptService, "BindableEvent", "MazeProgress")

local function buildingKey(section, building)
	return string.format("%s:%s", tostring(section), tostring(building))
end

local function snapshot(data)
	local completed = {}
	for key, value in pairs(data.completedBuildings or {}) do
		if value == true then
			completed[key] = true
		end
	end
	return completed
end

local function push(player, event)
	local data = Profiles.data(player)
	if not data then
		return
	end
	remote:FireClient(player, {
		kind = "state",
		completed = snapshot(data),
		event = event,
	})
end

progress.Event:Connect(function(payload)
	if not payload or payload.kind ~= "tower" or not payload.player then
		return
	end

	local data = Profiles.data(payload.player)
	if not data then
		return
	end

	local key = buildingKey(payload.section, payload.building)
	data.completedBuildings = data.completedBuildings or {}
	if data.completedBuildings[key] then
		return
	end
	data.completedBuildings[key] = true
	push(payload.player, {
		kind = "completed",
		section = payload.section,
		building = payload.building,
	})
end)

intents.OnServerEvent:Connect(function(player, payload)
	if type(payload) ~= "table" then
		return
	end

	local data = Profiles.data(player)
	if not data then
		return
	end

	if payload.kind == "sync" then
		push(player)
		return
	end
	if payload.kind ~= "reset" then
		return
	end

	data.completedBuildings = {}
	push(player, { kind = "reset" })
end)

Profiles.onReady(function(player, data)
	data.completedBuildings = data.completedBuildings or {}
	push(player)
end)
