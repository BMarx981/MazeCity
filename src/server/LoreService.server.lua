-- LoreService (Script) -> ServerScriptService
-- The Cartographer's Trail, per docs/LORE.MD Section 9.1 and PETS_PLAN.md
-- Clutch 7 unit 3. Owns the whole of "which fragment is next and has it been
-- earned yet", and owns nothing about what a fragment says: the seventeen lines
-- and the order they come in are content in ReplicatedStorage.Journal.
--
-- **Fragments unlock strictly in order, so the profile stores a count.** A
-- trigger only counts once every earlier fragment is unlocked, which is why the
-- unlock loop below re-asks after every advance rather than sweeping the array:
-- an unlock can make its own successor immediately satisfiable, and a player who
-- has already done the next four things gets four toasts in a row.
--
-- The two trigger kinds need different treatment and that is the substance of
-- this file.
--
--  * A **Stat** trigger reads a running total in the profile, so late
--    satisfaction is free to detect and it banks nothing. `data.stats` is still
--    true whenever the fragment gets around to asking.
--  * An **Event** trigger leaves no total behind, so it is remembered in
--    `codex.journal.banked` the first time it happens and the bank is re-read on
--    every unlock. Two things put a flag there and they are the reason this file
--    has two halves. A **fact** arrives on a channel from the service that held
--    the moment. A **witness** is a predicate over the profile itself, for the
--    four pet-side fragments the saved data already remembers: an egg in the
--    shelf, an incubator with something in it, a hatch counter, a pet past its
--    first stage.
--
-- A witness banks rather than being consulted at unlock time, which is the one
-- thing about this worth stating twice: the predicate is a *detector*, the bank
-- is the *record*. Pet release does not exist yet and eggs cannot be taken back
-- out of a roost, so every witness happens to be monotonic today, and the day
-- one of them stops being monotonic is the day a player would otherwise watch a
-- fragment they had earned go dark again.
--
-- What the journal is never told: which fragment a fact was for. A service fires
-- what happened (a Watcher spotted somebody, an encounter was survived), and the
-- two tables below are the only place those facts and the fragment ids meet, so
-- reordering the array or renaming a fragment reaches no other file.
--
-- The journal is one of four chapters and it is the only one with a rule. The
-- other two that have anything in them are records rather than decisions, and
-- they are here because this is already the file listening to both channels
-- they come off (PETS_PLAN.md Clutch 7 unit 5). `codex.kept` is a stage, 1 for
-- met and 2 for survived, raised and never lowered, taken off the same
-- encounter pair the journal reads facts from and taken for **every** type
-- rather than the four the trail names: what an encounter is worth to the
-- journal is a decision, what it is worth to the Codex is a fact. `codex.pets`
-- is a witness in exactly the sense above, the profile's own pet list read on
-- every re-check, so a hatch banks a page without IncubatorService learning
-- that a Codex exists. `codex.relics` has no writer and will not until
-- Lore.relics has a row in it (LORE.MD Section 5).
--
-- What the client is sent is **unlock state and nothing else**: a count, a stage
-- per Kept, a set of pet ids. Every line of text and every picture the Codex
-- draws is already on the client in ReplicatedStorage.Journal, ReplicatedStorage
-- .Lore and the two rig generators, so the chapter costs the same on the wire
-- whether a player has one entry or all of them. It is pushed rather than
-- requested, so a client that joined late is correct on its first frame, and it
-- is pushed only when something in it actually moved: an encounter opens every
-- time an enemy notices somebody, and a projection per notice is a projection
-- per notice.
--
-- How far the trail has got leaves as a **replicated player attribute** and not
-- only on the remote, which is the rule AbilityService's tiers already follow
-- and for the same reason: the wall writings are drawn from it, and a returning
-- player with nine fragments unlocks nothing on join, so a client waiting to be
-- told would stand in a maze with nothing written on it until it earned the
-- tenth. The remote still carries the events, because a toast is a moment and an
-- attribute is a state. The Cartographer title is the second attribute and it
-- is published on the same rule, being the same kind of thing: a state a client
-- has to be right about on its first frame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local Journal = require(ReplicatedStorage:WaitForChild("Journal"))
local Profiles = require(ServerScriptService:WaitForChild("PlayerProfiles"))
-- For one thing only: the 17/17 reward is a pet, and it is granted through the
-- same function every hatch goes through so that a full shelf refuses it the
-- same way. Nothing else in this file knows what a pet is.
local Inventory = require(ServerScriptService:WaitForChild("PetInventory"))

