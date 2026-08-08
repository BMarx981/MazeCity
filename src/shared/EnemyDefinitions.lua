-- EnemyDefinitions (ModuleScript) -> ReplicatedStorage.EnemyDefinitions
-- Content, not tuning. One row per enemy type: what it is, what it is worth in
-- a fight, what it looks like, and the knobs its behavior module reads. The
-- numbers that govern the system as a whole (the speed cap, the difficulty
-- multipliers, caps, budgets, update rates) live in Config.Enemies, on the same
-- split PetCatalog and Config.Pets already use: a roster grows by entries where
-- a system is tuned by edits.
--
-- Shared rather than server-side because the portrait builder runs on the
-- client and draws from the same rows the server spawns from (a client that
-- needs a replicated template folder to draw a bestiary costs the server a copy
-- of every rig).
--
-- ============================================================
-- Schema
-- ============================================================
-- Documented here rather than as Luau types, because the repo carries no
-- annotations and `luac -p` compatibility is worth more than the checking.
--
--   name            string, display name
--   behavior        EnemyTypes.Behavior, which module drives it
--   role            EnemyTypes.Role, what the spawn director balances across
--   spawnable       false to keep the director from ever rolling it directly
--
--   walkSpeed       studs/s, sustained. DESIGN value, see the speed note below
--   unwatchedSpeed  optional second sustained speed, for types that have one
--   chargeSpeed     optional burst speed, exempt from "slower than the player"
--   damage          per hit, already the shipped number
--   health          before the per-level scaling in EnemyFactory
--   leash           studs from its spawn marker it will chase, and no further
--   attackCooldown  seconds between hits
--
--   detection       studs it can notice a player from
--   attackRange     studs it can land a hit from
--   turnSpeed       degrees/s
--   acceleration    studs/s^2
--   aggroDelay      seconds between noticing and committing
--   memory          seconds it keeps hunting a player it has lost
--   stunDuration    seconds it is stunned for by its own failed moves
--   knockback       studs of impulse its hit applies
--   spawnCost       what it costs against a floor's budget
--
--   color           the one colour the whole rig is drawn in
--   look            sparse overrides on ModelGenerator's baseline shade.
--                   Absent means the baseline, which is what the Drifter is.
--   behaviorConfig  per-type knobs, read only by that type's behavior module
--
-- ============================================================
-- Speeds
-- ============================================================
-- Every speed here is a DESIGN value and is not what the game runs at.
-- EnemyFactory multiplies it by Config.Enemies.Difficulty.SpeedMultiplier and
-- clamps the result to Config.Enemies.MaxChaseSpeed, so the shipped band is
-- these integers times 0.9: 6.3 to 13.5, all of it under the unupgraded
-- player's 16, which is the promise that a straight corridor is always an
-- escape.
--
-- The integers are the point. A playtest read the roster as a hair too hard and
-- the whole set came down 10%; carrying that as one multiplier keeps the spread
-- between types legible and makes the next pass one number instead of nineteen.
-- Tenths scattered through this table would be a record of that pass that
-- nobody could read afterwards.
--
-- chargeSpeed is the exception to the cap and deliberately so: it is a straight
-- line the player watches an enemy wind up for, and sidestepping it is the whole
-- interaction. A burst that is not telegraphed does not get the exemption.
--
-- ============================================================
-- What is dormant
-- ============================================================
-- The six types the game ships (Drifter, Stalker, Sentry, Swarmer, Lurker,
-- Charger) are live and their numbers are the playtested ones. The other
-- thirteen have rows and no behavior module yet, so spawning one gets the
-- baseline shade and Chaser-ish nothing until phase E4. Their stats are the
-- brief's, placed into the same bands as the six so that E4 is a module and a
-- silhouette rather than a rebalance.
--
-- health is plumbed and dormant everywhere: nothing in the game damages an
-- enemy, so MaxHealth is a number nothing reads. It is entered correctly anyway,
-- so that adding a weapon is adding a weapon.

