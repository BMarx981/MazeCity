-- AccessoryCatalog (ModuleScript) -> ReplicatedStorage.AccessoryCatalog
-- Content, alongside PetCatalog and EggCatalog. What a piece of pet gear is
-- called, which slot it takes, what it does and what it costs. The numbers that
-- govern gear as a system (the storage cap, the per-effect caps, the sell-back
-- fraction) live in Config.Accessories, because those are what get turned
-- between playtests and this is what gets added to.
--
-- A profile stores an accessoryId and four mutable fields, never a name, a slot
-- or an effect value, so everything here can be rebalanced without touching a
-- saved profile. An id that disappears leaves owned instances orphaned, which
-- PetInventory turns into a warning and an item that comes off rather than a
-- crash: the row stays in the profile in case the entry comes back.
--
-- `model` names a child of ServerStorage/Accessories. Until one exists,
-- `placeholder` is what PetService draws, the same bargain ServerStorage/Pets
-- and ServerStorage/Enemies already strike: playable from a cold rojo build,
-- real art drops in by name with no code change.
--
-- Prices are read against the economy the shop is already tuned to. A floor
-- fully explored pays about 13 coins and a tower about 130, the Summit Egg is
-- 250 and the Royal 2500, so a Common is most of one tower, an Epic is a
-- campaign, and a Legendary is not for sale at all: an item with no `coinCost`
-- cannot be bought and cannot be sold back, which is the same one-field trick
-- that keeps the Streak Egg off the pedestal's shelf.
--
-- Every effect type in Config.Accessories.Caps is carried by something here,
-- and Dust Motes carries nothing at all, so the cosmetic case is exercised from
-- the first day rather than being discovered to be broken later.

local Accessories = {}

-- ============================================================
-- Head
-- ============================================================

Accessories.explorers_cap = {
	id = "explorers_cap",
	name = "Explorer's Cap",
	slot = "Head",
	rarity = "Common",
	model = "ExplorersCap",
	placeholder = { color = Color3.fromRGB(150, 120, 80), shape = "Block", size = Vector3.new(1.5, 0.5, 1.5) },
	effects = { { type = "RouteVision", value = 3 } },
	coinCost = 150,
}

Accessories.lantern_hat = {
	id = "lantern_hat",
	name = "Lantern Hat",
	slot = "Head",
	rarity = "Uncommon",
	model = "LanternHat",
	placeholder = { color = Color3.fromRGB(255, 230, 150), shape = "Cylinder", size = Vector3.new(0.9, 1, 0.9) },
	effects = { { type = "GlowRange", value = 10 } },
	coinCost = 350,
}

Accessories.tin_crown = {
	id = "tin_crown",
	name = "Tin Crown",
	slot = "Head",
	rarity = "Uncommon",
	model = "TinCrown",
	placeholder = { color = Color3.fromRGB(185, 190, 200), shape = "Cylinder", size = Vector3.new(1.4, 0.6, 1.4) },
	effects = {
		{ type = "ScoreBonus", value = 0.05 },
		{ type = "RouteVision", value = 2 },
	},
	coinCost = 400,
}

Accessories.cartographers_circlet = {
	id = "cartographers_circlet",
	name = "Cartographer's Circlet",
	slot = "Head",
	rarity = "Rare",
	model = "CartographersCirclet",
	placeholder = { color = Color3.fromRGB(140, 200, 255), shape = "Cylinder", size = Vector3.new(1.3, 0.35, 1.3) },
	effects = {
		{ type = "RouteVision", value = 8 },
		{ type = "PhantomSense", value = 24 },
	},
	coinCost = 1200,
}

Accessories.gilded_crown = {
	id = "gilded_crown",
	name = "Gilded Crown",
	slot = "Head",
	rarity = "Epic",
	model = "GildedCrown",
	placeholder = { color = Color3.fromRGB(255, 205, 90), shape = "Cylinder", size = Vector3.new(1.5, 0.9, 1.5) },
	effects = {
		{ type = "CoinMultiplier", value = 0.25 },
		{ type = "ScoreBonus", value = 0.1 },
	},
	coinCost = 3000,
}

