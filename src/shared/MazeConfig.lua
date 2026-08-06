-- MazeConfig (ModuleScript) -> ReplicatedStorage.MazeConfig
-- Single place to tune gameplay without regenerating any geometry.

local Config = {}

-- ============================================================
-- World generation
-- ============================================================
-- Read by MazeGenerator and WorldBootstrap at server start. Geometry
-- constants (cell size, wall height, plot layout) live in MazeGenerator's
-- CFG table; these are the knobs meant to change between playtests.

Config.World = {
	Seed = 20260802,
	Levels = 10,
	PregenerateSections = 2,
	LazyGeneration = true,
	-- Three lighting knobs, and they do different jobs. Brightness is overall
	-- level. Range is contrast: a light falls off toward its range, so a short
	-- range lights whatever is under the fixture far harder than the far wall,
	-- which is what glares off a player. Raising Range past the 62.5-stud lamp
	-- spacing flattens that ratio, so the fix for "player glares, walls dim" is
	-- more range and less brightness, not less brightness alone. Ambient, in
	-- default.project.json, is flat fill with no falloff at all; too much of it
	-- and the maze looks unlit and papery.
	LampBrightness = 0.8,
	LampRange = 110,
	-- Lamps per side of the per-floor grid, so 4 means 16 lamps at 50-stud
	-- spacing. This is the one lighting knob that changes part count: 420 parts
	-- per section between 3 and 4. Density matters more than range now that
	-- shadows are on, because a lamp only lights what it can see and nine of
	-- them cannot see into every wing of a 10x10 floor.
	LampGrid = 4,
	-- On. Off means light passes through walls and everything on the floor is
	-- lit by every lamp at once, which clips pale surfaces like a player's skin
	-- no matter what the exposure is set to. Costs shadow-casting lights per
	-- visible floor; turn off first if lighting ever shows up in a perf trace.
	LampShadows = true,
	MovingWallMinLevel = 4,
	PhantomWallsPerLevel = 4,
	-- Phantoms are placed where they measurably shorten the run to the stairs,
	-- not at random, or the player learns they are never worth walking through.
	-- This is the ceiling on how much of the route all of a floor's phantoms may
	-- remove between them; raise it for a shortcut-hunting game, drop it toward
	-- zero to go back to decorative phantoms.
	PhantomMaxShortcut = 0.35,
	-- A phantom is otherwise identical to the wall next to it, same colour, same
	-- material, so this number is the entire difference between a shortcut and a
	-- wall. 0.1 is a pane that is nine tenths there: at 0.25 the corridor behind
	-- showed through far too readily and a phantom stopped looking like a wall at
	-- all, which is the failure this end of the range has. The other end is a
	-- shortcut nobody ever finds, so tune it by eye in a lit corridor and again
	-- in a dark one, where the same value reads much more solid.
	PhantomTransparency = 0.1,
	-- Collectibles. A floor is 100 cells and exactly one of them mattered, so
	-- every dead end was pure punishment. Coins are what turn a wrong turn into a
	-- find: the dead-end ones pay for exploring, and the few on the route the
	-- player is already walking are the tutorial, because a mechanic nobody trips
	-- over in the first thirty seconds is a mechanic nobody learns. Coverage is
	-- deliberately partial rather than one coin per dead end: a Neon coin is
	-- visible from the corridor, so a passage either shows gold or does not, and
	-- the choice to walk down it is an actual choice.
	DeadEndCoinsPerLevel = 10,
	PathCoinsPerLevel = 3,
	-- One powerup every N levels rather than a per-level chance, so the part
	-- count stays a pure function of these settings instead of the seed and a
	-- double-build still verifies against a fixed number. Which kind, and which
	-- cell, are drawn; whether the level has one at all is not.
	PowerupEveryNLevels = 3,
	-- Coins in the arc above each roof bounce pad, which until now launched the
	-- player at nothing. Placed by pure geometry, drawing no random numbers.
	RoofArcCoins = 6,
}

-- ============================================================
-- Floor timers and scoring
-- ============================================================
-- The timer for a floor starts the moment a player touches that floor's
-- LevelTrigger, at the cell the stairs arrive in, and counts up from zero.
-- Par is a target worth points, never a deadline: running long costs score and
-- nothing else. Dying is the only way to lose a floor.

Config.TimerEnabled = true
Config.BaseSeconds = 150 -- par for level 0
Config.PerLevelReduction = 6 -- shaved off par per floor climbed
Config.MinSeconds = 65 -- floor on par
Config.GraceSeconds = 2 -- ignore re-triggers within this window

