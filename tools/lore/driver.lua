-- The scenarios. Each one is a fresh profile, so nothing leaks between them and
-- a failure names the rule it broke rather than the test that ran before it.

local ServerScriptService = game:GetService("ServerScriptService")
local progress = ServerScriptService:FindFirstChild("MazeProgress")
local petsChanged = ServerScriptService:FindFirstChild("PetsChanged")
local channel = ServerScriptService:FindFirstChild("LoreEvent")

local failures = 0
local function check(cond, message)
	if not cond then
		failures = failures + 1
		print("   FAIL: " .. message)
	end
end

local function toasts()
	local out = {}
	for _, entry in ipairs(FIRED) do
		table.insert(out, entry.payload)
	end
	return out
end

local function reset(label)
	print(label)
	FIRED = {}
	DEFERRED = {}
	return newPlayer(label)
end

-- The count the client would read. Asserted beside the profile's own count
-- everywhere it moves, because the two are written in different places and the
-- wall writings are drawn from the one the profile does not hold.
local function published(player)
	return player:GetAttribute("JournalUnlocked")
end

local function clearFloor(player, n)
	local data = profileOf(player)
	for _ = 1, n or 1 do
		data.stats.floorsCleared = data.stats.floorsCleared + 1
		progress:Fire({ kind = "floor", player = player })
	end
	drain()
end

local function topOut(player, n)
	local data = profileOf(player)
	for _ = 1, n or 1 do
		data.stats.summitsReached = data.stats.summitsReached + 1
		progress:Fire({ kind = "tower", player = player })
	end
	drain()
end

local function fact(player, payload)
	payload.player = player
	channel:Fire(payload)
	drain()
end

local function unlocked(player)
	return profileOf(player).codex.journal.unlocked
end

-- ============================================================

