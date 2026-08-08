-- EnemyStateMachine (ModuleScript) -> ServerScriptService.Enemy.EnemyStateMachine
-- The states in EnemyTypes.State and the transitions between them, with the
-- entered and exited hooks the behavior modules hang off.
--
-- Filled in at phase E2. It is a separate module from the controller for one
-- reason: the debug state label and the client effect payload both want to know
-- what an enemy is doing without being allowed to change it.

local EnemyStateMachine = {}
EnemyStateMachine.__index = EnemyStateMachine

function EnemyStateMachine.new(_controller)
	error("EnemyStateMachine.new is not implemented until phase E2")
end

function EnemyStateMachine:transition(_state)
	error("EnemyStateMachine:transition is not implemented until phase E2")
end

function EnemyStateMachine:current()
	error("EnemyStateMachine:current is not implemented until phase E2")
end

function EnemyStateMachine:timeInState()
	error("EnemyStateMachine:timeInState is not implemented until phase E2")
end

return EnemyStateMachine