local EnemyTypes = require(script.Parent:WaitForChild("EnemyTypes"))

local Behavior = EnemyTypes.Behavior
local Role = EnemyTypes.Role

local types = {}

-- ============================================================
-- The six that are live
-- ============================================================

-- The default, and the one a player meets first. Wanders its spawn cell, chases
-- at a speed that loses ground on every corner. Its look is the baseline every
-- other entry is a delta against, so it has none.
types.Drifter = {
	name = "Drifter",
	behavior = Behavior.Chaser,
	role = Role.Basic,
	walkSpeed = 11,
	damage = 12,
	health = 60,
	leash = 150,
	attackCooldown = 1.4,
	detection = 55,
	attackRange = 4,
	turnSpeed = 180,
	acceleration = 30,
	aggroDelay = 0.25,
	memory = 6,
	stunDuration = 0,
	knockback = 4,
	spawnCost = 2,
	color = Color3.fromRGB(120, 160, 220),
	look = {},
	-- The only type that mills about at its post instead of standing still. It is
	-- a flag rather than a property of Chaser because Stalker, Sprinter and Brute
	-- are Chasers too and all three are supposed to be waiting.
	behaviorConfig = {
		idleWander = true,
	},
}

-- Slows to a crawl while the player is facing it and closes fast the moment
-- they turn away. The one that makes a corridor behind you worth checking.
types.Stalker = {
	name = "Stalker",
	behavior = Behavior.Chaser,
	role = Role.Basic,
	walkSpeed = 9,
	unwatchedSpeed = 15,
	damage = 14,
	health = 70,
	leash = 190,
	attackCooldown = 1.2,
	detection = 70,
	attackRange = 4,
	turnSpeed = 240,
	acceleration = 35,
	aggroDelay = 0.1,
	memory = 10,
	stunDuration = 0,
	knockback = 5,
	spawnCost = 3,
	color = Color3.fromRGB(200, 150, 90),
	-- Tall, narrow, and trailing four segments instead of three: it reads as
	-- something stretched upward and always slightly too close, and the slow deep
	-- bob is what sells it standing still while you look at it.
	look = {
		bobScale = 1.35,
		bobRate = 0.7,
		head = Vector3.new(1.15, 1.5, 1.2),
		headOffset = 2,
		hood = Vector3.new(1.75, 3, 1.8),
		hoodOffset = 1.85,
		hoodTransparency = 0.42,
		core = 0.62,
		hands = 0.4,
		handSpread = 0.95,
		handHeight = 0,
		tail = {
			{ size = 1.15, y = -0.5 },
			{ size = 0.95, y = -1.35 },
			{ size = 0.72, y = -2.1 },
			{ size = 0.5, y = -2.75 },
		},
		eyeSize = 0.3,
		eyeSpread = 0.22,
	},
}

-- Barely leaves its cell. The short leash is the point: it is a hazard with a
-- position, so it can be mapped and walked around, and blundering into one is
-- the most expensive contact in the game.
types.Sentry = {
	name = "Sentry",
	behavior = Behavior.Guard,
	role = Role.Heavy,
	walkSpeed = 12,
	damage = 20,
	health = 110,
	leash = 70,
	attackCooldown = 1.8,
	detection = 50,
	attackRange = 5,
	turnSpeed = 120,
	acceleration = 20,
	aggroDelay = 0.4,
	memory = 7,
	stunDuration = 0.25,
	knockback = 10,
	spawnCost = 4,
	color = Color3.fromRGB(150, 150, 160),
	-- Squat, wide, plated, crowned, and with no tail at all: everything else here
	-- floats and this one is planted, which is the whole of what a player needs to
	-- know about a thing that will not follow them. Four eyes in a row because it
	-- is watching an approach rather than a person.
	look = {
		scale = 1.12,
		bobScale = 0.25,
		bobRate = 0.5,
		head = Vector3.new(1.7, 1.25, 1.5),
		headOffset = 1.25,
		hood = Vector3.new(2.9, 2, 2.6),
		hoodOffset = 1.15,
		hoodTransparency = 0.22,
		core = 1.25,
		coreOffset = Vector3.new(0, 0.25, -0.25),
		hands = 0.6,
		handSpread = 1.75,
		handHeight = 0.15,
		tail = {},
		plates = { size = Vector3.new(0.55, 1.5, 1.9), spread = 1.5, height = 1 },
		crown = { count = 5, size = Vector3.new(0.28, 1.1, 0.28), radius = 1, height = 2.2, tilt = 0.35 },
		eyeCount = 4,
		eyeSize = 0.26,
		eyeSpread = 0.28,
		eyeDepth = 0.7,
	},
}

