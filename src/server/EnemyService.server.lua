-- EnemyService (Script) -> ServerScriptService
-- Spawns one enemy per EnemySpawn marker. Enemy type comes from the marker's
-- EnemyType attribute (set by building style) unless the section overrides it.
--
-- Drop your own rigs in ServerStorage/Enemies/<TypeName>. If a rig is missing
-- a coloured placeholder is used so the level is still playable.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))

local enemyFolder = ServerStorage:FindFirstChild("Enemies")

local liveFolder = workspace:FindFirstChild("LiveEnemies")
if not liveFolder then
	liveFolder = Instance.new("Folder")
	liveFolder.Name = "LiveEnemies"
	liveFolder.Parent = workspace
end

local function weld(a, b)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

local function makePlaceholder(enemyType)
	local profile = Config.getProfile(enemyType)
	local model = Instance.new("Model")
	model.Name = enemyType

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Color = profile.color
	root.Material = Enum.Material.SmoothPlastic
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.4, 1.4, 1.4)
	head.Shape = Enum.PartType.Ball
	head.Color = profile.color:Lerp(Color3.new(0, 0, 0), 0.35)
	head.Material = Enum.Material.Neon
	head.CFrame = root.CFrame * CFrame.new(0, 1.7, 0)
	head.Parent = model
	weld(root, head)

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.HipHeight = 1.4
	humanoid.Parent = model

	model.PrimaryPart = root
	return model
end

local function templateFor(enemyType)
	if enemyFolder then
		local t = enemyFolder:FindFirstChild(enemyType)
		if t and t:IsA("Model") then
			return t:Clone()
		end
	end
	return makePlaceholder(enemyType)
end

local function nearestTarget(root, leash)
	local best, bestDist = nil, leash
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 then
			-- only chase within the same floor band
			if math.abs(hrp.Position.Y - root.Position.Y) < 16 then
				local d = (hrp.Position - root.Position).Magnitude
				if d < bestDist then
					best, bestDist = hrp, d
				end
			end
		end
	end
	return best
end

local function driveEnemy(model, humanoid, root, profile, marker)
	local lastAttack = 0

	root.Touched:Connect(function(hit)
		local char = hit:FindFirstAncestorOfClass("Model")
		local targetHum = char and char:FindFirstChildOfClass("Humanoid")
		if not targetHum or not Players:GetPlayerFromCharacter(char) then return end
		if os.clock() - lastAttack < profile.attackCooldown then return end
		lastAttack = os.clock()
		targetHum:TakeDamage(profile.damage)
	end)

	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = false,
		})

		while model.Parent and humanoid.Health > 0 do
			local target = nearestTarget(root, profile.leash)
			if not target then
				task.wait(1)
			else
				local ok = pcall(function()
					path:ComputeAsync(root.Position, target.Position)
				end)

				if ok and path.Status == Enum.PathStatus.Success then
					local waypoints = path:GetWaypoints()
					for i = 2, math.min(#waypoints, 6) do
						if not model.Parent or humanoid.Health <= 0 then return end
						humanoid:MoveTo(waypoints[i].Position)
						humanoid.MoveToFinished:Wait()
					end
				else
					humanoid:MoveTo(target.Position)
					task.wait(0.4)
				end
				task.wait(0.15)
			end
		end
	end)

	humanoid.Died:Connect(function()
		task.delay(3, function()
			model:Destroy()
		end)
		task.delay(Config.EnemyRespawnSeconds, function()
			if marker.Parent then
				-- rebuilt by the spawn loop below
				marker:SetAttribute("NeedsRespawn", true)
			end
		end)
	end)
end

local function spawnFromMarker(marker)
	if not marker:IsA("BasePart") then return end

	local section = marker:GetAttribute("Section") or 1
	local level = marker:GetAttribute("Level") or 0
	local enemyType = Config.resolveEnemyType(section, marker:GetAttribute("EnemyType"))
	local profile = Config.getProfile(enemyType)

	local model = templateFor(enemyType)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not humanoid or not root then
		warn("EnemyService: rig for " .. enemyType .. " has no Humanoid or HumanoidRootPart")
		model:Destroy()
		return
	end

	humanoid.MaxHealth = Config.EnemyHealthBase + level * Config.EnemyHealthPerLevel
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = profile.walkSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject

	model:PivotTo(marker.CFrame)
	model.Parent = liveFolder
	model:SetAttribute("Section", section)
	model:SetAttribute("Level", level)

	marker:SetAttribute("NeedsRespawn", false)
	driveEnemy(model, humanoid, root, profile, marker)
end

for _, marker in ipairs(CollectionService:GetTagged("EnemySpawn")) do
	spawnFromMarker(marker)
end
CollectionService:GetInstanceAddedSignal("EnemySpawn"):Connect(spawnFromMarker)

task.spawn(function()
	while true do
		task.wait(5)
		for _, marker in ipairs(CollectionService:GetTagged("EnemySpawn")) do
			if marker:GetAttribute("NeedsRespawn") then
				spawnFromMarker(marker)
			end
		end
	end
end)
