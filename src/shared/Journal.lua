-- Journal (ModuleScript) -> ReplicatedStorage.Journal
-- The Cartographer's Trail, seventeen fragments of one climber's journal, told
-- entirely through wall writings. Content, alongside Lore: docs/LORE.MD Section
-- 9 is the source of truth for every line here and for the order they come in.
--
-- **Array order is unlock order.** Fragments unlock strictly in sequence: a
-- trigger only counts once every earlier fragment is unlocked, and an
-- accomplishment that arrives out of order is banked and granted when its turn
-- comes. That is why the profile stores a count rather than a set, and it is
-- why reordering this array is a content decision with a real effect on pacing:
-- LORE.MD says as much, the current order being a best guess at the director's
-- real encounter pacing.
--
-- `day` carries the dateline, so `text` never repeats it. The Codex draws
-- "Day 41" from the number and the sentence from the string.
--
-- `hint` is what the Codex prints under a locked row's `???` (LORE.MD 6.2 and
-- 9.2), and it is required of every fragment rather than optional: a locked row
-- with nothing under it reads as a bug rather than as a thing to go and do. It
-- is deliberately blunter and shorter than the fragment it hides, names no
-- mechanic a player has to have met, and explains nothing.
--
-- Two trigger kinds, and they need different treatment from whatever service
-- reads them. A `Stat` trigger reads a running total in the profile, so late
-- satisfaction is free to detect and it banks nothing. An `Event` trigger
-- leaves no total behind, so the first time one happens it is banked in the
-- codex and the bank is re-read on every unlock.
--
-- Stat triggers name `floorsCleared` and `summitsReached` and the check at the
-- bottom refuses any other, `mazesCompleted` above all: that field counts
-- whatever Config.Pets.HatchUnit currently says a maze is, so a fragment gated
-- on it would have its pacing silently rewritten by a config flip meant for
-- eggs.

-- The module is the array itself, per LORE.MD 9.3, so `#Journal` is the
-- chapter's size and ipairs walks it in unlock order.
local Journal = {
	{
		id = "day_1",
		day = 1,
		text = "I came here to map it. How hard can a maze be?",
		hint = "Finish a floor.",
		trigger = { type = "Stat", stat = "floorsCleared", value = 1 },
	},
	{
		id = "day_3",
		day = 3,
		text = "Finished mapping the third floor. Woke up. There is a different third floor now.",
		hint = "Finish five.",
		trigger = { type = "Stat", stat = "floorsCleared", value = 5 },
	},
	{
		id = "day_9",
		day = 9,
		text = "The walls moved again. I have stopped drawing in ink.",
		hint = "Reach a roof.",
		trigger = { type = "Stat", stat = "summitsReached", value = 1 },
	},
	-- Pays off the Cracked Lantern's "Recovered from Floor 12" inscription, on
	-- the day the gear economy ships one. A player who connects them gets the
	-- moment; a player who does not loses nothing.
	{
		id = "day_11",
		day = 11,
		text = "The Maze grew an eye at the end of the corridor. It saw me first. Everything came.",
		hint = "Be seen.",
		trigger = { type = "Event", event = "FirstWatcherSpotted" },
	},
	{
		id = "day_14",
		day = 14,
		text = "Found something warm inside a wall the Maze hadn't finished. It is not a stone.",
		hint = "Find something warm.",
		trigger = { type = "Event", event = "FirstEggAcquired" },
	},
	{
		id = "day_15",
		day = 15,
		text = "Carried it to the top. The summit is the only place my maps still work.",
		hint = "Carry it to the top.",
		trigger = { type = "Event", event = "FirstEggPlaced" },
	},
	{
		id = "day_16",
		day = 16,
		text = "It hatched where the Maze can't reach, and it came out free. It glows. It already knows the way down.",
		hint = "Wait for it to open.",
		trigger = { type = "Event", event = "FirstHatch" },
	},
	{
		id = "day_22",
		day = 22,
		text = "It grows faster than the Maze does. I think that frightens the walls.",
		hint = "Let one grow.",
		trigger = { type = "Event", event = "FirstEvolution" },
	},
	{
		id = "day_25",
		day = 25,
		text = "It didn't want to hurt me. It wanted everything else to. I ran before the echo finished.",
		hint = "Survive the bell.",
		trigger = { type = "Event", event = "FirstShriekerSurvived" },
	},
	-- Reinforces the no-coin-Mimic rule inside the story itself, which is the
	-- other half of the Mimic's Codex line.
	{
		id = "day_30",
		day = 30,
		text = "The lamp was not a lamp. I trust the coins and nothing else now.",
		hint = "Catch something pretending.",
		trigger = { type = "Event", event = "FirstMimicRevealed" },
	},
	-- Teaches the Shadow's counter-play as the Cartographer's own coping
	-- behavior: keep it watched and it cannot move.
	{
		id = "day_33",
		day = 33,
		text = "Something follows me that only moves when I look away. I have started walking backward.",
		hint = "Watch what follows you.",
		trigger = { type = "Event", event = "FirstShadowFrozen" },
	},
	-- Deliberately incomplete. Day 41 finishes the thought behind a seven day
	-- streak, which makes the story itself enforce the daily loop.
	{
		id = "day_40",
		day = 40,
		text = "I was wrong about everything. The Maze is not a wall.",
		hint = "Top out five towers.",
		trigger = { type = "Stat", stat = "summitsReached", value = 5 },
	},
	-- The one trigger in the table that reads like a stat and is not. The
	-- profile's streak counts daily claims and wraps back to 1 past seven, so
	-- this can only be caught at the claim itself and can never be a poll.
	{
		id = "day_41",
		day = 41,
		text = "It builds every night. Shells grow before the thing inside them does.",
		hint = "Come back seven nights.",
		trigger = { type = "Event", event = "SevenDayStreak" },
	},
	-- Teaches the Gatekeeper's leash as advice from a survivor. Its source is
	-- the reason an encounter's close carries one: EnemyTargeting drops a held
	-- target for exactly two reasons, and outrunning a leash is the one this
	-- fragment is about.
	{
		id = "day_44",
		day = 44,
		text = "Even the doors hunt now. But they always go home. Remember that. They always go home.",
		hint = "Outlast a door.",
		trigger = { type = "Event", event = "FirstGatekeeperLeashSurvived" },
	},
	-- Pays off the Cartographer's Satchel inscription the way day 11 pays off
	-- the lantern.
	{
		id = "day_47",
		day = 47,
		text = "Lost my satchel today. Floor 47 wants me to forget what I mapped. I won't.",
		hint = "Top out ten towers.",
		trigger = { type = "Stat", stat = "summitsReached", value = 10 },
	},
	{
		id = "day_50",
		day = 50,
		text = "Something on the high floors wears a climber's boots. It walked like it remembered walking.",
		hint = "Meet what the high floors keep.",
		trigger = { type = "Event", event = "FirstWardenEncounter" },
	},
	-- The end of the story, and it spawns only at the Nest, which is where
	-- every run of the player's own already ends.
	{
		id = "day_53",
		day = 53,
		text = "If you are reading this, the Maze finished my map for me. Leave the eggs at the Nest. Keep climbing. Do not look for me in the walls.",
		hint = "Walk away from it.",
		trigger = { type = "Event", event = "FirstWardenSurvived" },
		nestOnly = true,
	},
}