-- Alone it is nothing. One that spots the player wakes every other Swarmer
-- within packRadius on the same floor, so a bad room produces a crowd.
types.Swarmer = {
	name = "Swarmer",
	behavior = Behavior.Swarmer,
	role = Role.Fast,
	walkSpeed = 13,
	damage = 6,
	health = 35,
	leash = 170,
	attackCooldown = 0.7,
	detection = 60,
	attackRange = 3,
	turnSpeed = 300,
	acceleration = 50,
	aggroDelay = 0,
	memory = 5,
	stunDuration = 0,
	knockback = 2,
	spawnCost = 1,
	color = Color3.fromRGB(110, 200, 170),
	-- Small, one big eye, no hands, and three motes orbiting it. The motes are the
	-- tell: a single Swarmer already looks like several things moving at once,
	-- which is a fair warning about what happens when it calls.
	look = {
		scale = 0.62,
		bobScale = 0.8,
		bobRate = 2.4,
		head = 1.7,
		headOffset = 1.2,
		hood = 2.2,
		hoodOffset = 1.15,
		hoodTransparency = 0.3,
		core = 0.5,
		hands = 0,
		tail = {
			{ size = 1, y = -0.5 },
			{ size = 0.55, y = -1.1 },
		},
		motes = { count = 3, size = 0.42, radius = 2.1, height = 1.3, rate = 1.6 },
		eyeCount = 1,
		eyeSize = 0.72,
		eyeDepth = 0.75,
	},
	behaviorConfig = {
		packRadius = 120,
	},
}

-- Sits dormant and nearly invisible until the player is inside ambushRange, then
-- reveals and commits. Cannot be avoided by anyone who has not learned the
-- floor, which is exactly what makes learning it worth something.
types.Lurker = {
	name = "Lurker",
	behavior = Behavior.Ambusher,
	role = Role.Ambush,
	walkSpeed = 14,
	damage = 16,
	health = 65,
	leash = 120,
	attackCooldown = 1.5,
	detection = 45,
	attackRange = 4,
	turnSpeed = 220,
	acceleration = 35,
	aggroDelay = 0.6,
	memory = 8,
	stunDuration = 0.7,
	knockback = 5,
	spawnCost = 4,
	color = Color3.fromRGB(210, 205, 185),
	-- A wide flat cowl with four eyes in a row and six tendrils hanging under it,
	-- which is the same crown the Sentry wears pointed downward. Broad and low so
	-- that folded against a corridor wall at 0.88 transparency it passes for part
	-- of the maze, which is the only thing this one has to do well.
	look = {
		bobScale = 0.5,
		bobRate = 0.85,
		head = Vector3.new(1.7, 1, 1.3),
		headOffset = 1.35,
		hood = Vector3.new(3.4, 1.5, 2.4),
		hoodOffset = 1.4,
		hoodTransparency = 0.28,
		core = 0.7,
		hands = 0,
		tail = {
			{ size = Vector3.new(2.2, 0.9, 1.6), y = -0.35 },
			{ size = Vector3.new(1.5, 0.7, 1.1), y = -1.05 },
		},
		crown = { count = 6, size = Vector3.new(0.22, 1.5, 0.22), radius = 1.25, height = -1.4, tilt = -0.15 },
		eyeCount = 4,
		eyeSize = 0.28,
		eyeSpread = 0.3,
		eyeHeight = 0.1,
		eyeDepth = 0.55,
	},
	behaviorConfig = {
		ambushRange = 34,
	},
}