local function findOrCreate(parent, className, name)
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local made = Instance.new(className)
	made.Name = name
	made.Parent = parent
	return made
end

local remote = findOrCreate(ReplicatedStorage, "RemoteEvent", "LoreUpdate")
-- The Codex's one request. Every projection after it is pushed, so this is not
-- a poll and there is nothing to ask for twice: it exists because a remote
-- fired at a player whose LocalScripts have not connected yet is a chapter that
-- never arrives, and a player who opens the panel before their next floor would
-- be told they have nothing.
local intents = findOrCreate(ReplicatedStorage, "RemoteEvent", "LoreIntent")
local progress = findOrCreate(ServerScriptService, "BindableEvent", "MazeProgress")
local petsChanged = findOrCreate(ServerScriptService, "BindableEvent", "PetsChanged")
local channel = findOrCreate(ServerScriptService, "BindableEvent", "LoreEvent")

-- ============================================================
-- Facts to fragment events
-- ============================================================
-- The one place the enemy system's vocabulary and the journal's meet. EnemyLore
-- states that a type opened or survived an encounter and this decides what that
-- is worth, which is why adding a fragment about the Trapper is an edit here and
-- nowhere in the AI.
--
-- `survived` is the enemy giving up while the player is alive, and the two
-- qualifiers are what keep a fragment honest about what it claims. A Shrieker
-- that chased somebody and never screamed is not a scream survived, so the
-- Shrieker row wants the `screamed` mark the behavior puts on the encounter. A
-- Gatekeeper that lost sight of somebody is not a leash reset, so its row wants
-- the reason EnemyLore reads off the close.

local ENCOUNTER = {
	Watcher = { opened = "FirstWatcherSpotted" },
	Warden = { opened = "FirstWardenEncounter", survived = "FirstWardenSurvived" },
	Shrieker = { survived = "FirstShriekerSurvived", mark = "screamed" },
	Gatekeeper = { survived = "FirstGatekeeperLeashSurvived", reason = "leash" },
}

-- Facts that are not an encounter's ends. Keyed by the fact, valued by the
-- fragment event, so the two names may differ and usually should: the left is
-- what an enemy did, the right is what the journal calls it.
local MOMENT = {
	MimicRevealed = "FirstMimicRevealed",
	ShadowFrozen = "FirstShadowFrozen",
	SevenDayStreak = "SevenDayStreak",
}

-- ============================================================
-- Witnesses
-- ============================================================
-- Event triggers the saved profile already answers, so no service has to fire
-- them. Each is read on every re-check and banks the first time it is true.
--
-- The three egg ones are written to survive their own subject disappearing: an
-- egg acquired stops being in the shelf the moment it is placed, and an egg
-- placed stops being in the roost the moment it hatches, so each predicate ors
-- in the states that can only be reached through it.

local WITNESS = {
	FirstEggAcquired = function(data)
		-- next() rather than a length: both collections are maps keyed by uid, so
		-- the # of either is always zero.
		return next(data.eggs) ~= nil or data.incubator ~= nil or data.stats.eggsHatched > 0
	end,
	FirstEggPlaced = function(data)
		return data.incubator ~= nil or data.stats.eggsHatched > 0
	end,
	FirstHatch = function(data)
		return data.stats.eggsHatched > 0
	end,
	FirstEvolution = function(data)
		for _, pet in pairs(data.pets) do
			if (pet.stage or 0) > 0 then
				return true
			end
		end
		return false
	end,
}

-- ============================================================
-- Unlocking
-- ============================================================

local function journalOf(data)
	-- Defensive against a profile written before the codex existed. adopt already
	-- fills it, and this is one comparison against the alternative of a fragment
	-- that unlocks into nothing on a save from an older build.
	local codex = data.codex
	if not codex or not codex.journal then
		return nil
	end
	return codex.journal
end

-- The attributes this service writes, and the count is the whole of what a
-- client needs to draw a writing: the fragments themselves are content in
-- ReplicatedStorage.Journal, which every client already has, so a count is all
-- that crosses the wire and nothing about a line has to be sent twice. The
-- title is stamped on the same terms and only ever earned, never taken back.
local function publish(player, journal)
	player:SetAttribute("JournalUnlocked", journal.unlocked)
	if journal.unlocked >= #Journal then
		player:SetAttribute("CodexTitle", Config.Lore.CompletionTitle)
	end
end

