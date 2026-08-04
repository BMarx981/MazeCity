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
	LampBrightness = 2.6,
	MovingWallMinLevel = 4,
	PhantomWallsPerLevel = 4,
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

Config.SlideBoostSpeed = 105
Config.SlideMaxSeconds = 30 -- safety release if someone gets stuck
Config.BouncePadCooldown = 0.6

return Config
