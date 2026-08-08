-- EnemyStatusService (ModuleScript) -> ServerScriptService.Enemy.EnemyStatusService
-- Timed statuses on players and on enemies: Slow, Stun, Reveal, Marked.
--
-- Filled in at phase E2. One rule decides the shape: a status never writes a
-- permanent value. It records what it found, applies its own, and restores what
-- it found when it expires or when the character respawns, which is the same
-- restore-closure discipline PickupService already uses for its powerups. Two
-- systems that each set WalkSpeed absolutely will eventually overlap, and the
-- loser leaves a player slowed for the rest of the session.

local EnemyStatusService = {}

function EnemyStatusService.apply(_instance, _statusName, _seconds, _magnitude)
	error("EnemyStatusService.apply is not implemented until phase E2")
end

function EnemyStatusService.has(_instance, _statusName)
	error("EnemyStatusService.has is not implemented until phase E2")
end

function EnemyStatusService.clear(_instance, _statusName)
	error("EnemyStatusService.clear is not implemented until phase E2")
end

function EnemyStatusService.clearAll(_instance)
	error("EnemyStatusService.clearAll is not implemented until phase E2")
end

return EnemyStatusService
