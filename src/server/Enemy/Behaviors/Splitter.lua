-- Splitter (ModuleScript) -> ServerScriptService.Enemy.Behaviors.Splitter
-- Two of it, eventually. Everything it does while alive is a Chaser; the whole type
-- is one hook.
--
-- It is dormant in practice and will stay that way until something can damage an
-- enemy, because the split is on death and death is reachable only through a debug
-- command. That is not a reason to leave it unwritten: the lifecycle is real, and
-- wiring it now means the day a weapon arrives it is a weapon and not also a
-- spawning system.
--
-- The children are the reason EnemySpawner exists. An enemy that no marker placed
-- has no marker to be keyed by, so it is keyed by its own rig: it is never
-- respawned, it does not hold a marker's slot, and it goes for good when the player
-- walks far enough away. All three are right for something that only exists because
-- something else died.
--
-- They also arrive outside the spawn scan, so they are the one thing in the city
-- that can push the live count past Config.Enemies.GlobalCap. Two children of a
-- thing that just died is a deliberate exception rather than a hole: refusing to
-- split at the cap would make the mechanic silently stop working in exactly the
-- crowded room where a player would notice.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyDefinitions = require(ReplicatedStorage:WaitForChild("EnemyDefinitions"))

local BaseBehavior = require(script.Parent:WaitForChild("BaseBehavior"))
local EnemySpawner = require(script.Parent.Parent:WaitForChild("EnemySpawner"))

-- Far enough apart that the two do not spawn inside one another and immediately
-- shove, close enough to read as one thing having come apart.
local SPREAD = 3.5

local Splitter = BaseBehavior.extend({
	onDeath = function(controller)
		local config = controller.behaviorConfig
		-- The guard that makes the child row safe to point at this module. A child that
		-- could split is a room that fills up until the server gives out.
		if config.canSplit == false then
			return
		end

		local childType = config.childType
		local count = config.childCount or 0
		if not childType or count <= 0 or not EnemyDefinitions.types[childType] then
			return
		end

		local origin = controller.root.Position
		for index = 1, count do
			local angle = (index - 1) / count * math.pi * 2
			local at = origin + Vector3.new(math.cos(angle) * SPREAD, 0, math.sin(angle) * SPREAD)
			EnemySpawner.spawn(childType, CFrame.new(at), {
				-- Its parent's marker, so the children inherit the patch of maze it owned
				-- and the leash that goes with it rather than each claiming a new one
				-- wherever the fight happened to end.
				home = controller.home,
				section = controller.section,
				building = controller.building,
				level = controller.level,
			})
		end
	end,
})

return Splitter
