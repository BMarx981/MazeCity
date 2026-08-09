-- Trapper (ModuleScript) -> ServerScriptService.Enemy.Behaviors.Trapper
-- Leaves things behind rather than doing anything itself. The floor is what it
-- attacks with, and the type is legible the moment a player sees one of its snares:
-- a coloured disc in a corridor is a sentence about where the thing that made it
-- has been.
--
-- It drops them where it stands and never at the player, which is the whole of what
-- makes them fair. A snare placed under somebody is a hit with no warning; a snare
-- placed behind a Trapper is a corridor that is worse to come back down, and coming
-- back down a corridor is what a maze makes you do.
--
-- Dropping one does not claim the tick. It keeps walking through the same chase the
-- controller would have run anyway, so a Trapper reads as a chaser that litters
-- rather than as a thing that stops to work.
--
-- The snares themselves are EnemyCombat's, and so is destroying them: they take a
-- player's health, so their validation lives with every other hit in the game. All
-- this file owns is when and where.

local BaseBehavior = require(script.Parent:WaitForChild("BaseBehavior"))
local EnemyCombat = require(script.Parent.Parent:WaitForChild("EnemyCombat"))
local EnemyPathfinding = require(script.Parent.Parent:WaitForChild("EnemyPathfinding"))

local Players = game:GetService("Players")

-- How far under the rig it looks for floor to place on. The rig hovers, so the
-- answer is never zero, and a placement that finds nothing is a Trapper standing
-- over a stairwell hole.
local PROBE_DROP = 12

local function anyoneStandingOn(position, radius)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - position).Magnitude <= radius then
			return true
		end
	end
	return false
end

local Trapper = BaseBehavior.extend({
	init = function(controller)
		controller.traps = {}
	end,

	update = function(controller)
		-- Pruned by asking the parts rather than by keeping a second set of deadlines:
		-- a snare that has been walked into or has expired has already destroyed itself
		-- through EnemyCombat, and its handle is the honest place to read that from.
		local live = {}
		for _, handle in ipairs(controller.traps) do
			if handle.part and handle.part.Parent then
				table.insert(live, handle)
			end
		end
		controller.traps = live
		return false
	end,

	onChase = function(controller)
		local config = controller.behaviorConfig
		local now = os.clock()
		if now < (controller.trapReadyAt or 0) then
			return false
		end
		if #controller.traps >= (config.maxTraps or 0) then
			return false
		end

		local radius = config.trapTriggerRadius or 4
		local ground = EnemyPathfinding.groundBelow(controller.root.Position, PROBE_DROP)
		if not ground or anyoneStandingOn(ground, radius) then
			return false
		end

		controller.trapReadyAt = now + (config.trapCooldown or 0)
		table.insert(
			controller.traps,
			EnemyCombat.placeTrap(controller, ground, {
				radius = radius,
				lifetime = config.trapLifetime,
				damage = controller.stats.damage,
				slowMultiplier = config.slowMultiplier,
				slowDuration = config.slowDuration,
			})
		)
		return false
	end,

	onStopped = function(controller)
		EnemyCombat.clearRuntime(controller)
	end,
})

return Trapper
