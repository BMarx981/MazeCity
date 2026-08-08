-- EnemyPathfinding (ModuleScript) -> ServerScriptService.Enemy.EnemyPathfinding
-- Paths, waypoint following, replanning and stuck detection, staggered so that
-- twenty five enemies do not all compute on the same frame.
--
-- Filled in at phase E2, generalising what the live EnemyService already does.
-- Two of those are hard won and must survive the move: nothing blocks on
-- MoveToFinished, whose eight second internal timeout turns a clipped corner
-- into an enemy standing still, and a plan goes stale on both a timer and a
-- drift, because the timer catches a moving wall closing across a clear path
-- and the drift catches the player rounding a corner, and neither alone caught
-- both.
--
-- Teleporting is not navigation. The give-up teleport home stays as the last
-- resort it is; a Blinker moves by its own validated rules in its own module.

local EnemyPathfinding = {}
EnemyPathfinding.__index = EnemyPathfinding

function EnemyPathfinding.new(_controller)
	error("EnemyPathfinding.new is not implemented until phase E2")
end

function EnemyPathfinding:moveTo(_position)
	error("EnemyPathfinding:moveTo is not implemented until phase E2")
end

function EnemyPathfinding:halt()
	error("EnemyPathfinding:halt is not implemented until phase E2")
end

function EnemyPathfinding:needsReplan(_position)
	error("EnemyPathfinding:needsReplan is not implemented until phase E2")
end

function EnemyPathfinding:isStuck()
	error("EnemyPathfinding:isStuck is not implemented until phase E2")
end

return EnemyPathfinding