-- "restartLevel"  respawn at the start of the floor the player died on
-- "restartTower"  respawn at the tower's ground entrance, losing floor progress
Config.DeathAction = "restartLevel"

function Config.getParTime(level)
	local t = Config.BaseSeconds - (level * Config.PerLevelReduction)
	return math.max(Config.MinSeconds, t)
end

-- Clearing a floor pays a flat base plus SpeedBonusPerSecond for every second
-- under par, and the whole award scales with how high the floor was. Reaching
-- the roof pays TowerBonus on top of the last floor's award.
Config.Scoring = {
	FloorClearBase = 100,
	SpeedBonusPerSecond = 4,
	LevelMultiplier = 0.15, -- award is multiplied by 1 + level * this
	TowerBonus = 1000,
}

function Config.scoreFloor(level, elapsed)
	local s = Config.Scoring
	local saved = math.max(0, Config.getParTime(level) - elapsed)
	local raw = s.FloorClearBase + saved * s.SpeedBonusPerSecond
	return math.floor(raw * (1 + level * s.LevelMultiplier))
end

-- ============================================================
-- Collectibles
-- ============================================================
-- Coins are a second currency, not score: score measures how fast a floor was
-- cleared and coins measure how much of it was looked at, so a player who is
-- slow because they explored is not punished twice. Milestone P is what gives
-- them somewhere to go.
--
-- A coin taken is gone for everyone and comes back on a timer, so a floor
-- restarted after a death is worth walking again.
--
-- MazeGenerator no longer reads any of the powerup tables: it places an orb and
-- stops there. PickupService rolls what the orb turns out to be when it is
-- touched, which is why the roll list is an ordinary list here rather than a
-- fixed-length one whose length generation depended on.

Config.Collectibles = {
	CoinValue = 1,
	CoinRespawnSeconds = 25,
	PowerupRespawnSeconds = 75,
	-- Coins spin on the client only, and only within this range: it is a visual
	-- on an anchored part, so it never leaves the machine that drew it and the
	-- server's idea of where the coin is never moves.
	SpinDegreesPerSecond = 150,
	SpinRange = 80,
	SpinRefreshSeconds = 0.5,
	-- Touching a coin is not how a coin is collected any more. A 3.4-stud disc
	-- reached by Touched alone had to be walked into almost exactly, which reads
	-- as the coin being broken rather than as the player having missed; the roof
	-- arcs were worse, since a coin at ARC_RADIUS 3.2 left about half a stud of
	-- margin against a torso on a vertical launch. PickupService sweeps this
	-- radius around each player instead, and Touched stays as the instant path.
	PickupRadius = 8,
	PickupSweepSeconds = 0.07,
	-- What an orb can turn out to be. Rolled by PickupService when the orb is
	-- touched, not stamped by MazeGenerator when it is built, so an orb is a
	-- mystery box: the same orb is a different thing to the second player to reach
	-- it, and to the same player after it respawns. Nothing in generation reads
	-- this list any more, which is why entries can now be added and removed freely
	-- where the old generation-time draw made the length load-bearing.
	--
	-- Jump used to be here and was dead weight, there being nothing in a maze to
	-- jump onto or over.
	PowerupRoll = { "Speed", "Reveal", "CoinBoost", "Ghost", "Freeze" },
	-- The one colour every orb wears, since the effect is unknown until it is
	-- taken. Deliberately not any of the per-kind colours below: those are what
	-- the banner and the HUD chip use once the roll has happened.
	PowerupOrbColor = Color3.fromRGB(255, 250, 225),
	PowerupKinds = {
		Speed = {
			label = "Fast feet",
			duration = 12,
			walkSpeedMultiplier = 1.45,
			color = Color3.fromRGB(120, 235, 255),
		},
		-- The route to the stairs, lit as a trail of markers the player can follow.
		-- The compass says which way; this says which turns, which is the whole
		-- difference on a floor where the arrow points through four walls. Entirely
		-- client-side: MazeGenerator stamps the route on each LevelTrigger and
		-- TimerGui draws it, so PickupService has no effect to apply or undo.
		Reveal = {
			label = "Show the way",
			duration = 10,
			color = Color3.fromRGB(150, 255, 170),
		},
		-- Pays twice: a lump sum the moment it is taken, and double value on every
		-- coin picked up while it runs. The lump is what makes it land as a prize
		-- on its own, since a multiplier alone is worth nothing to a player who
		-- has already cleared the floor out; the multiplier is what sends one who
		-- has not back through the dead ends they skipped.
		CoinBoost = {
			label = "Coin rush!",
			duration = 15,
			coinGrantMin = 10,
			coinGrantMax = 30,
			coinMultiplier = 2,
			color = Color3.fromRGB(255, 214, 110),
		},
		-- Not invisibility to other players: enemies stop seeing you, which is
		-- the only thing that matters in a game with no combat, and it cannot
		-- strand anyone the way a walk-through-walls ghost could.
		Ghost = {
			label = "Unseen",
			duration = 10,
			color = Color3.fromRGB(220, 200, 255),
			highlightColor = Color3.fromRGB(200, 180, 255),
		},
		Freeze = {
			label = "Freeze!",
			duration = 8,
			color = Color3.fromRGB(255, 255, 255),
		},
	},
}

