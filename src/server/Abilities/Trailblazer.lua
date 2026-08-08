-- Trailblazer (ModuleScript) -> ServerScriptService.Abilities.Trailblazer
-- Light the route from here to the stairs, for a few seconds, for a chunk of the
-- charge.
--
-- The whole server side of this is a number. TimerGui already decodes the
-- current floor's LevelTrigger.Route into markers for the Reveal orb, and the
-- route itself is an attribute generation stamped on the trigger, so there is
-- nothing here to apply and nothing to undo: `cast` returns the seconds and
-- AbilityService carries them to the client on the event.
--
-- That is also why it is the one Cast in the set. A route is read in a glance
-- and then walked, so a held key would be spent staring at the floor; and an
-- ability with no server effect has nothing to hold open anyway.
--
-- The client is trusted with exactly one thing, which is how long to draw for,
-- and the worst a modified client does with it is show itself a route it could
-- already have read off a replicated attribute. Nothing about the maze, the
-- timer or the coins is decided here.

local BaseAbility = require(script.Parent:WaitForChild("BaseAbility"))

local Trailblazer = BaseAbility.extend({
	cast = function(_player, _char, tier, def)
		local seconds = def.RevealSecondsPerTier[math.min(tier, #def.RevealSecondsPerTier)]
		return true, { seconds = seconds }
	end,
})

return Trailblazer
