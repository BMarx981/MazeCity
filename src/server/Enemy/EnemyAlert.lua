-- EnemyAlert (ModuleScript) -> ServerScriptService.Enemy.EnemyAlert
-- One enemy telling the others where the player is. The only place in the system
-- where one controller writes another's state, which is why it is one function
-- rather than a loop copied into four behavior modules.
--
-- It writes three fields and every one of them is load-bearing, which was found by
-- watching the Swarmer's version fail with fewer. Setting lastSeen alone had the
-- alerted enemy clear the position on its very next tick without ever walking to
-- it: the controller's search branch is what consumes lastSeen and it is gated on
-- searchUntil. alertUntil is the third, and only the Swarmer reads it, to hold a
-- widened leash for as long as the call lasts so it can pick the player up for
-- itself on the way over instead of arriving at an empty corridor.
--
-- A radius in a maze is not a neighbourhood, so distance is never the only filter.
-- The floor band always applies, because a shriek heard through a slab is an enemy
-- two storeys up walking into a wall for six seconds. sameBuilding narrows it
-- further for the types whose alert is supposed to stay indoors.
--
-- Distance is measured marker to marker rather than rig to rig, for the same
-- reason the leash is: who hears a call is a property of where an enemy belongs,
-- not of where it has wandered to, and an alert that chained off whichever enemy
-- had strayed nearest would carry across a floor one hop at a time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))

local EnemyRegistry = require(script.Parent:WaitForChild("EnemyRegistry"))

local EnemyAlert = {}

-- opts: radius (required), seconds, behavior to restrict recipients to one kind,
-- sameBuilding to keep it inside the tower it was raised in.
--
-- Returns how many were told, which is what a caller logs or ignores; nothing in
-- the game reads it yet and it costs nothing to answer honestly.
function EnemyAlert.broadcast(source, position, opts)
	local radius = opts.radius or 0
	local deadline = os.clock() + (opts.seconds or 0)
	local told = 0

	for _, other in pairs(EnemyRegistry.all()) do
		if other ~= source and other.alive then
			local sameFloor = math.abs(other.homeY - source.homeY) < Config.Enemies.FloorBand
			local sameKind = opts.behavior == nil or other.stats.behavior == opts.behavior
			local sameTower = not opts.sameBuilding
				or (other.section == source.section and other.building == source.building)
			if sameFloor and sameKind and sameTower and (other.home - source.home).Magnitude <= radius then
				other.alertUntil = deadline
				other.lastSeen = position
				other.searchUntil = deadline
				told = told + 1
			end
		end
	end

	return told
end

return EnemyAlert