-- ============================================================
-- The other chapters
-- ============================================================
-- Records rather than rules. Neither of these decides anything: one writes down
-- that a thing was met, the other that a thing was hatched, and what either is
-- worth saying is the Codex's to draw from Lore.

local KEPT_MET = 1
local KEPT_SURVIVED = 2

-- Raised and never lowered, so an encounter survived cannot be undone by the
-- next one that merely happened, and the order the two arrive in does not
-- matter. Every type, not the four the trail names: the journal picks its
-- moments, the Codex counts them all.
local function recordKept(data, enemyType, stage)
	if type(enemyType) ~= "string" then
		return false
	end
	local kept = data.codex.kept
	if (kept[enemyType] or 0) >= stage then
		return false
	end
	kept[enemyType] = stage
	return true
end

-- A witness in the sense the header names, over the pet list the profile
-- already keeps: owning one is the record that it hatched, so nothing in the
-- incubator or the pet service has to fire anything. It banks rather than being
-- derived at draw time for the reason every witness here does, which pet
-- release is the day it matters: a page read is a page kept.
local function witnessPets(data)
	local pets = data.codex.pets
	local gained = false
	for _, pet in pairs(data.pets) do
		if pet.petId and not pets[pet.petId] then
			pets[pet.petId] = true
			gained = true
		end
	end
	return gained
end

-- Unlock state and nothing else. The tables go over the wire as copies, which
-- is the engine's doing rather than a precaution, but it is also why this can
-- hand over the profile's own chapters without a client holding a reference to
-- anything the server writes.
local function push(player, data, journal)
	if not Config.Lore.CodexEnabled then
		return
	end
	remote:FireClient(player, {
		kind = "codex",
		unlocked = journal.unlocked,
		total = #Journal,
		kept = data.codex.kept,
		pets = data.codex.pets,
		relics = data.codex.relics,
		title = journal.unlocked >= #Journal and Config.Lore.CompletionTitle or nil,
	})
end

-- The one reward LORE.MD 9.2 writes down, and the only thing in this file that
-- hands a player something. It goes through the grant every hatch goes through,
-- so a full shelf refuses it; `rewarded` is therefore set by the grant landing
-- and not by the trail finishing, and an unpaid one is tried again on every
-- later re-check. Announced on the remote rather than banked into the toast
-- queue's fragment shape, a reward being a different sentence from a fragment.
local function payCompletion(player, data, journal)
	if journal.rewarded or journal.unlocked < #Journal then
		return false
	end
	local ok = Inventory.grantPet(data, Config.Lore.CompletionPet)
	if not ok then
		return false
	end
	journal.rewarded = true
	petsChanged:Fire({ player = player })
	remote:FireClient(player, {
		kind = "completed",
		total = #Journal,
		title = Config.Lore.CompletionTitle,
		petId = Config.Lore.CompletionPet,
	})
	return true
end

local function satisfied(data, journal, fragment)
	local trigger = fragment.trigger
	if trigger.type == "Stat" then
		return (data.stats[trigger.stat] or 0) >= trigger.value
	end
	return journal.banked[trigger.event] == true
end

local function announce(player, index)
	local fragment = Journal[index]
	remote:FireClient(player, {
		kind = "unlocked",
		index = index,
		total = #Journal,
		id = fragment.id,
		day = fragment.day,
		text = fragment.text,
	})
end

-- The whole of the unlock rule. Only ever the next locked fragment, and the loop
-- re-asks after each advance because an unlock can make its successor
-- satisfiable in the same instant: everything banked before its turn came up
-- lands here, in order, one toast each.
--
-- `quiet` is the one caller that is not a player doing something. A profile
-- landing re-derives every witness from saved data, so every fragment it finds
-- was earned in some earlier session and possibly under a build where this
-- service did not exist: an existing save joining for the first time clears its
-- whole backlog in one pass, and toasting each of those is a minute and a half
-- of chip for somebody who did nothing. It is summarised into one line instead,
-- which also means nothing important is lost if it arrives before the client's
-- own GUI has connected. Live play is never quiet, and cannot be: nothing is
-- earned during a load.
local function recheck(player, quiet)
	local data = Profiles.data(player)
	if not data then
		return
	end
	local journal = journalOf(data)
	if not journal then
		return
	end

	for event, witness in pairs(WITNESS) do
		if not journal.banked[event] and witness(data) then
			journal.banked[event] = true
		end
	end

	local moved = witnessPets(data)
	local gained = 0
	while journal.unlocked < #Journal do
		local fragment = Journal[journal.unlocked + 1]
		if not satisfied(data, journal, fragment) then
			break
		end
		journal.unlocked = journal.unlocked + 1
		gained = gained + 1
		if not quiet then
			announce(player, journal.unlocked)
		end
	end

	-- Stamped on every re-check and not only on a gain, because the first
	-- re-check a player gets is their profile landing: a rejoining player whose
	-- count has not moved still needs it published once or their maze is blank.
	publish(player, journal)

	if payCompletion(player, data, journal) then
		moved = true
	end
	-- Quiet is a join, and a join is exactly the client that has nothing yet, so
	-- it pushes whether or not anything moved. The rest push only on a change.
	if quiet or gained > 0 or moved then
		push(player, data, journal)
	end

	if quiet and gained > 0 then
		remote:FireClient(player, {
			kind = "caughtUp",
			count = gained,
			index = journal.unlocked,
			total = #Journal,
		})
	end
