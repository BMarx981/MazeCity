-- WallWalkService (Script) -> ServerScriptService
-- The Wall Walker upgrade. Holding the key puts the player's character in a
-- collision group that does not collide with maze walls, and drains a meter that
-- refills on reaching the next floor.
--
-- Containment is not enforced here. It is a property of which parts generation
-- put in the MazeWall group: interior and boundary maze walls, and nothing else.
-- The facade, the slabs, the stairs and the parapets keep the default group, so
-- a phasing player can cross any wall on their floor, end up in the apron ring
-- between the maze edge and the facade with slab under their feet, and get no
-- further. There is no check in this file that can be forgotten, because there
-- is no check.
--
-- The one thing that does need care is the end of a phase. Going solid while
-- overlapping a wall is how a player gets stuck inside geometry, so the phase
-- holds past empty until they are clear, capped by Config.WallWalk.GraceSeconds
-- because a grid maze's walls all touch at the corners and somebody who never
-- steps out of one could otherwise ride the grace forever.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local MazeGenerator = require(ServerScriptService:WaitForChild("MazeGenerator"))

local WALL_GROUP = MazeGenerator.WALL_GROUP
local WALKER_GROUP = "WallWalker"
local DEFAULT_GROUP = "Default"

-- MazeGenerator registers the wall group at require time and WorldBootstrap
-- requires it before building, so by here it exists. Registered again anyway,
-- idempotently, because "the other script ran first" is not a thing to rely on
-- and CollisionGroupSetCollidable needs both ends to be real.
MazeGenerator.ensureCollisionGroup(WALL_GROUP)
MazeGenerator.ensureCollisionGroup(WALKER_GROUP)
PhysicsService:CollisionGroupSetCollidable(WALL_GROUP, WALKER_GROUP, false)

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

local remote = findOrCreate(ReplicatedStorage, "RemoteEvent", "WallWalkUpdate")
local intents = findOrCreate(ReplicatedStorage, "RemoteEvent", "WallWalkIntent")

-- player -> { fuel, capacity, phasing, graceUntil, floorKey, parts, highlight, added }
local state = {}

local sweepParams = OverlapParams.new()
sweepParams.FilterType = Enum.RaycastFilterType.Exclude