do
	local name = reset("1. a fresh save unlocks nothing")
	local p = profileOf(name)
	fireReady(name)
	drain()
	check(unlocked(name) == 0, "fresh profile unlocked " .. unlocked(name))
	check(#toasts() == 0, "fresh profile toasted")
	check(p.codex.journal.banked.FirstHatch == nil, "fresh profile banked a hatch")
	-- Stamped on a join that gained nothing, which is the case the attribute
	-- exists for: a client is told where the trail stands before it is told
	-- anything moved.
	check(published(name) == 0, "a fresh join published " .. tostring(published(name)))
end

do
	local name = reset("2. stat triggers land in order")
	clearFloor(name, 1)
	check(unlocked(name) == 1, "one floor should unlock exactly 1, got " .. unlocked(name))
	clearFloor(name, 3)
	check(unlocked(name) == 1, "four floors is still 1, got " .. unlocked(name))
	clearFloor(name, 1)
	check(unlocked(name) == 2, "five floors should unlock 2, got " .. unlocked(name))
	topOut(name, 1)
	check(unlocked(name) == 3, "first summit should unlock 3, got " .. unlocked(name))
	check(published(name) == 3, "the attribute says " .. tostring(published(name)) .. " and the profile says 3")
	local t = toasts()
	check(#t == 3, "three toasts expected, got " .. #t)
	check(t[1].index == 1 and t[2].index == 2 and t[3].index == 3, "toasts out of order")
	check(t[1].day == 1, "fragment 1 is day " .. tostring(t[1].day))
end

do
	local name = reset("3. an out-of-order accomplishment banks and waits")
	local p = profileOf(name)
	fact(name, { kind = "Encounter", phase = "opened", enemyType = "Warden" })
	check(unlocked(name) == 0, "a Warden met on floor one unlocked " .. unlocked(name))
	check(p.codex.journal.banked.FirstWardenEncounter == true, "the encounter was not banked")
	check(#toasts() == 0, "banking toasted")
end

do
	local name = reset("4. a missing source blocks its successors and nothing else")
	clearFloor(name, 5)
	topOut(name, 1)
	check(unlocked(name) == 3, "expected 3, got " .. unlocked(name))
	-- 4 is FirstWatcherSpotted. Everything after it is earned and must stay dark.
	fact(name, { kind = "Encounter", phase = "opened", enemyType = "Warden" })
	fact(name, { kind = "MimicRevealed" })
	topOut(name, 9)
	check(unlocked(name) == 3, "fragments jumped a gap, at " .. unlocked(name))
	fact(name, { kind = "Encounter", phase = "opened", enemyType = "Watcher" })
	check(unlocked(name) >= 4, "the gap did not open when its source arrived")
end

do
	local name = reset("5. witnesses bank from saved data with nothing fired")
	local p = profileOf(name)
	p.stats.eggsHatched = 1
	fireReady(name)
	drain()
	local banked = p.codex.journal.banked
	check(banked.FirstEggAcquired == true, "a hatch does not imply an egg acquired")
	check(banked.FirstEggPlaced == true, "a hatch does not imply an egg placed")
	check(banked.FirstHatch == true, "a hatch was not witnessed")
	check(banked.FirstEvolution == nil, "an evolution was witnessed that never happened")

	p.pets = { u1 = { stage = 1 } }
	petsChanged:Fire({ player = name })
	drain()
	check(banked.FirstEvolution == true, "a stage 1 pet was not witnessed as an evolution")
end

do
	local name = reset("6. an encounter qualifier is required, not decorative")
	local p = profileOf(name)
	fact(name, { kind = "Encounter", phase = "survived", enemyType = "Shrieker", marks = {} })
	check(p.codex.journal.banked.FirstShriekerSurvived == nil, "a Shrieker that never screamed banked a scream")
	fact(name, { kind = "Encounter", phase = "survived", enemyType = "Shrieker", marks = { screamed = true } })
	check(p.codex.journal.banked.FirstShriekerSurvived == true, "a scream survived did not bank")

	fact(name, { kind = "Encounter", phase = "survived", enemyType = "Gatekeeper", reason = "lost" })
	check(p.codex.journal.banked.FirstGatekeeperLeashSurvived == nil, "losing sight banked as a leash reset")
	fact(name, { kind = "Encounter", phase = "survived", enemyType = "Gatekeeper", reason = "leash" })
	check(p.codex.journal.banked.FirstGatekeeperLeashSurvived == true, "a leash reset did not bank")
end

do
	local name = reset("7. the whole trail, every fragment reachable")
	local p = profileOf(name)
	local Journal = MODULES.Journal

	-- Everything an Event fragment needs, banked up front and out of order, then
	-- the stats walked up. If sequencing works, the seventeen come out in order
	-- however they went in.
	fact(name, { kind = "Encounter", phase = "survived", enemyType = "Warden" })
	fact(name, { kind = "Encounter", phase = "survived", enemyType = "Gatekeeper", reason = "leash" })
	fact(name, { kind = "Encounter", phase = "opened", enemyType = "Warden" })
	fact(name, { kind = "ShadowFrozen" })
	fact(name, { kind = "MimicRevealed" })
	fact(name, { kind = "Encounter", phase = "survived", enemyType = "Shrieker", marks = { screamed = true } })
	fact(name, { kind = "SevenDayStreak" })
	fact(name, { kind = "Encounter", phase = "opened", enemyType = "Watcher" })
	p.stats.eggsHatched = 1
	p.pets = { u1 = { stage = 1 } }
	petsChanged:Fire({ player = name })
	drain()
	check(unlocked(name) == 0, "an Event-only profile unlocked without clearing a floor")

	clearFloor(name, 5)
	topOut(name, 10)
	check(unlocked(name) == #Journal, "expected all " .. #Journal .. ", got " .. unlocked(name))
	check(published(name) == #Journal, "the attribute says " .. tostring(published(name)) .. " at the end of the trail")

	local t = toasts()
	check(#t == #Journal, "expected " .. #Journal .. " toasts, got " .. #t)
	local ordered = true
	for i, payload in ipairs(t) do
		if payload.index ~= i or payload.id ~= Journal[i].id then
			ordered = false
		end
		if payload.total ~= #Journal then
			ordered = false
		end
	end
	check(ordered, "toasts did not walk the array in order")
	check(t[#t].id == "day_53", "the last fragment is " .. tostring(t[#t].id))
end

do
	local name = reset("8. an existing save catches up in one line, not seventeen")
	local p = profileOf(name)
	p.stats.floorsCleared = 40
	p.stats.summitsReached = 30
	p.stats.eggsHatched = 4
	p.pets = { u1 = { stage = 2 } }
	fireReady(name)
	drain()
	local t = toasts()
	check(#t == 1, "a backlog toasted " .. #t .. " times")
	check(t[1] and t[1].kind == "caughtUp", "the catch-up was not summarised")
	check(t[1] and t[1].count == unlocked(name), "the summary count disagrees with the unlock count")
	check(unlocked(name) == 3, "expected 3 from stats alone, got " .. unlocked(name))
	-- The quiet path publishes too. It is the one that matters most: a returning
	-- player is exactly the client that would otherwise stand in an unwritten
	-- maze until it earned something.
	check(published(name) == 3, "a quiet catch-up published " .. tostring(published(name)))

	-- And live play after it is loud again.
	-- And live play after it is loud again. Four of the five it releases were
	-- banked by the witnesses above, so the run is the point: the catch-up is
	-- quiet because it is a load, not because a backlog is.
	FIRED = {}
	fact(name, { kind = "Encounter", phase = "opened", enemyType = "Watcher" })
	local live = toasts()
	check(#live == 5, "a live unlock released " .. #live .. " fragments, expected 5")
	check(live[1] and live[1].kind == "unlocked", "a live unlock did not toast as one")
	check(unlocked(name) == 8, "expected 8 after the Watcher, got " .. unlocked(name))
end

do
	local name = reset("9. nothing unlocks twice")
	clearFloor(name, 5)
	topOut(name, 1)
	local before = #toasts()
	for _ = 1, 5 do
		fireReady(name)
		petsChanged:Fire({ player = name })
		progress:Fire({ kind = "floor", player = name })
	end
	drain()
	check(#toasts() == before, "re-checking re-toasted " .. (#toasts() - before) .. " fragments")
end

print("")
if failures > 0 then
	-- Level 0 so the message is the message rather than a stack trace, and so the
	-- CLI exits non-zero: this is meant to be runnable as a check, not only read.
	error(failures .. " failures", 0)
end
print("lore: all checks passed")
