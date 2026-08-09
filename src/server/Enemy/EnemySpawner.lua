-- EnemySpawner (ModuleScript) -> ServerScriptService.Enemy.EnemySpawner
-- The one way an enemy comes to life: a rig from the factory, a controller around
-- it, an entry in the registry, and a running tick. Three lines that were inside
-- EnemyService until E4 needed a second caller.
--
-- The second caller is the Splitter, whose children are an enemy nothing placed a
-- marker for. E5's spawn director is the third and is the reason this is a module
-- rather than a function on the service: the director decides what a floor holds
-- and then has to make it, and a Script cannot be required.
--
-- The registry key is whatever identity the caller has. A marker for an enemy that
-- came off one, and the rig itself for one that did not; the registry only needs
-- something stable to key on and something the despawn sweep can hand back. A
-- child therefore has no marker, is never respawned, and disappears for good when
-- the player walks away, which is exactly right for something that only exists
-- because something else died.
--
-- EnemyController is required lazily rather than at the top. Behaviors are required
-- by the controller, the Splitter is a behavior, and the Splitter needs this
-- module: requiring the controller here would close that ring at load time. Inside
-- the function it resolves on the first spawn, by which point everything is loaded.

local EnemyFactory = require(script.Parent:WaitForChild("EnemyFactory"))
local EnemyRegistry = require(script.Parent:WaitForChild("EnemyRegistry"))

local EnemySpawner = {}

-- options: key (registry identity, defaults to the model), marker, home, section,
-- building, level, onDied. Returns the controller, or nil if the rig could not be
-- built, which the caller is expected to treat as "no enemy here" rather than as an
-- error: a type name that resolves to nothing has already warned.
function EnemySpawner.spawn(typeName, spawnCFrame, options)
	options = options or {}
	local EnemyController = require(script.Parent:WaitForChild("EnemyController"))

	local model, anim, stats = EnemyFactory.create(typeName, spawnCFrame, {
		section = options.section,
		level = options.level,
	})
	if not model then
		return nil
	end

	local controller = EnemyController.new(model, stats, {
		anim = anim,
		marker = options.marker,
		home = options.home or spawnCFrame.Position,
		section = options.section,
		building = options.building,
		level = options.level,
	})
	if not controller then
		model:Destroy()
		return nil
	end

	-- Set before start rather than after, because a rig that dies inside its first
	-- tick would otherwise die with nobody listening.
	controller.onDied = options.onDied

	EnemyRegistry.add(options.key or model, controller)
	controller:start()
	return controller
end

return EnemySpawner
