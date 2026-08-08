-- Ambusher (ModuleScript) -> ServerScriptService.Enemy.Behaviors.Ambusher
-- Scenery until somebody is close enough, then reveals and commits. The Lurker,
-- and the only type in the roster that cannot be avoided by anyone who has not
-- learned the floor, which is exactly what makes learning it worth something.
--
-- It works by refusing targets rather than by hiding from them. An unrevealed
-- Lurker sees a player perfectly well and declines to have one, which is what
-- keeps the whole thing in this file: no other module has an opinion about
-- targeting, no attribute is written for the controller to check, and the fade is
-- cosmetic.
--
-- Two things it must not do, both learned the hard way. It never fully vanishes,
-- because a hit that lands from nothing is a hit that reads as a bug rather than
-- as an ambush; the fade stops at Config.Juice.EnemyLurkerHiddenTransparency. And
-- it cannot bite while hidden, which EnemyCombat enforces off controller.hidden,
-- so the reveal always comes first even when a player walks straight into one.
--
-- It re-hides only from Idle. Having given up and walked home it is scenery again,
-- which is the second half of the trick: a floor a player crossed once still has
-- something in it the next time they come through.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local EnemyTypes = require(ReplicatedStorage:WaitForChild("EnemyTypes"))

local BaseBehavior = require(script.Parent:WaitForChild("BaseBehavior"))
local EnemyRig = require(script.Parent.Parent:WaitForChild("EnemyRig"))

local Ambusher = BaseBehavior.extend({
	init = function(controller)
		controller.revealed = false
		EnemyRig.setHidden(controller, true)
	end,

	filterTarget = function(controller, target)
		if not controller.revealed then
			local range = controller.behaviorConfig.ambushRange or 0
			local close = target ~= nil
				and (target.Position - controller.root.Position).Magnitude <= range
				and controller:hasLineOfSightTo(target)
			if not close then
				return nil
			end

			controller.revealed = true
			EnemyRig.setHidden(controller, false)
			controller:flash(Config.Juice.EnemyTellSeconds)
			controller:playSound(Config.Sounds.EnemyAlert, Config.Juice.EnemyAlertVolume, 1.25)
			return target
		end

		if not target and controller.machine:current() == EnemyTypes.State.Idle then
			if os.clock() >= (controller.rehideAt or 0) then
				controller.revealed = false
				EnemyRig.setHidden(controller, true)
			end
		end
		return target
	end,

	onTargetLost = function(controller)
		controller.rehideAt = os.clock() + (controller.behaviorConfig.rehideSeconds or 0)
	end,
})

return Ambusher
