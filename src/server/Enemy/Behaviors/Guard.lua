-- Guard (ModuleScript) -> ServerScriptService.Enemy.Behaviors.Guard
-- Holds a post. Sentry, Watcher and Gatekeeper.
--
-- What makes a Sentry a Sentry is its row, not this file: a leash of 70 where a
-- Drifter has 150, the heaviest hit in the roster and the slowest cooldown to go
-- with it. It is a hazard with a position, so it can be mapped and walked around,
-- and blundering into one is the most expensive contact in the game.
--
-- The Gatekeeper is the same again with no code at all. Its short leash is a row
-- field and its hurry back to its post is returnSpeed, another row field, because a
-- second sustained speed has to go through EnemyFactory's clamp exactly as the
-- first one does. A multiplier in this file would have reached the humanoid without
-- it.
--
-- The Watcher is the one that adds something, and it is the brief's scan rotation
-- finally arriving: a Guard with a scanArc turns on the spot instead of standing
-- still, and one that spots somebody tells the floor rather than doing anything
-- about it itself. Both are gated on config the other two rows do not carry, so a
-- Sentry is exactly the Sentry that went through a playtest.
--
-- The other half of the brief's Guard, a windup before the swing and knockback on
-- the hit, is not here and belongs to the types that asked for it: the Brute swings
-- slowly through Chaser and the Warden shoves through its own module.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyTypes = require(ReplicatedStorage:WaitForChild("EnemyTypes"))
local BaseBehavior = require(script.Parent:WaitForChild("BaseBehavior"))
local EnemyAlert = require(script.Parent.Parent:WaitForChild("EnemyAlert"))

-- Captured once rather than read every tick, because the scan itself writes the
-- root's facing: reading it back would sweep the arc's own arc and the Watcher
-- would spin.
local function scanBase(controller)
	if not controller.scanBase then
		local look = controller.root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		controller.scanBase = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
	end
	return controller.scanBase
end

local Guard = BaseBehavior.extend({
	onIdle = function(controller)
		local config = controller.behaviorConfig
		if not config.scanArc then
			controller.machine:transition(EnemyTypes.State.Idle)
			controller:halt()
			return true
		end

		-- Turning on the spot is a Patrol and not an Idle, on the same reading Chaser's
		-- wander uses: Idle should mean a thing that is doing nothing.
		controller.machine:transition(EnemyTypes.State.Patrol)
		controller:halt()

		local base = scanBase(controller)
		local period = config.scanPeriod or 4
		local angle = math.sin(os.clock() * math.pi * 2 / period) * math.rad((config.scanArc or 0) / 2)
		local cos, sin = math.cos(angle), math.sin(angle)
		local facing = Vector3.new(base.X * cos - base.Z * sin, 0, base.X * sin + base.Z * cos)
		controller.root.CFrame = CFrame.lookAt(controller.root.Position, controller.root.Position + facing)
		return true
	end,

	onTargetAcquired = function(controller, target)
		local config = controller.behaviorConfig
		if not config.alertRadius then
			return
		end
		EnemyAlert.broadcast(controller, target.Position, {
			radius = config.alertRadius,
			seconds = config.alertSeconds or 0,
			sameBuilding = true,
		})
	end,
})

return Guard