-- Slow until it has a clear straight line, then telegraphs and sprints down it,
-- overshoots and has to recover. The only enemy that outruns a player, and only
-- along a line they were shown in advance.
types.Charger = {
	name = "Charger",
	behavior = Behavior.Charger,
	role = Role.Fast,
	walkSpeed = 10,
	chargeSpeed = 27,
	damage = 18,
	health = 90,
	leash = 210,
	attackCooldown = 1.6,
	detection = 80,
	attackRange = 5,
	turnSpeed = 140,
	acceleration = 55,
	aggroDelay = 0.2,
	memory = 9,
	stunDuration = 0.2,
	knockback = 14,
	spawnCost = 5,
	color = Color3.fromRGB(210, 100, 95),
	-- Front-heavy: deep hood, shoulder plates, and two horns swept forward along
	-- the line it is going to travel. The horns are the telegraph before the
	-- telegraph, and a player who has met one once knows what the shape at the end
	-- of the corridor is about to do.
	look = {
		scale = 1.15,
		bobScale = 0.55,
		bobRate = 1.5,
		head = Vector3.new(1.5, 1.35, 1.8),
		headOffset = 1.4,
		hood = Vector3.new(2.5, 2.1, 3),
		hoodOffset = 1.35,
		hoodTransparency = 0.2,
		core = 1.1,
		coreOffset = Vector3.new(0, 0.4, -0.4),
		hands = 0.66,
		handSpread = 1.55,
		handHeight = 0.25,
		tail = {
			{ size = 1.3, y = -0.5 },
			{ size = 0.8, y = -1.15 },
		},
		plates = { size = Vector3.new(0.6, 1.3, 2.1), spread = 1.35, height = 0.95 },
		horns = { size = Vector3.new(0.3, 0.34, 1.9), spread = 0.72, height = 1.9, forward = 0.95, tilt = -0.25 },
		eyeSize = 0.36,
		eyeSpread = 0.34,
		eyeDepth = 0.85,
	},
	-- The windup, rush duration and recovery are still locals in EnemyService and
	-- are deliberately not copied here. They move into this block at E3, with the
	-- behavior module that reads them; entered now they would be two numbers, and
	-- the one the game uses would be the one nobody edited.
	behaviorConfig = {
		chargeRange = 95,
		chargeCooldown = 4.5,
		damageMultiplier = 1.6,
	},
}

-- ============================================================
-- The thirteen with rows and no module yet (phase E4)
-- ============================================================

-- Stationary, sees a long way, and tells everyone. The counterpart to the
-- Sentry: one owns a doorway by standing in it, this one owns a corridor by
-- watching down it.
types.Watcher = {
	name = "Watcher",
	behavior = Behavior.Guard,
	role = Role.Support,
	walkSpeed = 9,
	damage = 10,
	health = 55,
	leash = 110,
	attackCooldown = 1.5,
	detection = 90,
	attackRange = 4,
	turnSpeed = 160,
	acceleration = 20,
	aggroDelay = 0.8,
	memory = 6,
	stunDuration = 0,
	knockback = 3,
	spawnCost = 3,
	color = Color3.fromRGB(235, 210, 90),
	behaviorConfig = {
		scanArc = 120,
		scanPeriod = 4,
		alertRadius = 70,
	},
}