-- ============================================================
-- Validation
-- ============================================================
-- Same posture as Lore's key check and for the same reason: a fragment nothing
-- can ever satisfy looks exactly like a fragment whose service is broken.

local ALLOWED_STATS = {
	floorsCleared = true,
	summitsReached = true,
}

local seenIds = {}
local seenEvents = {}

for index, fragment in ipairs(Journal) do
	if type(fragment.id) ~= "string" or fragment.id == "" then
		error(string.format("Journal: fragment %d has no id", index))
	end
	if seenIds[fragment.id] then
		error(string.format("Journal: %q is used by two fragments", fragment.id))
	end
	seenIds[fragment.id] = true

	-- Required, not optional. A fragment with no hint is a Codex row that says
	-- `???` and nothing else, which is indistinguishable from one whose service
	-- is broken.
	if type(fragment.hint) ~= "string" or fragment.hint == "" then
		error(string.format("Journal: %q has no locked hint", fragment.id))
	end

	local trigger = fragment.trigger
	if type(trigger) ~= "table" then
		error(string.format("Journal: %q has no trigger", fragment.id))
	end

	if trigger.type == "Stat" then
		if not ALLOWED_STATS[trigger.stat] then
			error(
				string.format(
					"Journal: %q triggers on stat %q, which is not one the journal may read",
					fragment.id,
					tostring(trigger.stat)
				)
			)
		end
		if type(trigger.value) ~= "number" or trigger.value <= 0 then
			error(string.format("Journal: %q has no threshold on its stat trigger", fragment.id))
		end
	elseif trigger.type == "Event" then
		if type(trigger.event) ~= "string" or trigger.event == "" then
			error(string.format("Journal: %q has no event on its event trigger", fragment.id))
		end
		-- Two fragments on one event would both unlock the moment it banks, so
		-- the second would land without ever having been earned.
		if seenEvents[trigger.event] then
			error(string.format("Journal: %q is the trigger for two fragments", trigger.event))
		end
		seenEvents[trigger.event] = true
	else
		error(string.format("Journal: %q has trigger type %q", fragment.id, tostring(trigger.type)))
	end
end

return Journal