function Config.getPowerupKind(name)
	return Config.Collectibles.PowerupKinds[name] or Config.Collectibles.PowerupKinds.Speed
end

-- ============================================================
-- Shop and persistence
-- ============================================================
-- The shop is what coins are for. One stall per tower plaza, built by the
-- generator as a pure function of the door position (invariant 6: no random
-- numbers), bought from via ProximityPrompts that SaveService binds through the
-- ShopItem tag. Upgrades are permanent, tiered, and paid for out of
-- leaderstats.Coins; SaveService owns the profile they live in.
--
-- Costs are tuned against a floor paying 13 coins fully explored: the first
-- tier of something lands inside the first tower, the last tier is a few
-- towers of pocket money, and nothing is ever locked, only slower.

Config.Shop = {
	-- The baseline the upgrades move. These are Roblox's character defaults,
	-- written down here because SaveService re-applies them on every spawn and
	-- a magic 16 in a service is how the enemy tuning comment goes stale.
	BaseWalkSpeed = 16,
	BaseJumpPower = 50,
	BaseJumpHeight = 7.2,
	-- Pedestal order on the stall, left to right.
	Order = { "Speed", "Jump", "Magnet" },
	Upgrades = {
		Speed = {
			Label = "Fast Feet",
			Costs = { 25, 60, 120 },
			-- Absolute studs per second per tier, not a multiplier, so the top
			-- tier is a known 20.5 the enemy band below is tuned against.
			WalkSpeedPerTier = 1.5,
			Color = Color3.fromRGB(120, 235, 255),
		},
		Jump = {
			Label = "Moon Boots",
			Costs = { 20, 50, 100 },
			-- Fractional boost per tier, applied to whichever jump system the
			-- character is using (JumpPower or JumpHeight).
			JumpBoostPerTier = 0.15,
			Color = Color3.fromRGB(190, 160, 255),
		},
		Magnet = {
			Label = "Coin Magnet",
			Costs = { 30, 70, 140 },
			-- Studs added to PickupService's sweep radius per tier. The base
			-- radius is Collectibles.PickupRadius; three tiers roughly doubles it,
			-- which inhales a corridor of coins without vacuuming through walls
			-- badly enough to feel like cheating.
			RadiusPerTier = 2.5,
			Color = Color3.fromRGB(255, 214, 110),
		},
	},
	PromptDistance = 10,
	PromptHoldSeconds = 0.25,
}

-- One DataStore profile per player: coins, upgrade tiers, furthest section
-- reached. A profile that fails to load is never saved over, so a Studio
-- session without API access (or a bad day at the datastore) degrades to
-- session-only progress rather than wiping anything.
Config.Persistence = {
	DataStoreName = "MazeCityProfiles",
	-- Version lives in the key, so a schema change starts clean without
	-- touching old data.
	KeyPrefix = "v1_p_",
	AutosaveSeconds = 90,
}

-- ============================================================
-- Enemies
-- ============================================================
-- Each building carries an EnemyType attribute derived from its style, and
-- every EnemySpawn marker inherits it. Override per section here if you want
-- a whole district to feel different regardless of building style.

