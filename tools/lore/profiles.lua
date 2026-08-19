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

function newProfile(player)
	store[player] = {
		pets = {},
		eggs = {},
		incubator = nil,
		stats = { mazesCompleted = 0, floorsCleared = 0, summitsReached = 0, eggsHatched = 0 },
		daily = { lastClaimDayUtc = 0, streak = 0 },
		codex = { pets = {}, kept = {}, relics = {}, journal = { unlocked = 0, banked = {} } },
	}
	return store[player]
end

function profileOf(player)
	return store[player]
end

function fireReady(player)
	for _, fn in ipairs(ready) do
		fn(player)
	end
end
