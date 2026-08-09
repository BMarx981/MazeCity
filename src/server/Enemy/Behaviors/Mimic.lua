-- Mimic (ModuleScript) -> ServerScriptService.Enemy.Behaviors.Mimic
-- Sits still wearing a prop until somebody walks up to it. The Ambusher's trick
-- taken one step further: a Lurker is a shape you did not notice, a Mimic is a
-- shape you noticed and dismissed.
--
-- It refuses targets rather than hiding from them, which is the Lurker's mechanism
-- and is why both types fit in one small file each: an undisguised Mimic sees a
-- player perfectly well and declines to have one. Nothing else in the system has an
-- opinion about it, and EnemyCombat already refuses a bite from anything with
-- controller.hidden set, so walking into a crate cannot take health off you before
-- it has stopped being a crate.
--
-- Which prop it wears is chosen once, at spawn, from the intersection of the row's
-- allowlist and the props its rig was actually built with. Two lists rather than
-- one because they answer different questions: the recipe in `look` is what the
-- model generator can draw, and behaviorConfig.disguises is what this type is
-- allowed to be. A prop in one and not the other is skipped rather than guessed at,
-- so the failure is a Mimic that looks like a Mimic and not an invisible enemy.
--
-- It does not re-hide. A Lurker that has given up becomes scenery again because a
-- floor you crossed once should still have something in it; a Mimic that has been
-- opened is a trick that has been spent, and putting the lid back on would teach a
-- player to distrust every prop in the city forever.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local ModelGenerator = require(ReplicatedStorage:WaitForChild("ModelGenerator"))

local BaseBehavior = require(script.Parent:WaitForChild("BaseBehavior"))
local EnemyRig = require(script.Parent.Parent:WaitForChild("EnemyRig"))

-- Both halves of the wardrobe at once: the shade goes away and one prop appears, or
-- the reverse. Written as one function so the two can never disagree about which of
-- them is on screen.
local function wear(controller, prop)
	for part in pairs(controller.disguiseParts) do
		if part.Parent then
			part.Transparency = (part == prop) and 0 or 1
		end
	end
	-- The props are in controller.skin like everything else, so they have to be
	-- excluded from the shade's visibility in both directions: without that, revealing
	-- would put every prop back to the transparency it was authored with and the crate
	-- would reappear on top of the thing that came out of it.
	EnemyRig.setInvisible(controller, prop ~= nil, controller.disguiseParts)
end

local Mimic = BaseBehavior.extend({
	init = function(controller, config)
		local byName = ModelGenerator.disguisesOf(controller.model)
		controller.revealed = false
		-- Every prop the rig carries, as a set of parts rather than the name map it
		-- arrives as, because every read after this one is "is this part a prop" while
		-- walking the skin. All of them, not just the allowed ones: a prop the rig
		-- built and the row does not allow still has to be turned off, or the Mimic
		-- wears two.
		controller.disguiseParts = {}
		for _, part in pairs(byName) do
			controller.disguiseParts[part] = true
		end

		local allowed = {}
		for _, name in ipairs(config.disguises or {}) do
			if byName[name] then
				table.insert(allowed, byName[name])
			end
		end
		if #allowed == 0 then
			-- Nothing it may wear, so it is an ordinary ambusher with a very short range.
			-- Not a warning: a hand-made rig from ServerStorage is entitled to have no
			-- props, and this is what that looks like rather than an error.
			controller.revealed = true
			wear(controller, nil)
			return
		end
		-- Runtime randomness, deliberately not the world seed, on the same reasoning
		-- PickupService rolls a powerup on touch: the same crate in the same corner
		-- every time is a crate that gets memorised once and never looked at again.
		wear(controller, allowed[math.random(#allowed)])
	end,

	filterTarget = function(controller, target)
		if controller.revealed then
			return target
		end
		local range = controller.behaviorConfig.revealRange or 0
		if not target or (target.Position - controller.root.Position).Magnitude > range then
			return nil
		end

		controller.revealed = true
		wear(controller, nil)
		controller:flash(controller.behaviorConfig.revealDuration or Config.Juice.EnemyTellSeconds)
		controller:playSound(Config.Sounds.EnemyAlert, Config.Juice.EnemyAlertVolume, 0.9)
		return target
	end,
})

return Mimic