local function capacityFor(player)
	local tier = player:GetAttribute("WallWalkTier") or 0
	if tier <= 0 then
		return 0
	end
	local seconds = Config.Shop.Upgrades.WallWalker.SecondsPerTier
	return seconds[math.min(tier, #seconds)] or 0
end

local function entryFor(player)
	local entry = state[player]
	if not entry then
		entry = { fuel = 0, capacity = 0, phasing = false, graceUntil = 0, floorKey = nil }
		state[player] = entry
	end
	return entry
end

local function push(player, event)
	local entry = state[player]
	if not entry then
		return
	end
	remote:FireClient(player, {
		kind = "state",
		fuel = entry.fuel,
		capacity = entry.capacity,
		phasing = entry.phasing,
		grace = entry.graceUntil > os.clock(),
		event = event,
	})
end

-- ============================================================
-- The phase itself
-- ============================================================

local function setGroup(char, group)
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
end

local function startPhase(player)
	local entry = entryFor(player)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if entry.phasing or not humanoid or humanoid.Health <= 0 then
		return
	end
	if entry.fuel <= 0 or entry.capacity <= 0 then
		push(player, { kind = "empty" })
		return
	end

	entry.phasing = true
	setGroup(char, WALKER_GROUP)

	-- An accessory or a tool added mid-phase arrives in the default group and
	-- would catch on a wall the rest of the character passes through.
	entry.added = char.DescendantAdded:Connect(function(inst)
		if inst:IsA("BasePart") and entry.phasing then
			inst.CollisionGroup = WALKER_GROUP
		end
	end)

	-- Restored against BaseWalkSpeed rather than against whatever it was, so a
	-- Fast Feet purchase or a Speed powerup landing mid-phase is not undone when
	-- the phase ends. Same rule PickupService's boost follows.
	local base = char:GetAttribute("BaseWalkSpeed") or humanoid.WalkSpeed
	humanoid.WalkSpeed = base * Config.WallWalk.WalkSpeedMultiplier

	local shimmer = Instance.new("Highlight")
	shimmer.Name = "WallWalkHighlight"
	shimmer.FillColor = Config.WallWalk.HighlightColor
	shimmer.FillTransparency = Config.WallWalk.HighlightTransparency
	shimmer.OutlineTransparency = 0.1
	shimmer.Parent = char
	entry.highlight = shimmer

	push(player, { kind = "started" })
end

local function endPhase(player, reason)
	local entry = state[player]
	if not entry or not entry.phasing then
		return
	end

	entry.phasing = false
	entry.graceUntil = 0

	if entry.added then
		entry.added:Disconnect()
		entry.added = nil
	end
	if entry.highlight then
		entry.highlight:Destroy()
		entry.highlight = nil
	end

	local char = player.Character
	if char then
		setGroup(char, DEFAULT_GROUP)
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Parent then
			humanoid.WalkSpeed = char:GetAttribute("BaseWalkSpeed") or Config.Shop.BaseWalkSpeed
		end
	end

	push(player, { kind = reason or "stopped" })
end

-- True while any part of the maze is still overlapping the player. Answered by
-- the engine broadphase against a radius, not by a distance test over the city's
-- walls, and read only at the moment a phase wants to end.
local function insideWall(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	sweepParams.FilterDescendantsInstances = { char }
	local near = workspace:GetPartBoundsInRadius(root.Position, Config.WallWalk.ClearanceRadius, sweepParams)
	for _, part in ipairs(near) do
		if part.CollisionGroup == WALL_GROUP then
			return true
		end
	end
	return false
end

-- ============================================================
-- Fuel
-- ============================================================

local function refill(player)
	local entry = entryFor(player)
	entry.capacity = capacityFor(player)
	entry.fuel = entry.capacity
	push(player, { kind = "refilled" })
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	local pushDue = false
	accumulator = accumulator + dt
	if accumulator >= Config.WallWalk.PushSeconds then
		accumulator = 0
		pushDue = true
	end

	for player, entry in pairs(state) do
		if not player.Parent then
			state[player] = nil
		elseif entry.phasing then
			if entry.fuel > 0 then
				entry.fuel = math.max(0, entry.fuel - dt)
				if entry.fuel <= 0 then
					-- Empty is where the grace starts, not where the phase stops.
					entry.graceUntil = now + Config.WallWalk.GraceSeconds
				end
			elseif not insideWall(player) or now >= entry.graceUntil then
				endPhase(player, "empty")
			end

			if pushDue and entry.phasing then
				push(player)
			end
		end
	end
end)

-- ============================================================
-- Intents
-- ============================================================
-- Two kinds and no rate limit worth the name: start on an empty meter is a
-- refusal, stop while stopped is a no-op, and neither allocates. The cost of a
-- player spamming them is a collision group assignment per character part, which
-- is why start is ignored outright while already phasing.

intents.OnServerEvent:Connect(function(player, payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.kind == "start" then
		startPhase(player)
	elseif payload.kind == "stop" then
		-- A manual stop still owes the player the same clearance check an empty
		-- meter gets, or letting go inside a wall is how they get stuck.
		local entry = state[player]
		if entry and entry.phasing then
			if insideWall(player) then
				entry.fuel = 0
				entry.graceUntil = os.clock() + Config.WallWalk.GraceSeconds
			else
				endPhase(player, "stopped")
			end
		end
	end
end)

-- ============================================================
-- Floors
-- ============================================================
-- The meter refills on arriving at a floor, which is what makes a tier a budget
-- per floor rather than per life. Bound here rather than read off MazeProgress
-- because that fires on a floor cleared, and the first floor of a tower is
-- entered without one having been cleared.

local function bindLevelTrigger(part)
	if not part:IsA("BasePart") then
		return
	end
	part.Touched:Connect(function(hit)
		local char = hit:FindFirstAncestorOfClass("Model")
		local player = char and Players:GetPlayerFromCharacter(char)
		if not player then
			return
		end
		local key = string.format(
			"%s:%s:%s",
			tostring(part:GetAttribute("Section")),
			tostring(part:GetAttribute("Building")),
			tostring(part:GetAttribute("Level"))
		)
		local entry = entryFor(player)
		if entry.floorKey ~= key then
			entry.floorKey = key
			refill(player)
		end
	end)
end

for _, part in ipairs(CollectionService:GetTagged("LevelTrigger")) do
	bindLevelTrigger(part)
end
CollectionService:GetInstanceAddedSignal("LevelTrigger"):Connect(bindLevelTrigger)

-- ============================================================
-- Lifecycle
-- ============================================================

local function bindPlayer(player)
	entryFor(player)

	player.CharacterAdded:Connect(function()
		-- The old character is gone with its collision groups, so this only has to
		-- forget it. Dying is also a fresh floor: the respawn is at the floor's
		-- start, and arriving there without a meter would make a death cost two
		-- things instead of one.
		local entry = entryFor(player)
		entry.phasing = false
		entry.graceUntil = 0
		entry.highlight = nil
		if entry.added then
			entry.added:Disconnect()
			entry.added = nil
		end
		entry.floorKey = nil
		task.wait(0.2)
		refill(player)
	end)

	-- The tier arrives with the profile, which lands after the join, so the
	-- capacity has to be re-read rather than sampled once.
	player:GetAttributeChangedSignal("WallWalkTier"):Connect(function()
		local entry = entryFor(player)
		local was = entry.capacity
		entry.capacity = capacityFor(player)
		-- A purchase tops the meter up by what it just bought rather than refilling
		-- it, so buying tier 3 halfway down a floor is not also a free refill.
		entry.fuel = math.min(entry.capacity, entry.fuel + math.max(0, entry.capacity - was))
		push(player, { kind = "tier" })
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end
Players.PlayerAdded:Connect(bindPlayer)

Players.PlayerRemoving:Connect(function(player)
	local entry = state[player]
	if entry and entry.added then
		entry.added:Disconnect()
	end
	state[player] = nil
end)
