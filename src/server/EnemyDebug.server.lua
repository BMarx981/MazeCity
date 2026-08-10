-- EnemyDebug (Script) -> ServerScriptService
-- The Studio-only enemy commands and visualizers the plan schedules at E5. The
-- whole file returns immediately outside Studio, so nothing here exists in a
-- live server: no command surface, no visual, no folder.
--
-- Two ways in, same dispatcher. Chat "/enemy <command> ..." as any player, or
-- from the command bar during Play:
--
--   game:GetService("ServerScriptService").EnemyDebugCommand:Invoke("spawn", "Warden")
--
-- Commands: models (regenerate templates, proving idempotence), spawn <Type>
-- [count], wave <budget>, clear, damage [amount], kill (nearest enemy to the
-- speaker; nothing else in the game can damage one, which is what makes these
-- two the only door to the Died path), ai (freeze everything, toggling), and
-- the visualizer toggles detect, leash, paths, labels.
--
-- Visuals redraw on a slow loop into workspace.EnemyDebug, never MazeCity, and
-- the folder is emptied when every toggle is off. Detection rings ride the rig
-- and leash rings sit on the marker, which is the difference worth seeing:
-- detection is where the enemy is, leash is the patch of maze it owns.
--
-- Debug spawns have no marker, so they register keyed by their own rig, are
-- never respawned, and tidy themselves up shortly after death.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

if not RunService:IsStudio() then
	return
end

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local ModelGenerator = require(ReplicatedStorage:WaitForChild("ModelGenerator"))

local Enemy = script.Parent:WaitForChild("Enemy")
local EnemyPathfinding = require(Enemy:WaitForChild("EnemyPathfinding"))
local EnemyRegistry = require(Enemy:WaitForChild("EnemyRegistry"))
local EnemySpawner = require(Enemy:WaitForChild("EnemySpawner"))
local SpawnDirector = require(Enemy:WaitForChild("SpawnDirector"))

local REDRAW_INTERVAL = 0.25
local RING_THICKNESS = 0.15

local show = { detect = false, leash = false, paths = false, labels = false }

local function debugFolder()
	local folder = workspace:FindFirstChild("EnemyDebug")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "EnemyDebug"
		folder.Parent = workspace
	end
	return folder
end

local function speakerRoot(speaker)
	local player = speaker or Players:GetPlayers()[1]
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function nearestController(position)
	local best, bestDistance = nil, math.huge
	for _, controller in pairs(EnemyRegistry.all()) do
		if controller.alive and controller.root.Parent then
			local d = (controller.root.Position - position).Magnitude
			if d < bestDistance then
				best, bestDistance = controller, d
			end
		end
	end
	return best
end

-- ============================================================
-- Spawning
-- ============================================================

-- No onDied and no key: the spawner keys it by its own rig and installs the
-- default teardown, which is exactly what a debug spawn wants. It used to pass
-- both, written out here, and E6 found the same three lines missing from the
-- Splitter's children; the spawner owns them for everybody now.
local function debugSpawn(typeName, position)
	local ground = EnemyPathfinding.groundBelow(position + Vector3.new(0, 2, 0), 14)
	local at = (ground or position) + Vector3.new(0, 3, 0)
	return EnemySpawner.spawn(typeName, CFrame.new(at), { home = at })
end

local function spawnRing(typeNames, center)
	local spawned = 0
	for index, typeName in ipairs(typeNames) do
		local angle = (index - 1) / #typeNames * math.pi * 2
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * 8
		if debugSpawn(typeName, center + offset) then
			spawned = spawned + 1
		end
	end
	return spawned
end

-- ============================================================
-- Visualizers
-- ============================================================

local function ring(folder, position, radius, color)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(RING_THICKNESS, radius * 2, radius * 2)
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Transparency = 0.75
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = folder
end

local function dot(folder, position, color)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(0.8, 0.8, 0.8)
	part.Position = position
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = folder
end

local function label(folder, controller)
	local anchor = Instance.new("Part")
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = controller.root.Position + Vector3.new(0, 4, 0)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Parent = folder

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 160, 0, 24)
	billboard.AlwaysOnTop = true
	billboard.Parent = anchor

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.4
	text.TextScaled = true
	text.Font = Enum.Font.Code
	local targetName = "-"
	local character = controller.target and controller.target.Parent
	if character then
		targetName = character.Name
	end
	text.Text = string.format("%s %s > %s", controller.enemyType, controller.machine:current(), targetName)
	text.Parent = billboard
