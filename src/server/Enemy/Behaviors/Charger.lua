-- Charger (ModuleScript) -> ServerScriptService.Enemy.Behaviors.Charger
-- Slow until it has a clear straight line, then telegraphs and sprints down it,
-- overshoots, and has to recover. The only enemy that outruns a player, and only
-- along a line they were shown in advance.
--
-- The direction is locked when the windup ends and never re-aimed. Re-aiming
-- mid-charge would make the telegraph a lie and the sidestep pointless, which is
-- the whole of the interaction this type exists for. Hitting a wall ends the charge
-- early and that is the recovery beat: a sidestep leaves it eating the corner it
-- was aimed down.
--
-- It is the one type that uses the attack triplet of states, and reading them in
-- order is the design: AttackWindup is the flash, Attack is the locked line,
-- Recover is the beat afterwards where the player gets away for free.
--
-- The windup used to be a task.wait inside the think loop. It is a deadline on
-- AttackWindup now, because a parked thread meant a Freeze powerup landing during
-- a windup did not stop the charge until after it had already started, and a
-- powerup that visibly fails to stop the one enemy it most needs to stop is worse
-- than one that does nothing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local EnemyTypes = require(ReplicatedStorage:WaitForChild("EnemyTypes"))

local BaseBehavior = require(script.Parent:WaitForChild("BaseBehavior"))

local State = EnemyTypes.State

-- How far past its aim point it keeps asking to go. Far enough that it never
-- arrives and slows down inside its own charge, and it is the charge duration that
-- ends the move rather than the distance.
local OVERRUN = 24

local function flatTo(from, to)
	return Vector3.new(to.X - from.X, 0, to.Z - from.Z)
end

local function canCharge(controller, target)
	local config = controller.behaviorConfig
	if os.clock() < (controller.chargeReadyAt or 0) then
		return false
	end
	local flat = flatTo(controller.root.Position, target.Position)
	-- Too close to be worth telegraphing, and a rush that starts inside the
	-- player's own reach is one they cannot step out of.
	if flat.Magnitude < (config.chargeMinRange or 0) or flat.Magnitude > (config.chargeRange or 0) then
		return false
	end
	return controller:hasLineOfSightTo(target)
end

local function beginWindup(controller, target)
	local config = controller.behaviorConfig
	local aim = flatTo(controller.root.Position, target.Position)
	if aim.Magnitude < 0.1 then
		return false
	end

	controller.chargeReadyAt = os.clock() + (config.chargeCooldown or 0)
	controller.chargeAim = aim.Unit
	controller.machine:transition(State.AttackWindup)
	controller:halt()
	controller:flash(config.chargeWindup or 0)
	controller:playSound(Config.Sounds.EnemyCharge, Config.Juice.EnemyChargeVolume, 0.55)
	-- Faced now rather than when the line locks, so the shape at the end of the
	-- corridor is pointing at the player for the whole of the warning.
	controller.root.CFrame = CFrame.lookAt(controller.root.Position, controller.root.Position + controller.chargeAim)
	return true
end

local function stepCharge(controller)
	local config = controller.behaviorConfig
	local now = os.clock()
	-- The grace before the stall test is there because it is not moving yet on the
	-- first tick of the rush.
	local speed = controller.root.AssemblyLinearVelocity.Magnitude
	local stalled = speed < (config.chargeStallSpeed or 0) and now - controller.chargeFrom > 0.35

	if now >= controller.chargeUntil or stalled then
		controller.machine:transition(State.Recover)
		controller:halt()
		return
	end
	controller.path:direct(controller.root.Position + controller.chargeDir * OVERRUN)
end

local Charger = BaseBehavior.extend({
	update = function(controller)
		local config = controller.behaviorConfig
		local state = controller.machine:current()

		if state == State.AttackWindup then
			if controller.machine:timeInState() < (config.chargeWindup or 0) then
				return true
			end
			controller.chargeDir = controller.chargeAim
			controller.chargeFrom = os.clock()
			controller.chargeUntil = controller.chargeFrom + (config.chargeSeconds or 0)
			controller.humanoid.WalkSpeed = controller.stats.chargeSpeed
			controller.machine:transition(State.Attack)
			return true
		end

		if state == State.Attack then
			stepCharge(controller)
			if controller.path:isStuck() then
				controller:goHome()
			end
			return true
		end

		if state == State.Recover then
			if controller.machine:timeInState() < (config.chargeRecover or 0) then
				controller:halt()
				return true
			end
			controller.machine:transition(State.Chase)
		end

		return false
	end,

	onChase = function(controller, target)
		if not canCharge(controller, target) then
			return false
		end
		return beginWindup(controller, target)
	end,
})

return Charger
