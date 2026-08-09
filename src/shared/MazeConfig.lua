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
	-- The cycle: closed for DwellClosed, tween open, open for DwellOpen, tween
	-- shut, each drawn per wall from its range. Here rather than only in
	-- MazeGenerator.CFG because these are the numbers a playtest moves, and they
	-- are baked onto the parts as attributes, so a change needs a regenerated world
	-- rather than a restarted service.
	--
	-- Two sums are worth holding in your head while you move them. DwellClosed[2]
	-- plus MovingWallTween[2] is the longest a player can be held at a shut wall,
	-- currently 8 seconds. And the dwells against the tweens are how much of its
	-- life a wall spends standing still, currently about half; raising the dwells
	-- is what turns machinery back into scenery.
	--
	-- Shortening the tween buys both of those and is the wrong lever: it is the
	-- only part of the cycle a player can read as intent, and a wall that snaps
	-- shut is one nobody gets out from under.
	MovingWallTween = { 3, 5 },
	MovingWallDwellClosed = { 1.5, 3 },
	MovingWallDwellOpen = { 5, 9 },
	-- The floor mark under a moving wall: a disc where a rotating one turns, a
	-- rail along the path a sliding one runs. A wall that has already moved is a
	-- wall the player can read; the mark is for the one they are walking up to for
	-- the first time, which was the one that got them.
	--
	-- Transparency is the whole of the tuning and it is the same trade the phantom
	-- has. Too solid and a floor with four of them reads as painted markings rather
	-- than as scuffs the mechanism left; too faint and the hint arrives after the
	-- wall does. Judge it on a lit floor and again on a dark one, where the same
	-- value reads much stronger.
	--
	-- Drawn whatever Config.MovingWallsEnabled says, because that is a runtime
	-- switch on a service and this is geometry: turning the walls off leaves the
	-- marks behind rather than changing what a section is made of. Set the
	-- transparency to 1 to have them drawn and unseen.
	MovingWallMarkColor = Color3.fromRGB(240, 170, 60),
	MovingWallMarkTransparency = 0.45,
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
	-- A fixed count on every level rather than one orb every third level. Three
	-- per tower meant most floors had none at all and the one that did was in a
	-- dead end nobody had a reason to walk into, so the mystery box was something
	-- a player met roughly once a session. It stays a count rather than a chance
	-- for the same reason the coins do: the part count is then a pure function of
	-- these settings instead of the seed, and a double-build still verifies
	-- against a fixed number. Where they land is drawn; how many is not.
	PowerupsPerLevel = 3,
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
	-- Thirty seconds each, where these used to run 8 to 15. Par for a floor is 65
	-- seconds at the top of a tower and 150 at the bottom, so the old durations
	-- expired inside the same corridor the orb was found in and there was barely
	-- anything to spend one on; thirty is most of a floor at the top and about a
	-- fifth of one at the bottom, long enough to change how the rest of the floor
	-- is walked. Freeze is the one to watch when tuning: it is the only kind that
	-- removes a whole system rather than improving the player, so if any of these
	-- wants to come back down it is that one.
	PowerupKinds = {
		Speed = {
			label = "Fast feet",
			duration = 30,
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
			duration = 30,
			color = Color3.fromRGB(150, 255, 170),
		},
		-- Pays twice: a lump sum the moment it is taken, and double value on every
		-- coin picked up while it runs. The lump is what makes it land as a prize
		-- on its own, since a multiplier alone is worth nothing to a player who
		-- has already cleared the floor out; the multiplier is what sends one who
		-- has not back through the dead ends they skipped.
		CoinBoost = {
			label = "Coin rush!",
			duration = 30,
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
			duration = 30,
			color = Color3.fromRGB(220, 200, 255),
			highlightColor = Color3.fromRGB(200, 180, 255),
		},
		Freeze = {
			label = "Freeze!",
			duration = 30,
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
	-- The baseline the upgrades move. Roblox's character default, written down
	-- here because SaveService re-applies it on every spawn and a magic 16 in a
	-- service is how the enemy tuning comment goes stale. Jump used to have two
	-- entries beside it and does not any more: nothing sets a character's jump,
	-- because nothing in a maze is jumped onto or over.
	BaseWalkSpeed = 16,
	-- Pedestal order on the stall, left to right, and the passives only: the
	-- abilities follow them in Config.Abilities.Order. Two lists rather than one
	-- because they are two different questions, and Config.shopOrder joins them,
	-- so adding an ability is one list edit rather than two that can disagree
	-- about what the shop sells.
	--
	-- Changing a key here changes which upgrade a generated pedestal sells, and
	-- nothing about where the pedestal is: buildShop reads the joined list for
	-- the Upgrade attribute and the board text, so a swap moves no geometry. The
	-- count is the thing that does move geometry, the stall being sized to fit
	-- what it sells.
	Order = { "Speed", "Magnet" },
	Upgrades = {
		Speed = {
			Label = "Fast Feet",
			Costs = { 25, 60, 120 },
			-- Absolute studs per second per tier, not a multiplier, so the top
			-- tier is a known 20.5 the enemy band below is tuned against.
			WalkSpeedPerTier = 1.5,
			Color = Color3.fromRGB(120, 235, 255),
		},
		-- Replaced Moon Boots, which bought nothing: a jump reaches no geometry a
		-- maze contains, which is the same reason Jump came out of PowerupRoll
		-- above. This is the shop's answer to a wall instead.
		WallWalker = {
			Label = "Wall Walker",
			Costs = { 30, 75, 150 },
			-- Mode is what makes a row an ability rather than a passive: it is bound
			-- to a key, it competes for the selection, and it spends the charge. A
			-- row without one is Fast Feet, a number that is simply always true.
			Mode = "Hold",
			-- Seconds of phasing a full charge buys, indexed by tier. A list rather
			-- than a per-tier scalar like the passives, because the curve is
			-- deliberately not linear: three seconds is one wall and a moment of
			-- hesitation, ten is a route. It is also the whole balance of the
			-- ability, a floor refilling the charge being the only other limit.
			SecondsPerTier = { 3, 6, 10 },
			Color = Color3.fromRGB(190, 160, 255),
		},
		-- The answer to an enemy where the Wall Walker is the answer to a wall.
		-- Deliberately the same effect as the Ghost orb, down to the attribute it
		-- sets, because a player who has met the orb already knows what this does;
		-- what the shop sells is having it on a key instead of on a floor that
		-- happened to hold one. Longer per tier than the phase because it saves
		-- nothing on its own: cloaked is still walking the same maze.
		Cloak = {
			Label = "Cloak",
			Costs = { 40, 90, 175 },
			Mode = "Hold",
			SecondsPerTier = { 4, 8, 14 },
			Color = Color3.fromRGB(220, 200, 255),
		},
		-- The answer to being lost, which is the third thing a floor does to a
		-- player and the one the compass arrow only half solves: it says which way
		-- and never which turns. Cast rather than Hold, because a route is read in
		-- a glance and a held key would be spent staring at the floor.
		--
		-- The tiers buy both halves at once, a cheaper cast and a longer look, so
		-- a full charge is one cast at tier 1, two at tier 2 and three at tier 3.
		-- Nothing server side happens: TimerGui already draws this route for the
		-- Reveal orb, so the ability is the cast, the charge, and a client event.
		Trailblazer = {
			Label = "Trailblazer",
			Costs = { 35, 80, 160 },
			Mode = "Cast",
			ChargeCostPerTier = { 0.6, 0.45, 0.3 },
			RevealSecondsPerTier = { 8, 13, 20 },
			Color = Color3.fromRGB(150, 255, 170),
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

-- Every key the stall sells, passives first and then abilities. MazeGenerator
-- reads it to lay pedestals out and SaveService reads nothing else: a pedestal
-- carries its own key and both sides resolve that key against Shop.Upgrades, so
-- neither has an opinion about which of the two lists it came from.
--
-- A key with no row is dropped rather than sold, silently, because this is
-- called once per building and thirty warnings a section is not a better bug
-- report than one missing plinth. AbilityService warns by name at startup for
-- the ability half, which is where a new key is actually going to be added.
function Config.shopOrder()
	local keys = {}
	for _, list in ipairs({ Config.Shop.Order, Config.Abilities.Order }) do
		for _, key in ipairs(list) do
			if Config.Shop.Upgrades[key] then
				table.insert(keys, key)
			end
		end
	end
	return keys
end

-- The row, but only if it is an ability. Mode is the whole test, so a caller
-- never has to know Config.Abilities.Order to ask whether a key is one.
function Config.abilityDef(key)
	local def = key and Config.Shop.Upgrades[key]
	if def and def.Mode then
		return def
	end
	return nil
end

-- ============================================================
-- Abilities
-- ============================================================
-- The active half of the shop. An upgrade is a number that is always true; an
-- ability is a verb on a key, and a player who owns three can only be using one
-- at a time. Which one is their choice and it is changeable anywhere, at any
-- point, which is the whole reason this is a block of its own: Fast Feet and
-- Coin Magnet have nothing to choose between.
--
-- Sprint is deliberately not one of these. It is free, it has its own key and
-- its own meter, and it never competes for the selection, because a movement
-- verb every player owns from their first floor is not a thing to give up a
-- phase for (Config.Sprint).
--
-- One charge, not one meter each, and this is the decision the rest of the
-- system falls out of. The charge is a fraction of a floor's budget and each
-- ability spends it at its own rate, so owning three is three ways to spend one
-- floor rather than three floors' worth of resource, and switching on an empty
-- bar buys nothing. It is also one bar to read rather than three, which matters
-- more than it sounds for a player who is still learning to read.
Config.Abilities = {
	-- Selection order. The HUD bar, the number keys and the shop pedestals after
	-- the passives all read this one list, so an ability arrives in all three by
	-- being added here. A key with no Shop.Upgrades row warns and is skipped.
	Order = { "WallWalker", "Cloak", "Trailblazer" },
	-- The charge refills to full on reaching a floor, at the same LevelTrigger
	-- the Wall Walker's meter always refilled at and for the same reason: a tier
	-- is a budget bought for each floor, and MazeProgress is the wrong signal
	-- because a tower's first floor is entered without one having been cleared.
	RefillOnFloor = true,
	-- Below this a Hold will not start and a Cast is refused. The same floor
	-- Config.Sprint.MinimumToStart sets, and the same fraction of a full meter
	-- (0.6 of 4 seconds), for the same reason: an ability that fires, does
	-- nothing and stops on the next frame reads as broken rather than as spent.
	-- A fraction of a charge here, where sprint's is in seconds, so it is worth
	-- the least where the meter is shortest: 0.45s at Wall Walker tier 1, which
	-- at the squeezed 12 studs a second is still five studs and a wall crossed.
	MinimumToStart = 0.15,
	-- How often the charge is pushed to the client while an ability is running.
	-- The client draws between pushes off the same numbers, so it is a correction
	-- rate and not a frame rate.
	PushSeconds = 0.15,
	-- Grace after the charge empties while the running ability says it is not
	-- safe to stop. Only the Wall Walker has an unsafe state (going solid inside
	-- a wall is how somebody gets stuck) but the cap lives here rather than in
	-- that module, because the cap is what stops any future ability riding its
	-- own unsafe state forever.
	GraceSeconds = 6,
	EmptyColor = Color3.fromRGB(230, 80, 80),
	GraceColor = Color3.fromRGB(255, 190, 90),
	-- Intents are select, use and release, and a player holding a key down sends
	-- two of them. The budget is a cost ceiling rather than a correctness
	-- measure, every intent being validated against what they own.
	IntentsPerSecond = 12,
}

-- The Wall Walker at runtime. What a tier buys is Shop.Upgrades.WallWalker
-- .SecondsPerTier; these are how the phase behaves once it is running. Grace
-- moved to Config.Abilities, being the one number the runtime applies to every
-- ability rather than to this one.
Config.WallWalk = {
	-- Radius around the root part that counts as "still in a wall". Wall thickness
	-- is 2, so this clears one comfortably. Erring large only ever extends the
	-- grace, which is the safe direction.
	ClearanceRadius = 2.5,
	HighlightColor = Color3.fromRGB(190, 160, 255),
	HighlightTransparency = 0.45,
	-- Phasing is not free movement: a wall still slows you to a squeeze, which is
	-- what stops the top tier being ten seconds of running in a straight line
	-- through the whole floor.
	WalkSpeedMultiplier = 0.75,
}

-- The Cloak at runtime, and a shorter block than the phase because the effect is
-- one attribute. Unseen is read by EnemyTargeting and is exactly what the Ghost
-- orb sets, so an enemy already knows how to lose you; the shimmer is the only
-- thing this has to draw, and it is a different colour from the orb's so a
-- player can tell a bought cloak from a found one.
Config.Cloak = {
	HighlightColor = Color3.fromRGB(200, 180, 255),
	HighlightTransparency = 0.55,
}

-- Sprint, and the one ability here that nothing sells. Every player has it from
-- their first floor, which is why the stamina regenerates on its own instead of
-- refilling at a LevelTrigger the way the Wall Walker's meter does: a movement
-- verb that runs out for the rest of the floor is a verb people stop reaching
-- for. Fast Feet remains what the shop sells to go faster permanently; this is
-- what the key does.
--
-- It multiplies through WalkSpeedResolver rather than writing WalkSpeed, so it
-- composes with a Speed orb and with the Wall Walker's squeeze instead of
-- replacing whichever landed first.
Config.Sprint = {
	-- Seconds of sprint from full. Short deliberately: long enough to cross a
	-- corridor or reach the next corner ahead of a Charger, nowhere near long
	-- enough to run a floor at sprint speed.
	Seconds = 4,
	-- Stamina per second recovered. Slower than the 1/s it drains at, so a chase
	-- stays a decision about when to spend it rather than a key held permanently.
	RegenPerSecond = 1.6,
	-- Recovery holds off this long after a sprint ends, which is what stops a
	-- tapped key from being a permanent sprint delivered at a stutter.
	RegenDelaySeconds = 1,
	-- Enemies are tuned on the rule that no sustained enemy speed reaches the
	-- unupgraded 16 (Config.Enemies.MaxChaseSpeed is 15), so a straight corridor
	-- is always an escape. Sprint does not change what is escapable, it changes
	-- how long the escape takes: 25.6 unupgraded, 32.8 on top of Fast Feet, for
	-- four seconds. Charger's telegraphed charge is still the one thing that
	-- catches a sprinting player, which is the point of its being telegraphed.
	WalkSpeedMultiplier = 1.6,
	-- Stamina below this cannot start a sprint. Without a floor, an empty meter
	-- is a key that fires, moves nobody a stud, and stops again on the next
	-- frame, which reads as the ability being broken rather than spent.
	MinimumToStart = 0.6,
	-- Standing still neither drains the meter nor refills it. Draining would
	-- charge a player for a key they are holding through a moving wall's dwell,
	-- and refilling would make hold-and-stop the fastest way to sprint.
	MoveThreshold = 0.1,
	-- How often the meter is pushed while it is moving. Same rate and the same
	-- reason as Config.Abilities.PushSeconds: the client draws between pushes off
	-- these numbers, so it is a correction rate, not a frame rate.
	PushSeconds = 0.15,
	Color = Color3.fromRGB(120, 240, 170),
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
-- Pets and eggs
-- ============================================================
-- Tuning only. The pet and egg catalogues are content and live in
-- ReplicatedStorage.PetCatalog and ReplicatedStorage.EggCatalog, because a
-- catalogue grows by entries where this grows by edits, and this file is long
-- enough already. Everything here is a number a playtest might move.

Config.Pets = {
	Enabled = true,
	-- What one "maze" is, for hatching and for XP. "tower" counts a tower topped
	-- out; "floor" counts a floor cleared. This is the number that silently
	-- rescales every mazesRequired in EggCatalog, so it is not a knob to flip on
	-- a whim: at "tower" the Summit Egg is two full climbs, at "floor" it is two
	-- floors. TowerTimerService fires both kinds on the MazeProgress bindable, so
	-- changing this needs no service edit, only a pass over the catalogue.
	HatchUnit = "tower",
	MaxEquipped = 1,
	PetStorageCap = 25,
	EggStorageCap = 5,
	-- Granted once, on the first join that finds an empty profile. Without it a
	-- new player has no way into the loop at all, since the only other sources
	-- are the summit pedestal (which costs coins they have not earned) and a
	-- seven day streak.
	StarterEggId = "summit_common",
	StreakEggId = "streak_seven",

	-- XP for the pet that is equipped when the maze is finished. A tower is worth
	-- eight floors rather than ten, so climbing is always better than farming the
	-- same floor, and the firefly's first level costs exactly one tower.
	XpPerFloor = 12,
	XpPerTower = 100,

	-- The follower. It is anchored and moved by CFrame rather than walked: a
	-- pathfinding pet in a maze whose walls move is a pet permanently stuck
	-- behind one, and a physics pet is one more thing to shove a player off a
	-- roof. Lerp is the fraction of the remaining gap closed per second.
	FollowDistance = 5.5,
	FollowSide = 2.5,
	FollowHeight = 3.2,
	FollowLerp = 7,
	-- Past this the pet stops easing and simply appears, which is what carries it
	-- through a slide, a zipline and a death respawn without a special case each.
	FollowTeleportRange = 60,
	BobHeight = 0.45,
	BobSeconds = 2.6,
	SpinDegreesPerSecond = 45,

	PromptDistance = 12,
	PromptHoldSeconds = 0.25,

	-- Daily reward. Coins and XP both scale with the streak, and day seven pays
	-- the streak egg on top. StreakLength is where the streak wraps back to one,
	-- so the egg is a weekly event rather than a one-off.
	DailyStreakLength = 7,
	DailyCoinBase = 25,
	DailyCoinPerStreak = 15,
	DailyXpBase = 60,
	DailyXpPerStreak = 30,

	NicknameMaxLength = 20,

	-- Hatching at this rarity or better is announced to the whole server. Read
	-- against RarityOrder, so raising it to "Legendary" narrows it without any
	-- other edit.
	BroadcastFrom = "Epic",
	RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary" },
	RarityColors = {
		Common = Color3.fromRGB(200, 205, 215),
		Uncommon = Color3.fromRGB(120, 220, 140),
		Rare = Color3.fromRGB(110, 175, 255),
		Epic = Color3.fromRGB(200, 130, 255),
		Legendary = Color3.fromRGB(255, 200, 90),
	},

	-- These are the first messages this game has ever accepted from a client, so
	-- they get a budget. A player who exceeds it has their extra intents dropped
	-- silently: every intent is idempotent or validated, so the cap is a cost
	-- ceiling rather than a correctness measure.
	IntentsPerSecond = 8,

	-- The Ward ability. How big a ward is and how long it runs are on the pet's
	-- catalogue row, because that is what the pet is; these two are the system's.
	--
	-- The scan is what arms it. A ward that ran on a blind timer would spend most
	-- of its uptime in an empty corridor, so PetService looks for an enemy inside
	-- the radius instead, and looks four times a second rather than every frame:
	-- the enemies it is looking at think at 0.12 and none of them can cross a ward
	-- in a quarter of a second.
	WardScanSeconds = 0.25,
	WardRingTransparency = 0.82,
	-- Studs above the floor the ring is drawn at. It is drawn on the ground and
	-- not around the pet on purpose: an area is something a player reads off the
	-- floor they are standing on, and a halo at pet height says nothing about how
	-- far it reaches.
	WardRingHeight = 0.3,

	-- Presentation.
	HatchRevealSeconds = 2.6,
	BroadcastSeconds = 4,
	PanelWidth = 420,
}

function Config.rarityIndex(rarity)
	for i, name in ipairs(Config.Pets.RarityOrder) do
		if name == rarity then
			return i
		end
	end
	return 1
end

function Config.rarityColor(rarity)
	return Config.Pets.RarityColors[rarity] or Config.Pets.RarityColors.Common
end

-- ============================================================
-- Pet accessories
-- ============================================================
-- Tuning only, and a sibling of Config.Pets rather than a block inside it: the
-- caps below govern player stats the whole game is tuned against, not the pet
-- system. The items themselves are content and live in
-- ReplicatedStorage.AccessoryCatalog. See docs/PET_ACCESSORIES_PLAN.md.

Config.Accessories = {
	Enabled = true,
	-- Four slots against one equipped pet is at most four items live, which is
	-- what makes the caps below reachable but not trivially so. The list is
	-- iterated rather than pairs() over a pet's worn map, so a slot key left in a
	-- saved profile by an older build is ignored instead of scoring.
	Slots = { "Head", "Neck", "Back", "Aura" },
	AccessoryStorageCap = 40,
	-- Half the coin cost, floored. An item with no coinCost has no sale price and
	-- is refused rather than sold for nothing.
	SellFraction = 0.5,

	-- The ceiling on all gear combined, applied once in Inventory.wornEffects so
	-- that no consumer clamps anything.
	--
	-- These are not decoration. EnemyDefinitions is tuned on the stated rule
	-- that sustained enemy speed stays under the unupgraded player's 16 and that
	-- Fast Feet's 20.5 leaves everything behind; gear at +2 puts the ceiling at
	-- 22.5 and moves nothing structural. Uncapped, it eventually makes the par
	-- times Config.getParTime shaves per floor a formality. Whoever raises
	-- WalkSpeed owes the enemy tuning comment at the top of that section a
	-- re-read.
	Caps = {
		WalkSpeed = 2,
		PickupRadius = 5,
		CoinMultiplier = 0.5,
		GlowRange = 25,
		WallWalkSeconds = 4,
		PetXp = 0.35,
		HatchProgress = 0.75,
		RouteVision = 14,
		PhantomSense = 30,
		ScoreBonus = 0.15,
		Armor = 0.4,
	},
}

-- ============================================================
-- Enemies
-- ============================================================
-- Each building carries an EnemyType attribute derived from its style, and
-- every EnemySpawn marker inherits it. Override per section here if you want
-- a whole district to feel different regardless of building style.

-- Which enemy type a marker holds is decided here. What that type is, what it
-- is worth in a fight and what it looks like moved to
-- ReplicatedStorage.EnemyDefinitions, on the same split PetCatalog and
-- Config.Pets already use: a roster grows by entries where a system is tuned by
-- edits. The knobs for the system as a whole are Config.Enemies below.
--
-- One rule from the old table is load-bearing enough to restate here, because
-- it is what Config.Enemies.MaxChaseSpeed and the accessory WalkSpeed cap are
-- both written against: no enemy's sustained speed reaches the unupgraded
-- player's 16, so a straight corridor is always an escape. Charger's charge is
-- the single exception and it is a telegraphed straight line.

-- Section index -> enemy type that replaces whatever the building style picked.
-- Leave a section out to keep per-building variety inside it.
Config.SectionEnemyOverride = {
	-- [2] = "Charger",
}

-- Deliberately does not check that the name it returns is a real type. That is
-- EnemyDefinitions.get's job and it warns when it falls back, so a typo in the
-- override table above now says so instead of being quietly skipped in favour of
-- the building's own style. Checking here as well would need this file to require
-- the roster, and would put the fallback in two places.
function Config.resolveEnemyType(sectionIndex, markerType)
	return Config.SectionEnemyOverride[sectionIndex] or markerType or "Drifter"
end

-- The knobs that govern the enemy system as a whole, as opposed to what any one
-- type is. Per-type numbers live on the ReplicatedStorage.EnemyDefinitions rows.
--
-- The flat Config.EnemyXxx keys moved in here at E2, with the service that reads
-- them. There was a window where both existed and it was deliberately kept shut:
-- two names for one number is two numbers as soon as somebody edits the wrong one.
Config.Enemies = {
	-- The hard ceiling on sustained speed, applied by EnemyFactory to every stat
	-- copy so no definition row can put an enemy past it. The player walks at 16
	-- unupgraded, so this is the promise that a straight corridor is always an
	-- escape.
	--
	-- It is a backstop and not the tuning. The shipped band is 6.3 to 13.5, well
	-- under this, and that is where the roster belongs: a type that has to be
	-- clamped is a type whose row is wrong. Burst moves stay exempt, Charger's
	-- chargeSpeed included, because a telegraphed line the player is shown in
	-- advance is a thing to sidestep rather than outrun.
	MaxChaseSpeed = 15,

	-- Global multipliers over every definition row, applied to a per-spawn copy
	-- and never written back into the row itself.
	--
	-- SpeedMultiplier is the one that is not 1, and it is the record of a
	-- playtest: the roster read as a hair too hard and the whole set came down
	-- 10%. Carried here rather than as tenths scattered through nineteen rows,
	-- because the spread between the types is what matters and the next pass
	-- should be able to move all of it at once. The rows stay tidy integers.
	--
	-- Damage is deliberately 1. The brief wanted it halved, and that was right
	-- when the rows still held the brief's numbers; a later playtest raised damage
	-- per type against a hit that is now both telegraphed and escapable, and the
	-- per-type ratios are nothing like uniform, so no single multiplier
	-- reproduces them. That tuning lives in the rows where it can be moved one
	-- type at a time.
	Difficulty = {
		HealthMultiplier = 1,
		DamageMultiplier = 1,
		SpeedMultiplier = 0.9,
		DetectionMultiplier = 1,
		CooldownMultiplier = 1,
		BudgetMultiplier = 1,
	},

	-- Live rigs, server wide and per building, enforced by EnemyService's scan.
	--
	-- They are closer to biting than the note here used to claim. SpawnRange is 190
	-- studs measured in three dimensions and LEVEL_HEIGHT is 20.5, so a player
	-- halfway up a tower is in range of markers nine floors above and below them as
	-- well as the neighbouring buildings: the reachable set is well past 40. That is
	-- the intended sound of a tower with things in it, and the cap is what stops it
	-- also being the frame budget.
	GlobalCap = 40,
	PerBuildingCap = 12,

	-- A rig exists only while somebody is near enough to meet it. Generation places
	-- 3 markers on each of 10 levels in each of 6 buildings, so a section is 180
	-- enemies and the old service built every one of them at world build time and
	-- kept it forever: 360 live Humanoids before anyone had climbed a floor, and
	-- another 180 per lazily generated section. Gating the pathfinding rather than
	-- the rig left the whole cost standing, and a server spending its frame on
	-- hundreds of idle Humanoid state machines is what made the survivors move like
	-- they were underwater.
	--
	-- Spawn and despawn differ so a player pacing the boundary does not thrash the
	-- rig. Despawn is measured from the enemy rather than its marker, so one that
	-- chased somebody across the floor is not deleted out from under them.
	SpawnRange = 190,
	DespawnRange = 260,
	-- Y slack that still counts as the same floor, for both target selection and
	-- noticing that an enemy has fallen down a stairwell and has to walk home.
	-- LEVEL_HEIGHT is 20.5, so this is comfortably inside one storey.
	FloorBand = 16,
	-- How long a marker whose enemy died stays empty. Nothing in the game damages an
	-- enemy yet, so this is reachable only through the Died path; it is kept because
	-- that path is real rather than as a hook for a weapon that may never arrive.
	RespawnSeconds = 25,
	-- Enemies scale up as players climb. The base a level is added to is per type
	-- and lives on its EnemyDefinitions row, since a Swarmer and a Brute have no
	-- business starting from the same number. Dormant with health itself.
	HealthPerLevel = 14,

	-- What a floor may spend on enemies, read by the spawn director at E5 once a
	-- marker is a position rather than an enemy. Base is set to buy roughly the
	-- three cheap enemies a floor holds today, so level 1 does not change feel on
	-- the day the director lands and only the climb gets heavier.
	FloorBudget = {
		Base = 6,
		PerLevel = 1.1,
		Max = 18,
	},

	-- How often a controller thinks, and how often the scan decides which markers
	-- should be holding a rig at all.
	--
	-- This replaces the FastUpdateHz / TargetingHz / PathRecompute pair the plan
	-- asked for at E0, and the reason is worth keeping. Those three described three
	-- rates for a loop that turned out to be one loop: 0.12 is the tick that went
	-- through a playtest, and splitting target selection down to 3 Hz would have made
	-- every enemy in the city up to a third of a second slower to notice anybody in
	-- exchange for skipping a four-element loop over the player list. The frame
	-- spike the staggered groups exist to prevent is handled instead by each
	-- controller starting its thread at a random offset inside one interval, which
	-- costs one wait and changes no timing at all.
	ThinkInterval = 0.12,
	ScanInterval = 0.5,
	-- How stale a plan may get before it is recomputed. A drift test in
	-- EnemyPathfinding covers the player rounding a corner and Path.Blocked covers a
	-- moving wall; this is the backstop under both, and it is not jittered because a
	-- stale plan is a wall walked into.
	PathReplanSeconds = 0.7,

	-- Two stickiness mechanisms answering different questions. The multiplier widens
	-- the leash once a target is held, so a player standing on the boundary is not
	-- picked up and dropped several times a second. The bonus is in studs and is
	-- subtracted from the held target's score, so an enemy between two players
	-- commits to one instead of recomputing into the other one every tick. A single
	-- player only ever exercises the first.
	TargetRetain = 1.25,
	TargetStickinessBonus = 12,

	-- Studs of clearance kept outside a safe zone, so nothing camps the line a
	-- player has to cross to get out of one.
	SafeZoneMargin = 12,
}

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
	EnemyAlert = "rbxasset://sounds/impact_water.mp3", -- one-shot on acquiring a target, and on a Lurker revealing
	EnemyCharge = "rbxasset://sounds/action_jump.mp3", -- one-shot under a Charger's windup, pitched down
	-- The two E4 types that make a noise nothing else makes. Everything else added
	-- in that phase reuses one of the three above, pitched: a Spitter and a Blinker
	-- both read as an alert, and a Warden's slam is the charge thump.
	EnemyShriek = "rbxasset://sounds/impact_water.mp3", -- one-shot at the end of a Shrieker's windup, pitched hard down
	EnemySlam = "rbxasset://sounds/action_jump.mp3", -- one-shot as a Warden's shockwave lands
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
	EnemyEyeColor = Color3.fromRGB(255, 236, 190),
	EnemyAlertVolume = 0.45,
	EnemyChargeVolume = 0.55,
	-- The rig is a hovering shade rather than anything with legs, which is a
	-- decision and not a shortcut: a walk cycle needs either art or a skeleton,
	-- and a thing that floats needs neither and never foot-slides. Everything
	-- below drives Motor6Ds from one Heartbeat loop over the live enemies.
	EnemyBobHeight = 0.42, -- studs the body rises and falls at rest
	EnemyBobRate = 2.1, -- radians per second of that bob
	EnemyLeanAngle = 0.32, -- radians the body tips into its own movement, at full speed
	EnemyTailSway = 0.5, -- radians the trailing segments swing, growing down the chain
	EnemyHandOrbit = 0.35, -- studs the floating hands drift, counter-phase to the bob
	EnemyLookYaw = 0.9, -- radians the head may turn off-body to keep the player in view
	EnemyLookPitch = 0.45,
	-- Neon carries the glow instead of a PointLight. Forty active shades with a
	-- light each is forty lights, and Roblox's budget for those is small enough
	-- that the maze lamps would start dropping out to pay for the enemies.
	EnemyWispTexture = "rbxasset://textures/particles/smoke_main.dds",
	EnemyWispRate = 7,
	EnemyLurkerHiddenTransparency = 0.88, -- what an unrevealed Lurker fades its body to
	-- The things E4's types leave lying around: a Spitter's bolt, a Trapper's
	-- snare, a Blinker's arrival mark, a Burrower's mound, a Warden's ring. Their
	-- sizes and lifetimes are on the rows, since a trap's radius is what the type
	-- is; only how they are drawn is here, and every one of them is drawn in its
	-- own enemy's colour so that a thing on the floor names what put it there.
	EnemyProjectileTransparency = 0.1,
	EnemyTrapTransparency = 0.42,
	EnemyTrapHeight = 0.4, -- studs above the slab a snare disc sits
	EnemyMarkerTransparency = 0.55, -- blink arrival marks and burrow mounds
	EnemyShockwaveSeconds = 0.35, -- how long the ring is drawn for after it lands
	EnemyStatueMaterial = Enum.Material.Slate, -- a Shadow held still by being watched
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
	-- The rounded back. A bare triangle reads as a shape rather than as a
	-- pointer partly because both of its ends look like ends: it is as easy to
	-- read the flat edge as the business end as it is to read the point. A
	-- half-moon on the back is what a compass needle and a mouse cursor both
	-- use to settle that, and it gives the hot tip above something to be the
	-- opposite of.
	-- Width of the half-moon as a fraction of Size, and where its flat edge sits
	-- down the box, also as a fraction of Size. The client cuts the circle in
	-- half rather than hiding the top half behind the triangle, so these two are
	-- independent: the moon cannot grow or drift its way into showing a far side
	-- the way it could when the glyph was what covered it. The glyph does not
	-- fill its box (the same reason TipFraction is larger than it looks), so
	-- BaseY is still an eyeball number for where the triangle's flat bottom
	-- actually falls. Too small a BaseY tucks the moon up behind the glyph and
	-- it shrinks; too large and it detaches downward. Err small: overlap is
	-- invisible, a gap is not.
	BaseDiameter = 0.28,
	BaseY = 0.73,
	RetargetSeconds = 1, -- how often the target part is re-resolved, for lazily built sections
}

return Config
