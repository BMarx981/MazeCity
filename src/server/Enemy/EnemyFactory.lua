-- EnemyFactory (ModuleScript) -> ServerScriptService.Enemy.EnemyFactory
-- Turns a type name into a live rig: picks a template, applies the runtime
-- stats, and parents it into workspace.LiveEnemies.
--
-- Template priority is settled and does not change: a hand-made rig at
-- ServerStorage/Enemies/<TypeName> beats a generated template beats building one
-- on the spot. An artist can replace any single type without touching code and
-- without the other nineteen changing, and the game plays from a cold rojo build
-- with no Studio-side setup at all.
--
-- Runtime stats are a copy, and every read of a stat has to come from that copy.
-- The difficulty multipliers and the speed cap are applied once, here, so that
-- nothing downstream has to remember to apply them; a behavior that reaches into
-- EnemyDefinitions for a walkSpeed gets the design value and runs 11% fast.
-- Nothing writes back into the row: a multiplier applied in place is applied
-- again to the next enemy of that type, and again to the one after that.
--
-- It does not register anything and does not start anything. It hands back a rig,
-- its joint data and its stats; EnemyService wraps those in an EnemyController and
-- puts that in EnemyRegistry. Keeping the two apart is what lets the bestiary
-- portraits and a debug spawn build a rig without one of them coming to life.

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local EnemyDefinitions = require(ReplicatedStorage:WaitForChild("EnemyDefinitions"))
local ModelGenerator = require(ReplicatedStorage:WaitForChild("ModelGenerator"))
local MazeGenerator = require(script.Parent.Parent:WaitForChild("MazeGenerator"))

local EnemyFactory = {}

-- Enemies do not collide with each other. Three of them meeting in a corridor
-- used to wedge into a shoving match none of them could path out of, which was
-- most of what "they just stand there" turned out to be. They still collide with
-- everything else, so nothing about containment changes: the maze walls are in
-- their own group and this one is not made non-collidable with it.
EnemyFactory.CollisionGroup = "Enemy"

MazeGenerator.ensureCollisionGroup(EnemyFactory.CollisionGroup)
PhysicsService:CollisionGroupSetCollidable(EnemyFactory.CollisionGroup, EnemyFactory.CollisionGroup, false)
-- The one pair MazeGenerator.ENEMY_BLOCK_GROUP collides with, and the whole
-- reason it exists: phantom walls and stairwell mouths are solid to an enemy and
-- to nothing else. True is already the engine default, and it is written out
-- because a default nobody stated is a default somebody will change: this line
-- failing is a Charger walking up a staircase.
PhysicsService:CollisionGroupSetCollidable(EnemyFactory.CollisionGroup, MazeGenerator.ENEMY_BLOCK_GROUP, true)

-- Every sustained speed on a row, and the one burst speed that is exempt from the
-- cap. Named rather than inferred from the field name, because "anything ending
-- in Speed" would silently start clamping a multiplier the day somebody adds
-- sprintSpeedMultiplier to a row instead of to its behaviorConfig.
local SUSTAINED_SPEEDS = { "walkSpeed", "unwatchedSpeed" }
local BURST_SPEEDS = { "chargeSpeed" }

-- Always a table on a runtime copy, so a behaviour can read
-- profile.behaviorConfig.whatever without a nil check at every site. Frozen
-- because it is shared by every row that has no block of its own.
local NO_BEHAVIOR_CONFIG = table.freeze({})

local liveFolder = workspace:FindFirstChild("LiveEnemies")
if not liveFolder then
	liveFolder = Instance.new("Folder")
	liveFolder.Name = "LiveEnemies"
	liveFolder.Parent = workspace
end
EnemyFactory.liveFolder = liveFolder

local templates = ModelGenerator.ensureTemplates(ServerStorage)
local handMade = ServerStorage:FindFirstChild("Enemies")

-- The ceiling any sustained speed is held to, exported because a behavior that
-- computes a speed rather than reading one (a sprint multiplier, a pack bonus)
-- has to hold its own product to the same promise: nothing chases a player at
-- their own walking speed.
function EnemyFactory.clampSpeed(speed)
	return math.min(speed, Config.Enemies.MaxChaseSpeed)
