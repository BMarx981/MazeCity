-- Chaser (ModuleScript) -> ServerScriptService.Enemy.Behaviors.Chaser
-- Walks at the player and keeps walking. The baseline, and the module the most
-- types ride: Drifter and Stalker today, Sprinter and Brute at E4.
--
-- It overrides exactly one hook, which is the point of splitting stats from
-- behavior. Everything that separates a Drifter from a Stalker is on the rows: a
-- Stalker has an unwatchedSpeed, so the controller slows it while you look at it
-- and lets it close when you turn away, and a Drifter has idleWander, so it mills
-- about its marker instead of standing at it. Neither is a branch here.
--
-- Wandering is a Patrol rather than an Idle, because a type that moves at its post
-- and a type that holds it are different things to read off the state attribute
-- during a Play session, and Idle should mean idle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyTypes = require(ReplicatedStorage:WaitForChild("EnemyTypes"))
local BaseBehavior = require(script.Parent:WaitForChild("BaseBehavior"))

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

local Chaser = BaseBehavior.extend({
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