-- No coinCost: day seven of a streak is the only coin-free way to get one, and
-- no coinCost still means no coin purchase and no sell-back. robuxCost is the
-- authored exception to the derived ladder (docs/ROBUX_PLAN.md), inert until a
-- robuxProductId joins it, and whether to sell it at all is the plan's open
-- decision on the streak items: holding it back is deleting this one field.
Accessories.beacon_crown = {
	id = "beacon_crown",
	name = "Beacon Crown",
	slot = "Head",
	rarity = "Legendary",
	model = "BeaconCrown",
	placeholder = { color = Color3.fromRGB(255, 245, 200), shape = "Cylinder", size = Vector3.new(1.6, 1.1, 1.6) },
	effects = {
		{ type = "RouteVision", value = 14 },
		{ type = "GlowRange", value = 20 },
	},
	robuxCost = 799,
}

-- ============================================================
-- Neck
-- ============================================================

Accessories.coin_chain = {
	id = "coin_chain",
	name = "Coin Chain",
	slot = "Neck",
	rarity = "Common",
	model = "CoinChain",
	placeholder = { color = Color3.fromRGB(255, 214, 110), shape = "Cylinder", size = Vector3.new(1.2, 0.25, 1.2) },
	effects = { { type = "PickupRadius", value = 2 } },
	coinCost = 150,
}

Accessories.bell_collar = {
	id = "bell_collar",
	name = "Bell Collar",
	slot = "Neck",
	rarity = "Common",
	model = "BellCollar",
	placeholder = { color = Color3.fromRGB(190, 110, 90), shape = "Block", size = Vector3.new(1.1, 0.4, 1.1) },
	effects = { { type = "PetXp", value = 0.1 } },
	coinCost = 200,
}

Accessories.guard_collar = {
	id = "guard_collar",
	name = "Guard Collar",
	slot = "Neck",
	rarity = "Uncommon",
	model = "GuardCollar",
	placeholder = { color = Color3.fromRGB(120, 130, 140), shape = "Block", size = Vector3.new(1.2, 0.5, 1.2) },
	effects = { { type = "Armor", value = 0.15 } },
	coinCost = 500,
}

Accessories.compass_pendant = {
	id = "compass_pendant",
	name = "Compass Pendant",
	slot = "Neck",
	rarity = "Rare",
	model = "CompassPendant",
	placeholder = { color = Color3.fromRGB(110, 175, 255), shape = "Ball", size = Vector3.new(0.7, 0.7, 0.7) },
	effects = {
		{ type = "PhantomSense", value = 30 },
		{ type = "RouteVision", value = 2 },
	},
	coinCost = 1000,
}

Accessories.warm_amulet = {
	id = "warm_amulet",
	name = "Warm Amulet",
	slot = "Neck",
	rarity = "Rare",
	model = "WarmAmulet",
	placeholder = { color = Color3.fromRGB(255, 150, 90), shape = "Ball", size = Vector3.new(0.8, 0.8, 0.8) },
	effects = { { type = "HatchProgress", value = 0.5 } },
	coinCost = 1400,
}

Accessories.heartstone_locket = {
	id = "heartstone_locket",
	name = "Heartstone Locket",
	slot = "Neck",
	rarity = "Epic",
	model = "HeartstoneLocket",
	placeholder = { color = Color3.fromRGB(235, 90, 110), shape = "Ball", size = Vector3.new(0.9, 0.9, 0.9) },
	effects = {
		{ type = "Armor", value = 0.3 },
		{ type = "WalkSpeed", value = 0.5 },
	},
	coinCost = 3200,
}

-- ============================================================
-- Back
-- ============================================================

Accessories.scrap_cape = {
	id = "scrap_cape",
	name = "Scrap Cape",
	slot = "Back",
	rarity = "Common",
	model = "ScrapCape",
	placeholder = { color = Color3.fromRGB(140, 135, 125), shape = "Block", size = Vector3.new(1.6, 1.8, 0.2) },
	effects = { { type = "WalkSpeed", value = 0.5 } },
	coinCost = 200,
}

Accessories.runners_cloak = {
	id = "runners_cloak",
	name = "Runner's Cloak",
	slot = "Back",
	rarity = "Uncommon",
	model = "RunnersCloak",
	placeholder = { color = Color3.fromRGB(90, 175, 120), shape = "Block", size = Vector3.new(1.8, 2, 0.2) },
	effects = { { type = "WalkSpeed", value = 1 } },
	coinCost = 600,
}

