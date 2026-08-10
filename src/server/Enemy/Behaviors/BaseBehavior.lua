-- BaseBehavior (ModuleScript) -> ServerScriptService.Enemy.Behaviors.BaseBehavior
-- The interface every behavior module implements, as a working set of no-ops.
--
-- A behavior is a table of hooks over the controller, not a subclass of it: the
-- controller stays the only thing that touches the Humanoid, so dormancy, the
-- freeze deadline, the stun and the attack tell are written once and cannot be
-- forgotten by a module that only meant to change how something walks.
--
-- The hook set was written at E0 from the brief, revised at E2 against the five
-- behaviors the game shipped then, and gained onStopped at E4 when behaviors
-- started leaving things in the world. Four hooks were added at E2 and one changed
-- meaning, and both are worth knowing about:
--
--   update now returns a claim. A Charger mid-rush owns its ticks outright and
--   must be able to say so, or the controller reacquires a target and walks it
--   off the line the player was shown. Truthy means "this tick is mine, stop".
--
--   filterTarget, onTargetAcquired, onTargetLost, onChase and onIdle are new.
--   They exist because target selection has three points a type needs to reach
--   into and only three: whether a candidate counts at all (a Lurker is scenery
--   until you are close), what happens on the transition (a Swarmer calls its
--   pack), and what to do with the target once picked (a Charger charges it).
--
-- Where the hooks fall in a tick is fixed and is the controller's business:
-- freeze, stun and off-floor gates, then update, then target selection wrapped
-- in filterTarget and the two transition hooks, then onChase or onIdle. The
-- order matters and is asserted in the E2 harness rather than left to memory.
--
-- Every hook returning nothing means "the controller decides". The three that
-- return a value say so in their comment; a behavior that returns nothing from
-- one of those gets the default, which is always the shipped behavior.

local BaseBehavior = {}

function BaseBehavior.init(_controller, _config) end

function BaseBehavior.onStateEntered(_controller, _state) end

function BaseBehavior.onStateExited(_controller, _state) end

-- Runs before target selection. Return truthy to claim the whole tick: no
-- targeting, no movement, no attack. For a move that owns the rig for a fixed
-- span and must not be interrupted by an ordinary chase decision.
function BaseBehavior.update(_controller, _dt)
	return false
end

-- The target the controller picked, or nil. Return it, or nil to refuse it.
-- Called every tick, so a type that hides again has somewhere to say so.
function BaseBehavior.filterTarget(_controller, target)
	return target
end

function BaseBehavior.onTargetAcquired(_controller, _target) end

function BaseBehavior.onTargetLost(_controller) end

-- Runs with a live target. Return truthy to claim the rest of the tick, attack
-- check and stuck check included: a Charger that has just started its windup is
-- eighteen studs away and neither of those has anything to say about it.
function BaseBehavior.onChase(_controller, _target)
	return false
end

-- Runs with nothing to chase and nowhere to walk back to. Return truthy to
-- claim it; unclaimed, the controller halts the rig where it stands, which is
-- what a type that holds a post wants.
function BaseBehavior.onIdle(_controller)
	return false
end

-- Return truthy to suppress the controller's melee. A behavior that lands its
-- own hit (a charge, a projectile, a shockwave) has to be able to say so rather
-- than land two.
function BaseBehavior.tryAttack(_controller, _character)
	return false
end

function BaseBehavior.onDamaged(_controller, _amount, _source) end

function BaseBehavior.onDeath(_controller, _source) end

-- The rig is going away: undo anything this behavior did to the world or to the
-- rig that the rig going away does not undo by itself. Added at E4, which is the
-- phase that gave behaviors things to leave behind.
--
-- It runs from the controller's stop, so it covers the ordinary case as well as
-- death. That is the case that matters: a player walking away is how almost every
-- enemy in the city ends.
--
-- Everything filed with EnemyCombat (a Spitter's bolts, a Trapper's snares, a
-- Blinker's mark, a Warden's ring) is *not* this hook's job any more. Four of the
-- five behaviors that had one used it for exactly that call and nothing else, so
-- E6 moved it into the controller's stop where it cannot be forgotten. What is
-- left here is the case the controller cannot know about: the Burrower unanchors
-- the root it anchored to travel under the floor.
function BaseBehavior.onStopped(_controller) end

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