-- Catches a player who dawdles, then has to stop and breathe. The exhaustion is
-- the whole design: it is the fastest thing in the maze and it cannot stay that
-- way, so outrunning one is a matter of holding a line rather than of speed.
types.Sprinter = {
	name = "Sprinter",
	behavior = Behavior.Chaser,
	role = Role.Fast,
	walkSpeed = 12,
	damage = 10,
	health = 35,
	leash = 160,
	attackCooldown = 1.4,
	detection = 60,
	attackRange = 3,
	turnSpeed = 280,
	acceleration = 65,
	aggroDelay = 0,
	memory = 4,
	stunDuration = 0,
	knockback = 2,
	spawnCost = 3,
	color = Color3.fromRGB(240, 150, 70),
	-- The sprint is a multiplier rather than a second speed, so it scales with the
	-- difficulty pass like everything else. 12 * 0.9 * 1.35 is 14.6, which is under
	-- the player's 16: this one is not telegraphed the way a charge is, so it does
	-- not get the burst exemption and its module must clamp the product.
	behaviorConfig = {
		sprintSpeedMultiplier = 1.35,
		sprintDuration = 3,
		exhaustDuration = 2.5,
		exhaustedSpeedMultiplier = 0.55,
	},
}

-- The slowest thing in the game and the hardest to be touched by. Anyone can
-- walk away from it, which is what lets it hit as hard as it does.
types.Brute = {
	name = "Brute",
	behavior = Behavior.Chaser,
	role = Role.Heavy,
	walkSpeed = 7,
	damage = 26,
	health = 150,
	leash = 100,
	attackCooldown = 2.4,
	detection = 35,
	attackRange = 5,
	turnSpeed = 90,
	acceleration = 12,
	aggroDelay = 0.5,
	memory = 5,
	stunDuration = 0.4,
	knockback = 18,
	spawnCost = 6,
	color = Color3.fromRGB(70, 120, 80),
	behaviorConfig = {
		swingWindup = 0.9,
		turnLockDuring = 0.6,
	},
}

-- The only enemy that threatens a player who is keeping their distance, and the
-- reason a corridor is not automatically safe once you have room.
types.Spitter = {
	name = "Spitter",
	behavior = Behavior.Ranged,
	role = Role.Ranged,
	walkSpeed = 9,
	damage = 11,
	health = 50,
	leash = 140,
	attackCooldown = 2,
	detection = 75,
	attackRange = 40,
	turnSpeed = 180,
	acceleration = 18,
	aggroDelay = 0.4,
	memory = 8,
	stunDuration = 0.4,
	knockback = 0,
	spawnCost = 5,
	color = Color3.fromRGB(160, 110, 200),
	behaviorConfig = {
		preferredDistance = 28,
		minimumDistance = 14,
		projectileSpeed = 55,
		projectileLifetime = 3,
		projectileRadius = 1.25,
		slowMultiplier = 0.7,
		slowDuration = 2,
	},
}

-- Arrives somewhere it was not. The arrival warning is what keeps it fair: it
-- can appear beside a player but cannot act for half a second afterwards.
types.Blinker = {
	name = "Blinker",
	behavior = Behavior.Blinker,
	role = Role.Unusual,
	walkSpeed = 10,
	damage = 15,
	health = 60,
	leash = 175,
	attackCooldown = 2.2,
	detection = 65,
	attackRange = 4,
	turnSpeed = 200,
	acceleration = 25,
	aggroDelay = 0.2,
	memory = 10,
	stunDuration = 0.3,
	knockback = 6,
	spawnCost = 6,
	color = Color3.fromRGB(185, 140, 235),
	behaviorConfig = {
		blinkCooldown = 5,
		blinkMinDistance = 12,
		blinkMaxDistance = 35,
		arrivalWarningTime = 0.5,
		minimumPlayerSeparation = 7,
	},
}

-- Barely fights. What it does is tell the floor where you are, which is worse.
-- The alert is filtered to the same building and floor band, because a radius
-- in a maze is not a neighbourhood.
types.Shrieker = {
	name = "Shrieker",
	behavior = Behavior.Shrieker,
	role = Role.Support,
	walkSpeed = 8,
	damage = 5,
	health = 45,
	leash = 100,
	attackCooldown = 3.5,
	detection = 55,
	attackRange = 10,
	turnSpeed = 140,
	acceleration = 15,
	aggroDelay = 0.5,
	memory = 6,
	stunDuration = 0,
	knockback = 0,
	spawnCost = 4,
	color = Color3.fromRGB(240, 150, 190),
	behaviorConfig = {
		alertRadius = 80,
		shriekWindup = 0.7,
		revealDuration = 4,
	},
}

