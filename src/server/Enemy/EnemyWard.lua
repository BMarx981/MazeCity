-- EnemyWard (ModuleScript) -> ServerScriptService.Enemy.EnemyWard
-- The only thing in the enemy system that knows pets exist, and it knows one
-- thing: whether a position is inside a running ward.
--
-- The channel is the one the Ghost powerup and the Cloak ability already use. A
-- service that owns an effect writes a flag on an instance and the enemy side
-- reads it; here PetService writes WardRadius on a follower rig for as long as
-- that pet's ward is up and clears it when it lapses, so the attribute existing
-- *is* the ward being up. There is no second flag to disagree with the first, and
-- this file cannot be wrong about the timing because it does not know any.
--
-- What a ward does to an enemy is not here either. This answers the question and
-- EnemyController decides what to do about it, which is to drop the target,
-- forget where it saw anybody and walk back to its own marker. Nothing is
-- damaged, stunned or moved: there is no combat in this game and a pet is not
-- where one would start.
--
-- The list of wards is cached and the positions are not. Rebuilding it is a
-- GetChildren and an attribute read per follower, which is cheap but happens once
-- per enemy per tick otherwise; the positions have to be live or a ward would
-- protect the corridor its pet was in a moment ago. One think interval is the
-- staleness bound, so a ward is felt on the next tick of every enemy in the city
-- at worst.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))

local EnemyWard = {}

local cached = {}
local cachedAt = -1

local function refresh()
	local now = os.clock()
	if now - cachedAt < Config.Enemies.ThinkInterval then
		return
	end
	cachedAt = now
	table.clear(cached)

	-- Looked up rather than held: LivePets is PetService's folder and this module
	-- may well be required before it exists.
	local live = workspace:FindFirstChild("LivePets")
	if not live then
		return
	end
	for _, model in ipairs(live:GetChildren()) do
		local radius = model:GetAttribute("WardRadius")
		local primary = radius and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart"))
		if primary then
			table.insert(cached, { part = primary, radius = radius })
		end
	end
end

function EnemyWard.covers(position)
	refresh()
	for _, ward in ipairs(cached) do
		if ward.part.Parent and (ward.part.Position - position).Magnitude <= ward.radius then
			return true
		end
	end
	return false
end

return EnemyWard
