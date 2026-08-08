-- EnemyRegistry (ModuleScript) -> ServerScriptService.Enemy.EnemyRegistry
-- Every live controller, keyed by the marker it was spawned from.
--
-- A module rather than a table inside EnemyService, because a Script cannot be
-- required and two things other than the service need to read it: a Swarmer
-- calling its pack has to find the other Swarmers on its floor, and the caps
-- have to be answerable before a spawn rather than after it.
--
-- Keyed by marker and not by model, because a marker is permanent and a rig is
-- not. That is also what makes "is this marker already occupied" a lookup instead
-- of a scan.
--
-- The per-building counts are kept incrementally rather than counted on demand.
-- The scan asks for one every half second per unoccupied marker in range, and a
-- count that walks the whole registry to answer turns a cheap question into a
-- quadratic one on the exact code path that already sweeps 900 markers.

local EnemyRegistry = {}

local byMarker = {}
local buildingCounts = {}
local count = 0

local function buildingKey(controller)
	return string.format("%d:%d", controller.section or 0, controller.building or 0)
end

function EnemyRegistry.add(marker, controller)
	if byMarker[marker] then
		return false
	end
	byMarker[marker] = controller
	count = count + 1
	local key = buildingKey(controller)
	buildingCounts[key] = (buildingCounts[key] or 0) + 1
	return true
end

function EnemyRegistry.remove(marker)
	local controller = byMarker[marker]
	if not controller then
		return nil
	end
	byMarker[marker] = nil
	count = count - 1
	local key = buildingKey(controller)
	local remaining = (buildingCounts[key] or 1) - 1
	buildingCounts[key] = remaining > 0 and remaining or nil
	return controller
end

function EnemyRegistry.get(marker)
	return byMarker[marker]
end

function EnemyRegistry.all()
	return byMarker
end

function EnemyRegistry.count()
	return count
end

function EnemyRegistry.countInBuilding(section, building)
	return buildingCounts[string.format("%d:%d", section or 0, building or 0)] or 0
end

return EnemyRegistry
