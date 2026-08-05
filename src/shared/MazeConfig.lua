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
	LampBrightness = 0.6,
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
-- Enemies
-- ============================================================
-- Each building carries an EnemyType attribute derived from its style, and
-- every EnemySpawn marker inherits it. Override per section here if you want
-- a whole district to feel different regardless of building style.

-- Player WalkSpeed is 16. Anything below that can never close distance in a
-- corridor, which is why four of these used to be harmless. Sentry stays the
-- slow heavy hitter, but at 14 it still gains ground on a player who stops to
-- read a junction. Leashes are wide enough to cross most of a 250-stud floor.
Config.EnemyProfiles = {
	Drifter = { walkSpeed = 15, damage = 12, leash = 150, attackCooldown = 1.2, color = Color3.fromRGB(120, 160, 220) },
	Stalker = { walkSpeed = 17, damage = 18, leash = 190, attackCooldown = 1.0, color = Color3.fromRGB(200, 150, 90) },
	Sentry = { walkSpeed = 14, damage = 26, leash = 120, attackCooldown = 1.8, color = Color3.fromRGB(150, 150, 160) },
	Swarmer = { walkSpeed = 19, damage = 8, leash = 170, attackCooldown = 0.6, color = Color3.fromRGB(110, 200, 170) },
	Lurker = { walkSpeed = 16, damage = 22, leash = 135, attackCooldown = 1.4, color = Color3.fromRGB(210, 205, 185) },
	Charger = { walkSpeed = 21, damage = 20, leash = 210, attackCooldown = 1.1, color = Color3.fromRGB(210, 100, 95) },
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
Config.BouncePadPower = 140
Config.BouncePadCooldown = 0.6

return Config
