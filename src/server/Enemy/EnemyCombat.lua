-- EnemyCombat (ModuleScript) -> ServerScriptService.Enemy.EnemyCombat
-- Everything that takes a player's health, validated here and nowhere else.
--
-- Filled in at phase E2. The shipped melee flow is the default and stays as it
-- is: flash for Config.Feel.EnemyTellSeconds, then check that the player is
-- still inside EnemyTellReach and still has line of sight before the damage
-- lands. The order is the whole design. Damage that lands because an effect
-- played is damage a player could not have avoided, and a hit that cannot be
-- avoided is the one thing the kid-first tuning refuses.

local EnemyCombat = {}

function EnemyCombat.canReach(_controller, _character)
	error("EnemyCombat.canReach is not implemented until phase E2")
end

function EnemyCombat.tryMelee(_controller, _character)
	error("EnemyCombat.tryMelee is not implemented until phase E2")
end

function EnemyCombat.applyDamage(_controller, _character, _amount)
	error("EnemyCombat.applyDamage is not implemented until phase E2")
end

return EnemyCombat