end

local function anyShown()
	return show.detect or show.leash or show.paths or show.labels
end

local drawing = false
local function ensureDrawLoop()
	if drawing then
		return
	end
	drawing = true
	task.spawn(function()
		while anyShown() do
			local folder = debugFolder()
			folder:ClearAllChildren()
			for _, controller in pairs(EnemyRegistry.all()) do
				if controller.alive and controller.root.Parent then
					if show.detect then
						ring(folder, controller.root.Position, controller.stats.detection, Color3.fromRGB(255, 170, 60))
					end
					if show.leash then
						ring(folder, controller.home, controller.stats.leash, Color3.fromRGB(90, 160, 255))
					end
					if show.paths and controller.path.waypoints then
						for _, waypoint in ipairs(controller.path.waypoints) do
							dot(folder, waypoint.Position, controller.stats.color)
						end
					end
					if show.labels then
						label(folder, controller)
					end
				end
			end
			task.wait(REDRAW_INTERVAL)
		end
		debugFolder():ClearAllChildren()
		drawing = false
	end)
end

-- ============================================================
-- The dispatcher
-- ============================================================

local commands = {}

function commands.models()
	local templates = ModelGenerator.ensureTemplates(ServerStorage)
	return string.format("regenerated %d templates", #templates:GetChildren())
end

function commands.spawn(speaker, typeName, count)
	if not typeName then
		return "usage: spawn <Type> [count]"
	end
	local root = speakerRoot(speaker)
	if not root then
		return "no character to spawn beside"
	end
	local wanted = {}
	for _ = 1, math.clamp(tonumber(count) or 1, 1, 12) do
		table.insert(wanted, typeName)
	end
	return string.format("spawned %d %s", spawnRing(wanted, root.Position), typeName)
end

function commands.wave(speaker, budget)
	local root = speakerRoot(speaker)
	if not root then
		return "no character to spawn beside"
	end
	local rolled = SpawnDirector.rollWave(tonumber(budget) or Config.Enemies.FloorBudget.Base)
	if #rolled == 0 then
		return "budget bought nothing"
	end
	spawnRing(rolled, root.Position)
	return "wave: " .. table.concat(rolled, ", ")
end

function commands.clear()
	local cleared = 0
	for marker, controller in pairs(EnemyRegistry.all()) do
		EnemyRegistry.remove(marker)
		controller:destroy()
		cleared = cleared + 1
	end
	return string.format("cleared %d", cleared)
end

function commands.damage(speaker, amount)
	local root = speakerRoot(speaker)
	local controller = root and nearestController(root.Position)
	if not controller then
		return "nothing near"
	end
	controller:takeDamage(tonumber(amount) or 25, "debug")
	return string.format("%s at %d/%d", controller.enemyType, controller.humanoid.Health, controller.humanoid.MaxHealth)
end

function commands.kill(speaker)
	local root = speakerRoot(speaker)
	local controller = root and nearestController(root.Position)
	if not controller then
		return "nothing near"
	end
	controller:takeDamage(controller.humanoid.Health, "debug")
	return "killed " .. controller.enemyType
end

function commands.ai()
	local frozen = (workspace:GetAttribute("EnemyFreezeUntil") or 0) > os.clock() + 3600
	workspace:SetAttribute("EnemyFreezeUntil", frozen and 0 or math.huge)
	return frozen and "ai on" or "ai off"
end

local function toggle(name)
	commands[name] = function()
		show[name] = not show[name]
		if show[name] then
			ensureDrawLoop()
		end
		return name .. (show[name] and " on" or " off")
	end
end
toggle("detect")
toggle("leash")
toggle("paths")
toggle("labels")

local function dispatch(speaker, command, ...)
	local handler = commands[string.lower(tostring(command or ""))]
	if not handler then
		local names = {}
		for name in pairs(commands) do
			table.insert(names, name)
		end
		table.sort(names)
		return "commands: " .. table.concat(names, ", ")
	end
	local result = handler(speaker, ...)
	print("[EnemyDebug] " .. tostring(result))
	return result
end

local bindable = Instance.new("BindableFunction")
bindable.Name = "EnemyDebugCommand"
bindable.OnInvoke = function(command, ...)
	return dispatch(nil, command, ...)
end
bindable.Parent = script.Parent

Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(message)
		local words = string.split(message, " ")
		if string.lower(words[1]) == "/enemy" then
			dispatch(player, select(2, table.unpack(words)))
		end
	end)
end)
