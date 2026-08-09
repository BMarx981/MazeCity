-- Burrower (ModuleScript) -> ServerScriptService.Enemy.Behaviors.Burrower
-- Goes under the floor and comes up somewhere else. The Blinker's problem with a
-- travel time, and it is the travel time that makes it fair: a mound slides along
-- the floor for the whole of burrowDuration, so a player can watch the thing coming
-- and be somewhere else when it arrives.
--
-- It uses the Charger's attack triplet with all three beats spent:
--
--   AttackWindup  the dive, shown before it happens
--   Attack        underground, invisible, harmless, tracked by the mound
--   Recover       out and warning, still harmless, for emergenceWarning
--
-- The rig is anchored while it travels rather than made non-collidable. A root that
-- cannot collide is a root that falls, and a Humanoid that has fallen out of the
-- building is a goHome teleport at best. Anchored, it goes exactly where it is put
-- and nothing can push it on the way.
--
-- It cannot touch anybody until the warning ends, which is EnemyCombat's rule about
-- controller.hidden rather than a check here. That is the one thing this type must
-- get right: a thing arriving from below that hits on arrival is a hit nobody could
-- have avoided.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local EnemyTypes = require(ReplicatedStorage:WaitForChild("EnemyTypes"))

local BaseBehavior = require(script.Parent:WaitForChild("BaseBehavior"))
local EnemyCombat = require(script.Parent.Parent:WaitForChild("EnemyCombat"))
local EnemyPathfinding = require(script.Parent.Parent:WaitForChild("EnemyPathfinding"))
local EnemyRig = require(script.Parent.Parent:WaitForChild("EnemyRig"))

local State = EnemyTypes.State

-- How long the dive is shown for. The melee tell, because a dive is the same
-- promise as a swing: something is about to happen where this thing is standing.
local DIVE_TELL = Config.Juice.EnemyTellSeconds
-- How far under its own floor it travels, and how wide the mound reads.
local DEPTH = 5
local MOUND_RADIUS = 2.6
-- Candidate directions tried around the player, in order, before it gives up and
-- chases on foot for another cooldown.
local ARC_TRIES = 6
local PROBE_HEIGHT = 6
local PROBE_DROP = 10

local function pickEmergence(controller, target)
	local config = controller.behaviorConfig
	local minimum = config.emergenceDistanceMin or 0
	local span = (config.emergenceDistanceMax or minimum) - minimum
	local origin = target.Position

	for index = 1, ARC_TRIES do
		local angle = (index - 1) / ARC_TRIES * math.pi * 2
		local distance = minimum + span * ((index % 2 == 0) and 0.8 or 0.35)
		local candidate = origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local ground =
			EnemyPathfinding.groundBelow(candidate + Vector3.new(0, PROBE_HEIGHT, 0), PROBE_HEIGHT + PROBE_DROP)
		-- Clear from the player rather than from the Burrower: it is underground and
		-- every wall is between the two of them, so the question that matters is whether
		-- the place it surfaces is a place on the player's side of the maze.
		if ground and EnemyPathfinding.isClearBetween(origin, candidate) then
			return ground
		end
	end
	return nil
end

local function submerge(controller)
	controller.root.Anchored = true
	EnemyRig.setInvisible(controller, true)
	controller.burrowFrom = controller.root.Position
	controller.burrowMound = EnemyCombat.markGround(
		controller,
		controller.burrowFrom,
		MOUND_RADIUS,
		controller.behaviorConfig.burrowDuration or 0
	)
	controller.machine:transition(State.Attack)
end

local function surface(controller)
	local warning = controller.behaviorConfig.emergenceWarning or 0
	controller.model:PivotTo(CFrame.new(controller.burrowTo + Vector3.new(0, controller.humanoid.HipHeight, 0)))
	controller.root.Anchored = false
	EnemyRig.setInvisible(controller, false)
	-- Visible but still hidden as far as EnemyCombat is concerned: it can be seen and
	-- walked away from for the whole of the warning, and it cannot bite.
	controller.hidden = true
	controller.path:reset()
	controller:flash(warning)
	controller:playSound(Config.Sounds.EnemyCharge, Config.Juice.EnemyChargeVolume, 0.75)
	controller.machine:transition(State.Recover)
end

local Burrower = BaseBehavior.extend({
	update = function(controller)
		local config = controller.behaviorConfig
		local state = controller.machine:current()

		if state == State.AttackWindup then
			if controller.machine:timeInState() < DIVE_TELL then
				controller:halt()
				return true
			end
			submerge(controller)
			return true
		end

		if state == State.Attack then
			local duration = config.burrowDuration or 0
			local elapsed = controller.machine:timeInState()
			if elapsed >= duration then
				surface(controller)
				return true
			end
			-- The rig rides under the mound rather than behind it, so a player who tracks
			-- the mound is tracking the enemy and not a decoy.
			local alpha = duration > 0 and (elapsed / duration) or 1
			local at = controller.burrowFrom:Lerp(controller.burrowTo, alpha)
			controller.model:PivotTo(CFrame.new(at - Vector3.new(0, DEPTH, 0)))
			if controller.burrowMound and controller.burrowMound.part.Parent then
				controller.burrowMound.part.Position = at + Vector3.new(0, Config.Juice.EnemyTrapHeight, 0)
			end
			return true
		end

		if state == State.Recover then
			if controller.machine:timeInState() < (config.emergenceWarning or 0) then
				controller:halt()
				return true
			end
			controller.hidden = false
			controller.machine:transition(State.Chase)
		end

		return false
	end,

	onChase = function(controller, target)
		local config = controller.behaviorConfig
		if os.clock() < (controller.burrowReadyAt or 0) then
			return false
		end
		-- Already on top of them, so there is nothing to arrive from. It uses its hands.
		local distance = (target.Position - controller.root.Position).Magnitude
		if distance < (config.emergenceDistanceMin or 0) then
			return false
		end

		local destination = pickEmergence(controller, target)
		if not destination then
			return false
		end

		controller.burrowReadyAt = os.clock() + (config.burrowCooldown or 0)
		controller.burrowTo = destination
		controller.machine:transition(State.AttackWindup)
		controller:halt()
		controller:flash(DIVE_TELL)
		controller:playSound(Config.Sounds.EnemyCharge, Config.Juice.EnemyChargeVolume, 0.45)
		return true
	end,

	-- Despawning underground would leave an anchored invisible rig and a mound, and
	-- the rig is destroyed by the controller either way. The anchor is put back
	-- regardless so that a rig handed anywhere else is a rig with physics.
	onStopped = function(controller)
		controller.root.Anchored = false
		EnemyCombat.clearRuntime(controller)
	end,
})

return Burrower
