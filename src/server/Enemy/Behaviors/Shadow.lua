-- Shadow (ModuleScript) -> ServerScriptService.Enemy.Behaviors.Shadow
-- Moves only while nobody is looking at it. Watched, it is a statue, and the
-- material change is what says the statue is deliberate rather than stuck.
--
-- That last part is the whole design problem with this type. Every other enemy in
-- the game that stops moving has stopped because something is wrong, so a Shadow
-- that just halts reads as the bug this system was written to fix. The material
-- change is not decoration: it is the difference between "it is playing a game with
-- you" and "it is broken".
--
-- Facing is read off the character's own CFrame on the server. There is no client
-- look-direction remote in this game at all, so there is nothing to validate and
-- nothing to spoof, and the answer is only ever used to make an enemy stiller.
--
-- minimumMoveDistanceWhileUnseen is what stops it stuttering on the threshold. Once
-- it starts moving it covers that much ground before it may be frozen again, so a
-- player flicking their view left and right gets a Shadow that crosses the corridor
-- rather than one that vibrates in place. It is the same idea as the targeting
-- stickiness bonus and it is here for the same reason: a threshold with no
-- hysteresis is a coin flip several times a second.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local EnemyTypes = require(ReplicatedStorage:WaitForChild("EnemyTypes"))

local Players = game:GetService("Players")

local BaseBehavior = require(script.Parent:WaitForChild("BaseBehavior"))
local EnemyTargeting = require(script.Parent.Parent:WaitForChild("EnemyTargeting"))
local EnemyLore = require(script.Parent.Parent:WaitForChild("EnemyLore"))

local State = EnemyTypes.State

-- Only players close enough to make one out count. Beyond the leash it is a shape
-- at the end of a corridor and being looked at in that direction is not the same as
-- being watched.
--
-- Returns the watcher's root part rather than a boolean, which the freeze itself
-- has no use for: the journal wants to know who caught it, and the audit in
-- docs/PETS_PLAN.md recorded this as the one Kept moment that was discrete but
-- did not record its player. It is the same loop and the same cost.
local function watchedBy(controller, threshold)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if hrp and humanoid and EnemyTargeting.isCharacterVisible(character, humanoid) then
			local toEnemy = controller.root.Position - hrp.Position
			if toEnemy.Magnitude <= controller.stats.leash and toEnemy.Magnitude > 0.5 then
				if hrp.CFrame.LookVector:Dot(toEnemy.Unit) > threshold then
					return hrp
				end
			end
		end
	end
	return nil
end

-- Cached against the flag rather than written every tick: it is a property write per
-- part on a rig with a dozen of them, and the state changes seconds apart.
local function setStatue(controller, on)
	if controller.statue == on then
		return
	end
	controller.statue = on
	for _, item in ipairs(controller.skin) do
		if item.part.Parent then
			item.part.Material = on and Config.Juice.EnemyStatueMaterial
				or (controller.materials[item.part] or item.part.Material)
		end
	end
end

local Shadow = BaseBehavior.extend({
	init = function(controller)
		-- Recorded off the rig it was handed rather than assumed to be Neon, because a
		-- hand-made rig from ServerStorage/Enemies is entitled to its own materials and
		-- should get them back.
		controller.materials = {}
		for _, item in ipairs(controller.skin) do
			controller.materials[item.part] = item.part.Material
		end
		controller.statue = false
	end,

	update = function(controller)
		local config = controller.behaviorConfig
		local minimum = config.minimumMoveDistanceWhileUnseen or 0
		local from = controller.unseenFrom
		local covered = from and (controller.root.Position - from).Magnitude or math.huge

		local watcher = covered >= minimum and watchedBy(controller, config.lookDotThreshold or 0.75) or nil
		if watcher then
			controller.unseenFrom = nil
			-- Only on the edge into the statue, not every tick it stays one: setStatue
			-- already caches against the flag and this is the same moment.
			if not controller.statue then
				EnemyLore.moment(controller, "ShadowFrozen", watcher)
			end
			setStatue(controller, true)
			controller.machine:transition(State.Idle)
			controller:halt()
			return true
		end

		if not from then
			controller.unseenFrom = controller.root.Position
		end
		setStatue(controller, false)
		return false
	end,
})

return Shadow
