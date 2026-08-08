-- SpawnDirector (ModuleScript) -> ServerScriptService.Enemy.SpawnDirector
-- Decides what a floor is populated with, inside a budget, and owns respawn.
--
-- Filled in at phase E5. It reinterprets what an EnemySpawn marker is: today a
-- marker is one enemy of the building's type, afterwards a marker is a position
-- and the group of (Section, Building, Level) markers shares a budget. That is
-- a runtime change only, so no marker moves and no part count changes.
--
-- Its randomness is runtime randomness, deliberately not drawn from the world
-- seed, for the same reason PickupService rolls its powerups on touch: a floor
-- that presents the same six enemies to every player on every server is a floor
-- that gets memorised once and never read again.

local SpawnDirector = {}

function SpawnDirector.groupKeyOf(_marker)
	error("SpawnDirector.groupKeyOf is not implemented until phase E5")
end

function SpawnDirector.budgetFor(_level)
	error("SpawnDirector.budgetFor is not implemented until phase E5")
end

function SpawnDirector.roll(_groupKey, _budget)
	error("SpawnDirector.roll is not implemented until phase E5")
end

function SpawnDirector.start(_services)
	error("SpawnDirector.start is not implemented until phase E5")
end

return SpawnDirector
