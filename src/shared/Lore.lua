-- Lore (ModuleScript) -> ReplicatedStorage.Lore
-- Player-facing flavour text, keyed by the ids of the things it describes.
-- Content, the same bargain PetCatalog and EnemyDefinitions strike: it grows by
-- entries where tuning grows by edits, and nothing here runs at gameplay time.
--
-- docs/LORE.MD is the source of truth for every line in this file. Text is
-- written there and copied here, never the other way around, so a line changed
-- in a branch is changed in both or in neither.
--
-- A key mirrors the case of the table it points at rather than one blanket
-- convention, because the sources do not agree with each other:
-- EnemyDefinitions.types is PascalCase and the three catalogues key on a
-- snake_case `id`. CLAUDE.md's PascalCase rule governs attributes, tags and
-- config keys; a catalogue id is content and is spelled the way its catalogue
-- spells it.
--
-- The check at the bottom runs one way only: every key here must resolve to a
-- real id, while an id with no lore is legal and simply has no flavour text.
-- That is what makes a typo a startup error rather than a Codex row that
-- silently never appears, and it is why the two coverage conflicts in
-- docs/PETS_PLAN.md cannot come back unnoticed.

local PetCatalog = require(script.Parent:WaitForChild("PetCatalog"))
local EggCatalog = require(script.Parent:WaitForChild("EggCatalog"))
local EnemyDefinitions = require(script.Parent:WaitForChild("EnemyDefinitions"))
local AccessoryCatalog = require(script.Parent:WaitForChild("AccessoryCatalog"))

local Lore = {}

-- ============================================================
-- Pets
-- ============================================================
-- A pet's story explains its ability: the lore and the utility are the same
-- sentence. `evolutionLines` is positional against the catalogue's `evolutions`
-- array, so line 1 belongs to stage 2, and a line with no stage under it is
-- refused below. Firefly's second evolution "Solar" is written in LORE.MD and
-- is deliberately not here: PetCatalog ships one stage per pet, and text no
-- stage can ever show is text nobody reads.
--
-- `broadcastLine` is the same story at the length a server-wide banner holds,
-- and it is a second register rather than a duplicate (LORE.MD 2 and 6.1):
-- `hatchLine` is read by the one player standing at the roost, the short one by
-- everybody else mid-maze for two seconds. Absent means the broadcast quotes
-- nothing and names the rarity instead, which is the one-field rule `coinCost`
-- and `robuxProductId` already follow, so a new pet costs no line here.

Lore.pets = {
	firefly = {
		broadcastLine = "Nothing down there was lit, so it lit itself.",
		hatchLine = "Hatched in the lightless lower floors, where the only way to survive was to become the light.",
		evolutionLines = {
			"The dark floors fear it now.",
		},
	},
	lumen_moth = {
		broadcastLine = "It is the light, stretched thin as a corridor.",
		hatchLine = "It does not carry the light. It is the light, stretched thin enough to cross a whole corridor as one shape.",
		evolutionLines = {
			"It has been burning far longer than it has been alive. Whatever colour it started as is gone.",
		},
	},
	ward_hound = {
		broadcastLine = "The Maze never said what it was keeping out.",
		hatchLine = "The Maze built it to keep things out and never said out of where, so it decided that part for itself. It cannot hold forever, and it will not spend itself on an empty corridor.",
		evolutionLines = {
			"It stopped flinching a long time ago.",
		},
	},
	coin_bat = {
		broadcastLine = "It has never once put its first coin down.",
		hatchLine = "It found one coin a very long time ago and has never once put it down. Everything else it finds, it brings to you.",
		evolutionLines = {
			"Two coins now. It has not explained where the second one came from.",
		},
	},
	compass_crow = {
		broadcastLine = "It remembers every dead end.",
		hatchLine = "It has flown every corridor the Maze has ever built. It remembers all of them, especially the ones that go nowhere.",
		evolutionLines = {
			"It no longer follows the Maze. The Maze follows it.",
		},
	},
}

-- ============================================================
-- Eggs
-- ============================================================
-- Shown when the egg is acquired and while it is incubating. The Streak Egg's
-- line is read by a player who came back seven days running, and it answers
-- journal fragment 13 without either one naming the other.

