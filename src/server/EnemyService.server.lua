-- EnemyService (Script) -> ServerScriptService
-- Bootstrap and registry. It decides which EnemySpawn markers should be holding a
-- rig right now, builds and tears them down, and drives the animation. It does not
-- decide anything an enemy does.
--
-- Where the rest of it lives, because this file used to be all of it:
--
--   ReplicatedStorage.EnemyDefinitions   the rows: what a type is and is worth
--   ReplicatedStorage.ModelGenerator     the rig builder
--   ReplicatedStorage.EnemyTypes         the names, states and roles
--   Enemy/EnemyFactory                   template, runtime stats, the speed cap
--   Enemy/EnemySpawner                   the one way an enemy comes to life
--   Enemy/SpawnDirector                  what a floor holds, inside its budget
--   Enemy/EnemyController                one per rig: the tick and the state
--   Enemy/Behaviors/*                    what each type does with that tick
--   Enemy/EnemyRegistry                  every live controller, keyed by marker
--
-- A marker is permanent, its rig is not. Generation tags 180 markers per section
-- and they live forever; a rig is built when a player comes within
-- Config.Enemies.SpawnRange and torn down past DespawnRange. The old service built
-- all 180 at world build time and gated only the pathfinding, so a two-section
-- city carried 360 idle Humanoid state machines and the server had no frame left to
-- move the handful that mattered.
--
-- What a marker holds is SpawnDirector's answer, since E5: the group of markers
-- sharing a floor shares a budget, and typeFor is the whole of what this file
-- knows about it. nil is a real answer, meaning the roll left that position
-- empty, and it costs nothing against the caps.
--
-- The caps are enforced here and nowhere else, which is why the candidate markers
-- are sorted before any of them is spent. A cap over an unordered sweep of a hash
-- table gives you forty arbitrary enemies out of the hundred in range; sorted, the
-- forty you get are the forty nearest, which is the same forty a player would say
-- were there.
--
-- Two placement rules run inside the spend loop, and deliberately after the
-- caps so their raycasts only fire for markers actually about to spawn: nothing
-- materialises within Config.Enemies.MinSpawnDistance of a player, and nothing
-- materialises in a player's direct line of sight. Both postpone rather than
-- refuse; the marker stays a candidate for the sweep after the player moves on.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))

local Enemy = script.Parent:WaitForChild("Enemy")
local EnemyPathfinding = require(Enemy:WaitForChild("EnemyPathfinding"))
local EnemyRegistry = require(Enemy:WaitForChild("EnemyRegistry"))
local EnemyRig = require(Enemy:WaitForChild("EnemyRig"))
local EnemySafeZones = require(Enemy:WaitForChild("EnemySafeZones"))
local EnemySpawner = require(Enemy:WaitForChild("EnemySpawner"))
local SpawnDirector = require(Enemy:WaitForChild("SpawnDirector"))

-- Every marker in the city, whether or not it currently holds a rig, and the
-- markers whose enemy died and are serving out their respawn delay.
local markers = {}
local deadUntil = {}

-- ============================================================
-- Spawning and despawning
-- ============================================================

local function despawn(marker)
	local controller = EnemyRegistry.remove(marker)
	if controller then
		controller:destroy()
	end
end

local function spawnFromMarker(marker)
	if not marker:IsA("BasePart") or EnemyRegistry.get(marker) then
		return false
	end

	local enemyType = SpawnDirector.typeFor(marker)
	if not enemyType then
		return false
	end
	local section = marker:GetAttribute("Section") or 1
	local building = marker:GetAttribute("Building") or 0
	local level = marker:GetAttribute("Level") or 0

	-- Arming the respawn is this file's business and not the controller's: the
	-- controller knows it died, this knows that a marker is now empty and for how
	-- long. An ordinary walk-away despawn goes through despawn() and never gets here,
	-- so a player who steps off a floor and comes straight back does not find it
	-- empty for the whole delay.
	local controller = EnemySpawner.spawn(enemyType, marker.CFrame, {
		key = marker,
		marker = marker,
		home = marker.Position,
		section = section,
		building = building,
		level = level,
		onDied = function()
			deadUntil[marker] = os.clock() + Config.Enemies.RespawnSeconds
			despawn(marker)
		end,
	})
	return controller ~= nil
end

-- ============================================================
-- Animation
-- ============================================================

RunService.Heartbeat:Connect(function(dt)
	for _, controller in pairs(EnemyRegistry.all()) do
		if controller.alive and controller.root.Parent then
			EnemyRig.animate(controller, dt)
		end
	end
end)

-- ============================================================
-- Markers
-- ============================================================

local function trackMarker(marker)
	if marker:IsA("BasePart") then
		markers[marker] = true
	end
end

for _, marker in ipairs(CollectionService:GetTagged("EnemySpawn")) do
	trackMarker(marker)
end
CollectionService:GetInstanceAddedSignal("EnemySpawn"):Connect(trackMarker)
CollectionService:GetInstanceRemovedSignal("EnemySpawn"):Connect(function(marker)
	markers[marker] = nil
	deadUntil[marker] = nil
	despawn(marker)
end)

-- ============================================================
-- The scan
-- ============================================================

-- One flat sweep rather than a spatial index. A five section city is about 900
-- markers, so this is 1800 magnitude tests a second at four players, which is
-- nothing next to a single Humanoid. If section count ever grows far enough for
-- that to matter, bucket markers by position here; do not put the cost back into
-- keeping the rigs alive.
local function nearestPlayerDistance(positions, pos)
	local best = math.huge
	for _, p in ipairs(positions) do
		local d = (p - pos).Magnitude
		if d < best then
			best = d
		end
	end
	return best
end

-- Whether any player has a clear line to the marker. One raycast per player,
-- and only ever asked about a marker the caps have already agreed to spend on.
--
-- Asked from the player toward the marker and not the other way round, which is
-- not arbitrary: isClearBetween also refuses a destination inside a safe zone, so
-- with the arguments reversed a player standing on a plaza pad answered "no clear
-- line" for every marker around them and enemies materialised in front of them.
-- The marker is the thing whose visibility is in question, so the marker is the
-- `to`.
local function inViewOfAny(pos, positions)
	for _, p in ipairs(positions) do
		if EnemyPathfinding.isClearBetween(p, pos) then
			return true
		end
	end
	return false
end

task.spawn(function()
	local positions = {}
	local candidates = {}

	while true do
		task.wait(Config.Enemies.ScanInterval)
		local now = os.clock()

		table.clear(positions)
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if hrp and humanoid and humanoid.Health > 0 then
				table.insert(positions, hrp.Position)
			end
		end

		table.clear(candidates)
		for marker in pairs(markers) do
			if not marker.Parent then
				markers[marker] = nil
				despawn(marker)
			elseif not EnemyRegistry.get(marker) and now >= (deadUntil[marker] or 0) then
				local distance = nearestPlayerDistance(positions, marker.Position)
				if distance <= Config.Enemies.SpawnRange then
					table.insert(candidates, { marker = marker, distance = distance })
				end
			end
		end

		table.sort(candidates, function(a, b)
			return a.distance < b.distance
		end)
		-- The global cap ends the sweep; a full building only skips its own markers, so
		-- the next candidate in the tower next door still gets its chance.
		for _, candidate in ipairs(candidates) do
			if EnemyRegistry.count() >= Config.Enemies.GlobalCap then
				break
			end
			local marker = candidate.marker
			local section = marker:GetAttribute("Section") or 1
			local building = marker:GetAttribute("Building") or 0
			if
				EnemyRegistry.countInBuilding(section, building) < Config.Enemies.PerBuildingCap
				and candidate.distance >= Config.Enemies.MinSpawnDistance
				and not EnemySafeZones.repels(marker.Position)
				and not inViewOfAny(marker.Position, positions)
			then
				spawnFromMarker(marker)
			end
		end

		-- Despawn is measured from the rig, not the marker, so an enemy that chased
		-- somebody to the far side of the floor is not deleted mid chase. The
		-- director hears about these and not about deaths: a walk-away ends the
		-- visit and releases the floor's composition, a death holds it so the
		-- respawn brings back the enemy the budget already paid for.
		for marker, controller in pairs(EnemyRegistry.all()) do
			local gone = not controller.root.Parent
			if gone or nearestPlayerDistance(positions, controller.root.Position) > Config.Enemies.DespawnRange then
				despawn(marker)
				SpawnDirector.noteDespawned(marker)
			end
		end
	end
end)
