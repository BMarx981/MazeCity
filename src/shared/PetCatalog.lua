-- PetCatalog (ModuleScript) -> ReplicatedStorage.PetCatalog
-- Content, not tuning. A pet's name, rarity, rig and ability live here; the
-- numbers that govern the system as a whole (storage caps, XP per floor, follow
-- distance) live in Config.Pets, because those are what get turned between
-- playtests and this is what gets added to.
--
-- A player profile stores a petId and mutable state, never a name or a rate, so
-- everything in this file can be rebalanced without touching a saved profile.
-- The one field that cannot move freely is a key: an id that disappears leaves
-- every instance referencing it orphaned, which resolvePet turns into a warning
-- and a skipped pet rather than a crash.
--
-- `model` names a child of ServerStorage/Pets. Until one exists, `placeholder`
-- is what PetService draws, the same fallback EnemyService uses for rigs. Two of
-- the four pets carry Glow because Glow is the ability that is implemented end
-- to end, and an ability nobody can roll is an ability nobody can test.

local Pets = {}

Pets.firefly = {
	id = "firefly",
	name = "Firefly",
	rarity = "Common",
	model = "Firefly",
	placeholder = { color = Color3.fromRGB(255, 236, 150), shape = "Ball", size = 1.6 },
	ability = { type = "Glow", params = { radius = 14, brightness = 1.1 } },
	evolutions = {
		{
			level = 10,
			model = "FireflyRadiant",
			displaySuffix = "Radiant",
			abilityMultiplier = 1.5,
			placeholder = { color = Color3.fromRGB(255, 214, 90), shape = "Ball", size = 1.9 },
		},
		{
			level = 25,
			model = "FireflySolar",
			displaySuffix = "Solar",
			abilityMultiplier = 2.5,
			placeholder = { color = Color3.fromRGB(255, 150, 60), shape = "Ball", size = 2.2 },
		},
	},
	maxLevel = 50,
	xpCurve = { base = 100, growth = 1.15 },
}

Pets.lumen_moth = {
	id = "lumen_moth",
	name = "Lumen Moth",
	rarity = "Uncommon",
	model = "LumenMoth",
	placeholder = { color = Color3.fromRGB(190, 235, 255), shape = "Block", size = 1.8 },
	ability = { type = "Glow", params = { radius = 22, brightness = 1.4 } },
	evolutions = {
		{
			level = 12,
			model = "LumenMothPale",
			displaySuffix = "Pale",
			abilityMultiplier = 1.6,
			placeholder = { color = Color3.fromRGB(225, 245, 255), shape = "Block", size = 2.1 },
		},
	},
	maxLevel = 50,
	xpCurve = { base = 130, growth = 1.16 },
}

-- CoinMagnet and DeadEndPing are catalogued but not implemented: they are named
-- in the plan's "later clutches" list. PetService applies the abilities it knows
-- and ignores the rest, so a pet with an unbuilt ability still hatches, levels,
-- evolves and follows. It just does not do anything yet, which is a visible gap
-- rather than a broken pet.
Pets.coin_bat = {
	id = "coin_bat",
	name = "Coin Bat",
	rarity = "Rare",
	model = "CoinBat",
	placeholder = { color = Color3.fromRGB(255, 214, 110), shape = "Block", size = 2 },
	ability = { type = "CoinMagnet", params = { radius = 6 } },
	evolutions = {
		{
			level = 15,
			model = "CoinBatGilded",
			displaySuffix = "Gilded",
			abilityMultiplier = 1.5,
			placeholder = { color = Color3.fromRGB(255, 236, 170), shape = "Block", size = 2.3 },
		},
	},
	maxLevel = 50,
	xpCurve = { base = 160, growth = 1.17 },
}

Pets.compass_crow = {
	id = "compass_crow",
	name = "Compass Crow",
	rarity = "Epic",
	model = "CompassCrow",
	placeholder = { color = Color3.fromRGB(120, 130, 170), shape = "Block", size = 2.2 },
	ability = { type = "DeadEndPing", params = { cooldown = 30, range = 40 } },
	evolutions = {
		{
			level = 15,
			model = "CompassCrowWayfinder",
			displaySuffix = "Wayfinder",
			abilityMultiplier = 1.4,
			placeholder = { color = Color3.fromRGB(150, 170, 220), shape = "Block", size = 2.5 },
		},
	},
	maxLevel = 50,
	xpCurve = { base = 150, growth = 1.18 },
}

return Pets
