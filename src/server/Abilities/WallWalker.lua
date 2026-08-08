-- WallWalker (ModuleScript) -> ServerScriptService.Abilities.WallWalker
-- Phase through maze walls while the key is held. Was WallWalkService, which
-- owned its own meter, its own remotes and its own LevelTrigger binding; all
-- three moved to AbilityService when the shop started selling more than one
-- thing to hold a key for, and what is left here is the phase itself.
--
-- Named for the shop key rather than for the verb, because AbilityService finds
-- a module by looking up the key: Config.Abilities.Order says "WallWalker" and
-- the file has to answer to that. Config.WallWalk keeps the shorter name.
--
-- Containment is not enforced in this file. It is a property of which parts
-- generation put in the MazeWall group: interior and boundary maze walls, and
-- nothing else. The facade, the slabs, the stairs and the parapets keep the
-- default group, so a phasing player can cross any wall on their floor, end up
-- in the apron ring between the maze edge and the facade with slab under their
-- feet, and get no further. There is no check here that can be forgotten,
-- because there is no check.
--
-- The one thing that does need care is the end of a phase, and it is the reason
-- `blocked` exists on the interface at all. Going solid while overlapping a wall
-- is how a player gets stuck inside geometry, so the service holds the phase
-- past an empty charge until they are clear, capped by
-- Config.Abilities.GraceSeconds because a grid maze's walls all touch at the
-- corners and somebody who never steps out of one could otherwise ride the
-- grace forever.

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local MazeGenerator = require(ServerScriptService:WaitForChild("MazeGenerator"))
local WalkSpeed = require(ServerScriptService:WaitForChild("WalkSpeedResolver"))
local BaseAbility = require(script.Parent:WaitForChild("BaseAbility"))

local WALL_GROUP = MazeGenerator.WALL_GROUP
local BLOCK_GROUP = MazeGenerator.ENEMY_BLOCK_GROUP
local WALKER_GROUP = "WallWalker"
local DEFAULT_GROUP = "Default"

-- MazeGenerator registers the wall group at require time and WorldBootstrap
-- requires it before building, so by here it exists. Registered again anyway,
-- idempotently, because "the other script ran first" is not a thing to rely on
-- and CollisionGroupSetCollidable needs both ends to be real.
MazeGenerator.ensureCollisionGroup(WALL_GROUP)
MazeGenerator.ensureCollisionGroup(WALKER_GROUP)
MazeGenerator.ensureCollisionGroup(BLOCK_GROUP)
PhysicsService:CollisionGroupSetCollidable(WALL_GROUP, WALKER_GROUP, false)
-- The enemy barrier is already absent to a Default character, and a phasing one
-- has to be excused separately or the upgrade would be the one state in which a
-- phantom wall and a stairwell mouth become solid.
PhysicsService:CollisionGroupSetCollidable(BLOCK_GROUP, WALKER_GROUP, false)

-- player -> { added = RBXScriptConnection, highlight = Highlight }. Only ever
-- holds an entry while a phase is running, so leaving mid-phase is the same
-- teardown as letting go of the key.
local live = {}

local sweepParams = OverlapParams.new()
sweepParams.FilterType = Enum.RaycastFilterType.Exclude

local function setGroup(char, group)
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
end

local WallWalk = BaseAbility.extend({
	start = function(player, char)
		setGroup(char, WALKER_GROUP)

		local entry = {}
		-- An accessory or a tool added mid-phase arrives in the default group and
		-- would catch on a wall the rest of the character passes through.
		entry.added = char.DescendantAdded:Connect(function(inst)
			if inst:IsA("BasePart") and live[player] == entry then
				inst.CollisionGroup = WALKER_GROUP
			end
		end)

		-- A named factor in WalkSpeedResolver, so the squeeze multiplies with a
		-- Speed powerup or a sprint rather than replacing whichever landed first,
		-- and ending the phase removes only this term. Sprinting through a wall is
		-- therefore 1.6 * 0.75, faster than walking but still paying the squeeze.
		WalkSpeed.set(char, "WallWalk", Config.WallWalk.WalkSpeedMultiplier)

		local shimmer = Instance.new("Highlight")
		shimmer.Name = "WallWalkHighlight"
		shimmer.FillColor = Config.WallWalk.HighlightColor
		shimmer.FillTransparency = Config.WallWalk.HighlightTransparency
		shimmer.OutlineTransparency = 0.1
		shimmer.Parent = char
		entry.highlight = shimmer

		live[player] = entry
		return true
	end,

	stop = function(player, char)
		local entry = live[player]
		live[player] = nil
		if entry then
			if entry.added then
				entry.added:Disconnect()
			end
			if entry.highlight then
				entry.highlight:Destroy()
			end
		end

		-- Guarded because stop also runs for a character that has already died and
		-- been replaced, where the old parts are off the DataModel and the new ones
		-- were never in the group to begin with.
		if char and char.Parent then
			setGroup(char, DEFAULT_GROUP)
		end
		WalkSpeed.clear(char, "WallWalk")
	end,

	-- True while any maze wall still overlaps the player. Answered by the engine
	-- broadphase against a radius, not by a distance test over the city's walls,
	-- and read only at the moment the phase wants to end.
	blocked = function(_player, char)
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
	end,
})

return WallWalk