-- Every walkSpeed here is below the unupgraded player's 16, on purpose: a
-- straight corridor is always an escape, even for a player who has never
-- bought anything, so no chase is ever unwinnable and no enemy can corner a
-- player who keeps moving. Threat is carried by the growl, the eyes, the
-- windup flash and the chase itself, Pac-Man style, not by the numbers.
--
-- The Shop's Fast Feet upgrade moves the player baseline as high as 20.5, so
-- the band sits deliberately high in the space under 16: a fresh player still
-- escapes but feels the pressure, and an upgraded one walks away from
-- everything with ease, which is exactly what they paid for. The spread is
-- what makes the types feel different: a Charger is close enough to keep the
-- pressure on, a Sentry is a thing to walk around. Damage is low enough that a
-- bad corner costs progress toward the speed bonus rather than the floor.
-- Leashes are wide enough to cross most of a 250-stud floor.
Config.EnemyProfiles = {
	Drifter = { walkSpeed = 13, damage = 6, leash = 150, attackCooldown = 1.2, color = Color3.fromRGB(120, 160, 220) },
	Stalker = { walkSpeed = 14.5, damage = 9, leash = 190, attackCooldown = 1.0, color = Color3.fromRGB(200, 150, 90) },
	Sentry = { walkSpeed = 12.5, damage = 13, leash = 120, attackCooldown = 1.8, color = Color3.fromRGB(150, 150, 160) },
	Swarmer = { walkSpeed = 15, damage = 4, leash = 170, attackCooldown = 0.6, color = Color3.fromRGB(110, 200, 170) },
	Lurker = { walkSpeed = 13.5, damage = 11, leash = 135, attackCooldown = 1.4, color = Color3.fromRGB(210, 205, 185) },
	Charger = { walkSpeed = 15.5, damage = 10, leash = 210, attackCooldown = 1.1, color = Color3.fromRGB(210, 100, 95) },
}

-- Section index -> enemy type that replaces whatever the building style picked.
-- Leave a section out to keep per-building variety inside it.
Config.SectionEnemyOverride = {
	-- [2] = "Charger",
}

-- Enemies scale up as players climb.
Config.EnemyHealthBase = 90
Config.EnemyHealthPerLevel = 14
Config.EnemyRespawnSeconds = 25
-- Enemies with no player inside this radius stop pathfinding entirely. Keep it
-- above the largest leash above, or the leash is what stops mattering.
Config.EnemyActivationRange = 220

function Config.resolveEnemyType(sectionIndex, markerType)
	local override = Config.SectionEnemyOverride[sectionIndex]
	if override and Config.EnemyProfiles[override] then
		return override
	end
	if markerType and Config.EnemyProfiles[markerType] then
		return markerType
	end
	return "Drifter"
end

function Config.getProfile(enemyType)
	return Config.EnemyProfiles[enemyType] or Config.EnemyProfiles.Drifter
end

-- ============================================================
-- Moving walls
-- ============================================================

Config.MovingWallsEnabled = true
Config.MovingWallEasing = Enum.EasingStyle.Sine
-- If a player is standing in the space the wall is about to occupy, the move
-- is postponed by this many seconds rather than shoving them.
Config.MovingWallRetrySeconds = 3

-- ============================================================
-- Slides and roof toys
-- ============================================================

-- SlideEntrySpeed is the shove given on touching a SlideEntrance; the boosters
-- along the run then hold the rider at SlideBoostSpeed. The generator stamps
-- both BouncePadPower and SlideBoostSpeed onto the parts it makes, so changing
-- them here only affects sections generated afterwards; the service-side
-- fallbacks cover parts built before the change.
Config.SlideEntrySpeed = 30
Config.SlideBoostSpeed = 105
Config.SlideMaxSeconds = 30 -- safety release if someone gets stuck
-- BouncePadPower is the launch off a standing start: 140 against Roblox gravity
-- is very close to 50 studs, which is what ARC_TOP_HEIGHT = 40 was sized inside.
-- MomentumGain is what makes a pad a trampoline rather than a launcher. A pad
-- returns this fraction of the speed you landed on it with, so bouncing in place
-- climbs by itself and the player learns the rule in two bounces without being
-- told it. MaxPower is the ceiling that keeps the climb from running away: 210
-- tops out around 112 studs above the deck, high enough to read as ridiculous
-- and low enough that a drift off the parapet is still a landing on the plaza.
Config.BouncePadPower = 140
Config.BouncePadMomentumGain = 0.55
Config.BouncePadMaxPower = 210
-- Horizontal speed carried through a bounce. Above 1 so that running onto a pad
-- throws a genuine arc instead of dropping the player back on the same square.
Config.BouncePadForwardKeep = 1.35
Config.BouncePadCooldown = 0.35
-- Consecutive bounces without landing elsewhere ring the boing a step higher,
-- the same trick the coin streak uses. Audio only; the height comes from the
-- momentum rule above, so the sound is reporting the climb rather than faking it.
Config.BouncePadComboSeconds = 2.5
Config.BouncePadPitchStep = 0.07
Config.BouncePadPitchMax = 1.6

