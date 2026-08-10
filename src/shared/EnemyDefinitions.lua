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
--   returnSpeed     optional sustained speed for the walk back to its marker
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
-- Every one of the nineteen has a behavior module and a silhouette as of E4,
-- and all nineteen are met in play as of E5: a marker is a position now, and
-- SpawnDirector rolls what stands on it from the whole spawnable roster. A
-- building's style type is the roll's anchor rather than its whole answer, and
-- the role gates in Config.Enemies.Director decide how far up the tower each
-- of the other roles first appears.
--
-- Whole fields are dormant too, and the list is worth keeping honest because a
-- number nobody reads looks exactly like a number that is not working:
--
--   health, and Config.Enemies.HealthPerLevel with it. Nothing damages an enemy,
--           so MaxHealth is set correctly and read by nobody. The Splitter and the
--           Warden's enrage are the two things waiting on it.
--   detection  the brief separates noticing a player (detection) from giving up on
--           one (leash). The system uses leash for both, so an enemy notices from
--           150 studs where its row says 55. Wiring it makes the whole roster
--           easier, which is a tuning pass and not a refactor.
--   memory  seconds it keeps hunting a lost player. A flat 3.5 for everybody,
--           because that is the number that went through a playtest and Drifter's
--           6 would quietly make the city more persistent.
--   turnSpeed, acceleration, aggroDelay, stunDuration
--           entered from the brief, read by nothing. Each needs a mechanic that
--           does not exist yet rather than a line of plumbing.
--
-- spawnCost, role and spawnable came off this list at E5: they are the spawn
-- director's whole diet. What a floor holds is rolled against a budget of
-- spawnCost, balanced across role, and never SplitterChild because of
-- spawnable.
--
-- Two came off that list at E4 and are only partly read, which is worth saying
-- exactly. attackRange is the Ranged behavior's firing range and is read on the
-- Spitter alone; every melee type reaches Config.Juice.EnemyTellReach instead,
-- because how close a hit lands from is a promise the game makes once rather than
-- per type. knockback is read by the two hits heavy enough to shove you, the
-- Brute's swing and the Warden's shockwave, and both telegraph first.
--
-- They are entered correctly anyway, so that adding the mechanic is adding the
-- mechanic and not also a data pass.

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
		-- How long a called Swarmer stays called: it hunts the position it was given
		-- for this long, and holds the widened leash for the same span so it can pick
		-- the player up for itself on the way over.
		alertSeconds = 6,
		alertLeashMultiplier = 1.6,
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
		-- Seconds after losing a player before it is scenery again. Long enough that
		-- backing off and walking straight back in does not meet a fresh ambush.
		rehideSeconds = 6,
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
	-- chargeWindup is the number to be careful with. It is the length of the
	-- telegraph, so it is the whole difference between a move a player sidesteps and
	-- a move that just hits them, and 0.45 is what went through a playtest. The
	-- plan's kid-first default guessed 1.2 before anybody had played one.
	--
	-- damageMultiplier is dormant: a charge lands its hit through the same melee
	-- flow as everything else, so nothing reads this yet.
	behaviorConfig = {
		chargeRange = 95,
		-- Closer than this and there is no room to show the telegraph before the
		-- rush arrives, so it chases instead.
		chargeMinRange = 18,
		chargeCooldown = 4.5,
		chargeWindup = 0.45,
		chargeSeconds = 1.6,
		chargeRecover = 0.8,
		-- Below this it has hit something, which ends the rush early and is the
		-- recovery beat rather than a failure.
		chargeStallSpeed = 4,
		damageMultiplier = 1.6,
	},
}

