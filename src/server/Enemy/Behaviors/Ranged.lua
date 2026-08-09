-- Ranged (ModuleScript) -> ServerScriptService.Enemy.Behaviors.Ranged
-- Keeps its distance and throws things. The Spitter, and the only enemy that
-- threatens a player who already has room, which is the whole reason a corridor is
-- not automatically safe once you are out of arm's reach.
--
-- It is written as three bands rather than as a chase with an attack bolted on,
-- because the bands are the type: inside minimumDistance it backs away, out past
-- preferredDistance it closes, and in between it stands and works. Only the last of
-- those is where it wants to be, so a player walking straight at one pushes it
-- backwards down the corridor and a player running away pulls it along, and both
-- are legible without a health bar or an aggro icon.
--
-- attackRange is a row field and this is the only module in the game that reads
-- one: how close a melee hit lands from is a promise the game makes once, in
-- Config.Juice.EnemyTellReach, but how far a thrown thing carries is a property of
-- the thing.
--
-- The aim is locked when the windup starts and never re-taken, exactly as the
-- Charger's line is, and for the same reason: the flash is a promise about where
-- the danger is going to be, and re-aiming during it makes the promise a lie.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local EnemyTypes = require(ReplicatedStorage:WaitForChild("EnemyTypes"))

local BaseBehavior = require(script.Parent:WaitForChild("BaseBehavior"))
local EnemyCombat = require(script.Parent.Parent:WaitForChild("EnemyCombat"))

local State = EnemyTypes.State

local function flatTo(from, to)
	return Vector3.new(to.X - from.X, 0, to.Z - from.Z)
end

local function face(controller, position)
	local flat = flatTo(controller.root.Position, position)
	if flat.Magnitude > 0.1 then
		controller.root.CFrame = CFrame.lookAt(controller.root.Position, controller.root.Position + flat.Unit)
	end
end

local function beginSpit(controller, target)
	-- windingUp is the same flag melee sets, so a Touched event landing inside the
	-- windup cannot also start a swing. lastAttack is what attackCooldown is measured
	-- from, and setting it here rather than on release is what makes the cadence the
	-- row's rather than the row's plus a windup.
	controller.windingUp = true
	controller.lastAttack = os.clock()
	controller.spitAt = target.Position
	controller.machine:transition(State.AttackWindup)
	controller:halt()
	controller:flash(Config.Juice.EnemyTellSeconds)
	controller:playSound(Config.Sounds.EnemyAlert, Config.Juice.EnemyAlertVolume, 1.45)
	face(controller, target.Position)
end

local function release(controller)
	local config = controller.behaviorConfig
	controller.windingUp = false
	local aim = controller.spitAt and (controller.spitAt - controller.root.Position)
	controller.spitAt = nil
	if not aim then
		return
	end
	EnemyCombat.launchProjectile(controller, aim, {
		speed = config.projectileSpeed,
		lifetime = config.projectileLifetime,
		radius = config.projectileRadius,
		damage = controller.stats.damage,
		slowMultiplier = config.slowMultiplier,
		slowDuration = config.slowDuration,
	})
end

local Ranged = BaseBehavior.extend({
	update = function(controller)
		if controller.machine:current() ~= State.AttackWindup then
			return false
		end
		if controller.machine:timeInState() < Config.Juice.EnemyTellSeconds then
			controller:halt()
			return true
		end
		release(controller)
		controller.machine:transition(State.Chase)
		return true
	end,

	onChase = function(controller, target)
		local config = controller.behaviorConfig
		local flat = flatTo(controller.root.Position, target.Position)
		local distance = flat.Magnitude

		-- Too close to work. It gives ground rather than switching to melee, which is
		-- what stops the one enemy with reach from also being an enemy with hands.
		if distance < (config.minimumDistance or 0) then
			controller.machine:transition(State.Chase)
			controller.humanoid.WalkSpeed = controller:chaseSpeed(target)
			local retreat = (config.preferredDistance or distance) - distance
			controller.path:direct(controller.root.Position - flat.Unit * retreat)
			return true
		end

		if
			distance <= controller.stats.attackRange
			and EnemyCombat.canAttack(controller)
			and controller:hasLineOfSightTo(target)
		then
			beginSpit(controller, target)
			return true
		end

		-- In the band it wants, with nothing loaded: stand still and watch, so the
		-- player can see it is waiting rather than think it has lost interest.
		if distance <= (config.preferredDistance or 0) then
			controller.machine:transition(State.Chase)
			controller:halt()
			face(controller, target.Position)
			return true
		end

		return false
	end,

	onStopped = function(controller)
		EnemyCombat.clearRuntime(controller)
	end,
})

return Ranged