-- Sits still and is scenery until it is not. Never a coin: the game spends
-- every floor teaching a kid to grab every coin it can see, and a coin that
-- bites is the one lesson it must not then teach.
types.Mimic = {
	name = "Mimic",
	behavior = Behavior.Mimic,
	role = Role.Ambush,
	walkSpeed = 12,
	damage = 18,
	health = 70,
	leash = 125,
	attackCooldown = 1.8,
	detection = 20,
	attackRange = 4,
	turnSpeed = 220,
	acceleration = 30,
	aggroDelay = 0,
	memory = 6,
	stunDuration = 0.3,
	knockback = 6,
	spawnCost = 5,
	color = Color3.fromRGB(225, 185, 90),
	behaviorConfig = {
		disguises = { "Crate", "Lamp", "Sign" },
		revealRange = 9,
		revealDuration = 0.5,
	},
}

-- The elite. Everything it does is telegraphed and everything it does hurts,
-- and there is never more than one of them in a building.
types.Warden = {
	name = "Warden",
	behavior = Behavior.Warden,
	role = Role.Elite,
	walkSpeed = 11,
	damage = 22,
	health = 120,
	leash = 230,
	attackCooldown = 1.6,
	detection = 85,
	attackRange = 5,
	turnSpeed = 180,
	acceleration = 25,
	aggroDelay = 0.1,
	memory = 12,
	stunDuration = 0.5,
	knockback = 10,
	spawnCost = 9,
	color = Color3.fromRGB(60, 60, 75),
	behaviorConfig = {
		shockwaveCooldown = 7,
		shockwaveRadius = 14,
		shockwaveWindup = 1,
		alertRadius = 100,
		enrageHealthPercent = 0.35,
		enrageSpeedMultiplier = 1.2,
		perBuilding = 1,
	},
}

-- Two of it, eventually. Dormant in practice until something can damage an
-- enemy, since the split is on death and death is only reachable through debug.
types.Splitter = {
	name = "Splitter",
	behavior = Behavior.Splitter,
	role = Role.Unusual,
	walkSpeed = 11,
	damage = 15,
	health = 90,
	leash = 145,
	attackCooldown = 1.5,
	detection = 55,
	attackRange = 4,
	turnSpeed = 180,
	acceleration = 25,
	aggroDelay = 0.3,
	memory = 7,
	stunDuration = 0,
	knockback = 4,
	spawnCost = 7,
	color = Color3.fromRGB(170, 220, 90),
	behaviorConfig = {
		childType = "SplitterChild",
		childCount = 2,
	},
}

-- What a Splitter leaves behind. Not spawnable on its own: a director that can
-- roll one has an enemy in the world that nothing produced.
types.SplitterChild = {
	name = "Splitter Child",
	behavior = Behavior.Chaser,
	role = Role.Fast,
	spawnable = false,
	walkSpeed = 14,
	damage = 4,
	health = 18,
	leash = 145,
	attackCooldown = 1.2,
	detection = 45,
	attackRange = 3,
	turnSpeed = 300,
	acceleration = 45,
	aggroDelay = 0,
	memory = 5,
	stunDuration = 0,
	knockback = 2,
	spawnCost = 1,
	color = Color3.fromRGB(190, 235, 130),
	look = {
		scale = 0.55,
		bobScale = 0.9,
		bobRate = 2.6,
		hands = 0,
		tail = {
			{ size = 1, y = -0.5 },
		},
		eyeCount = 2,
		eyeSize = 0.3,
	},
	behaviorConfig = {
		canSplit = false,
	},
}