Lore.eggs = {
	summit_common = { flavor = "Warm to the touch. Something inside is waiting for still ground." },
	summit_royal = { flavor = "The Maze rearranged three floors trying to stop this one from being found." },
	streak_seven = {
		flavor = "Seven nights of the Maze rebuilding itself, and this one did not move. Something in it has been counting too.",
	},
}

-- ============================================================
-- The Kept
-- ============================================================
-- One row per EnemyDefinitions row, twenty of them, and the design rule is that
-- the line explains the mechanic: a player who reads one sentence should play
-- better against that enemy. A Kept entry unlocks twice, silhouette and name on
-- first encounter and `loreLine` on surviving one, which is why the profile's
-- `codex.kept` holds a stage rather than a flag.
--
-- The Warden is the only row with a `survivalLine`, and it is the journal's
-- reveal landing in the Codex: it describes the dormant enrage, so the day
-- enrage ships it reads as a warning that was always there.

Lore.kept = {
	Drifter = {
		loreLine = "The first thing the Maze ever managed to finish. It has never once learned a corner.",
	},
	Stalker = {
		loreLine = "It will not close while you are watching, and that is a rule rather than a mercy. The corridor behind you is the only one it is interested in.",
	},
	Sentry = {
		loreLine = "It was given a place and never anything else to do but hold it. Every climber it ever took walked in knowing exactly where it stood.",
	},
	Swarmer = {
		loreLine = "Alone it is barely worth the name it was given. It knows that, and it does not intend to be alone for long.",
	},
	Lurker = {
		loreLine = "It is part of the room until you come close enough to be worth standing up for. Leave it alone long enough and it is part of the room again.",
	},
	Charger = {
		loreLine = "It commits. Once it has chosen its line it cannot choose another, and the wall it finds instead of you takes a moment to forgive.",
	},
	Watcher = {
		loreLine = "The Maze cannot see. So it grew eyes in the corridors where climbers kept getting past.",
	},
	Sprinter = {
		loreLine = "Built in one night, in a hurry. It runs like it, and it rests like it.",
	},
	Brute = {
		loreLine = "A piece of wall that learned to swing. It never learned to turn.",
	},
	Spitter = {
		loreLine = "It spits the mortar the Maze builds with. Wet, it slows you. It knows that.",
	},
	Blinker = {
		loreLine = "It doesn't use the corridors. It walks inside the walls, and it takes a moment to remember which side it came out on.",
	},
	Shrieker = {
		loreLine = "It was never meant to fight. It is the Maze's bell.",
	},
	-- Canonizes the no-coin-Mimic rule. The game spends every floor teaching
	-- players to grab coins; this guarantees that trust is never punished, and
	-- LORE.MD writing rule 6 locks it against any future deception mechanic.
	Mimic = {
		loreLine = "It practices copying the things the Maze built. It never copies coins. The coins were never the Maze's.",
	},
	Shadow = {
		loreLine = "The Maze taught it one rule: never move while a climber is watching. It has never broken it. It is very patient.",
	},
	Trapper = {
		loreLine = "It doesn't hunt. It gardens. The snares are roots the Maze hasn't grown yet.",
	},
	Burrower = {
		loreLine = "For it, the floors are just more corridors.",
	},
	Gatekeeper = {
		loreLine = "It was a door first. It still thinks like one. It will chase you, but it cannot bear to leave its frame for long.",
	},
	Splitter = {
		loreLine = "The Maze's answer to being broken: become two.",
	},
	SplitterChild = {
		loreLine = "Half the thing. Twice the grudge.",
	},
	Warden = {
		loreLine = "One to a building. It does not patrol its floors. It mourns them.",
		survivalLine = "Something in it is still asleep. Do not be there when it wakes.",
	},
}

