-- EnemySafeZones (ModuleScript) -> ServerScriptService.Enemy.EnemySafeZones
-- Whether a position is somewhere enemies do not go: the plaza pad outside each
-- tower door. Runtime boxes over the TowerStart parts the generator already
-- places, per the plan's D4: no new geometry, no new tag, and a lazily built
-- section's plaza is safe the moment its tag replicates.
--
-- Two questions, and callers must pick the right one. covers is the zone
-- itself and is the player's protection: targeting refuses a character inside
-- it, and every way of taking health checks it before landing. repels is the
-- zone plus Config.Enemies.SafeZoneMargin and is the enemy's exclusion: rigs
-- back off it, destinations inside it are rejected, markers inside it stay
-- empty. The margin exists so nothing camps the one line a player has to cross
-- to get out, which would turn the pad from a refuge into a trap with a moat.
--
-- The zone is a box and not a radius because the pad is one: axis-aligned by
-- construction (the generator never rotates it), so the test is four compares.
-- It is bounded in Y to the pad's own storey, because the pads sit at street
-- level directly under ten floors of maze and a zone reaching upward would
-- carve a silent hole in every floor above the door.
--
-- What being inside one does to an enemy is not here. This answers the
-- question; EnemyController turns a repelled position into the same walk-home
-- branch a pet's ward uses, and EnemyCombat refuses the hit.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))

-- Studs above the pad's surface that still count as standing on it, and the
-- slack below so the pad's own thickness is inside its zone. A property of the
-- pad and a character's height, not tuning.
local ZONE_HEIGHT = 10
local ZONE_BELOW = 2

local EnemySafeZones = {}

local zones = {}
local dirty = true

-- Rebuilt only when the tag population changes, never per query: the pads are
-- anchored generator parts that exist for the life of the server, so unlike a
-- ward there is nothing live to re-read.
local function refresh()
	if not dirty then
		return
	end
	dirty = false
	table.clear(zones)
	for _, pad in ipairs(CollectionService:GetTagged("TowerStart")) do
		if pad:IsA("BasePart") then
			local p, s = pad.Position, pad.Size
			table.insert(zones, {
				minX = p.X - s.X / 2,
				maxX = p.X + s.X / 2,
				minZ = p.Z - s.Z / 2,
				maxZ = p.Z + s.Z / 2,
				minY = p.Y - ZONE_BELOW,
				maxY = p.Y + ZONE_HEIGHT,
			})
		end
	end
end

CollectionService:GetInstanceAddedSignal("TowerStart"):Connect(function()
	dirty = true
end)
CollectionService:GetInstanceRemovedSignal("TowerStart"):Connect(function()
	dirty = true
end)

local function inside(zone, position, pad)
	return position.X >= zone.minX - pad
		and position.X <= zone.maxX + pad
		and position.Z >= zone.minZ - pad
		and position.Z <= zone.maxZ + pad
		and position.Y >= zone.minY
		and position.Y <= zone.maxY
end

-- Inside a zone itself. The player's side of the contract: not targetable, not
-- damageable, and a projectile crossing this line dies at it.
function EnemySafeZones.covers(position)
	refresh()
	for _, zone in ipairs(zones) do
		if inside(zone, position, 0) then
			return true
		end
	end
	return false
end

-- Inside a zone or its margin. The enemy's side: nothing stands here, arrives
-- here, or spawns here.
function EnemySafeZones.repels(position)
	refresh()
	for _, zone in ipairs(zones) do
		if inside(zone, position, Config.Enemies.SafeZoneMargin) then
			return true
		end
	end
	return false
end

return EnemySafeZones
