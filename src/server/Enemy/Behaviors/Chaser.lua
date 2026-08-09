-- Chaser (ModuleScript) -> ServerScriptService.Enemy.Behaviors.Chaser
-- Walks at the player and keeps walking. The baseline, and the module the most
-- types ride: Drifter, Stalker, Sprinter, Brute and a Splitter's children.
--
-- Everything that separates one of them from another is on the rows, which is the
-- point of splitting stats from behavior. A Stalker has an unwatchedSpeed, so the
-- controller slows it while you look at it and lets it close when you turn away. A
-- Drifter has idleWander, so it mills about its marker instead of standing at it.
-- A Sprinter has a sprint block and a Brute has a swing block. None of them is a
-- branch on a type name, and adding a sixth is a row rather than an edit here.
--
-- Wandering is a Patrol rather than an Idle, because a type that moves at its post
-- and a type that holds it are different things to read off the state attribute
-- during a Play session, and Idle should mean idle.
--
-- The two config-gated blocks are worth reading as a pair, because they are the
-- same shape: each is a burst the row describes, each names a multiplier or a
-- windup rather than writing the humanoid, and each is inert on a row that does not
-- ask for it. The speed goes through controller.speedMultiplier so that
-- EnemyFactory's clamp still holds, and the swing goes through EnemyCombat so that
-- the four validations a hit needs are still made in one place.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyTypes = require(ReplicatedStorage:WaitForChild("EnemyTypes"))
local BaseBehavior = require(script.Parent:WaitForChild("BaseBehavior"))
local EnemyCombat = require(script.Parent.Parent:WaitForChild("EnemyCombat"))

-- Spawn markers sit at cell centres and CELL is 25, so a wander this tight cannot
-- cross a wall and needs no pathfinding to stay honest. EnemyController's
-- RETURN_RADIUS has to stay at least this much past its HOME_RADIUS or a wanderer
-- that reached the edge of its own wander reads as needing to come home.
local WANDER_RADIUS = 8
local WANDER_MIN_SECONDS = 2.5
local WANDER_MAX_SECONDS = 5.5
-- Slow enough that a wandering enemy is legibly not chasing anybody, which is the
-- only thing the speed has to communicate.
local WANDER_SPEED_FRACTION = 0.45

-- The Sprinter, and nothing else in the roster has one. It runs down a clock, has
-- to stop and breathe, and then may go again, so outrunning it is a matter of
-- holding a line for three seconds rather than of being faster than it.
--
-- The sprint is started off the target the controller picked last tick, since
-- update runs before selection. That is one tick of delay, an eighth of a second,
-- and reaching forward for this tick's target would mean duplicating the whole of
-- EnemyTargeting.pick to save it.
local function stepSprint(controller, config)
	local now = os.clock()
	if controller.exhaustedUntil and now < controller.exhaustedUntil then
		controller.speedMultiplier = config.exhaustedSpeedMultiplier or 1
		return
	end
	if controller.sprintUntil then
		if now < controller.sprintUntil then
			controller.speedMultiplier = config.sprintSpeedMultiplier or 1
			return
		end
		controller.sprintUntil = nil
		controller.exhaustedUntil = now + (config.exhaustDuration or 0)
		controller.speedMultiplier = config.exhaustedSpeedMultiplier or 1
		return
	end

	controller.speedMultiplier = 1
	if controller.target then
		controller.sprintUntil = now + (config.sprintDuration or 0)
		controller.speedMultiplier = config.sprintSpeedMultiplier or 1
	end
end

local Chaser = BaseBehavior.extend({
	update = function(controller)
		local config = controller.behaviorConfig

		-- A Brute that has started a swing is committed to where it is standing. It
		-- claims the tick outright rather than merely halting, so nothing re-aims it
		-- and the sidestep the long telegraph is for actually works.
		if controller.swingLockUntil and os.clock() < controller.swingLockUntil then
			controller:halt()
			return true
		end

		if config.sprintSpeedMultiplier then
			stepSprint(controller, config)
		end
		return false
	end,

	-- Suppresses the controller's melee whenever the row asks for its own swing, and
	-- unconditionally: a Brute whose swing is on cooldown must not fall back to the
	-- short tell everything else uses, which would be the hardest hit in the game
	-- arriving with the shortest warning.
	tryAttack = function(controller, character)
		local config = controller.behaviorConfig
		local windup = config.swingWindup
		if not windup then
			return false
		end
		if EnemyCombat.tryMelee(controller, character, { tell = windup, knockback = controller.stats.knockback }) then
			controller.swingLockUntil = os.clock() + (config.turnLockDuring or 0)
		end
		return true
	end,

	onIdle = function(controller)
		if not controller.behaviorConfig.idleWander then
			return false
		end

		local now = os.clock()
		if not controller.wanderGoal or now >= (controller.wanderAt or 0) then
			local angle = math.random() * math.pi * 2
			local radius = math.random() * WANDER_RADIUS
			controller.wanderGoal = controller.home + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			controller.wanderAt = now + WANDER_MIN_SECONDS + math.random() * (WANDER_MAX_SECONDS - WANDER_MIN_SECONDS)
		end

		controller.machine:transition(EnemyTypes.State.Patrol)
		controller.humanoid.WalkSpeed = controller.stats.walkSpeed * WANDER_SPEED_FRACTION
		controller.path:direct(controller.wanderGoal)
		return true
	end,
})

return Chaser