-- Moves only while nobody is looking at it. Watched, it is a statue, and the
-- material change is what says the statue is deliberate rather than stuck.
types.Shadow = {
	name = "Shadow",
	behavior = Behavior.Shadow,
	role = Role.Unusual,
	walkSpeed = 14,
	damage = 17,
	health = 65,
	leash = 180,
	attackCooldown = 1.6,
	detection = 70,
	attackRange = 4,
	turnSpeed = 360,
	acceleration = 60,
	aggroDelay = 0,
	memory = 10,
	stunDuration = 0.5,
	knockback = 5,
	spawnCost = 7,
	color = Color3.fromRGB(85, 65, 110),
	-- Character facing, server side. There is no client look-direction remote at
	-- all, so there is nothing to validate and nothing to spoof.
	behaviorConfig = {
		lookDotThreshold = 0.75,
		minimumMoveDistanceWhileUnseen = 4,
	},
}

-- Leaves things behind rather than doing anything itself. The floor is what it
-- attacks with.
types.Trapper = {
	name = "Trapper",
	behavior = Behavior.Trapper,
	role = Role.Support,
	walkSpeed = 9,
	damage = 8,
	health = 65,
	leash = 140,
	attackCooldown = 2,
	detection = 60,
	attackRange = 4,
	turnSpeed = 160,
	acceleration = 20,
	aggroDelay = 0.3,
	memory = 8,
	stunDuration = 0,
	knockback = 2,
	spawnCost = 6,
	color = Color3.fromRGB(230, 170, 70),
	behaviorConfig = {
		trapCooldown = 5,
		maxTraps = 3,
		trapLifetime = 18,
		trapTriggerRadius = 4,
		slowMultiplier = 0.55,
		slowDuration = 2.5,
	},
}

-- Goes under the floor and comes up somewhere else. The emergence warning has
-- to finish before it can touch anybody, which is the whole of what keeps a
-- thing arriving from below fair.
types.Burrower = {
	name = "Burrower",
	behavior = Behavior.Burrower,
	role = Role.Ambush,
	walkSpeed = 12,
	damage = 16,
	health = 75,
	leash = 170,
	attackCooldown = 2,
	detection = 70,
	attackRange = 5,
	turnSpeed = 220,
	acceleration = 35,
	aggroDelay = 0.4,
	memory = 9,
	stunDuration = 0.2,
	knockback = 8,
	spawnCost = 6,
	color = Color3.fromRGB(150, 110, 80),
	behaviorConfig = {
		burrowCooldown = 6,
		burrowDuration = 2,
		emergenceWarning = 0.8,
		emergenceDistanceMin = 7,
		emergenceDistanceMax = 16,
	},
}

-- A door with opinions. The shortest leash in the roster, so it is a thing to
-- go around rather than a thing that follows.
types.Gatekeeper = {
	name = "Gatekeeper",
	behavior = Behavior.Guard,
	role = Role.Heavy,
	walkSpeed = 8,
	damage = 24,
	health = 130,
	leash = 65,
	attackCooldown = 2,
	detection = 45,
	attackRange = 5,
	turnSpeed = 110,
	acceleration = 15,
	aggroDelay = 0.2,
	memory = 12,
	stunDuration = 0.3,
	knockback = 12,
	spawnCost = 7,
	color = Color3.fromRGB(135, 135, 125),
	behaviorConfig = {
		returnSpeedMultiplier = 1.3,
	},
}

for _, row in pairs(types) do
	table.freeze(row)
end

local EnemyDefinitions = {}

-- Separate from the module table so that iterating the roster cannot hand back a
-- function. A `for name in pairs(EnemyDefinitions)` that yields "get" is a
-- spawn request for an enemy called get, and it fails somewhere else entirely.
EnemyDefinitions.types = table.freeze(types)

-- The one place an unknown type name is caught. A section override or a marker
-- attribute naming a type that does not exist warns and falls back rather than
-- silently becoming something else, because a typo that produces Drifters
-- quietly is a typo nobody finds.
function EnemyDefinitions.get(typeName)
	local row = types[typeName]
	if row then
		return row
	end
	if typeName ~= nil then
		warn("EnemyDefinitions: no row for " .. tostring(typeName) .. ", using Drifter")
	end
	return types.Drifter
end

return table.freeze(EnemyDefinitions)
