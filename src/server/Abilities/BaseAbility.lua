-- BaseAbility (ModuleScript) -> ServerScriptService.Abilities.BaseAbility
-- The interface every ability module implements, as a working set of no-ops.
--
-- An ability is a table of hooks over AbilityService, not a service of its own.
-- The service owns the one thing all three share and none of them should have to
-- remember: the charge. It picks the selection, spends the charge at the rate
-- the row states, refuses a start on an empty bar, ends a Hold when the bar runs
-- out, holds past empty while the ability says stopping is unsafe, and drops
-- everything on a respawn. A module writes only what makes it different, which
-- for the Cloak is two lines and an attribute.
--
-- The split is the same one the enemy tree draws between EnemyController and a
-- Behavior, and for the same reason: the freeze deadline and the floor band are
-- written once in the controller because a module that only meant to change how
-- something walks cannot be expected to remember them.
--
-- Which hooks a module implements follows from its row's Mode:
--
--   Hold  start, stop, and optionally blocked. The service drains while it runs.
--   Cast  cast, and nothing else. The service spends ChargeCostPerTier once.
--
-- An unknown key is an error at require time rather than a hook nobody calls.
-- `onStart` for `start` is the shape of that mistake and it is invisible
-- otherwise: the module looks written, the hook never fires, and the key does
-- nothing at all.

local BaseAbility = {}

-- Begin a Hold. The charge is already known to be above MinimumToStart. Return
-- false to refuse (no character, nothing to act on); the service pushes a
-- refusal to the client and spends nothing.
function BaseAbility.start(_player, _char, _tier, _def)
	return true
end

-- End a Hold. Always paired with a start that returned true, and always called
-- exactly once: on the charge emptying, on the key coming up, on a death, and on
-- the player leaving. Undoing has to be safe on a character already gone, which
-- is why the character is passed rather than read back off the player.
function BaseAbility.stop(_player, _char, _reason) end

-- True while it is not safe to stop. The service holds the ability running past
-- an empty charge for as long as this says so, capped by
-- Config.Abilities.GraceSeconds. Only the Wall Walker has anything to say here.
function BaseAbility.blocked(_player, _char)
	return false
end

-- Fire a Cast. Return false to refuse and spend nothing. A second return value
-- is passed through to the client on the event, which is how Trailblazer tells
-- TimerGui how long to keep the route lit.
function BaseAbility.cast(_player, _char, _tier, _def)
	return true
end

-- A concrete ability writes only what makes it different. A flat copy rather
-- than an __index chain, so every hook is present on every ability and the
-- service can call them unconditionally instead of testing four fields for nil.
function BaseAbility.extend(overrides)
	local ability = {}
	for key, value in pairs(BaseAbility) do
		if key ~= "extend" then
			ability[key] = value
		end
	end
	for key, value in pairs(overrides or {}) do
		if ability[key] == nil then
			error(string.format("BaseAbility.extend: %q is not an ability hook", tostring(key)))
		end
		ability[key] = value
	end
	return ability
end

return BaseAbility
