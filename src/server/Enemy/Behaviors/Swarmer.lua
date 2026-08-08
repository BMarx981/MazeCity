-- Swarmer (ModuleScript) -> ServerScriptService.Enemy.Behaviors.Swarmer
-- Alone it is nothing. One that spots the player wakes every other Swarmer within
-- packRadius on the same floor, so a bad room produces a crowd.
--
-- The call reaches into other controllers, which is the only place in the system
-- one enemy writes another's state, and it writes three fields rather than one for
-- a reason found by watching it fail. Setting lastSeen alone had the alerted
-- Swarmer clear the position on its very next tick without ever walking to it: the
-- search branch is what consumes lastSeen and it is gated on searchUntil. The
-- widened leash is the third, and it is what lets an alerted one pick the player
-- up for itself on the way over instead of arriving at an empty corridor.
--
-- The leash is re-asserted every tick rather than set once at the call, because
-- targeting reads it fresh and a multiplier that expires has to expire somewhere.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyTypes = require(ReplicatedStorage:WaitForChild("EnemyTypes"))
local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))

local BaseBehavior = require(script.Parent:WaitForChild("BaseBehavior"))
local EnemyRegistry = require(script.Parent.Parent:WaitForChild("EnemyRegistry"))

local Swarmer = BaseBehavior.extend({
	update = function(controller)
		local alertUntil = controller.alertUntil
		if alertUntil and os.clock() < alertUntil then
			controller.leashMultiplier = controller.behaviorConfig.alertLeashMultiplier or 1
		else
			controller.leashMultiplier = 1
		end
		return false
	end,

	onTargetAcquired = function(controller, target)
		local config = controller.behaviorConfig
		local radius = config.packRadius or 0
		local deadline = os.clock() + (config.alertSeconds or 0)

		for _, other in pairs(EnemyRegistry.all()) do
			if other ~= controller and other.alive and other.stats.behavior == EnemyTypes.Behavior.Swarmer then
				local sameFloor = math.abs(other.homeY - controller.homeY) < Config.Enemies.FloorBand
				if sameFloor and (other.home - controller.home).Magnitude <= radius then
					other.alertUntil = deadline
					other.lastSeen = target.Position
					other.searchUntil = deadline
				end
			end
		end
	end,
})

return Swarmer
