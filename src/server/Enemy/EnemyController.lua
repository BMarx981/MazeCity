-- EnemyController (ModuleScript) -> ServerScriptService.Enemy.EnemyController
-- One per live rig. Owns that enemy's runtime state, drives its state machine,
-- and calls into its behavior module for anything type specific.
--
-- Filled in at phase E2. The division it enforces: the controller knows how to
-- move, look, attack and die, the behavior knows when. A behavior that reaches
-- past the controller into the Humanoid is a behavior that has to re-implement
-- dormancy, freezing and the tell, and one of the fifteen will get it wrong.
--
-- Dormancy wraps all of it. A controller with nobody inside the activation
-- range runs the cheap poll and nothing else, which is what keeps a city of
-- markers affordable and is not a thing the staggered update groups replace.

local EnemyController = {}
EnemyController.__index = EnemyController

function EnemyController.new(_model, _definition, _services)
	error("EnemyController.new is not implemented until phase E2")
end

function EnemyController:start()
	error("EnemyController:start is not implemented until phase E2")
end

function EnemyController:stop()
	error("EnemyController:stop is not implemented until phase E2")
end

function EnemyController:destroy()
	error("EnemyController:destroy is not implemented until phase E2")
end

function EnemyController:setTarget(_character)
	error("EnemyController:setTarget is not implemented until phase E2")
end

function EnemyController:applyStun(_seconds)
	error("EnemyController:applyStun is not implemented until phase E2")
end

function EnemyController:takeDamage(_amount, _source)
	error("EnemyController:takeDamage is not implemented until phase E2")
end

return EnemyController