end

-- A fresh table per spawn. Fields the multipliers do not touch are copied across
-- unchanged, so a stat added to a row arrives here without this function being
-- edited; behaviorConfig is carried by reference because the row is frozen.
function EnemyFactory.runtimeStats(typeName, level)
	local row = EnemyDefinitions.get(typeName)
	local difficulty = Config.Enemies.Difficulty
	-- table.clone drops the frozen flag, which is what makes this writable while
	-- the row it came from stays read-only.
	local stats = table.clone(row)

	for _, key in ipairs(SUSTAINED_SPEEDS) do
		if row[key] then
			stats[key] = EnemyFactory.clampSpeed(row[key] * difficulty.SpeedMultiplier)
		end
	end
	-- Not clamped, and deliberately: a charge is a straight line the player was
	-- shown in advance, and sidestepping it is the whole interaction. It still
	-- scales with the difficulty pass, so the set stays in proportion.
	for _, key in ipairs(BURST_SPEEDS) do
		if row[key] then
			stats[key] = row[key] * difficulty.SpeedMultiplier
		end
	end

	stats.damage = row.damage * difficulty.DamageMultiplier
	stats.detection = row.detection * difficulty.DetectionMultiplier
	stats.attackCooldown = row.attackCooldown * difficulty.CooldownMultiplier
	-- The per-type base scales with the climb. Nothing in the game damages an
	-- enemy, so this is a number nothing reads; it is computed correctly anyway so
	-- that adding a weapon is adding a weapon.
	stats.health = (row.health + (level or 0) * Config.Enemies.HealthPerLevel) * difficulty.HealthMultiplier
	stats.behaviorConfig = row.behaviorConfig or NO_BEHAVIOR_CONFIG
	stats.enemyType = typeName

	return stats
end

-- A rig, and the joint data to animate it with, or nil for a hand-made rig that
-- brings its own idea of how it moves.
function EnemyFactory.template(typeName)
	if handMade then
		local rig = handMade:FindFirstChild(typeName)
		if rig and rig:IsA("Model") then
			local clone = rig:Clone()
			clone:SetAttribute("EnemyType", typeName)
			return clone, ModelGenerator.rigOf(clone)
		end
	end

	local generated = templates:FindFirstChild(typeName)
	if generated then
		local clone = generated:Clone()
		return clone, ModelGenerator.rigOf(clone)
	end

	-- Only reachable for a type that was added to the roster after startup, which
	-- is a live-edit in Studio rather than anything a player can cause.
	local model = ModelGenerator.build(typeName)
	return model, ModelGenerator.rigOf(model)
end

function EnemyFactory.create(typeName, spawnCFrame, options)
	options = options or {}
	local stats = EnemyFactory.runtimeStats(typeName, options.level)
	local model, rig = EnemyFactory.template(typeName)

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not humanoid or not root then
		warn("EnemyFactory: rig for " .. tostring(typeName) .. " has no Humanoid or HumanoidRootPart")
		model:Destroy()
		return nil
	end

	humanoid.MaxHealth = stats.health
	humanoid.Health = stats.health
	humanoid.WalkSpeed = stats.walkSpeed
	-- Nothing damages an enemy, so a health bar over one is a promise the game
	-- does not keep.
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	-- A maze floor is flat and every one of these is a way for a rig to end up on
	-- its side in a corridor with no way back onto its feet.
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)

	-- The group is applied here rather than in ModelGenerator because a group
	-- registered on the server does not exist on a client, and the same builder
	-- draws the bestiary portraits.
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.CanCollide then
			part.CollisionGroup = EnemyFactory.CollisionGroup
		end
	end

	model:PivotTo(spawnCFrame)
	model.Parent = liveFolder
	if options.section then
		model:SetAttribute("Section", options.section)
	end
	if options.level then
		model:SetAttribute("Level", options.level)
	end

	return model, rig, stats
end

function EnemyFactory.destroy(model)
	if model and model.Parent then
		model:Destroy()
	end
end

function EnemyFactory.definitionOf(model)
	local typeName = model and model:GetAttribute("EnemyType")
	if not typeName then
		return nil
	end
	return EnemyDefinitions.types[typeName]
end

return EnemyFactory
