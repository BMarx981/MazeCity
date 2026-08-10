-- Blinker (ModuleScript) -> ServerScriptService.Enemy.Behaviors.Blinker
-- Arrives somewhere it was not. It is the one type that ignores the maze, so
-- everything about it is written to keep that from being unfair.
--
-- Three rules, and all three are the fairness:
--
--   It never lands on you. The destination stops minimumPlayerSeparation short of
--   the nearest player, and a candidate closer than that to anybody is thrown away
--   rather than nudged, because a nudged destination is one nobody checked.
--
--   It never lands somewhere you could not stand. Every candidate has to have floor
--   under it and a clear line from where the Blinker is now, which is what stops
--   one appearing inside a wall or halfway down a stairwell shaft.
--
--   It cannot act on arrival. arrivalWarningTime is a Recover state: it is visible,
--   flashing, and harmless for that long, so a blink is a warning rather than a hit.
--
-- It uses the Charger's attack triplet with the beats reordered, which is worth
-- reading as the pattern rather than as a coincidence. There is no windup because
-- the move takes no time; the free beat the player gets is spent on the far end
-- instead of the near one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local EnemyTypes = require(ReplicatedStorage:WaitForChild("EnemyTypes"))

local Players = game:GetService("Players")

local BaseBehavior = require(script.Parent:WaitForChild("BaseBehavior"))
local EnemyCombat = require(script.Parent.Parent:WaitForChild("EnemyCombat"))
local EnemyPathfinding = require(script.Parent.Parent:WaitForChild("EnemyPathfinding"))

local State = EnemyTypes.State

-- How far above the floor a candidate is tested from, and how far down it looks for
-- one. A cell is 25 studs across and a storey is 20.5, so a drop bigger than this
-- would find the floor below through a stairwell hole.
local PROBE_HEIGHT = 6
local PROBE_DROP = 10

local function tooCloseToAnyone(position, separation)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - position).Magnitude < separation then
			return true
		end
	end
	return false
end

-- Walks in from the far end: the furthest point short of the player first, then
-- closer, so it takes the boldest arrival that passes rather than the first one it
-- can find. Returns the floor point to stand on, or nil if none of them is a place
-- a thing may be.
local function pickDestination(controller, target)
	local config = controller.behaviorConfig
	local separation = config.minimumPlayerSeparation or 0
	local from = controller.root.Position
	local toward = Vector3.new(target.Position.X - from.X, 0, target.Position.Z - from.Z)
	if toward.Magnitude < 0.1 then
		return nil
	end
	local direction = toward.Unit
	local reach = toward.Magnitude - separation

	for _, fraction in ipairs({ 1, 0.75, 0.5 }) do
		local distance = reach * fraction
		if distance >= (config.blinkMinDistance or 0) then
			local candidate = from + direction * distance
			local probe = candidate + Vector3.new(0, PROBE_HEIGHT, 0)
			local ground = EnemyPathfinding.groundBelow(probe, PROBE_DROP + PROBE_HEIGHT)
			if
				ground
				and not tooCloseToAnyone(ground, separation)
				and EnemyPathfinding.isClearBetween(from, candidate)
			then
				return ground
			end
		end
	end
	return nil
end

local function blink(controller, destination)
	local config = controller.behaviorConfig
	controller.blinkReadyAt = os.clock() + (config.blinkCooldown or 0)
	controller:halt()
	controller.model:PivotTo(CFrame.new(destination + Vector3.new(0, controller.humanoid.HipHeight, 0)))
	-- The stuck window is measured from a position it was at a moment ago and half a
	-- corridor away, so it has to be dropped or the first tick after a blink reads as
	-- having moved impossibly far and the one after that as not moving at all.
	controller.path:reset()

	local warning = config.arrivalWarningTime or 0
	controller:flash(warning)
	controller:playSound(Config.Sounds.EnemyAlert, Config.Juice.EnemyAlertVolume, 1.7)
	EnemyCombat.markGround(controller, destination, config.minimumPlayerSeparation or 4, warning)
	controller.machine:transition(State.Recover)
end

local Blinker = BaseBehavior.extend({
	update = function(controller)
		if controller.machine:current() ~= State.Recover then
			return false
		end
		if controller.machine:timeInState() < (controller.behaviorConfig.arrivalWarningTime or 0) then
			controller:halt()
			return true
		end
		controller.machine:transition(State.Chase)
		return false
	end,

	onChase = function(controller, target)
		local config = controller.behaviorConfig
		if os.clock() < (controller.blinkReadyAt or 0) then
			return false
		end
		local distance = (target.Position - controller.root.Position).Magnitude
		if distance < (config.blinkMinDistance or 0) or distance > (config.blinkMaxDistance or 0) then
			return false
		end

		local destination = pickDestination(controller, target)
		if not destination then
			return false
		end
		blink(controller, destination)
		return true
	end,
})

return Blinker