-- The roof zipline down to the plaza. The ride is a tween along the cable
-- rather than physics on a rope: the drop is 195 studs onto a street with a
-- 380-stud void two plots away, and a rider who clips off the line mid-descent
-- has no way back. Speed is studs per second along the cable; the boarding hop
-- is the short move from the deck pad out to the cable itself.
Config.ZipSpeed = 95
Config.ZipBoardSeconds = 0.35
Config.ZipMaxSeconds = 20 -- safety release, mirroring SlideMaxSeconds
-- How far under the cable the rider's root part hangs. The ride used to put the
-- root exactly on the cable and aim it down the slope, so the line ran through
-- the character lengthwise and the whole thing read as being impaled rather than
-- as holding on. Five studs is a bit more than root-to-head, which puts the
-- cable just above the hands.
Config.ZipHangOffset = 5

-- ============================================================
-- Sound
-- ============================================================
-- Every asset below is an rbxasset:// path, which ships inside the Roblox
-- client rather than being fetched from the Creator Store: it cannot 404, costs
-- nothing, and needs no ownership check, which matters because a bad audio ID
-- fails silently and reads as a broken effect rather than a missing file. Swap
-- any entry for an "rbxassetid://<id>" string once you have picked something
-- you like; this table is the only place in the codebase that names a sound.

Config.Sounds = {
	FloorClear = "rbxasset://sounds/electronicpingshort.wav", -- bright ping, played as the three-note rise below on clearing a floor
	TowerClear = "rbxasset://sounds/electronicpingshort.wav", -- same ping, played as the arpeggio below, for topping out
	Death = "rbxasset://sounds/uuhhh.mp3", -- the classic Roblox grunt, used as the death sting
	SlideWhoosh = "rbxasset://sounds/action_falling.mp3", -- looping wind, held for the length of a slide ride
	ZipWhoosh = "rbxasset://sounds/action_falling.mp3", -- the same wind on the roof zipline, separate so it can be swapped for a metallic zing
	BouncePad = "rbxasset://sounds/action_jump.mp3", -- boing on launching off a roof pad
	EnemyGrowl = "rbxasset://sounds/bass.mp3", -- looping low drone, louder and higher the closer the enemy is
	PhantomPass = "rbxasset://sounds/impact_water.mp3", -- soft bloop on phasing through a phantom wall
	CoinPickup = "rbxasset://sounds/electronicpingshort.wav", -- the same ping, pitched well up so a coin never reads as a floor clear
	PowerupPickup = "rbxasset://sounds/electronicpingshort.wav",
	-- Topping out plays the ping once per entry: an ascending arpeggio built out
	-- of the one chime, because nothing shipping in the client is a fanfare.
	-- Each entry is { seconds after the banner, PlaybackSpeed }.
	TowerClearArpeggio = { { 0, 1 }, { 0.12, 1.26 }, { 0.24, 1.5 }, { 0.42, 2 } },
	-- Clearing a floor got the same treatment for the same reason: one ping is
	-- an acknowledgement, three rising ones are a reward. Kept to three notes
	-- ending below the tower's top note, so a floor never sounds like a roof.
	FloorClearArpeggio = { { 0, 1 }, { 0.1, 1.26 }, { 0.2, 1.5 } },
	PowerupArpeggio = { { 0, 1.1 }, { 0.08, 1.5 }, { 0.16, 1.9 } },
}

-- ============================================================
-- Juice
-- ============================================================
-- Presentation only. Nothing here changes what is reachable or how much a floor
-- is worth, with one exception: EnemyTellSeconds delays contact damage, which is
-- deliberate. An enemy that hits the instant it touches reads as random; one
-- that flashes first reads as fair and gives a player who is already moving a
-- window to get out of the way.

