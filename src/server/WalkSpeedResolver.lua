-- WalkSpeedResolver (ModuleScript) -> ServerScriptService
-- The one writer of humanoid.WalkSpeed. Four things want to change how fast a
-- player moves and they arrive in any order: the shop's Fast Feet tier, the
-- Speed powerup, the Wall Walker's squeeze, and Sprint. Each one used to
-- multiply BaseWalkSpeed itself and restore by writing BaseWalkSpeed back, which
-- is last-writer-wins dressed up as a convention: a Speed orb taken before a
-- sprint was silently cancelled the moment that sprint ended, and a phase
-- started during an orb dropped the orb's 1.45 on the floor.
--
-- So a source names itself and states a multiplier, and this module owns the
-- product. Nobody outside it reads or writes humanoid.WalkSpeed, which is the
-- whole of why the four compose: clearing "Sprint" cannot disturb "Powerup"
-- because clearing is removing a factor, not restoring a remembered number.
--
-- BaseWalkSpeed stays exactly what it was, a character attribute stamped by
-- SaveService. It is the baseline the product multiplies, so a purchase made
-- while three of these are live moves everyone's arithmetic at once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))

local Resolver = {}

-- character -> { [source] = multiplier }. Weak keys: a character replaced by a
-- respawn takes its factors with it, so no caller has to remember to clear a
-- source off a body that no longer exists. Keyed by character rather than by
-- player for the same reason, the old humanoid's speed being nobody's business
-- once it is off the DataModel.
local sources = setmetatable({}, { __mode = "k" })

-- Recomputes and writes. Safe to call on a character with no factors, which is
-- what SaveService does after stamping a new BaseWalkSpeed.
function Resolver.apply(char)
	if not char or not char.Parent then
		return nil
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or not humanoid.Parent then
		return nil
	end

	-- Never the live WalkSpeed as a fallback, which is what the old call sites
	-- used. Reading it back while a factor is applied is precisely how a boost
	-- becomes permanent or gets squared. A character with no attribute is a
	-- profile that has not landed yet, and the shop baseline is what SaveService
	-- is going to stamp on it.
	local speed = char:GetAttribute("BaseWalkSpeed") or Config.Shop.BaseWalkSpeed
	local applied = sources[char]
	if applied then
		for _, multiplier in pairs(applied) do
			speed = speed * multiplier
		end
	end

	humanoid.WalkSpeed = speed
	return speed
end

function Resolver.set(char, source, multiplier)
	if not char then
		return nil
	end
	local applied = sources[char]
	if not applied then
		applied = {}
		sources[char] = applied
	end
	applied[source] = multiplier
	return Resolver.apply(char)
end

function Resolver.clear(char, source)
	if not char then
		return nil
	end
	local applied = sources[char]
	-- Clearing something never set is an ordinary no-op rather than a write,
	-- because every caller clears on paths that can run twice: a powerup expiring
	-- on the same frame the player dies, a phase ended by both the meter and the
	-- key.
	if not applied or applied[source] == nil then
		return nil
	end
	applied[source] = nil
	return Resolver.apply(char)
end

return Resolver