Accessories.coin_satchel = {
	id = "coin_satchel",
	name = "Coin Satchel",
	slot = "Back",
	rarity = "Rare",
	model = "CoinSatchel",
	placeholder = { color = Color3.fromRGB(165, 120, 70), shape = "Block", size = Vector3.new(1.1, 1, 0.7) },
	effects = { { type = "CoinMultiplier", value = 0.2 } },
	coinCost = 1300,
}

Accessories.phase_pack = {
	id = "phase_pack",
	name = "Phase Pack",
	slot = "Back",
	rarity = "Rare",
	model = "PhasePack",
	placeholder = { color = Color3.fromRGB(160, 130, 255), shape = "Block", size = Vector3.new(1.2, 1.2, 0.8) },
	effects = { { type = "WallWalkSeconds", value = 2 } },
	coinCost = 1500,
}

Accessories.moth_wings = {
	id = "moth_wings",
	name = "Moth Wings",
	slot = "Back",
	rarity = "Epic",
	model = "MothWings",
	placeholder = { color = Color3.fromRGB(225, 245, 255), shape = "Block", size = Vector3.new(3, 1.6, 0.15) },
	effects = {
		{ type = "WalkSpeed", value = 1.5 },
		{ type = "PetXp", value = 0.15 },
	},
	coinCost = 3500,
}

-- ============================================================
-- Aura
-- ============================================================
-- A particle rather than a solid, so `size` is read as the particle size and
-- `rate` as the emission rate. Nothing in this slot is ever a part.

Accessories.dust_motes = {
	id = "dust_motes",
	name = "Dust Motes",
	slot = "Aura",
	rarity = "Common",
	model = "DustMotes",
	placeholder = {
		color = Color3.fromRGB(230, 225, 200),
		shape = "Particle",
		size = Vector3.new(0.35, 0.35, 0.35),
		rate = 6,
	},
	-- Deliberately empty. Cosmetic-only gear is a first-class case, and one item
	-- that carries no effect keeps the resolver honest from day one.
	effects = {},
	coinCost = 250,
}

Accessories.coin_glimmer = {
	id = "coin_glimmer",
	name = "Coin Glimmer",
	slot = "Aura",
	rarity = "Uncommon",
	model = "CoinGlimmer",
	placeholder = {
		color = Color3.fromRGB(255, 220, 120),
		shape = "Particle",
		size = Vector3.new(0.4, 0.4, 0.4),
		rate = 9,
	},
	effects = { { type = "PickupRadius", value = 2.5 } },
	coinCost = 700,
}

Accessories.warding_sparks = {
	id = "warding_sparks",
	name = "Warding Sparks",
	slot = "Aura",
	rarity = "Rare",
	model = "WardingSparks",
	placeholder = {
		color = Color3.fromRGB(120, 210, 255),
		shape = "Particle",
		size = Vector3.new(0.3, 0.3, 0.3),
		rate = 14,
	},
	effects = { { type = "Armor", value = 0.2 } },
	coinCost = 1400,
}

Accessories.wayfinder_halo = {
	id = "wayfinder_halo",
	name = "Wayfinder Halo",
	slot = "Aura",
	rarity = "Epic",
	model = "WayfinderHalo",
	placeholder = {
		color = Color3.fromRGB(200, 130, 255),
		shape = "Particle",
		size = Vector3.new(0.45, 0.45, 0.45),
		rate = 16,
	},
	effects = {
		{ type = "RouteVision", value = 10 },
		{ type = "ScoreBonus", value = 0.08 },
	},
	coinCost = 3400,
}

-- No coinCost: event gear, never for coins and never sold back. The authored
-- robuxCost is the same exception beacon_crown carries, and the easy yes of the
-- plan's open decision: this has no retention role to protect.
Accessories.ember_trail = {
	id = "ember_trail",
	name = "Ember Trail",
	slot = "Aura",
	rarity = "Legendary",
	model = "EmberTrail",
	placeholder = {
		color = Color3.fromRGB(255, 140, 70),
		shape = "Particle",
		size = Vector3.new(0.5, 0.5, 0.5),
		rate = 20,
	},
	effects = {
		{ type = "GlowRange", value = 14 },
		{ type = "WalkSpeed", value = 1 },
	},
	robuxCost = 799,
}

return Accessories
