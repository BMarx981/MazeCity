-- Guard (ModuleScript) -> ServerScriptService.Enemy.Behaviors.Guard
-- Holds a post. Sentry today, Gatekeeper and Warden at E4.
--
-- What makes a Sentry a Sentry is its row, not this file: a leash of 70 where a
-- Drifter has 150, the heaviest hit in the roster and the slowest cooldown to go
-- with it. It is a hazard with a position, so it can be mapped and walked around,
-- and blundering into one is the most expensive contact in the game.
--
-- So the only hook it wants is the one that says it does not wander, and that
-- happens to be the controller's default too. It is written out anyway rather than
-- left as an empty extend, because "a Guard stands at its marker" is a rule
-- somebody should be able to read in Guard.lua instead of having to know what the
-- controller does with an unclaimed idle.
--
-- The brief's Guard is larger than this: a scan rotation while idle, a windup
-- before the swing, and knockback on the hit. None of it is here and that is
-- deliberate. The Sentry that went through a playtest is this one, `knockback` is
-- a row field nothing reads on any type, and inventing three mechanics inside a
-- refactor is how a port stops being checkable. They belong with E4's Warden,
-- which needs a telegraphed heavy hit anyway.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyTypes = require(ReplicatedStorage:WaitForChild("EnemyTypes"))
local BaseBehavior = require(script.Parent:WaitForChild("BaseBehavior"))

local Guard = BaseBehavior.extend({
	onIdle = function(controller)
		controller.machine:transition(EnemyTypes.State.Idle)
		controller:halt()
		return true
	end,
})

return Guard
