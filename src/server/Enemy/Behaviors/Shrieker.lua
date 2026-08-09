-- Shrieker (ModuleScript) -> ServerScriptService.Enemy.Behaviors.Shrieker
-- Barely fights. What it does is tell the floor where you are, and take away the
-- one answer a player has to being told.
--
-- The shriek does two things off one windup and one duration, deliberately: an
-- alert to everything nearby, and a Revealed status on the player for as long as
-- the alert lasts. One event, one number, so a player who hears it once knows
-- exactly how long they are in trouble for. Revealed is the only thing in the game
-- that beats the Ghost powerup or the Cloak ability, and it is short, telegraphed
-- and attached to a thing standing in front of you that can be walked away from.
--
-- The alert is filtered to the same building and floor band, which is EnemyAlert's
-- doing rather than this file's. A radius in a maze is not a neighbourhood, and a
-- shriek heard through a slab is six enemies upstairs walking into a wall.
--
-- It uses the melee cooldown as its cadence rather than a knob of its own. The row
-- gives it the longest attackCooldown in the roster at 3.5 seconds, which is the
-- shriek's cooldown by any other name.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local EnemyTypes = require(ReplicatedStorage:WaitForChild("EnemyTypes"))

local BaseBehavior = require(script.Parent:WaitForChild("BaseBehavior"))
local EnemyAlert = require(script.Parent.Parent:WaitForChild("EnemyAlert"))
local EnemyCombat = require(script.Parent.Parent:WaitForChild("EnemyCombat"))
local EnemyStatusService = require(script.Parent.Parent:WaitForChild("EnemyStatusService"))

local State = EnemyTypes.State

local function shriek(controller)
	local config = controller.behaviorConfig
	controller.windingUp = false

	local target = controller.target
	local at = target and target.Position or controller.lastSeen
	if not at then
		return
	end

	local seconds = config.revealDuration or 0
	controller:playSound(Config.Sounds.EnemyShriek, Config.Juice.EnemyAlertVolume, 0.55)
	EnemyAlert.broadcast(controller, at, {
		radius = config.alertRadius or 0,
		seconds = seconds,
		sameBuilding = true,
	})

	local character = target and target.Parent
	if character then
		EnemyStatusService.apply(character, "Revealed", seconds)
	end
end

local Shrieker = BaseBehavior.extend({
	update = function(controller)
		if controller.machine:current() ~= State.AttackWindup then
			return false
		end
		if controller.machine:timeInState() < (controller.behaviorConfig.shriekWindup or 0) then
			controller:halt()
			return true
		end
		shriek(controller)
		controller.machine:transition(State.Chase)
		return true
	end,

	onChase = function(controller, target)
		if not EnemyCombat.canAttack(controller) or not controller:hasLineOfSightTo(target) then
			return false
		end
		local windup = controller.behaviorConfig.shriekWindup or 0
		controller.windingUp = true
		controller.lastAttack = os.clock()
		controller.machine:transition(State.AttackWindup)
		controller:halt()
		controller:flash(windup)
		return true
	end,
})

return Shrieker
