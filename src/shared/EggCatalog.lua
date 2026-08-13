-- EggCatalog (ModuleScript) -> ReplicatedStorage.EggCatalog
-- Content, alongside PetCatalog. What an egg costs, how long it takes and what
-- can come out of it.
--
-- `mazesRequired` counts whatever Config.Pets.HatchUnit says a maze is, which is
-- towers topped out. Two is a real climb and eight is a campaign, which is the
-- whole difference between the two Climb eggs; the numbers are the spec's, and
-- they only mean this because the unit was settled before they were written
-- down. Flipping HatchUnit to "floor" without rescaling every number in this
-- file turns the royal egg into most of one tower.
--
-- `hatchTable` weights are relative, not percentages: a new entry does not need
-- the others renormalised, which is the point of storing them this way.

local Eggs = {}

Eggs.summit_common = {
	id = "summit_common",
	name = "Summit Egg",
	color = Color3.fromRGB(220, 235, 245),
	mazesRequired = 2,
	source = "Climb",
	coinCost = 250,
	hatchTable = {
		{ petId = "firefly", weight = 60 },
		{ petId = "lumen_moth", weight = 25 },
		{ petId = "ward_hound", weight = 8 },
		{ petId = "coin_bat", weight = 10 },
		{ petId = "compass_crow", weight = 5 },
	},
}

Eggs.summit_royal = {
	id = "summit_royal",
	name = "Royal Summit Egg",
	color = Color3.fromRGB(190, 150, 255),
	mazesRequired = 8,
	source = "Climb",
	coinCost = 2500,
	hatchTable = {
		{ petId = "lumen_moth", weight = 30 },
		{ petId = "ward_hound", weight = 35 },
		{ petId = "coin_bat", weight = 40 },
		{ petId = "compass_crow", weight = 30 },
	},
}

-- Day seven of a daily streak, and the only coin-free way to get one. No
-- coinCost, which is what keeps it out of the pedestal's buy list without
-- needing a second flag: an egg with no price cannot be sold. robuxCost is the
-- authored exception to the derived ladder, there being no coin price to derive
-- from, and it is inert until a robuxProductId joins it. Whether selling this
-- for Robux at all guts the streak is docs/ROBUX_PLAN.md's first open decision;
-- holding it back is deleting this one field.
Eggs.streak_seven = {
	id = "streak_seven",
	name = "Streak Egg",
	color = Color3.fromRGB(120, 235, 190),
	mazesRequired = 4,
	source = "Streak",
	robuxCost = 799,
	hatchTable = {
		{ petId = "lumen_moth", weight = 20 },
		{ petId = "ward_hound", weight = 30 },
		{ petId = "coin_bat", weight = 45 },
		{ petId = "compass_crow", weight = 35 },
	},
}

return Eggs
