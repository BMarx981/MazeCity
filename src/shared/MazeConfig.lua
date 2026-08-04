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
	LampBrightness = 1.1,
	MovingWallMinLevel = 4,
	PhantomWallsPerLevel = 4,
}

-- ============================================================
-- Floor timers
-- ============================================================
-- The timer for a floor starts the moment a player touches that floor's
-- LevelTrigger, which the plugin places at the cell the stairs arrive in.

Config.TimerEnabled = true
Config.BaseSeconds = 150          -- allowance for level 0
Config.PerLevelReduction = 6      -- shaved off per floor climbed
Config.MinSeconds = 65            -- floor on the allowance
Config.GraceSeconds = 2           -- ignore re-triggers within this window

-- "restartLevel"  send the player back to the start of the floor they failed
-- "restartTower"  send them back to the tower's ground entrance
Config.FailAction = "restartLevel"

function Config.getLevelTime(level)
	local t = Config.BaseSeconds - (level * Config.PerLevelReduction)
	return math.max(Config.MinSeconds, t)
end

-- ============================================================
-- Enemies
-- ============================================================
-- Each building carries an EnemyType attribute derived from its style, and
-- every EnemySpawn marker inherits it. Override per section here if you want
-- a whole district to feel different regardless of building style.

Config.EnemyProfiles = {
	Drifter = { walkSpeed = 9, damage = 12, leash = 90, attackCooldown = 1.2, color = Color3.fromRGB(120, 160, 220) },
	Stalker = { walkSpeed = 13, damage = 18, leash = 130, attackCooldown = 1.0, color = Color3.fromRGB(200, 150, 90) },
	Sentry = { walkSpeed = 6, damage = 26, leash = 60, attackCooldown = 1.8, color = Color3.fromRGB(150, 150, 160) },
	Swarmer = { walkSpeed = 16, damage = 8, leash = 110, attackCooldown = 0.6, color = Color3.fromRGB(110, 200, 170) },
	Lurker = { walkSpeed = 11, damage = 22, leash = 75, attackCooldown = 1.4, color = Color3.fromRGB(210, 205, 185) },
	Charger = { walkSpeed = 18, damage = 20, leash = 150, attackCooldown = 1.1, color = Color3.fromRGB(210, 100, 95) },
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
Config.SlideMaxSeconds = 30       -- safety release if someone gets stuck
Config.BouncePadCooldown = 0.6

return Config
