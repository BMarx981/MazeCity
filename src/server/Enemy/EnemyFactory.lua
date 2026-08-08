-- EnemyFactory (ModuleScript) -> ServerScriptService.Enemy.EnemyFactory
-- Turns a type name into a live rig: picks a template, applies the runtime
-- stats, parents it into workspace.LiveEnemies and hands it to EnemyService.
--
-- Filled in at phase E1. Template priority is settled and does not change: a
-- hand-made rig at ServerStorage/Enemies/<TypeName> beats a generated one beats
-- the procedural shade, so an artist can replace any single type without
-- touching code and without the other eighteen changing.
--
-- Runtime stats are a copy. Nothing here writes back into the definitions
-- table, because a difficulty multiplier applied in place is applied again to
-- the next enemy of that type and again to the one after that.

local EnemyFactory = {}

function EnemyFactory.create(_typeName, _spawnCFrame, _options)
	error("EnemyFactory.create is not implemented until phase E1")
end

function EnemyFactory.destroy(_model)
	error("EnemyFactory.destroy is not implemented until phase E1")
end

function EnemyFactory.definitionOf(_model)
	error("EnemyFactory.definitionOf is not implemented until phase E1")
end

return EnemyFactory