end

local function bank(player, event)
	if not event then
		return
	end
	local data = Profiles.data(player)
	if not data then
		return
	end
	local journal = journalOf(data)
	if not journal or journal.banked[event] then
		return
	end
	journal.banked[event] = true
	recheck(player)
end

-- ============================================================
-- Channels
-- ============================================================

-- Deferred, and it is load-bearing rather than tidy. PetService is the only
-- writer of data.stats and it writes them from its own MazeProgress handler, so
-- a check that ran synchronously would read the total from before the floor that
-- fired it whenever this script happened to connect first. Which of the two
-- connected first is not a thing either file can know.
--
-- The same sentence names the one coupling worth knowing about: every Stat
-- trigger in the journal is downstream of that writer, so Config.Pets.Enabled
-- turned off is five fragments that never come up and the twelve behind them
-- sitting still. Deliberate rather than defended against, the flag being an
-- off switch for a whole system and not a tuning knob.
progress.Event:Connect(function(payload)
	if not Config.Lore.Enabled or not payload or not payload.player then
		return
	end
	task.defer(recheck, payload.player)
end)

petsChanged.Event:Connect(function(payload)
	if not Config.Lore.Enabled or not payload or not payload.player then
		return
	end
	task.defer(recheck, payload.player)
end)

channel.Event:Connect(function(payload)
	if not Config.Lore.Enabled or not payload or not payload.player then
		return
	end

	if payload.kind == "Encounter" then
		-- The Codex half runs for every type and before any of the journal's
		-- qualifiers, because a Shrieker that never screamed is still a Shrieker
		-- somebody met: the qualifiers say what a fragment may claim, not what
		-- was in the corridor.
		local data = Profiles.data(payload.player)
		local journal = data and journalOf(data)
		if journal then
			local stage = payload.phase == "survived" and KEPT_SURVIVED or KEPT_MET
			if recordKept(data, payload.enemyType, stage) then
				push(payload.player, data, journal)
			end
		end

		local row = ENCOUNTER[payload.enemyType]
		if not row then
			return
		end
		if row.mark and not (payload.marks and payload.marks[row.mark]) then
			return
		end
		if row.reason and payload.reason ~= row.reason then
			return
		end
		bank(payload.player, row[payload.phase])
		return
	end

	bank(payload.player, MOMENT[payload.kind])
end)

-- Answered rather than trusted: a sync carries nothing, and the reply is the
-- same projection every other caller sends, so the worst a client can do by
-- asking repeatedly is be told what it already knows. The floor is one reply
-- per SyncSeconds, which is generous for a join and useless as a way to make
-- the server work.
local lastSync = {}

intents.OnServerEvent:Connect(function(player, payload)
	if not Config.Lore.CodexEnabled or type(payload) ~= "table" or payload.kind ~= "sync" then
		return
	end
	local now = os.clock()
	if lastSync[player] and now - lastSync[player] < Config.Lore.SyncSeconds then
		return
	end
	lastSync[player] = now

	local data = Profiles.data(player)
	local journal = data and journalOf(data)
	if journal then
		push(player, data, journal)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastSync[player] = nil
end)

-- A profile landing is itself a re-check: every witness is a fact about saved
-- data, and a returning player whose stats already clear the next fragment has
-- earned it whether or not they climb anything this session. Replays for players
-- already loaded, so registration order does not matter.
Profiles.onReady(function(player)
	if Config.Lore.Enabled then
		recheck(player, true)
	end
end)
