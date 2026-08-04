-- TowerTimerService (Script) -> ServerScriptService
-- Starts a fresh timer the moment a player reaches a new floor.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))

local remote = ReplicatedStorage:FindFirstChild("TimerUpdate")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "TimerUpdate"
	remote.Parent = ReplicatedStorage
end

local state = {}

local function keyFor(trigger)
	return string.format(
		"%s:%s:%s",
		tostring(trigger:GetAttribute("Section")),
		tostring(trigger:GetAttribute("Building")),
		tostring(trigger:GetAttribute("Level"))
	)
end

local function findTowerStart(section, building)
	for _, spawn in ipairs(CollectionService:GetTagged("TowerStart")) do
		local folder = spawn:FindFirstAncestorWhichIsA("Folder")
		while folder do
			if folder:GetAttribute("Building") == building and folder:GetAttribute("Section") == section then
				return spawn
			end
			folder = folder.Parent and folder.Parent:FindFirstAncestorWhichIsA("Folder")
		end
	end
	return nil
end

local function teleport(player, cframe)
	local char = player.Character
	if not char then
		return
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = cframe + Vector3.new(0, 4, 0)
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

local function push(player)
	local s = state[player]
	if not s then
		remote:FireClient(player, nil)
		return
	end
	remote:FireClient(player, {
		level = s.level,
		tower = s.tower,
		remaining = math.max(0, s.deadline - os.clock()),
		allowance = s.allowance,
	})
end

local function startFloor(player, trigger)
	local level = trigger:GetAttribute("Level") or 0
	local allowance = Config.getLevelTime(level)

	state[player] = {
		key = keyFor(trigger),
		level = level,
		section = trigger:GetAttribute("Section"),
		building = trigger:GetAttribute("Building"),
		tower = trigger:GetAttribute("TowerName") or "Tower",
		allowance = allowance,
		deadline = os.clock() + allowance,
		anchor = trigger.CFrame,
		startedAt = os.clock(),
	}

	push(player)
end

local function fail(player)
	local s = state[player]
	if not s then
		return
	end

	if Config.FailAction == "restartTower" then
		local spawn = findTowerStart(s.section, s.building)
		if spawn then
			teleport(player, spawn.CFrame)
			state[player] = nil
			push(player)
			return
		end
	end

	teleport(player, s.anchor)
	s.deadline = os.clock() + s.allowance
	s.startedAt = os.clock()
	push(player)
end

local function bindTrigger(trigger)
	if not trigger:IsA("BasePart") then
		return
	end
	trigger.Touched:Connect(function(hit)
		local char = hit:FindFirstAncestorOfClass("Model")
		if not char then
			return
		end
		local player = Players:GetPlayerFromCharacter(char)
		if not player then
			return
		end

		local s = state[player]
		local key = keyFor(trigger)
		if s and s.key == key then
			return
		end
		if s and (os.clock() - s.startedAt) < Config.GraceSeconds then
			return
		end

		startFloor(player, trigger)
	end)
end

for _, trigger in ipairs(CollectionService:GetTagged("LevelTrigger")) do
	bindTrigger(trigger)
end
CollectionService:GetInstanceAddedSignal("LevelTrigger"):Connect(bindTrigger)

Players.PlayerRemoving:Connect(function(player)
	state[player] = nil
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.2)
		push(player)
	end)
end)

if Config.TimerEnabled then
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator = accumulator + dt
		if accumulator < 0.25 then
			return
		end
		accumulator = 0

		local now = os.clock()
		for player, s in pairs(state) do
			if player.Parent then
				if now >= s.deadline then
					fail(player)
				else
					push(player)
				end
			else
				state[player] = nil
			end
		end
	end)
end