-- ============================================================
-- Relics
-- ============================================================
-- Every accessory is a relic of a previous climber (LORE.MD Section 5), and the
-- design rule is Sections 2 and 3's read over gear: the inscription explains the
-- effect. `recovered` is the second half of the format and not decoration. It is
-- a floor number for everything the counter sells, that being the only address
-- this world has, and the two items no coin can reach say where they came from
-- instead. Floor 12 and Floor 47 are not free choices: the journal answers both
-- (Journal.lua, days 11 and 47), which is why renaming either item is a doc
-- change across two files rather than a config edit here.
--
-- `set` stays unwritten. The Cartographer's kit is already three items of this
-- table read in order, and a set with no set bonus is a grouping: a chapter that
-- groups by something nobody can complete is the meter that cannot fill, which
-- is the rule that keeps the Splitter Child out of the Kept denominator.

Lore.relics = {
	explorers_cap = {
		inscription = "Its owner marked the next three turns inside the brim, so they could be read without stopping.",
		recovered = "Recovered from Floor 3.",
	},
	lantern_hat = {
		inscription = "Still lit. Nobody has worked out what it is burning.",
		recovered = "Recovered from Floor 12.",
	},
	tin_crown = {
		inscription = "Beaten out of a ration tin by somebody who had decided they were going to be remembered.",
		recovered = "Recovered from Floor 8.",
	},
	cartographers_circlet = {
		inscription = "The Cartographer wore it to keep both hands free for the map. It reads a wall the hands would have had to touch.",
		recovered = "Recovered from Floor 40.",
	},
	gilded_crown = {
		inscription = "Worn by a climber who came down rich exactly once and went back up anyway.",
		recovered = "Recovered from Floor 22.",
	},
	beacon_crown = {
		inscription = "Lit every night for seven nights, so the floors below would know somebody was still up there.",
		recovered = "Recovered from seven days of returning.",
	},
	coin_chain = {
		inscription = "Every link is a coin somebody drilled through rather than spend. It has been pulling them in ever since.",
		recovered = "Recovered from Floor 5.",
	},
	bell_collar = {
		inscription = "A bell for a companion that kept getting lost. It learned the sound faster than it learned the corridor.",
		recovered = "Recovered from Floor 6.",
	},
	guard_collar = {
		inscription = "Cut from the padding of a climber's own coat, which is the whole of what a guard collar has ever been.",
		recovered = "Recovered from Floor 9.",
	},
	compass_pendant = {
		inscription = "It does not point north. It points at the wall that is lying about being a wall.",
		recovered = "Recovered from Floor 19.",
	},
	warm_amulet = {
		inscription = "Kept against the skin for a whole climb, because the thing it was warming could not be put down.",
		recovered = "Recovered from Floor 15.",
	},
	heartstone_locket = {
		inscription = "It is heavier than it looks and it has been hit harder than that. Whoever it was for did not need it in the end.",
		recovered = "Recovered from Floor 33.",
	},
	scrap_cape = {
		inscription = "Sewn from four other capes, none of whose owners are named on it.",
		recovered = "Recovered from Floor 2.",
	},
	runners_cloak = {
		inscription = "Cut short at the knee on purpose. Its owner had learned exactly what a long hem costs on a stair.",
		recovered = "Recovered from Floor 13.",
	},
	coin_satchel = {
		inscription = "The Cartographer lost one like it here and wrote the day down. This is not that one, and it is the same make.",
		recovered = "Recovered from Floor 47.",
	},
	phase_pack = {
		inscription = "It hums against a wall the way a held breath does. Two more seconds of being somewhere you are not.",
		recovered = "Recovered from Floor 28.",
	},
	moth_wings = {
		inscription = "Taken off nothing that ever flew. The Maze built them onto something and it learned anyway.",
		recovered = "Recovered from Floor 36.",
	},
	dust_motes = {
		inscription = "The air of the lower floors, kept in a jar and then let out again. It does nothing, and everybody wants it.",
		recovered = "Recovered from Floor 1.",
	},
	coin_glimmer = {
		inscription = "Struck off a hoard that was never carried down. What is left of it still leans towards money.",
		recovered = "Recovered from Floor 17.",
	},
	warding_sparks = {
		inscription = "It burns nothing and it stops nothing dead. It has still spent more time between a climber and the Kept than most gear ever will.",
		recovered = "Recovered from Floor 25.",
	},
	wayfinder_halo = {
		inscription = "The Cartographer's, near the end, when the map had stopped being on paper.",
		recovered = "Recovered from Floor 44.",
	},
	ember_trail = {
		inscription = "It has been alight since the Sanctum caught, which is longer than the district has had a name.",
		recovered = "Recovered from the Cinder Sanctum, still burning.",
	},
}

