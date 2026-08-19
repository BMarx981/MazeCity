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

local function reset(name)
	print(name)
	FIRED = {}
	DEFERRED = {}
	return newProfile(name)
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
	local p = reset("1. a fresh save unlocks nothing")
	fireReady("1. a fresh save unlocks nothing")
	drain()
	check(unlocked("1. a fresh save unlocks nothing") == 0, "fresh profile unlocked " .. unlocked("1. a fresh save unlocks nothing"))
	check(#toasts() == 0, "fresh profile toasted")
	check(p.codex.journal.banked.FirstHatch == nil, "fresh profile banked a hatch")
end

do
	local name = "2. stat triggers land in order"
	reset(name)
	clearFloor(name, 1)
	check(unlocked(name) == 1, "one floor should unlock exactly 1, got " .. unlocked(name))
	clearFloor(name, 3)
	check(unlocked(name) == 1, "four floors is still 1, got " .. unlocked(name))
	clearFloor(name, 1)
	check(unlocked(name) == 2, "five floors should unlock 2, got " .. unlocked(name))
	topOut(name, 1)
	check(unlocked(name) == 3, "first summit should unlock 3, got " .. unlocked(name))
	local t = toasts()
	check(#t == 3, "three toasts expected, got " .. #t)
	check(t[1].index == 1 and t[2].index == 2 and t[3].index == 3, "toasts out of order")
	check(t[1].day == 1, "fragment 1 is day " .. tostring(t[1].day))
end

do
	local name = "3. an out-of-order accomplishment banks and waits"
	local p = reset(name)
	fact(name, { kind = "Encounter", phase = "opened", enemyType = "Warden" })
	check(unlocked(name) == 0, "a Warden met on floor one unlocked " .. unlocked(name))
	check(p.codex.journal.banked.FirstWardenEncounter == true, "the encounter was not banked")
	check(#toasts() == 0, "banking toasted")
end

do
	local name = "4. a missing source blocks its successors and nothing else"
	reset(name)
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
	local name = "5. witnesses bank from saved data with nothing fired"
	local p = reset(name)
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
	local name = "6. an encounter qualifier is required, not decorative"
	local p = reset(name)
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
	local name = "7. the whole trail, every fragment reachable"
	local p = reset(name)
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
	local name = "8. an existing save catches up in one line, not seventeen"
	local p = reset(name)
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
	local name = "9. nothing unlocks twice"
	reset(name)
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