Config.Juice = {
	FloorClearVolume = 0.5,
	TowerClearVolume = 0.7,
	DeathVolume = 0.6,
	-- Confetti is ScreenGui frames rather than particles, so it costs no
	-- workspace instances and cannot be occluded by a wall the player is facing.
	ConfettiFloor = 44,
	ConfettiTower = 130,
	ConfettiSeconds = 2.2,
	SlideWhooshVolume = 0.45,
	ZipWhooshVolume = 0.5,
	BouncePadVolume = 0.6,
	BounceDustParticles = 26,
	-- Particle textures ship with the client for the same reason the sounds do.
	BounceDustTexture = "rbxasset://textures/particles/smoke_main.dds",
	BounceDustColor = Color3.fromRGB(210, 205, 190),
	EnemyGrowlVolume = 0.5,
	EnemyGrowlRange = 90, -- studs past which the growl is inaudible
	EnemyGrowlNearRange = 10, -- studs inside which it plays at full volume
	EnemyGrowlPitchFar = 0.7,
	EnemyGrowlPitchNear = 0.95,
	EnemyTellSeconds = 0.3, -- warning flash before contact damage lands
	EnemyTellColor = Color3.fromRGB(255, 90, 90),
	EnemyTellReach = 7, -- damage only lands if the player is still this close when the flash ends
	EnemyEyeColor = Color3.fromRGB(20, 20, 24),
	PhantomSparkleVolume = 0.35,
	PhantomSparkleSeconds = 0.7,
	PhantomSparkleParticles = 28,
	PhantomSparkleTexture = "rbxasset://textures/particles/sparkles_main.dds",
	PhantomSparkleColor = Color3.fromRGB(150, 235, 255),
	PhantomSparkleCooldown = 1.5, -- per wall, so brushing along one is not a light show
	CoinVolume = 0.4,
	-- Coins picked up in quick succession ring a step higher each time and reset
	-- once the streak lapses. It is the cheapest way to make a room full of coins
	-- feel like a run rather than a list, and it costs one number of state.
	CoinPitchBase = 1.5,
	CoinPitchStep = 0.06,
	CoinPitchMax = 2.3,
	CoinStreakSeconds = 1.5,
	CoinSparkleParticles = 16,
	CoinSparkleColor = Color3.fromRGB(255, 214, 110),
	PowerupVolume = 0.6,
	PowerupBannerSeconds = 2,
	ShopBannerSeconds = 1.6,
	-- A refused purchase gets the coin ping slowed down instead of a new asset:
	-- same voice, falling instead of rising, which is the whole message.
	ShopDeniedPitch = 0.6,
	-- The Reveal trail. Markers are drawn client-side into their own workspace
	-- folder, never into MazeCity, and one Highlight over the lot of them is what
	-- makes the trail readable through a wall; adorning per marker would blow past
	-- the renderer's highlight budget on a long route. The pulse runs from the
	-- player's end towards the stairs, because a trail that moves says "this way"
	-- and a trail that sits there only says "here".
	RouteDotSize = 1.6,
	RouteDotHeight = 2.5, -- above the floor slab, low enough to read as breadcrumbs
	RouteDotPulseSeconds = 1.4,
	RouteDotPulseScale = 2.1,
	RouteDotFade = 0.25,
}

-- ============================================================
-- Compass arrow
-- ============================================================
-- Client-only hint. By generation invariant 3 the stairs up from floor N arrive
-- at floor N+1's LevelTrigger cell, so the arrow points at the LevelTrigger one
-- level above the player's current floor, and at the RoofTrigger when there is
-- no floor above. It points through walls on purpose: it says which way, never
-- which turn.

Config.Compass = {
	-- Stays on. The arrow is the difference between a hard floor and an unfair
	-- one, and it is the only way to check a generated maze is solvable without
	-- reading the grid, so it is a debugging tool as much as a player aid. If it
	-- ever becomes something bought with coins, this is the switch to flip: the
	-- gate belongs on the server telling the client whether the player owns it,
	-- not on deleting the arrow.
	Enabled = true,
	Size = 64, -- pixels
	HeightOffset = 3.2, -- studs above the player's head
	Color = Color3.fromRGB(255, 220, 120),
	-- The point is a hotter colour than the body. A triangle in one flat colour
	-- reads as a shape rather than as a direction: there is nothing on it for the
	-- eye to land on, so it says "something is here" where it should say "that
	-- way". Colouring only the tip is what makes it a pointer.
	TipColor = Color3.fromRGB(255, 96, 72),
	-- How far down the arrow the tip colour has faded back into Color, as a
	-- fraction of the label. Small is a sharp hot point; past about 0.6 the whole
	-- arrow just looks red and the tip stops being a tip. The glyph does not fill
	-- its box, so this is a bigger number than the visible red fraction.
	TipFraction = 0.42,
	RetargetSeconds = 1, -- how often the target part is re-resolved, for lazily built sections
}

return Config