-- ============================================================
-- The city
-- ============================================================
-- The two chapters that name places rather than things, so neither is keyed by
-- a catalogue id and neither goes through checkKeys below. What checks them is
-- at the bottom: both are read by MazeGenerator at build time to compose a
-- tower's name, and an empty list there is a city of towers called nil.
--
-- Districts wrap. `Lore.districts[((section - 1) % #Lore.districts) + 1]`, which
-- is the whole of the rule and is why the list may grow or shrink freely: it
-- renames districts, it cannot break one. A city does not end, so the names
-- coming back around past section 8 is the intent and not an overflow.

Lore.districts = {
	"Lowwater",
	"Ashfall",
	"Thirdmarch",
	"Netherstair",
	"Greyhollow",
	"Coldmouth",
	"Lanternreach",
	"Saltgate",
}

-- Keyed by the `theme` on a MazeGenerator STYLES row, which is the one id in
-- this file that lives in a server module rather than in a catalogue. It cannot
-- be checked from here: MazeGenerator is in ServerScriptService and this is
-- ReplicatedStorage, so requiring it would put world generation in every
-- client. The generator checks the other way instead, at build time, warning
-- once for a style whose theme has no entry.
--
-- A tower is named for what it was before the Maze took it. The line is the
-- Codex entry; the name is what a signpost points at.

Lore.towers = {
	["Drowned Archive"] = {
		line = "Everything written here was written twice, because the first copy is under the water and the second is a guess.",
	},
	["Buried Reliquary"] = {
		line = "It was a place for keeping things safe. It is still very good at the keeping and has forgotten the rest.",
	},
	["Silent Monolith"] = {
		line = "No door was ever cut in it. The one you are walking through was not cut by anybody.",
	},
	["Alchemist Stack"] = {
		line = "Ten floors of somebody trying to turn one thing into another. The Maze finished the work and did not say what into what.",
	},
	["Ivory Ossuary"] = {
		line = "The climbers who did not come down are all still here, and the building is politely built out of the fact.",
	},
	["Cinder Sanctum"] = {
		line = "It burned. It is still burning, somewhere around floor six, and has been for longer than the district has had a name.",
	},
}

-- ============================================================
-- Validation
-- ============================================================

local function checkKeys(chapter, chapterName, source, sourceName)
	for key in pairs(chapter) do
		if source[key] == nil then
			error(string.format("Lore.%s: %q matches no %s id", chapterName, tostring(key), sourceName))
		end
	end
end

checkKeys(Lore.pets, "pets", PetCatalog, "PetCatalog")
checkKeys(Lore.eggs, "eggs", EggCatalog, "EggCatalog")
checkKeys(Lore.kept, "kept", EnemyDefinitions.types, "EnemyDefinitions.types")
checkKeys(Lore.relics, "relics", AccessoryCatalog, "AccessoryCatalog")

-- The place chapters have no catalogue to resolve against, so what is checked is
-- that they are usable at all. MazeGenerator indexes districts modulo the count
-- on every building it builds; an empty list is a divide by zero on the first
-- tower of the first section, which is a server that never finishes starting.
if #Lore.districts == 0 then
	error("Lore.districts is empty: every tower in the city is named after one")
end

for _, name in ipairs(Lore.districts) do
	if type(name) ~= "string" or name == "" then
		error("Lore.districts: every entry must be a non-empty string")
	end
end

for petId, entry in pairs(Lore.pets) do
	local stages = PetCatalog[petId].evolutions or {}
	local lines = entry.evolutionLines or {}
	if #lines > #stages then
		error(
			string.format("Lore.pets: %q has %d evolution lines and %s ships %d stages", petId, #lines, petId, #stages)
		)
	end
end

return Lore
