-- The PlayerProfiles surface LoreService uses, plus a fresh profile shaped like
-- the real defaults. Only the fields the service reads are here; anything it
-- grew that this does not carry shows up as an index error rather than as a
-- silently absent chapter.

local ready = {}
local store = {}

MODULES.PlayerProfiles = {
	data = function(player)
		return store[player]
	end,
	onReady = function(fn)
		table.insert(ready, fn)
	end,
}

-- A player is an object rather than a name, because LoreService publishes how far
-- the trail has got as a replicated attribute as well as into the profile, and
-- the harness has to be able to read what it wrote: the count in the saved data
-- and the number a client would see are two different things, and the whole
-- point of the attribute is that they never disagree.
function newPlayer(name)
	local player = { Name = name, attributes = {} }
	function player:SetAttribute(key, value)
		self.attributes[key] = value
	end
	function player:GetAttribute(key)
		return self.attributes[key]
	end

	store[player] = {
		pets = {},
		eggs = {},
		incubator = nil,
		stats = { mazesCompleted = 0, floorsCleared = 0, summitsReached = 0, eggsHatched = 0 },
		daily = { lastClaimDayUtc = 0, streak = 0 },
		codex = { pets = {}, kept = {}, relics = {}, journal = { unlocked = 0, banked = {} } },
	}
	return player
end

function profileOf(player)
	return store[player]
end

function fireReady(player)
	for _, fn in ipairs(ready) do
		fn(player)
	end
end
