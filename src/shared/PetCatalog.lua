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
-- tint. A stage's `look.primary` is also its one colour in the world: the Glow
-- light and the ward ring are tinted from it, so there is no second colour field
-- here for either to drift against.

local Pets = {}

Pets.firefly = {
	id = "firefly",
	name = "Firefly",
	rarity = "Common",
	model = "Firefly",
	ability = { type = "Glow", params = { radius = 14, brightness = 1.1 } },
	-- The smallest pet in the catalogue and the only one whose accent is most of
	-- its silhouette: the lantern is the Glow, so it grows at every stage.
	look = {
		primary = Color3.fromRGB(255, 196, 90),
		secondary = Color3.fromRGB(255, 238, 190),
		accent = Color3.fromRGB(255, 236, 150),
		primaryMaterial = "Pebble",
		secondaryMaterial = "SmoothPlastic",
		body = Vector3.new(1.05, 1, 2.15),
		head = Vector3.new(0.74, 0.72, 0.68),
		headOffset = Vector3.new(0, 0.36, -1.04),
		eyeSize = Vector3.new(0.22, 0.28, 0.14),
		eyeColor = Color3.fromRGB(58, 42, 28),
		pupilSize = Vector3.new(0.08, 0.1, 0.05),
		pupilColor = Color3.fromRGB(255, 222, 92),
		catchlight = { size = 0.055, material = "Neon" },
		eyeSpread = 0.24,
		eyeDepth = 0.42,
		wings = { size = Vector3.new(0.82, 0.1, 0.82), spread = 0.62, height = 0.34, z = -0.02, tilt = 0.28 },
		antennae = {
			size = Vector3.new(0.07, 0.07, 0.55),
			spread = 0.17,
			height = 1,
			z = -1.05,
			pitch = 0.9,
			tilt = 0.4,
		},
		charms = { { size = 0.72, offset = Vector3.new(0, -0.08, 1.32) } },
		details = {
			{
				name = "Thorax",
				size = Vector3.new(1.02, 0.92, 0.58),
				offset = Vector3.new(0, 0.04, -0.42),
				color = Color3.fromRGB(218, 126, 54),
				material = "Pebble",
			},
			{
				name = "ShellSeam",
				size = Vector3.new(0.1, 0.12, 0.94),
				offset = Vector3.new(0, 0.55, 0.02),
				color = Color3.fromRGB(170, 96, 44),
				material = "Pebble",
			},
			{
				name = "InsectLeg",
				size = Vector3.new(0.09, 0.34, 0.09),
				offset = Vector3.new(0.46, -0.38, -0.44),
				mirrored = true,
				roll = 0.35,
				color = Color3.fromRGB(92, 60, 34),
				material = "Pebble",
			},
			{
				name = "InsectLeg",
				size = Vector3.new(0.08, 0.32, 0.08),
				offset = Vector3.new(0.48, -0.4, -0.02),
				mirrored = true,
				roll = 0.42,
				color = Color3.fromRGB(92, 60, 34),
				material = "Pebble",
			},
			{
				name = "InsectLeg",
				size = Vector3.new(0.08, 0.3, 0.08),
				offset = Vector3.new(0.42, -0.4, 0.42),
				mirrored = true,
				roll = 0.32,
				color = Color3.fromRGB(92, 60, 34),
				material = "Pebble",
			},
			{
				name = "AbdomenSegment",
				size = Vector3.new(1.02, 0.96, 0.44),
				offset = Vector3.new(0, 0, 0.2),
				color = Color3.fromRGB(118, 82, 46),
				material = "Pebble",
			},
			{
				name = "AbdomenSegment",
				size = Vector3.new(0.94, 0.88, 0.4),
				offset = Vector3.new(0, -0.02, 0.56),
				color = Color3.fromRGB(154, 96, 42),
				material = "Pebble",
			},
			{
				name = "AbdomenSegment",
				size = Vector3.new(0.78, 0.74, 0.36),
				offset = Vector3.new(0, -0.04, 0.9),
				color = Color3.fromRGB(118, 82, 46),
				material = "Pebble",
			},
			{
				name = "LanternShell",
				size = Vector3.new(0.5, 0.16, 0.28),
				offset = Vector3.new(0, 0.02, 1.14),
				color = Color3.fromRGB(140, 85, 38),
			},
		},
		-- A blur rather than a beat: the fastest wings in the catalogue and the
		-- shallowest, which is the other half of reading as a point of light. The
		-- lantern breathes slowly underneath them, and the driver breathes it
		-- further still on this pet, the lantern being the Glow.
		motion = { flapRate = 14, flapAngle = 0.26, charmRate = 0.9, blinkEvery = 3.4 },
	},
	evolutions = {
		{
			level = 10,
			model = "FireflyRadiant",
			displaySuffix = "Radiant",
			abilityMultiplier = 1.5,
			look = {
				scale = 1.08,
				primary = Color3.fromRGB(255, 214, 90),
				charms = { { size = 0.94, offset = Vector3.new(0, -0.08, 1.42) } },
				halo = { count = 8, radius = 0.85, size = 0.16, height = 1.05 },
			},
		},
		{
			level = 25,
			model = "FireflySolar",
			displaySuffix = "Solar",
			abilityMultiplier = 2.5,
			look = {
				scale = 1.2,
				primary = Color3.fromRGB(255, 150, 60),
				secondary = Color3.fromRGB(255, 220, 170),
				accent = Color3.fromRGB(255, 190, 90),
				charms = { { size = 1.08, offset = Vector3.new(0, -0.08, 1.48) } },
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
	ability = { type = "Glow", params = { radius = 22, brightness = 1.4 } },
	-- Almost all wing. The body is the smallest here and the wings are wider than
	-- any other pet is long, which is the whole read at corridor distance: the
	-- Firefly is a point of light, this is a shape crossing in front of one.
	look = {
		primary = Color3.fromRGB(190, 235, 255),
		secondary = Color3.fromRGB(236, 250, 255),
		accent = Color3.fromRGB(200, 255, 255),
		primaryMaterial = "Fabric",
		secondaryMaterial = "Fabric",
		body = Vector3.new(0.82, 1.05, 1.85),
		head = Vector3.new(0.72, 0.78, 0.68),
		headOffset = Vector3.new(0, 0.4, -0.9),
		eyeSize = Vector3.new(0.34, 0.42, 0.14),
		eyeColor = Color3.fromRGB(218, 250, 255),
		eyeRim = { size = Vector3.new(0.43, 0.5, 0.08), color = Color3.fromRGB(250, 255, 255) },
		pupilSize = Vector3.new(0.14, 0.22, 0.06),
		pupilColor = Color3.fromRGB(78, 150, 178),
		catchlight = { size = 0.07, material = "Neon" },
		eyeTilt = 0.12,
		eyeSpread = 0.2,
		eyeDepth = 0.4,
		wings = { size = Vector3.new(2.5, 0.12, 2.05), spread = 1.1, height = 0.18, z = 0.08, tilt = 0.2 },
		antennae = {
			size = Vector3.new(0.13, 0.13, 1.05),
			spread = 0.22,
			height = 0.86,
			z = -0.75,
			pitch = 0.75,
			tilt = 0.35,
		},
		details = {
			{
				name = "ThoraxFuzz",
				size = Vector3.new(0.92, 0.9, 0.62),
				offset = Vector3.new(0, 0.05, -0.34),
				color = Color3.fromRGB(252, 255, 255),
				material = "Fabric",
			},
			{
				name = "Abdomen",
				size = Vector3.new(0.62, 0.8, 0.86),
				offset = Vector3.new(0, -0.02, 0.42),
				color = Color3.fromRGB(170, 224, 240),
				material = "Fabric",
			},
			{
				name = "AbdomenTip",
				size = Vector3.new(0.48, 0.62, 0.4),
				offset = Vector3.new(0, -0.04, 0.88),
				color = Color3.fromRGB(132, 204, 224),
				material = "Fabric",
			},
			{
				name = "MothLeg",
				size = Vector3.new(0.07, 0.32, 0.07),
				offset = Vector3.new(0.34, -0.42, -0.42),
				gait = "mothFront",
				mirrored = true,
				roll = 0.28,
				color = Color3.fromRGB(160, 215, 230),
				material = "Fabric",
			},
			{
				name = "MothLeg",
				size = Vector3.new(0.07, 0.3, 0.07),
				offset = Vector3.new(0.36, -0.43, -0.02),
				gait = "mothMiddle",
				mirrored = true,
				roll = 0.36,
				color = Color3.fromRGB(160, 215, 230),
				material = "Fabric",
			},
			{
				name = "MothLeg",
				size = Vector3.new(0.06, 0.28, 0.06),
				offset = Vector3.new(0.32, -0.42, 0.36),
				gait = "mothRear",
				mirrored = true,
				roll = 0.26,
				color = Color3.fromRGB(160, 215, 230),
				material = "Fabric",
			},
			{
				name = "WingVein",
				size = Vector3.new(1.4, 0.06, 0.08),
				offset = Vector3.new(1.08, 0.36, 0.15),
				mirrored = true,
				roll = 0.18,
				color = Color3.fromRGB(186, 230, 242),
				material = "Fabric",
			},
			{
				name = "WingEye",
				size = Vector3.new(0.42, 0.07, 0.42),
				offset = Vector3.new(1.45, 0.34, -0.32),
				mirrored = true,
				color = Color3.fromRGB(142, 210, 235),
			},
			{
				name = "WingEyeCore",
				size = Vector3.new(0.22, 0.08, 0.22),
				offset = Vector3.new(1.45, 0.38, -0.32),
				mirrored = true,
				colorKey = "accent",
				material = "Neon",
			},
			{
				name = "WingDust",
				size = Vector3.new(0.28, 0.06, 0.28),
				offset = Vector3.new(0.85, 0.34, 0.7),
				mirrored = true,
				color = Color3.fromRGB(255, 250, 220),
			},
		},
		-- The opposite corner from the Firefly on the same two numbers: slow and
		-- deep, which is what a moth does and what makes a shape crossing in front
		-- of a light read as a shape rather than as a second light.
		motion = {
			flapRate = 2.4,
			flapAngle = 0.78,
			antennaRate = 0.8,
			antennaAngle = 0.3,
			stepRate = 4.4,
			stepAngle = 0.12,
			stepLift = 0.035,
		},
	},
	evolutions = {
		{
			level = 12,
			model = "LumenMothPale",
			displaySuffix = "Pale",
			abilityMultiplier = 1.6,
			look = {
				scale = 1.08,
				primary = Color3.fromRGB(220, 244, 255),
				secondary = Color3.fromRGB(250, 253, 255),
				wings = { size = Vector3.new(3.1, 0.14, 2.5), spread = 1.4, height = 0.28, z = 0.1, tilt = 0.2 },
				-- Wider wings beat slower. Naming only the rate is the whole point
				-- of motion merging key by key: the deep angle the pet already had
				-- is what this stage is keeping.
				motion = { flapRate = 1.9 },
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
	ability = { type = "Ward", params = { radius = 16, activeSeconds = 6, rechargeSeconds = 10 } },
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
		primaryMaterial = "Fabric",
		secondaryMaterial = "Fabric",
		body = Vector3.new(1.75, 1.25, 2.65),
		belly = { size = Vector3.new(1.24, 0.66, 1.72), offset = Vector3.new(0, -0.28, -0.05) },
		head = Vector3.new(1.12, 1, 1.05),
		headOffset = Vector3.new(0, 0.42, -1.42),
		eyeSize = Vector3.new(0.32, 0.26, 0.12),
		eyeColor = Color3.fromRGB(255, 244, 210),
		eyeRim = { size = Vector3.new(0.42, 0.34, 0.09), color = Color3.fromRGB(90, 155, 182) },
		pupilSize = Vector3.new(0.14, 0.16, 0.05),
		pupilColor = Color3.fromRGB(35, 54, 70),
		catchlight = { size = 0.065, material = "Neon" },
		eyeTilt = 0.05,
		eyeSpread = 0.26,
		eyeHeight = 0.12,
		eyeDepth = 0.52,
		muzzle = { size = Vector3.new(0.62, 0.5, 0.78), height = -0.16, forward = 0.7 },
		ears = { size = Vector3.new(0.36, 0.82, 0.26), spread = 0.45, height = 0.86, z = -1.26, tilt = 0.48 },
		tail = { size = Vector3.new(0.36, 0.36, 0.78), offset = Vector3.new(0, 0.35, 1.4), tilt = 0.45 },
		details = {
			{
				name = "Nose",
				size = Vector3.new(0.34, 0.22, 0.18),
				offset = Vector3.new(0, 0.34, -2.42),
				color = Color3.fromRGB(35, 44, 52),
			},
			{
				name = "BrowPatch",
				size = Vector3.new(0.34, 0.08, 0.18),
				offset = Vector3.new(0.26, 0.86, -1.7),
				mirrored = true,
				color = Color3.fromRGB(93, 152, 178),
				material = "Fabric",
			},
			{
				name = "FrontLeg",
				size = Vector3.new(0.28, 0.64, 0.28),
				offset = Vector3.new(0.45, -0.5, -0.62),
				gait = "houndFront",
				mirrored = true,
				color = Color3.fromRGB(118, 192, 224),
				material = "Fabric",
			},
			{
				name = "FrontPaw",
				size = Vector3.new(0.3, 0.18, 0.34),
				offset = Vector3.new(0, -0.3, -0.08),
				attachTo = "FrontLeg",
				mirrored = true,
				colorKey = "secondary",
				material = "Fabric",
			},
			{
				name = "FrontPad",
				size = Vector3.new(0.2, 0.05, 0.16),
				offset = Vector3.new(0, -0.1, -0.02),
				attachTo = "FrontPaw",
				mirrored = true,
				color = Color3.fromRGB(68, 106, 128),
				material = "SmoothPlastic",
			},
			{
				name = "FrontOuterToe",
				size = Vector3.new(0.07, 0.06, 0.2),
				offset = Vector3.new(0.1, -0.04, -0.24),
				attachTo = "FrontPaw",
				mirrored = true,
				pitch = -0.08,
				color = Color3.fromRGB(72, 112, 134),
				material = "SmoothPlastic",
			},
			{
				name = "FrontInnerToe",
				size = Vector3.new(0.07, 0.06, 0.2),
				offset = Vector3.new(-0.1, -0.04, -0.24),
				attachTo = "FrontPaw",
				mirrored = true,
				pitch = -0.08,
				color = Color3.fromRGB(72, 112, 134),
				material = "SmoothPlastic",
			},
			{
				name = "BackLeg",
				size = Vector3.new(0.32, 0.66, 0.32),
				offset = Vector3.new(0.52, -0.5, 0.82),
				gait = "houndBack",
				mirrored = true,
				color = Color3.fromRGB(114, 186, 218),
				material = "Fabric",
			},
			{
				name = "BackPaw",
				size = Vector3.new(0.34, 0.2, 0.38),
				offset = Vector3.new(0, -0.31, -0.05),
				attachTo = "BackLeg",
				mirrored = true,
				colorKey = "secondary",
				material = "Fabric",
			},
			{
				name = "BackPad",
				size = Vector3.new(0.22, 0.055, 0.18),
				offset = Vector3.new(0, -0.11, -0.02),
				attachTo = "BackPaw",
				mirrored = true,
				color = Color3.fromRGB(68, 106, 128),
				material = "SmoothPlastic",
			},
			{
				name = "BackOuterToe",
				size = Vector3.new(0.075, 0.06, 0.22),
				offset = Vector3.new(0.12, -0.045, -0.27),
				attachTo = "BackPaw",
				mirrored = true,
				pitch = -0.08,
				color = Color3.fromRGB(72, 112, 134),
				material = "SmoothPlastic",
			},
			{
				name = "BackInnerToe",
				size = Vector3.new(0.075, 0.06, 0.22),
				offset = Vector3.new(-0.12, -0.045, -0.27),
				attachTo = "BackPaw",
				mirrored = true,
				pitch = -0.08,
				color = Color3.fromRGB(72, 112, 134),
				material = "SmoothPlastic",
			},
			{
				name = "ChestFluff",
				size = Vector3.new(0.78, 0.5, 0.46),
				offset = Vector3.new(0, -0.04, -1.12),
				color = Color3.fromRGB(232, 252, 255),
				material = "Fabric",
			},
			{
				name = "CheekRuff",
				size = Vector3.new(0.38, 0.24, 0.32),
				offset = Vector3.new(0.46, 0.42, -1.72),
				mirrored = true,
				colorKey = "secondary",
				material = "Fabric",
			},
			{
				name = "Shoulder",
				size = Vector3.new(0.42, 0.46, 0.58),
				offset = Vector3.new(0.62, 0, -0.42),
				mirrored = true,
				color = Color3.fromRGB(112, 188, 218),
				material = "Fabric",
			},
			{
				name = "Haunch",
				size = Vector3.new(0.5, 0.48, 0.72),
				offset = Vector3.new(0.66, -0.02, 0.82),
				mirrored = true,
				color = Color3.fromRGB(108, 180, 212),
				material = "Fabric",
			},
		},
		-- Upright, and wide enough to clear the chest at the bottom of its swing.
		-- It dips a little into the ribs down there, which is what a collar
		-- resting on a dog does.
		collar = { count = 12, radius = 1, size = 0.17, height = 0.35, z = -0.85, upright = true },
		-- The only pet with no wings, so all of its motion is the dog: a tail that
		-- wags rather than sways, ears that flick twice as often as anything else
		-- twitches, and a collar the driver runs off the ward rather than off a
		-- clock. Everything else here is the baseline.
		motion = {
			swayRate = 3.4,
			swayAngle = 0.5,
			twitchEvery = 1.9,
			twitchAngle = 0.4,
			stepRate = 4.8,
			stepAngle = 0.2,
			stepLift = 0.08,
		},
	},
	evolutions = {
		{
			level = 15,
			model = "WardHoundBulwark",
			displaySuffix = "Bulwark",
			abilityMultiplier = 1.45,
			look = {
				scale = 1.1,
				primary = Color3.fromRGB(180, 235, 255),
				body = Vector3.new(2.05, 1.45, 2.95),
				-- Upright rather than drooped, which is the cheapest legible tell
				-- in the whole catalogue: the same dog, listening.
				ears = { size = Vector3.new(0.44, 1, 0.32), spread = 0.55, height = 1.15, z = -1.2, tilt = 0.08 },
				-- Clear of the body all the way round, which is what makes it a
				-- shoulder ring rather than a bigger collar.
				collar = { count = 16, radius = 1.35, size = 0.2, height = 0.3, z = -0.55, upright = true },
				-- Ears up and steady rather than flicking every two seconds. The
				-- same dog, listening, in motion as well as in geometry.
				motion = { twitchEvery = 4.6, twitchAngle = 0.22 },
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
	ability = { type = "CoinMagnet", params = { radius = 6 } },
	-- Ears and membrane wings, and the coin it carries is the magnet. The
	-- evolution gets a second one rather than a bigger one, because two coins is
	-- a thing you can count from across a room and 20% more coin is not.
	look = {
		primary = Color3.fromRGB(82, 62, 58),
		secondary = Color3.fromRGB(178, 135, 104),
		accent = Color3.fromRGB(255, 214, 110),
		primaryMaterial = "Fabric",
		secondaryMaterial = "Fabric",
		body = Vector3.new(0.92, 0.92, 1.05),
		head = Vector3.new(0.92, 0.82, 0.8),
		headOffset = Vector3.new(0, 0.42, -0.76),
		eyeSize = Vector3.new(0.2, 0.25, 0.12),
		eyeColor = Color3.fromRGB(42, 24, 38),
		eyeRim = { size = Vector3.new(0.28, 0.33, 0.08), color = Color3.fromRGB(36, 28, 32) },
		pupilSize = Vector3.new(0.09, 0.12, 0.05),
		pupilColor = Color3.fromRGB(112, 58, 88),
		catchlight = { size = 0.07, material = "Neon" },
		eyeSpread = 0.28,
		eyeDepth = 0.46,
		ears = { size = Vector3.new(0.5, 1.12, 0.22), spread = 0.4, height = 0.94, z = -0.72, tilt = 0.12 },
		wings = {
			size = Vector3.new(2.6, 0.1, 1.42),
			spread = 1.22,
			height = 0.02,
			z = 0.16,
			tilt = -0.18,
			material = "SmoothPlastic",
		},
		charms = {
			{ size = Vector3.new(0.85, 0.85, 0.16), offset = Vector3.new(0, -1.15, 0.1), material = "Plastic" },
		},
		details = {
			{
				name = "InnerEar",
				size = Vector3.new(0.28, 0.64, 0.09),
				offset = Vector3.new(0.44, 1.18, -0.86),
				mirrored = true,
				color = Color3.fromRGB(214, 164, 136),
				material = "Fabric",
			},
			{
				name = "Nose",
				size = Vector3.new(0.2, 0.14, 0.12),
				offset = Vector3.new(0, 0.04, -0.48),
				attach = "head",
				color = Color3.fromRGB(28, 24, 26),
			},
			{
				name = "ChestPatch",
				size = Vector3.new(0.5, 0.44, 0.38),
				offset = Vector3.new(0, 0.02, -0.44),
				color = Color3.fromRGB(136, 94, 82),
				material = "Fabric",
			},
			{
				name = "BellyPatch",
				size = Vector3.new(0.56, 0.36, 0.46),
				offset = Vector3.new(0, -0.18, 0.14),
				color = Color3.fromRGB(146, 102, 86),
				material = "Fabric",
			},
			{
				name = "HindLeg",
				size = Vector3.new(0.1, 0.32, 0.1),
				offset = Vector3.new(0.28, -0.42, 0.34),
				mirrored = true,
				roll = 0.18,
				color = Color3.fromRGB(68, 48, 46),
				material = "Fabric",
			},
			{
				name = "BatFoot",
				size = Vector3.new(0.13, 0.09, 0.15),
				offset = Vector3.new(0, -0.18, 0.08),
				attachTo = "HindLeg",
				mirrored = true,
				color = Color3.fromRGB(58, 40, 38),
				material = "SmoothPlastic",
			},
			{
				name = "BatOuterToe",
				size = Vector3.new(0.035, 0.045, 0.18),
				offset = Vector3.new(0.065, -0.02, -0.14),
				attachTo = "BatFoot",
				mirrored = true,
				yaw = 0.32,
				color = Color3.fromRGB(46, 32, 32),
				material = "SmoothPlastic",
			},
			{
				name = "BatMiddleToe",
				size = Vector3.new(0.03, 0.04, 0.2),
				offset = Vector3.new(0, -0.02, -0.15),
				attachTo = "BatFoot",
				mirrored = true,
				color = Color3.fromRGB(46, 32, 32),
				material = "SmoothPlastic",
			},
			{
				name = "BatInnerToe",
				size = Vector3.new(0.035, 0.045, 0.18),
				offset = Vector3.new(-0.065, -0.02, -0.14),
				attachTo = "BatFoot",
				mirrored = true,
				yaw = -0.32,
				color = Color3.fromRGB(46, 32, 32),
				material = "SmoothPlastic",
			},
			{
				name = "Fang",
				size = Vector3.new(0.08, 0.22, 0.08),
				offset = Vector3.new(0.16, -0.18, -0.39),
				attach = "head",
				mirrored = true,
				color = Color3.fromRGB(255, 248, 232),
			},
			{
				name = "WingFinger",
				size = Vector3.new(0.08, 0.06, 1.16),
				offset = Vector3.new(0.08, 0.04, -0.02),
				attach = "wing",
				mirrored = true,
				pitch = 0.18,
				color = Color3.fromRGB(62, 45, 44),
				material = "SmoothPlastic",
			},
			{
				name = "WingFinger",
				size = Vector3.new(0.07, 0.05, 0.86),
				offset = Vector3.new(0.5, 0.02, 0.14),
				attach = "wing",
				mirrored = true,
				pitch = -0.18,
				color = Color3.fromRGB(62, 45, 44),
				material = "SmoothPlastic",
			},
			{
				name = "WingClaw",
				size = Vector3.new(0.18, 0.14, 0.18),
				offset = Vector3.new(1.2, 0.04, -0.18),
				attach = "wing",
				mirrored = true,
				color = Color3.fromRGB(62, 45, 44),
			},
		},
		-- Fast and shallow, and the ears twitch with it: a bat is a flicker. The
		-- coin swings under it on its own slower clock, which is what stops the
		-- whole silhouette reading as one vibrating object.
		motion = { flapRate = 9, flapAngle = 0.5, twitchEvery = 2.4, charmRate = 2.2, charmBob = 0.22 },
	},
	evolutions = {
		{
			level = 15,
			model = "CoinBatGilded",
			displaySuffix = "Gilded",
			abilityMultiplier = 1.5,
			look = {
				scale = 1.08,
				primary = Color3.fromRGB(104, 78, 58),
				secondary = Color3.fromRGB(222, 172, 102),
				-- The one place a group names its own colour: gilded wing edges
				-- are the tell, and they are the wing rather than a new part.
				wings = {
					size = Vector3.new(2.3, 0.12, 1.5),
					spread = 1.2,
					height = 0.04,
					z = 0.1,
					tilt = -0.12,
					color = Color3.fromRGB(255, 214, 110),
					material = "SmoothPlastic",
				},
				charms = {
					{
						size = Vector3.new(0.8, 0.8, 0.15),
						offset = Vector3.new(-0.52, -1.18, 0.1),
						material = "Plastic",
					},
					{
						size = Vector3.new(0.8, 0.8, 0.15),
						offset = Vector3.new(0.52, -1.18, 0.1),
						material = "Plastic",
					},
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
	ability = { type = "DeadEndPing", params = { cooldown = 30, range = 40 } },
	-- The only slate pet, and the only beak: the rarest thing in the catalogue
	-- should not also be the third round yellow one. The crest is a compass
	-- needle, which is the ability, and the evolution rings it.
	look = {
		primary = Color3.fromRGB(46, 54, 75),
		secondary = Color3.fromRGB(82, 94, 128),
		accent = Color3.fromRGB(150, 190, 255),
		primaryMaterial = "Fabric",
		secondaryMaterial = "Fabric",
		body = Vector3.new(1.12, 1.34, 2.55),
		head = Vector3.new(0.92, 0.9, 0.88),
		headOffset = Vector3.new(0, 0.58, -1.08),
		eyeSize = Vector3.new(0.24, 0.18, 0.12),
		eyeColor = Color3.fromRGB(242, 190, 76),
		eyeRim = { size = Vector3.new(0.34, 0.25, 0.08), color = Color3.fromRGB(22, 28, 44) },
		pupilSize = Vector3.new(0.08, 0.11, 0.05),
		pupilColor = Color3.fromRGB(16, 18, 24),
		catchlight = { size = 0.045, color = Color3.fromRGB(210, 235, 255), material = "Neon" },
		eyeTilt = -0.34,
		eyeSpread = 0.24,
		eyeDepth = 0.48,
		beak = {
			size = Vector3.new(0.34, 0.28, 0.92),
			height = -0.05,
			forward = 0.68,
			color = Color3.fromRGB(235, 176, 70),
			material = "SmoothPlastic",
		},
		wings = { size = Vector3.new(1.92, 0.12, 1.9), spread = 0.92, height = 0.2, z = 0.08, tilt = 0.14 },
		tail = { size = Vector3.new(1.18, 0.12, 1.42), offset = Vector3.new(0, 0.02, 1.72), tilt = -0.28 },
		crest = { size = Vector3.new(0.13, 0.85, 0.13), height = 0.72 },
		details = {
			{
				name = "WingTip",
				size = Vector3.new(0.28, 0.07, 1.42),
				offset = Vector3.new(0.3, 0.02, 0.12),
				attach = "wing",
				mirrored = true,
				pitch = -0.08,
				color = Color3.fromRGB(28, 34, 50),
				material = "Fabric",
			},
			{
				name = "ChestFeather",
				size = Vector3.new(0.68, 0.52, 0.48),
				offset = Vector3.new(0, 0.02, -0.82),
				color = Color3.fromRGB(66, 78, 108),
				material = "Fabric",
			},
			{
				name = "BackFeather",
				size = Vector3.new(0.5, 0.12, 1.32),
				offset = Vector3.new(0, 0.62, 0.32),
				color = Color3.fromRGB(30, 38, 58),
				material = "Fabric",
			},
			{
				name = "SideFeather",
				size = Vector3.new(0.24, 0.08, 1.1),
				offset = Vector3.new(0.5, 0.28, 0.22),
				mirrored = true,
				pitch = -0.12,
				color = Color3.fromRGB(30, 38, 58),
				material = "Fabric",
			},
			{
				name = "TailFeather",
				size = Vector3.new(0.22, 0.07, 1.12),
				offset = Vector3.new(0.36, 0.06, 1.78),
				mirrored = true,
				pitch = -0.22,
				color = Color3.fromRGB(31, 38, 58),
				material = "Fabric",
			},
			{
				name = "Leg",
				size = Vector3.new(0.1, 0.48, 0.1),
				offset = Vector3.new(0.28, -0.54, -0.34),
				mirrored = true,
				color = Color3.fromRGB(184, 126, 58),
				material = "SmoothPlastic",
			},
			{
				name = "CrowTarsus",
				size = Vector3.new(0.13, 0.1, 0.16),
				offset = Vector3.new(0, -0.25, -0.04),
				attachTo = "Leg",
				mirrored = true,
				color = Color3.fromRGB(218, 162, 70),
				material = "SmoothPlastic",
			},
			{
				name = "CrowMiddleToe",
				size = Vector3.new(0.045, 0.045, 0.25),
				offset = Vector3.new(0, -0.02, -0.2),
				attachTo = "CrowTarsus",
				mirrored = true,
				color = Color3.fromRGB(218, 162, 70),
				material = "SmoothPlastic",
			},
			{
				name = "CrowOuterToe",
				size = Vector3.new(0.04, 0.04, 0.2),
				offset = Vector3.new(0.08, -0.02, -0.16),
				attachTo = "CrowTarsus",
				mirrored = true,
				yaw = 0.48,
				color = Color3.fromRGB(218, 162, 70),
				material = "SmoothPlastic",
			},
			{
				name = "CrowInnerToe",
				size = Vector3.new(0.04, 0.04, 0.2),
				offset = Vector3.new(-0.08, -0.02, -0.16),
				attachTo = "CrowTarsus",
				mirrored = true,
				yaw = -0.48,
				color = Color3.fromRGB(218, 162, 70),
				material = "SmoothPlastic",
			},
			{
				name = "CrowBackClaw",
				size = Vector3.new(0.035, 0.035, 0.16),
				offset = Vector3.new(0, -0.02, 0.12),
				attachTo = "CrowTarsus",
				mirrored = true,
				color = Color3.fromRGB(184, 126, 58),
				material = "SmoothPlastic",
			},
		},
		-- A glide, not a flap: the slowest wings here and the widest tail sway,
		-- which is the bird steering rather than climbing. The needle leans on its
		-- base at its own rate, so the crest reads as an instrument settling and
		-- not as a feather.
		motion = { flapRate = 3.2, flapAngle = 0.42, swayRate = 1.4, swayAngle = 0.26, crestRate = 1.4 },
	},
	evolutions = {
		{
			level = 15,
			model = "CompassCrowWayfinder",
			displaySuffix = "Wayfinder",
			abilityMultiplier = 1.4,
			look = {
				scale = 1.08,
				primary = Color3.fromRGB(64, 76, 112),
				secondary = Color3.fromRGB(108, 126, 178),
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
