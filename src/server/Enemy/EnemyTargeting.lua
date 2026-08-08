-- EnemyTargeting (ModuleScript) -> ServerScriptService.Enemy.EnemyTargeting
-- Who an enemy is allowed to chase, and which of them it picks.
--
-- Filled in at phase E2. Four filters are contracts the rest of the game
-- already depends on and are not open for reinterpretation: a character with
-- Unseen set is not a candidate at all (the Ghost powerup), a player more than
-- Config.EnemyFloorBand off the enemy's own Y is on another floor, leash is
-- measured from the spawn marker and never from the enemy, and a player inside
-- a safe zone cannot be acquired.
--
-- Stickiness exists because a score recomputed three times a second off raw
-- distance makes an enemy standing between two players oscillate instead of
-- committing to either.

local EnemyTargeting = {}

function EnemyTargeting.isEligible(_controller, _character)
	error("EnemyTargeting.isEligible is not implemented until phase E2")
end

function EnemyTargeting.score(_controller, _character)
	error("EnemyTargeting.score is not implemented until phase E2")
end

function EnemyTargeting.pick(_controller)
	error("EnemyTargeting.pick is not implemented until phase E2")
end

return EnemyTargeting
