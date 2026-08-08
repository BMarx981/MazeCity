-- EnemyStateMachine (ModuleScript) -> ServerScriptService.Enemy.EnemyStateMachine
-- The states in EnemyTypes.State and the transitions between them, with the
-- entered and exited hooks the behavior modules hang off.
--
-- It is a separate module from the controller for one reason: the debug state
-- label and the client effect payload both want to know what an enemy is doing
-- without being allowed to change it.
--
-- Deliberately not a transition table. A maze enemy's states are not a graph
-- with illegal edges, they are a description of what it is doing right now, and
-- the one rule worth enforcing is that the name exists at all: a typo in a
-- transition is otherwise a state nothing matches and an enemy that stops
-- reacting, which reads exactly like the stuck bug the old service had.
--
-- The state is mirrored onto the model as a State attribute. That costs one
-- write per real transition, not per tick, and it is what makes an enemy
-- inspectable in the Studio explorer during a Play session, which is the only
-- debugging surface this project has until EnemyDebug lands at E5.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyTypes = require(ReplicatedStorage:WaitForChild("EnemyTypes"))

local EnemyStateMachine = {}
EnemyStateMachine.__index = EnemyStateMachine

function EnemyStateMachine.new(controller)
	local self = setmetatable({}, EnemyStateMachine)
	self.controller = controller
	self.state = EnemyTypes.State.Idle
	self.enteredAt = os.clock()
	return self
end

-- Re-entering the state you are already in is a no-op rather than a fresh pair
-- of hooks. The chase branch transitions to Chase on every tick it holds a
-- target, so an onStateEntered that fired eight times a second would be one
-- growl restart per tick.
function EnemyStateMachine:transition(state)
	if not EnemyTypes.State[state] then
		error(string.format("EnemyStateMachine: %q is not a state", tostring(state)))
	end
	if state == self.state then
		return false
	end

	local previous = self.state
	self.state = state
	self.enteredAt = os.clock()

	local controller = self.controller
	local behavior = controller.behavior
	behavior.onStateExited(controller, previous)
	behavior.onStateEntered(controller, state)

	if controller.model.Parent then
		controller.model:SetAttribute("State", state)
	end
	return true
end

function EnemyStateMachine:current()
	return self.state
end

function EnemyStateMachine:timeInState()
	return os.clock() - self.enteredAt
end

return EnemyStateMachine
