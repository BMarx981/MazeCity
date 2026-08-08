-- BaseBehavior (ModuleScript) -> ServerScriptService.Enemy.Behaviors.BaseBehavior
-- The interface every behavior module implements, as a working set of no-ops.
--
-- This one is not a stub. It is the contract itself, and it is filled in now
-- rather than at E3 because fourteen modules are about to be written against
-- it and an interface discovered fourteen times is fourteen slightly different
-- interfaces. The concrete behaviors arrive at E3 (the six the game ships) and
-- E4 (the rest of the roster).
--
-- A behavior is a table of hooks over the controller, not a subclass of it: the
-- controller stays the only thing that touches the Humanoid, so dormancy, the
-- freeze deadline and the attack tell are written once and cannot be forgotten
-- by a module that only meant to change how something walks.
--
-- Every hook returning nothing means "the controller decides". tryAttack is the
-- exception and returns a boolean, because a behavior that handles its own
-- attack (a charge, a projectile, a shockwave) has to be able to say so and
-- suppress the default melee rather than land two hits.

local BaseBehavior = {}

function BaseBehavior.init(_controller, _config) end

function BaseBehavior.onStateEntered(_controller, _state) end

function BaseBehavior.onStateExited(_controller, _state) end

function BaseBehavior.update(_controller, _dt) end

function BaseBehavior.tryAttack(_controller, _character)
	return false
end

function BaseBehavior.onDamaged(_controller, _amount, _source) end

function BaseBehavior.onDeath(_controller, _source) end

-- A concrete behavior writes only what makes it different. The result is a flat
-- copy rather than an __index chain so that every hook is present on every
-- behavior, which is what lets the controller call them unconditionally instead
-- of testing fifteen fields for nil on every enemy on every tick.
--
-- An unknown key is an error at require time, not a key nobody reads. onStateEnter
-- for onStateEntered is the shape of that mistake and it is invisible otherwise:
-- the module looks written, the hook never fires, and the enemy just stands there.
function BaseBehavior.extend(overrides)
	local behavior = {}
	for key, value in pairs(BaseBehavior) do
		if key ~= "extend" then
			behavior[key] = value
		end
	end
	for key, value in pairs(overrides or {}) do
		if behavior[key] == nil then
			error(string.format("BaseBehavior.extend: %q is not a behavior hook", tostring(key)))
		end
		behavior[key] = value
	end
	return behavior
end

return BaseBehavior