-- ============================================================
-- The thirteen that landed at E4
-- ============================================================
-- Same shape as the six above and written to the same rule: the silhouette says
-- what the thing does before its behavior gets a chance to. A Brute is the widest
-- thing in the roster and has no tail, a Sprinter is the narrowest and trails
-- four, a Watcher is one enormous eye on a stalk. None of them is the baseline
-- shade in a new colour, which is what the whole recipe system exists to avoid.

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
	-- One enormous eye on a tall thin body, ringed by a small crown, and no hands
	-- at all. It is the only silhouette in the roster that is mostly eye, which is
	-- the entire warning: a thing that does nothing but look at you is a thing that
	-- has already told somebody.
	look = {
		bobScale = 0.3,
		bobRate = 0.6,
		head = 1.9,
		headOffset = 1.9,
		hood = Vector3.new(2.2, 2.6, 2.2),
		hoodOffset = 1.6,
		hoodTransparency = 0.3,
		core = 0.55,
		hands = 0,
		tail = {
			{ size = 1.1, y = -0.5 },
			{ size = 0.7, y = -1.15 },
		},
		crown = { count = 5, size = Vector3.new(0.22, 0.8, 0.22), radius = 0.75, height = 2.6, tilt = 0.45 },
		eyeCount = 1,
		eyeSize = 0.95,
		eyeDepth = 0.9,
	},
	behaviorConfig = {
		scanArc = 120,
		scanPeriod = 4,
		alertRadius = 70,
		alertSeconds = 6,
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
	-- Narrow, drawn out along the line it travels, horns swept backward and four
	-- tail segments streaming behind. Everything about it points the way it is
	-- going, which is what makes the moment it stops to breathe legible.
	look = {
		scale = 0.85,
		bobScale = 1.1,
		bobRate = 2.6,
		head = Vector3.new(1.1, 1.1, 1.6),
		headOffset = 1.5,
		hood = Vector3.new(1.7, 1.6, 2.6),
		hoodOffset = 1.45,
		hoodTransparency = 0.38,
		core = 0.6,
		hands = 0.4,
		handSpread = 1,
		handHeight = 0.7,
		tail = {
			{ size = Vector3.new(1.1, 0.9, 1.5), y = -0.4 },
			{ size = Vector3.new(0.85, 0.7, 1.2), y = -1 },
			{ size = Vector3.new(0.6, 0.5, 0.9), y = -1.55 },
			{ size = Vector3.new(0.38, 0.34, 0.6), y = -2 },
		},
		horns = { size = Vector3.new(0.22, 0.22, 1.5), spread = 0.5, height = 1.7, forward = -0.7, tilt = 0.2 },
		eyeSize = 0.3,
		eyeSpread = 0.26,
	},
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
	-- The widest thing in the roster, plated at the shoulders, with no tail to
	-- stream behind it and hands hanging low. It reads as heavy standing still,
	-- which is the only thing a player needs to know before deciding to walk.
	look = {
		scale = 1.35,
		bobScale = 0.35,
		bobRate = 0.6,
		head = Vector3.new(1.6, 1.2, 1.4),
		headOffset = 1.15,
		hood = Vector3.new(3.2, 2.4, 2.8),
		hoodOffset = 1.1,
		hoodTransparency = 0.15,
		core = 1.4,
		coreOffset = Vector3.new(0, 0.3, -0.3),
		hands = 0.85,
		handSpread = 2,
		handHeight = -0.1,
		tail = {},
		plates = { size = Vector3.new(0.7, 1.8, 2.2), spread = 1.7, height = 1.1 },
		eyeSize = 0.22,
		eyeSpread = 0.4,
	},
	-- swingWindup is three times the melee tell every other type uses, and that is
	-- the trade the whole type is built on: the hardest hit in the roster, shown for
	-- long enough that standing in it is a choice. turnLockDuring is how long it
	-- cannot re-aim afterwards, so stepping around it works.
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
	-- A bulb of a head with three eyes and three motes circling close in. The motes
	-- are the ammunition and they are the tell: a shape with things orbiting it is
	-- a shape that can reach you from where it is standing.
	look = {
		scale = 0.95,
		bobScale = 0.7,
		bobRate = 1.3,
		head = Vector3.new(1.7, 1.5, 1.7),
		headOffset = 1.5,
		hood = Vector3.new(2.4, 2, 2.4),
		hoodOffset = 1.4,
		hoodTransparency = 0.3,
		core = 0.85,
		hands = 0.45,
		handSpread = 1.2,
		handHeight = 0.6,
		tail = {
			{ size = 1.2, y = -0.45 },
			{ size = 0.75, y = -1.1 },
		},
		motes = { count = 3, size = 0.36, radius = 1.5, height = 1.9, rate = 2.2 },
		eyeCount = 3,
		eyeSize = 0.26,
		eyeSpread = 0.26,
	},
	-- attackRange on the row is the firing range and the Ranged module is the only
	-- thing in the game that reads it. preferredDistance is where it wants to stand
	-- and minimumDistance is where it starts backing away, which is what stops the
	-- one enemy with reach from also being a melee enemy.
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
	-- Thin, faint, and orbited by four motes at arm's length. The hood is the most
	-- transparent in the roster on purpose: it is half here before it goes anywhere,
	-- so arriving somewhere else is the same thing it was already doing.
	look = {
		scale = 0.9,
		bobScale = 1.2,
		bobRate = 1.8,
		head = 1.3,
		headOffset = 1.7,
		hood = Vector3.new(1.9, 2.4, 1.9),
		hoodOffset = 1.55,
		hoodTransparency = 0.55,
		core = 0.55,
		hands = 0.38,
		handSpread = 1.1,
		handHeight = 0.8,
		tail = {
			{ size = 0.95, y = -0.45 },
			{ size = 0.6, y = -1.05 },
		},
		motes = { count = 4, size = 0.3, radius = 2.4, height = 1.2, rate = 2.6 },
		eyeSize = 0.28,
	},
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
	-- A wide flared bell with a ring of spines above it, and no hands. It is shaped
	-- like the noise it makes, which is the only warning a player gets that this one
	-- is worth reaching before it reaches everything else.
	look = {
		bobScale = 0.9,
		bobRate = 1.1,
		head = 1.3,
		headOffset = 1.7,
		hood = Vector3.new(3.6, 2.2, 2.2),
		hoodOffset = 1.5,
		hoodTransparency = 0.25,
		core = 0.7,
		hands = 0,
		tail = {
			{ size = 1.2, y = -0.45 },
			{ size = 0.7, y = -1.1 },
		},
		crown = { count = 7, size = Vector3.new(0.2, 0.9, 0.2), radius = 1.5, height = 2.3, tilt = 0.5 },
		eyeSize = 0.3,
		eyeSpread = 0.34,
	},
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
	-- Squat and wide with five small eyes in a row, so the reveal reads as a face
	-- opening across the whole front of it rather than as a shade stepping out.
	--
	-- The disguises are geometry and live here with the rest of the silhouette; the
	-- names in behaviorConfig are the allowlist the behavior may pick from, and it
	-- can only ever choose one that appears in both. A prop the rig cannot draw is
	-- therefore a prop no Mimic wears, rather than an invisible enemy.
	--
	-- None of them is a coin, and that is the one hard rule on this type: the game
	-- spends every floor teaching a kid to grab every coin they can see.
	look = {
		scale = 0.95,
		bobScale = 0.4,
		bobRate = 1.4,
		head = Vector3.new(1.8, 1.1, 1.4),
		headOffset = 1.25,
		hood = Vector3.new(2.6, 1.6, 2.2),
		hoodOffset = 1.2,
		hoodTransparency = 0.2,
		core = 0.8,
		hands = 0.5,
		handSpread = 1.5,
		handHeight = 0.1,
		tail = {
			{ size = 1.1, y = -0.4 },
		},
		eyeCount = 5,
		eyeSize = 0.2,
		eyeSpread = 0.22,
		eyeHeight = 0.05,
		disguises = {
			{
				name = "Crate",
				size = Vector3.new(3.2, 3.2, 3.2),
				color = Color3.fromRGB(150, 110, 70),
				material = Enum.Material.WoodPlanks,
			},
			{
				name = "Lamp",
				size = Vector3.new(1.2, 5.4, 1.2),
				color = Color3.fromRGB(95, 95, 105),
				material = Enum.Material.Metal,
			},
			{
				name = "Sign",
				size = Vector3.new(3.6, 4.2, 0.4),
				color = Color3.fromRGB(110, 115, 125),
				material = Enum.Material.Metal,
			},
		},
	},
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
	-- The only rig wearing plates and horns at once, at the largest scale in the
	-- roster, with three eyes rather than two. Everything the other types have one
	-- of, this has, which is what an elite is supposed to look like from the far end
	-- of a corridor.
	look = {
		scale = 1.3,
		bobScale = 0.45,
		bobRate = 0.8,
		head = 1.5,
		headOffset = 1.7,
		hood = Vector3.new(3, 2.6, 2.8),
		hoodOffset = 1.5,
		hoodTransparency = 0.18,
		core = 1.2,
		coreOffset = Vector3.new(0, 0.35, -0.3),
		hands = 0.7,
		handSpread = 1.8,
		handHeight = 0.3,
		tail = {
			{ size = 1.5, y = -0.5 },
			{ size = 1.05, y = -1.25 },
			{ size = 0.65, y = -1.9 },
		},
		plates = { size = Vector3.new(0.6, 1.6, 2), spread = 1.6, height = 1.15 },
		horns = { size = Vector3.new(0.28, 0.3, 1.4), spread = 0.6, height = 2.1, forward = 0.6, tilt = -0.15 },
		eyeCount = 3,
		eyeSize = 0.34,
		eyeSpread = 0.3,
		eyeDepth = 0.8,
	},
	-- enrageHealthPercent is dormant with health itself: nothing damages an enemy,
	-- so the threshold is never crossed. It is wired anyway, because the day a
	-- weapon exists the Warden should already be the fight it was written to be.
	-- perBuilding is the director's at E5.
	behaviorConfig = {
		shockwaveCooldown = 7,
		shockwaveRadius = 14,
		shockwaveWindup = 1,
		alertRadius = 100,
		alertSeconds = 8,
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
	-- Round, and carrying two motes big enough to read as halves rather than as
	-- sparks. Four small eyes across it, which is two faces' worth on one body.
	look = {
		scale = 1.05,
		bobScale = 0.85,
		bobRate = 1.5,
		head = 1.4,
		headOffset = 1.5,
		hood = Vector3.new(2.9, 2.5, 2.6),
		hoodOffset = 1.4,
		hoodTransparency = 0.32,
		core = 1,
		hands = 0.45,
		handSpread = 1.45,
		handHeight = 0.35,
		tail = {
			{ size = 1.3, y = -0.5 },
			{ size = 0.8, y = -1.15 },
		},
		motes = { count = 2, size = 0.75, radius = 1.7, height = 0.9, rate = 1.1 },
		eyeCount = 4,
		eyeSize = 0.24,
		eyeSpread = 0.24,
	},
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
	-- Tall, narrow and the least transparent hood in the roster, because the whole
	-- type turns on a material change and a translucent statue does not read as
	-- stone. Bright eyes on a dark body so that the thing which is definitely not
	-- moving is still definitely looking.
	look = {
		scale = 1.05,
		bobScale = 0.6,
		bobRate = 0.9,
		head = Vector3.new(1, 1.4, 1),
		headOffset = 2,
		hood = Vector3.new(1.7, 3.2, 1.7),
		hoodOffset = 1.9,
		hoodTransparency = 0.12,
		core = 0.5,
		hands = 0.34,
		handSpread = 0.85,
		handHeight = 0.2,
		tail = {
			{ size = Vector3.new(1, 1.2, 1), y = -0.5 },
			{ size = Vector3.new(0.7, 0.9, 0.7), y = -1.35 },
			{ size = Vector3.new(0.45, 0.6, 0.45), y = -2 },
		},
		eyeSize = 0.26,
		eyeSpread = 0.2,
		eyeDepth = 0.55,
	},
	-- Character facing, server side. There is no client look-direction remote at
	-- all, so there is nothing to validate and nothing to spoof.
	--
	-- minimumMoveDistanceWhileUnseen is what stops it stuttering on the threshold:
	-- once it starts moving it covers at least this far before being allowed to
	-- freeze again, so glancing away and back does not produce a twitch.
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
	-- Low, wide, big-handed, with four tendrils hanging under it. It is the shape of
	-- something that keeps reaching down to the floor, which is where everything it
	-- does happens.
	look = {
		scale = 0.95,
		bobScale = 0.55,
		bobRate = 1.2,
		head = Vector3.new(1.5, 1.1, 1.3),
		headOffset = 1.3,
		hood = Vector3.new(2.8, 1.7, 2.4),
		hoodOffset = 1.25,
		hoodTransparency = 0.3,
		core = 0.75,
		hands = 0.62,
		handSpread = 1.6,
		handHeight = 0.05,
		tail = {
			{ size = 1.2, y = -0.4 },
		},
		crown = { count = 4, size = Vector3.new(0.2, 1.2, 0.2), radius = 1.1, height = -1.1, tilt = -0.2 },
		eyeCount = 3,
		eyeSize = 0.24,
		eyeSpread = 0.26,
	},
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
	-- The only rig that hovers lower than the baseline, drawn forward along its own
	-- horns so they read as claws rather than as a crest. No tail: there is nothing
	-- trailing behind something that spends half its time under the floor.
	look = {
		scale = 1.05,
		bobScale = 0.3,
		bobRate = 1,
		hover = 1.6,
		head = Vector3.new(1.3, 1.1, 1.8),
		headOffset = 1.1,
		hood = Vector3.new(2.4, 1.5, 2.8),
		hoodOffset = 1.05,
		hoodTransparency = 0.22,
		core = 0.8,
		coreOffset = Vector3.new(0, 0.2, -0.35),
		hands = 0.6,
		handSpread = 1.3,
		handHeight = -0.15,
		tail = {},
		horns = { size = Vector3.new(0.32, 0.7, 1.6), spread = 0.75, height = 0.9, forward = 0.85, tilt = 0.35 },
		eyeSize = 0.24,
		eyeSpread = 0.26,
		eyeHeight = -0.05,
	},
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
	-- It hurries back to its post and nowhere else, which is what makes going around
	-- one work: the door closes behind you rather than following you through.
	--
	-- A row field rather than a behaviorConfig multiplier, and for the reason
	-- unwatchedSpeed is one: a second sustained speed has to go through
	-- EnemyFactory's clamp and the difficulty pass like the first, and a multiplier
	-- sitting in a behavior block would reach the humanoid without either.
	returnSpeed = 11,
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
	-- Tall, flat and plated, with a short crown and four eyes across it: a door
	-- standing in a doorway. No tail, because nothing about it is going anywhere.
	look = {
		scale = 1.2,
		bobScale = 0.2,
		bobRate = 0.45,
		head = Vector3.new(1.5, 1.3, 1.2),
		headOffset = 1.35,
		hood = Vector3.new(3.2, 2.6, 2),
		hoodOffset = 1.3,
		hoodTransparency = 0.16,
		core = 1.1,
		coreOffset = Vector3.new(0, 0.3, -0.2),
		hands = 0.6,
		handSpread = 1.9,
		handHeight = 0.1,
		tail = {},
		plates = { size = Vector3.new(0.6, 2, 1.6), spread = 1.75, height = 1.05 },
		crown = { count = 3, size = Vector3.new(0.3, 0.9, 0.3), radius = 0.8, height = 2.4, tilt = 0.2 },
		eyeCount = 4,
		eyeSize = 0.22,
		eyeSpread = 0.26,
		eyeDepth = 0.65,
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
