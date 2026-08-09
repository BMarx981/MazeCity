-- Swarmer (ModuleScript) -> ServerScriptService.Enemy.Behaviors.Swarmer
-- Alone it is nothing. One that spots the player wakes every other Swarmer within
-- packRadius on the same floor, so a bad room produces a crowd.
--
-- The call goes through EnemyAlert, which is where the three fields it writes and
-- the reasoning behind each of them now live: this was the only caller until E4
-- gave a Watcher, a Shrieker and a Warden the same thing to say. Restricting it to
-- other Swarmers is the whole difference between a pack and an alarm.
--
-- The widened leash is the half that stays here, because only this type reads
-- alertUntil. It is re-asserted every tick rather than set once at the call,
-- because targeting reads the leash fresh and a multiplier that expires has to
-- expire somewhere.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyTypes = require(ReplicatedStorage:WaitForChild("EnemyTypes"))

local BaseBehavior = require(script.Parent:WaitForChild("BaseBehavior"))
local EnemyAlert = require(script.Parent.Parent:WaitForChild("EnemyAlert"))

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
		EnemyAlert.broadcast(controller, target.Position, {
			radius = config.packRadius or 0,
			seconds = config.alertSeconds or 0,
			behavior = EnemyTypes.Behavior.Swarmer,
		})
	end,
})

return Swarmer
