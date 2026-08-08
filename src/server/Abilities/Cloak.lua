-- Cloak (ModuleScript) -> ServerScriptService.Abilities.Cloak
-- Enemies stop seeing you while the key is held.
--
-- The effect is one attribute. EnemyTargeting.isCharacterVisible refuses a
-- candidate whose character has Cloaked set, so a chase ends on the tick the
-- cloak goes up and nothing in the enemy tree had to learn what an ability is.
--
-- Cloaked rather than the Ghost orb's Unseen, which does the identical job two
-- lines above it in that function. One flag would have made PickupService and
-- this module joint owners of it: an orb taken during a cloak clears the flag
-- when it expires, and the cloak then silently does nothing until the key comes
-- up. Two flags with one writer each cost one attribute read on the enemy side
-- and nothing at all here.
--
-- Not invisibility to other players, for the same reason the orb is not: there
-- is no combat, so being unseen by an enemy is the whole of what hiding is
-- worth, and it cannot strand anyone the way a walk-through-walls ghost could.
--
-- Nothing here is unsafe to end, so `blocked` stays the base no-op: the cloak
-- drops the instant the charge runs out and the player is exactly where they
-- were standing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local BaseAbility = require(script.Parent:WaitForChild("BaseAbility"))

-- player -> Highlight. The attribute lives on the character and dies with it on
-- a respawn; the shimmer is an instance and has to be destroyed.
local shimmers = {}

local Cloak = BaseAbility.extend({
	start = function(player, char)
		char:SetAttribute("Cloaked", true)

		local shimmer = Instance.new("Highlight")
		shimmer.Name = "CloakHighlight"
		shimmer.FillColor = Config.Cloak.HighlightColor
		shimmer.FillTransparency = Config.Cloak.HighlightTransparency
		shimmer.OutlineTransparency = 0.2
		shimmer.Parent = char
		shimmers[player] = shimmer

		return true
	end,

	stop = function(player, char)
		local shimmer = shimmers[player]
		shimmers[player] = nil
		if shimmer then
			shimmer:Destroy()
		end

		-- Cleared only on a character still on the DataModel. A dead one took the
		-- attribute with it, and writing to a body that has already been replaced
		-- would be clearing it on the wrong character rather than on none.
		if char and char.Parent then
			char:SetAttribute("Cloaked", nil)
		end
	end,
})

return Cloak
