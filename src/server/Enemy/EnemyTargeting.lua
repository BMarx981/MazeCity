-- EnemyTargeting (ModuleScript) -> ServerScriptService.Enemy.EnemyTargeting
-- Who an enemy is allowed to chase, which of them it picks, and the two sight
-- questions every behavior asks: can I see it, and is it looking at me.
--
-- Four filters are contracts the rest of the game already depends on and are not
-- open for reinterpretation. A character with Unseen set is not a candidate at
-- all, which is the whole of the Ghost powerup. A player more than
-- Config.Enemies.FloorBand off the enemy's own Y is on another floor. Leash is
-- measured from the spawn marker and never from the enemy: measuring from the
-- enemy let a chase drag the whole floor along behind the player one enemy at a
-- time and meant leaving somewhere never actually shook anything off. From the
-- marker, an enemy owns a patch of maze and the player can leave it.
--
-- The fourth is the safe zone, landed at E5: a player standing on a plaza pad
-- is not a candidate, and one who reaches it mid-chase stops being one on the
-- next tick, which is the whole of "enemies abandon targets inside". There is
-- nowhere else it could go, which is why the stub said so.
--
-- Stickiness is two mechanisms and they answer different questions. The retain
-- multiplier widens the leash once a target is held, so a player standing on the
-- boundary is not picked up and dropped several times a second. The bonus is in
-- studs and is subtracted from the held target's score, so an enemy standing
-- between two players commits to one instead of recomputing into the other one
-- three times a second. One player can only ever exercise the first.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))

local EnemySafeZones = require(script.Parent:WaitForChild("EnemySafeZones"))
local EnemyStatusService = require(script.Parent:WaitForChild("EnemyStatusService"))

local EnemyTargeting = {}

-- One shared RaycastParams rewritten per call. Safe for the same reason
-- PickupService's taken guard is: nothing between writing the filter and firing
-- the ray yields, so no other enemy's tick can interleave and read a filter
-- meant for somebody else. RespectCanCollide keeps coins and triggers, which are
-- all CanCollide false, out of the answer.
local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.RespectCanCollide = true

-- Every enemy is excluded, not just the one asking, so an enemy standing behind
-- another one can still see you. They do not collide with each other either, and
-- a crowd that blinds itself is a crowd that stands still.
function EnemyTargeting.hasLineOfSight(from, toPart)
	local filter = { toPart.Parent }
	-- Looked up rather than held, and each one guarded, because a nil in this list
	-- is a hole in an array the engine reads by length: it would drop whichever
	-- folder came after it out of the filter and the ray would start hitting pets.
	local enemies = workspace:FindFirstChild("LiveEnemies")
	if enemies then
		table.insert(filter, enemies)
	end
	local pets = workspace:FindFirstChild("LivePets")
	if pets then
		table.insert(filter, pets)
	end
	losParams.FilterDescendantsInstances = filter

	local hit = workspace:Raycast(from, toPart.Position - from, losParams)
	return hit == nil
end

-- Whether the player is facing the enemy. Server side and off the character's
-- own CFrame, deliberately: a client-reported look direction is a remote to
-- validate and a thing to spoof, and the answer is only ever used to make an
-- enemy slower or stiller, never faster than its row allows.
function EnemyTargeting.isWatched(controller, hrp)
	local toEnemy = controller.root.Position - hrp.Position
	if toEnemy.Magnitude < 1 then
		return true
	end
	return hrp.CFrame.LookVector:Dot(toEnemy.Unit) > 0.45
end

-- The Ghost powerup and the Cloak ability. PickupService sets Unseen and clears
-- it when the effect ends; Abilities/Cloak sets Cloaked and clears it when the
-- key comes up. "Invisible to enemies" therefore costs two attribute reads here
-- and nothing anywhere else.
--
-- Two attributes rather than one shared flag, and not for tidiness: each has
-- exactly one writer. On one flag, an orb taken during a cloak would clear it on
-- expiry and leave the cloak silently doing nothing until the key came up, and
-- the reverse would end the orb early. A count would fix that and hand two
-- services joint ownership of a character attribute, which is worse than the
-- extra read. Anything else that wants to hide a player gets its own flag and a
-- clause here.
--
-- Both are deliberately not walk-through-walls: in a game with no combat, not
-- being chased is the whole of what hiding needs to be, and it cannot strand a
-- player outside the maze.
--
-- The Revealed status is the one thing that beats either, and it is the whole of
-- what a Shrieker does. It is checked first rather than folded into the same
-- expression so that the precedence is stated: a reveal outranks hiding, it does
-- not clear it, so an orb taken before the shriek is still running when the reveal
-- lapses. Neither writer ever sees the other's flag.
function EnemyTargeting.isCharacterVisible(character, humanoid)
	if humanoid == nil or humanoid.Health <= 0 then
		return false
	end
	if EnemyStatusService.has(character, "Revealed") then
		return true
	end
	return not character:GetAttribute("Unseen") and not character:GetAttribute("Cloaked")
end

-- Studs from the marker this enemy will chase to. leashMultiplier is how a
-- behavior widens its own reach for a while; a Swarmer that has been called by
-- one of its own is the only thing that sets it today.
function EnemyTargeting.leashFor(controller)
	local leash = controller.stats.leash
	if controller.target then
		leash = leash * Config.Enemies.TargetRetain
	end
	return leash * (controller.leashMultiplier or 1)
end

function EnemyTargeting.isEligible(controller, character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then
		return false
	end
	if not EnemyTargeting.isCharacterVisible(character, humanoid) then
		return false
	end
	if math.abs(hrp.Position.Y - controller.homeY) >= Config.Enemies.FloorBand then
		return false
	end
	if EnemySafeZones.covers(hrp.Position) then
		return false
	end
	return (hrp.Position - controller.home).Magnitude <= EnemyTargeting.leashFor(controller)
end

-- Lower is better. Distance from the marker, so the enemy prefers the player
-- deepest into the patch of maze it owns rather than the one nearest its feet,
-- which is the same reason the leash is measured from there.
function EnemyTargeting.score(controller, character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return math.huge
	end
	local distance = (hrp.Position - controller.home).Magnitude
	if controller.target and controller.target.Parent == character then
		distance = distance - Config.Enemies.TargetStickinessBonus
	end
	return distance
end

-- Returns the HumanoidRootPart, which is what the rest of the system carries a
-- target as: it is the thing whose Position is live without a second lookup, and
-- its Parent is the character when the growl or the attack needs it.
function EnemyTargeting.pick(controller)
	local best, bestScore = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and EnemyTargeting.isEligible(controller, character) then
			local score = EnemyTargeting.score(controller, character)
			if score < bestScore then
				best, bestScore = character:FindFirstChild("HumanoidRootPart"), score
			end
		end
	end
	return best
end

return EnemyTargeting
