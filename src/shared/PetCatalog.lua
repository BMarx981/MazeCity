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
-- `model` names a child of ServerStorage/Pets. Until one exists, `look` is the
-- recipe PetModelGenerator builds a rig from, the same bargain EnemyService
-- strikes with its `look` recipes: an artist's model still wins by name, and
-- nothing has to wait for one. Two of the four pets carry Glow because Glow is
-- the ability that is implemented end to end, and an ability nobody can roll is
-- an ability nobody can test.
--
-- A `look` is sparse: PetModelGenerator.DEFAULT_LOOK is the baseline, the pet
-- merges over it, and the stage merges over the pet. Three colours carry every
-- part (primary body, secondary soft parts, accent neon), and the accent is
-- always the ability made visible, which is what lets a stage read as stronger
-- without a label. See docs/PET_LOOKS_PLAN.md for the art direction and the
-- rule that an evolution must add or change a group rather than only scale and
-- tint. `placeholder` is what PetService drew before the generator and is
-- deleted in Set 2 of that plan.

local Pets = {}

Pets.firefly = {
	id = "firefly",
	name = "Firefly",
	rarity = "Common",
	model = "Firefly",
	placeholder = { color = Color3.fromRGB(255, 236, 150), shape = "Ball", size = 1.6 },
	-- The smallest pet in the catalogue and the only one whose accent is most of
	-- its silhouette: the lantern is the Glow, so it grows at every stage.
	look = {
		primary = Color3.fromRGB(255, 196, 90),
		secondary = Color3.fromRGB(255, 238, 190),
		accent = Color3.fromRGB(255, 236, 150),
		body = Vector3.new(1.5, 1.45, 1.8),
		head = 1,
		headOffset = Vector3.new(0, 0.5, -0.85),
		eyeSize = 0.3,
		eyeSpread = 0.2,
		eyeDepth = 0.42,
		wings = { size = Vector3.new(0.85, 0.12, 1), spread = 0.72, height = 0.42, z = 0.15, tilt = 0.35 },
		charms = { { size = 0.8, offset = Vector3.new(0, -0.1, 1.05) } },
	},
	evolutions = {
		{
			level = 10,
			model = "FireflyRadiant",
			displaySuffix = "Radiant",
			abilityMultiplier = 1.5,
			placeholder = { color = Color3.fromRGB(255, 214, 90), shape = "Ball", size = 1.9 },
			look = {
				scale = 1.08,
				primary = Color3.fromRGB(255, 214, 90),
				charms = { { size = 1, offset = Vector3.new(0, -0.1, 1.1) } },
				halo = { count = 8, radius = 0.85, size = 0.16, height = 1.05 },
			},
		},
		{
			level = 25,
			model = "FireflySolar",
			displaySuffix = "Solar",
			abilityMultiplier = 2.5,
			placeholder = { color = Color3.fromRGB(255, 150, 60), shape = "Ball", size = 2.2 },
			look = {
				scale = 1.2,
				primary = Color3.fromRGB(255, 150, 60),
				secondary = Color3.fromRGB(255, 220, 170),
				accent = Color3.fromRGB(255, 190, 90),
				charms = { { size = 1.15, offset = Vector3.new(0, -0.1, 1.15) } },
				halo = { count = 10, radius = 0.95, size = 0.18, height = 1.15 },
				motes = { count = 4, radius = 1.7, size = 0.22, height = 0.05 },
			},
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
	-- Almost all wing. The body is the smallest here and the wings are wider than
	-- any other pet is long, which is the whole read at corridor distance: the
	-- Firefly is a point of light, this is a shape crossing in front of one.
	look = {
		primary = Color3.fromRGB(190, 235, 255),
		secondary = Color3.fromRGB(236, 250, 255),
		accent = Color3.fromRGB(200, 255, 255),
		body = Vector3.new(1.15, 1.15, 1.6),
		head = 0.9,
		headOffset = Vector3.new(0, 0.42, -0.8),
		eyeSize = 0.36,
		eyeSpread = 0.2,
		eyeDepth = 0.4,
		pupilSize = 0.2,
		wings = { size = Vector3.new(2.4, 0.14, 2), spread = 1.1, height = 0.25, z = 0.1, tilt = 0.22 },
		antennae = {
			size = Vector3.new(0.11, 0.11, 0.9),
			spread = 0.22,
			height = 0.8,
			z = -0.75,
			pitch = 0.75,
			tilt = 0.35,
		},
	},
	evolutions = {
		{
			level = 12,
			model = "LumenMothPale",
			displaySuffix = "Pale",
			abilityMultiplier = 1.6,
			placeholder = { color = Color3.fromRGB(225, 245, 255), shape = "Block", size = 2.1 },
			look = {
				scale = 1.08,
				primary = Color3.fromRGB(220, 244, 255),
				secondary = Color3.fromRGB(250, 253, 255),
				wings = { size = Vector3.new(3.1, 0.14, 2.5), spread = 1.4, height = 0.28, z = 0.1, tilt = 0.2 },
			},
		},
	},
	maxLevel = 50,
	xpCurve = { base = 130, growth = 1.16 },
}

-- The one pet that is a defence rather than a convenience, and the only ability
-- in the catalogue that reaches into another system. An enemy inside a running
-- ward drops its target and walks back to its marker; it is never damaged, never
-- stunned and never moved, because there is no combat in this game and a pet is
-- not where one starts.
--
-- The three params are the balance and they are all here rather than in
-- Config.Pets, because how big a ward is and how long it lasts is what this pet
-- is. It is triggered rather than always on: an aura that never lapses is
-- strictly better than the Ghost powerup and the Cloak ability, which are the two
-- things a player spends coins on for this exact problem. At six seconds up and
-- ten down it is a way out of a corner rather than a way to ignore a floor.
--
-- The evolution multiplier scales radius and deliberately not uptime, for the
-- reason Glow scales range and not brightness: more corridor covered reads as a
-- stronger pet, more of the time covered reads as the enemies being switched off.
Pets.ward_hound = {
	id = "ward_hound",
	name = "Ward Hound",
	rarity = "Rare",
	model = "WardHound",
	placeholder = { color = Color3.fromRGB(140, 210, 235), shape = "Block", size = 2.1 },
	-- The one pet that stands near enemies on purpose, so it is the one that most
	-- has to not read as one: the stoutest body in the catalogue, a muzzle, ears
	-- and a tail, and none of the tapering the Kept are built out of. It floats
	-- like the rest, being a stout balloon of a dog, because a walk cycle needs
	-- art nothing here has.
	--
	-- The collar is the ward, which is why it is the accent and why the evolution
	-- spends itself widening it rather than growing the dog.
	look = {
		primary = Color3.fromRGB(140, 210, 235),
		secondary = Color3.fromRGB(205, 240, 250),
		accent = Color3.fromRGB(90, 240, 255),
		body = Vector3.new(2.2, 1.75, 2.5),
		belly = { size = Vector3.new(1.7, 1.2, 2), offset = Vector3.new(0, -0.32, 0.05) },
		head = 1.3,
		headOffset = Vector3.new(0, 0.5, -1.25),
		eyeSize = 0.32,
		eyeSpread = 0.26,
		eyeHeight = 0.12,
		eyeDepth = 0.52,
		muzzle = { size = Vector3.new(0.72, 0.6, 0.85), height = -0.18, forward = 0.75 },
		ears = { size = Vector3.new(0.42, 0.9, 0.3), spread = 0.5, height = 1, z = -1.2, tilt = 0.45 },
		tail = { size = Vector3.new(0.45, 0.45, 0.9), offset = Vector3.new(0, 0.45, 1.35), tilt = 0.5 },
		-- Upright, and wide enough to clear the chest at the bottom of its swing.
		-- It dips a little into the ribs down there, which is what a collar
		-- resting on a dog does.
		collar = { count = 12, radius = 1, size = 0.17, height = 0.35, z = -0.85, upright = true },
	},
	evolutions = {
		{
			level = 15,
			model = "WardHoundBulwark",
			displaySuffix = "Bulwark",
			abilityMultiplier = 1.45,
			placeholder = { color = Color3.fromRGB(180, 235, 255), shape = "Block", size = 2.4 },
			look = {
				scale = 1.1,
				primary = Color3.fromRGB(180, 235, 255),
				body = Vector3.new(2.65, 2, 2.85),
				-- Upright rather than drooped, which is the cheapest legible tell
				-- in the whole catalogue: the same dog, listening.
				ears = { size = Vector3.new(0.44, 1, 0.32), spread = 0.55, height = 1.15, z = -1.2, tilt = 0.08 },
				-- Clear of the body all the way round, which is what makes it a
				-- shoulder ring rather than a bigger collar.
				collar = { count = 16, radius = 1.35, size = 0.2, height = 0.3, z = -0.55, upright = true },
			},
		},
	},
	maxLevel = 50,
	xpCurve = { base = 165, growth = 1.17 },
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
	-- Ears and membrane wings, and the coin it carries is the magnet. The
	-- evolution gets a second one rather than a bigger one, because two coins is
	-- a thing you can count from across a room and 20% more coin is not.
	look = {
		primary = Color3.fromRGB(235, 190, 90),
		secondary = Color3.fromRGB(255, 228, 160),
		accent = Color3.fromRGB(255, 214, 110),
		body = Vector3.new(1.45, 1.5, 1.5),
		head = 1.12,
		headOffset = Vector3.new(0, 0.5, -0.8),
		eyeSize = 0.3,
		eyeSpread = 0.22,
		eyeDepth = 0.46,
		ears = { size = Vector3.new(0.48, 1.15, 0.26), spread = 0.42, height = 1.1, z = -0.78, tilt = 0.16 },
		wings = { size = Vector3.new(2.2, 0.12, 1.45), spread = 1.15, height = 0.15, z = 0.1, tilt = -0.12 },
		charms = { { size = Vector3.new(0.85, 0.85, 0.16), offset = Vector3.new(0, -1.15, 0.1) } },
	},
	evolutions = {
		{
			level = 15,
			model = "CoinBatGilded",
			displaySuffix = "Gilded",
			abilityMultiplier = 1.5,
			placeholder = { color = Color3.fromRGB(255, 236, 170), shape = "Block", size = 2.3 },
			look = {
				scale = 1.08,
				primary = Color3.fromRGB(250, 214, 120),
				secondary = Color3.fromRGB(255, 236, 170),
				-- The one place a group names its own colour: gilded wing edges
				-- are the tell, and they are the wing rather than a new part.
				wings = {
					size = Vector3.new(2.3, 0.12, 1.5),
					spread = 1.2,
					height = 0.15,
					z = 0.1,
					tilt = -0.12,
					color = Color3.fromRGB(255, 214, 110),
				},
				charms = {
					{ size = Vector3.new(0.8, 0.8, 0.15), offset = Vector3.new(-0.52, -1.18, 0.1) },
					{ size = Vector3.new(0.8, 0.8, 0.15), offset = Vector3.new(0.52, -1.18, 0.1) },
				},
			},
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
	-- The only slate pet, and the only beak: the rarest thing in the catalogue
	-- should not also be the third round yellow one. The crest is a compass
	-- needle, which is the ability, and the evolution rings it.
	look = {
		primary = Color3.fromRGB(120, 130, 170),
		secondary = Color3.fromRGB(92, 102, 142),
		accent = Color3.fromRGB(150, 190, 255),
		body = Vector3.new(1.55, 1.55, 2.15),
		head = 1.15,
		headOffset = Vector3.new(0, 0.6, -0.9),
		eyeSize = 0.32,
		eyeSpread = 0.24,
		eyeDepth = 0.48,
		beak = { size = Vector3.new(0.32, 0.3, 0.85), height = -0.05, forward = 0.62 },
		wings = { size = Vector3.new(1.9, 0.14, 1.6), spread = 1, height = 0.25, z = 0.05, tilt = 0.12 },
		tail = { size = Vector3.new(1.25, 0.14, 1.15), offset = Vector3.new(0, 0.12, 1.45), tilt = -0.2 },
		crest = { size = Vector3.new(0.13, 0.85, 0.13), height = 0.72 },
	},
	evolutions = {
		{
			level = 15,
			model = "CompassCrowWayfinder",
			displaySuffix = "Wayfinder",
			abilityMultiplier = 1.4,
			placeholder = { color = Color3.fromRGB(150, 170, 220), shape = "Block", size = 2.5 },
			look = {
				scale = 1.08,
				primary = Color3.fromRGB(150, 170, 220),
				secondary = Color3.fromRGB(118, 132, 180),
				crest = { size = Vector3.new(0.14, 1.05, 0.14), height = 0.85 },
				-- Needle and dial: the crest it always had, now standing in a
				-- compass rose the motion set can turn. Sat at the needle's base
				-- above the skull rather than ringing the head, because a ring
				-- wide enough to clear the head reaches back into the shoulders.
				halo = { count = 12, radius = 0.55, size = 0.13, height = 1.15, z = -0.9 },
			},
		},
	},
	maxLevel = 50,
	xpCurve = { base = 150, growth = 1.18 },
}

return Pets
