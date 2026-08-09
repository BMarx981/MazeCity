-- Warden (ModuleScript) -> ServerScriptService.Enemy.Behaviors.Warden
-- The elite. Everything it does is telegraphed and everything it does hurts, and
-- there is never more than one of them in a building.
--
-- Three things at once, which is what makes it the elite rather than a big Drifter:
-- it hits, it shoves everything around it, and it tells the rest of the floor where
-- you are the moment it sees you. None of the three is new machinery. The swing is
-- EnemyCombat's melee with the row's knockback spent, the shockwave is
-- EnemyCombat's, and the alert is EnemyAlert's, which is the same call a Watcher and
-- a Shrieker make.
--
-- The shockwave is the one move in the game that cannot be sidestepped, so it is the
-- one with the longest telegraph: a full second of flash while it stands still, and
-- it only starts inside shockwaveRadius, so backing out of the ring during the
-- windup is the counter. It also respects line of sight from the middle, which means
-- a corner is cover.
--
-- The enrage is wired and unreachable. Nothing damages an enemy, so the health
-- threshold is never crossed; it is here so that the day a weapon exists the Warden
-- is already the fight it was written to be, and it spends controller.speedMultiplier
-- rather than writing a WalkSpeed so the clamp still holds when it does.
--
-- perBuilding is not enforced here. It is a property of what a floor is allowed to
-- contain, which is E5's spawn director, and a type that enforced its own rarity
-- would be a type the director could not reason about.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local EnemyTypes = require(ReplicatedStorage:WaitForChild("EnemyTypes"))

local BaseBehavior = require(script.Parent:WaitForChild("BaseBehavior"))
local EnemyAlert = require(script.Parent.Parent:WaitForChild("EnemyAlert"))
local EnemyCombat = require(script.Parent.Parent:WaitForChild("EnemyCombat"))

local State = EnemyTypes.State

local function land(controller)
	local config = controller.behaviorConfig
	controller.windingUp = false
	controller:playSound(Config.Sounds.EnemySlam, Config.Juice.EnemyChargeVolume, 0.5)
	EnemyCombat.shockwave(controller, {
		radius = config.shockwaveRadius or 0,
		damage = controller.stats.damage,
		knockback = controller.stats.knockback,
	})
end

local Warden = BaseBehavior.extend({
	update = function(controller)
		local config = controller.behaviorConfig

		local humanoid = controller.humanoid
		local threshold = config.enrageHealthPercent
		if threshold and humanoid.MaxHealth > 0 and humanoid.Health / humanoid.MaxHealth <= threshold then
			controller.speedMultiplier = config.enrageSpeedMultiplier or 1
		else
			controller.speedMultiplier = 1
		end

		if controller.machine:current() ~= State.AttackWindup then
			return false
		end
		if controller.machine:timeInState() < (config.shockwaveWindup or 0) then
			controller:halt()
			return true
		end
		land(controller)
		controller.machine:transition(State.Chase)
		return true
	end,

	onTargetAcquired = function(controller, target)
		local config = controller.behaviorConfig
		EnemyAlert.broadcast(controller, target.Position, {
			radius = config.alertRadius or 0,
			seconds = config.alertSeconds or 0,
			sameBuilding = true,
		})
	end,

	onChase = function(controller, target)
		local config = controller.behaviorConfig
		if os.clock() < (controller.shockwaveReadyAt or 0) or not EnemyCombat.canAttack(controller) then
			return false
		end
		if (target.Position - controller.root.Position).Magnitude > (config.shockwaveRadius or 0) then
			return false
		end

		controller.shockwaveReadyAt = os.clock() + (config.shockwaveCooldown or 0)
		controller.windingUp = true
		controller.lastAttack = os.clock()
		controller.machine:transition(State.AttackWindup)
		controller:halt()
		controller:flash(config.shockwaveWindup or 0)
		controller:playSound(Config.Sounds.EnemyCharge, Config.Juice.EnemyChargeVolume, 0.4)
		return true
	end,

	-- The swing, so the row's knockback is spent on the one melee heavy enough to
	-- deserve it. The tell is the standard one: this is the ordinary hit, and the
	-- shockwave is the move worth a longer warning.
	tryAttack = function(controller, character)
		EnemyCombat.tryMelee(controller, character, { knockback = controller.stats.knockback })
		return true
	end,

	onStopped = function(controller)
		EnemyCombat.clearRuntime(controller)
	end,
})

return Warden
