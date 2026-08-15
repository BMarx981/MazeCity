-- MazeGenerator (ModuleScript) -> ServerScriptService.MazeGenerator
-- All world generation. Runs on the server at startup, driven by
-- WorldBootstrap. Deterministic: same seed and settings produce an
-- identical world. Never call math.random in this file.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
-- The shape of the roof zipline, shared with TraversalService so the cable this
-- file draws and the curve that file rides are the same curve.
local ZipPath = require(script.Parent:WaitForChild("ZipPath"))
-- Player-facing names for the districts and the towers. Content, so it lives
-- with the catalogues rather than in MazeConfig, and docs/LORE.MD is the source
-- of truth for every word of it.
local Lore = require(ReplicatedStorage:WaitForChild("Lore"))
-- The shape of a section's street maze. Pure, and checked outside Roblox by
-- tools/street: this file draws what that one decides and decides none of it.
local StreetPlan = require(script.Parent:WaitForChild("StreetPlan"))

local MazeGenerator = {}

-- The one collision group generation owns, and the whole of how the Wall Walker
-- upgrade is kept from stranding anyone. Interior and boundary maze walls go in
-- it; the facade, the slabs, the parapets, the stairs and everything on a roof
-- deck do not. A player who is non-collidable against this group can cross any
-- wall on a floor, land in the apron ring between the maze edge and the facade,
-- which has slab under it, and get no further, because the facade is not in the
-- group. Containment falls out of which function built the part rather than
-- needing a test.
--
-- Registered here rather than in WallWalkService because assigning an
-- unregistered CollisionGroup throws, and WorldBootstrap requires this module
-- before it builds anything. The service registers it too, idempotently, in case
-- it loads first.
MazeGenerator.WALL_GROUP = "MazeWall"

-- The second group generation owns, and the mirror image of the first: solid to
-- enemies and absent to everybody else. Two things go in it, and they are the
-- same problem twice.
--
-- A phantom wall is a hole to an enemy, because it is a hole: the one thing that
-- makes it a phantom is CanCollide false, and pathfinding reads exactly that. So
-- a shortcut found by the player was also a shortcut the enemies had always been
-- using, and the wall a player squeezed through was one they could be followed
-- through. In this group a phantom is collidable again, which puts it back in the
-- navmesh, and stays passable to a character because the group says so.
--
-- A stair flight is the same story upside down: it is walkable geometry, and
-- collision groups do not reach the navmesh, so nothing short of an obstacle
-- stops a planner routing an enemy up it. The barrier at the mouth of each flight
-- is that obstacle. Enemies belong to a floor, and this is what makes that true by
-- construction rather than by the floor band noticing afterwards and teleporting
-- somebody home.
--
-- The defining rule is set here because it is what the group means. Every other
-- rule belongs to whichever service owns the other end of it: WallWalkService
-- excuses a phasing player, EnemyFactory asserts the one pair that collides.
MazeGenerator.ENEMY_BLOCK_GROUP = "EnemyBlock"

function MazeGenerator.ensureCollisionGroup(name)
	for _, group in ipairs(PhysicsService:GetRegisteredCollisionGroups()) do
		if group.name == name then
			return
		end
	end
	PhysicsService:RegisterCollisionGroup(name)
end

MazeGenerator.ensureCollisionGroup(MazeGenerator.WALL_GROUP)
MazeGenerator.ensureCollisionGroup(MazeGenerator.ENEMY_BLOCK_GROUP)
PhysicsService:CollisionGroupSetCollidable(MazeGenerator.ENEMY_BLOCK_GROUP, "Default", false)
PhysicsService:CollisionGroupSetCollidable(MazeGenerator.ENEMY_BLOCK_GROUP, MazeGenerator.ENEMY_BLOCK_GROUP, false)
PhysicsService:CollisionGroupSetCollidable(MazeGenerator.ENEMY_BLOCK_GROUP, MazeGenerator.WALL_GROUP, false)

local CFG = {
	MAZE_W = 10,
	MAZE_H = 10,
	CELL = 25,
	WALL_HEIGHT = 18.5,
	WALL_THICKNESS = 2,
	SLAB = 1,
	LEVELS = 10,

	FACADE_OUTSET = 6,
	FACADE_THICKNESS = 2,
	PARAPET_HEIGHT = 9,

	DOOR_WIDTH = 16,
	DOOR_HEIGHT = 13,
	-- Windows are laid out per face with no knowledge of the door, so on the
	-- entry face a ground-floor pane can land across the opening. Any pane
	-- reaching within this margin of the door rectangle is still placed, so the
	-- part count per section is unchanged, but blanked: invisible and no touch.
	DOOR_CLEARANCE = 3,

	PHANTOM_PER_LEVEL = 4,
	-- Most of the route a floor's phantoms are allowed to remove between them.
	-- Uncapped greedy picking cut a typical floor from 60 cells to 12, which
	-- deletes the maze and makes every par time in MazeConfig unreachable in the
	-- wrong direction. Capped, a shortcut is worth hunting for and the floor is
	-- still a floor.
	PHANTOM_MAX_SHORTCUT = 0.35,
	-- A phantom is one of the floor's own walls, in the building's own colour and
	-- material, and the single thing that marks it is that you can see through
	-- it. Transparency is therefore the whole cue, which is what makes this a
	-- config knob: too low and the shortcut is invisible, too high and it reads
	-- as a doorway rather than as a wall worth testing.
	PHANTOM_TRANSPARENCY = 0.25,
	-- Lamps sit on a LAMP_GRID square grid, so spacing is FX/(LAMP_GRID+1): 62.5
	-- studs at 3, 50 at 4. Range stopped being the binding constraint once lamp
	-- shadows went on, because a shadowed lamp only lights corridors it can
	-- actually see into; nine of them leave whole wings of a 10x10 floor dark no
	-- matter how far they reach. Density is the fix, at 7 extra lamps per level,
	-- 420 per section. Config.World.LampGrid drops it back to 3 without an edit.
	LAMP_GRID = 4,
	LAMP_BRIGHTNESS = 2.6,
	-- Range must exceed lamp spacing or the coverage circles leave dark bands
	-- between them, and exceeding it by a lot is also how the near-to-far ratio
	-- gets flattened: a light falls off toward its range, so a short range means
	-- whatever is under the fixture is lit far harder than the far wall.
	LAMP_RANGE = 110,
	LAMP_SHADOWS = true,

	MOVING_WALL_MIN_LEVEL = 4,
	MOVING_WALL_BASE = 2,
	-- A moving wall's cycle is: closed for DwellClosed, tween open, open for
	-- DwellOpen, tween shut. Two different clocks live in here and they are tuned
	-- against each other.
	--
	-- The first is how long the player can be stuck: only the closed half counts,
	-- and arriving just as one shuts costs the full closed dwell plus a tween
	-- before the gap is passable again. That sum, not either range on its own, is
	-- the number that decides whether a wall is an obstacle or a wait. It was 25s,
	-- then 10, and is now 8.
	--
	-- The second is how much of its life the wall spends standing still, which is
	-- what makes a floor read as machinery rather than as scenery that occasionally
	-- twitches. It was about two thirds; it is about half. Both dwells came down to
	-- get there and the open one is the one with a cost: the window in which
	-- arriving at an open wall means walking straight through is shorter, so being
	-- caught by one is now a thing that happens rather than a thing that could.
	-- 5s is still three times what it takes to cross a cell at a walk, and the
	-- closing tween is passable for part of its length on top of that.
	--
	-- Tween is deliberately not shortened to buy either of these. It is the only
	-- part of the cycle the player can read as intent, and a wall that snaps shut
	-- is one nobody gets out from under.
	MOVING_WALL_TWEEN = { 3, 5 },
	MOVING_WALL_DWELL_CLOSED = { 1.5, 3 },
	MOVING_WALL_DWELL_OPEN = { 5, 9 },
	-- Spread over the cycle so neighbouring walls are not in lockstep. Still wider
	-- than the shortest cycle, which is what matters; a phase that wraps is as
	-- decorrelated as one that does not.
	MOVING_WALL_PHASE_MAX = 12,
	-- The floor mark. Thin enough to read as wear rather than as a lip to trip
	-- over, and it sits on the slab rather than in it, so there is no z-fight.
	MOVING_WALL_MARK_THICKNESS = 0.08,
	-- Width of one rail or scratch as a fraction of the wall's own thickness.
	-- Small on purpose: anything approaching the wall's width reads as a strip
	-- of floor somebody painted, where a sliver reads as the track the
	-- mechanism wore into the slab.
	MOVING_WALL_MARK_RAIL_FRAC = 0.22,
	-- Chords per quarter arc under a rotating wall. Three is the fewest that
	-- still reads as a curve at a 13.5 stud radius; the delta per rotating
	-- wall is twice this, one arc per wall tip.
	MOVING_WALL_MARK_ARC_SEGMENTS = 3,
	-- How far the mark's colour sits from the wall's own, as a lerp toward
	-- black. Zero is invisible against the wall; high values are the painted
	-- hazard stripe this replaced. The colour is derived, never absolute, so
	-- every style's marks match its walls without a table to maintain.
	MOVING_WALL_MARK_SHADE = 0.35,
	MOVING_WALL_MARK_TRANSPARENCY = 0.3,

	ENEMY_SPAWNS_PER_LEVEL = 3,

	COIN_DEAD_END_PER_LEVEL = 10,
	COIN_PATH_PER_LEVEL = 3,
	POWERUPS_PER_LEVEL = 3,
	ROOF_ARC_COINS = 6,
	COIN_SIZE = 3.4,
	COIN_THICKNESS = 0.45,
	COIN_HEIGHT = 3.6, -- above the slab, so a coin sits at chest height on a walk past
	POWERUP_SIZE = 4.4,
	POWERUP_HEIGHT = 4.2,
	-- The arc over a bounce pad. A pad at BouncePadPower 140 throws a character
	-- about 50 studs up, so the top coin has to sit inside that and the radius
	-- has to stay inside the width of a character's reach off a vertical launch.
	ARC_RADIUS = 3.2,
	ARC_BASE_HEIGHT = 11,
	ARC_TOP_HEIGHT = 40,
	BOUNCE_PAD_SIZE = 12,
	-- Where the row of pads sits across the deck, and how much daylight is left
	-- between a pad and the crown. The fraction is what the row wants; the
	-- clearance is what it settles for when the crown is wide enough to reach it,
	-- and it is measured to the pad edge rather than its centre, so the whole
	-- launch column is outside the crown and not just the spot underfoot.
	BOUNCE_PAD_Z_FRAC = 0.3,
	BOUNCE_PAD_CLEARANCE = 4,

	-- Crown spans, as fractions of the footprint except the water tank, which is
	-- an absolute width. They are config rather than literals inside buildCrown
	-- because crownHalfSpan reads them too: the crown is the only thing that
	-- stands over the middle of the deck, so its widest piece is what the bounce
	-- pads have to be placed clear of, and a crown that grew without that number
	-- growing with it would put a ceiling back over them.
	CROWN_SETBACK_BODY = 0.45,
	CROWN_SETBACK_CAP = 0.5,
	CROWN_SPIRE_BASE = 0.22,
	CROWN_TANK = 34,

	PLOT_COLS = 3,
	PLOT_ROWS = 2,
	STREET = 90,
	SECTION_GAP = 620,

	-- Zipline off the roof. OUTSET is measured from the maze footprint edge, so
	-- it has to clear the facade face at FACADE_OUTSET + FACADE_THICKNESS = 8 and
	-- the plaza, which reaches 36, without running into the neighbouring plot's
	-- facade at STREET + 8 = 98. Fifty puts it a little past the middle of the
	-- street with room for the landing pad either side. It is now the offset of
	-- the whole wrap rather than of one straight run, so that clearance is held
	-- on all four faces; the corner arcs have the same radius, which is what
	-- makes the spine a true constant-distance offset (see ZipPath).
	ZIP_OUTSET = 50,
	ZIP_DECK_INSET = 8, -- how far inside the parapet the boarding pad sits
	ZIP_END_MARGIN = 14, -- how far in from the facade corner the cable starts
	ZIP_START_LIFT = 6, -- cable height above the roof slab
	ZIP_END_Y = 4, -- cable height where it meets the street
	ZIP_CABLE_THICKNESS = 0.6,
	ZIP_PAD = 12,
	-- The corkscrew about the spine: four rotations, sixteen studs wide at the
	-- roof, tapering to nothing at the landing pad. Sixteen is the widest the
	-- twist can be and still keep the cable clear of the facade at 8 and the
	-- spawn pad at 36 on its way past them, and four rotations over a lap of
	-- roughly 1150 studs is about one turn a second at ride speed.
	--
	-- RISE squashes the swing vertically, and the three numbers are a set: a
	-- circular corkscrew at these turns and this radius climbs 402 studs over a
	-- ride that only descends 197, which puts genuine uphill in every turn.
	-- 0.35 is the most vertical swing that keeps the whole curve descending,
	-- with room to spare. tools/zipline/check.sh is what says so; raising any of
	-- the three without running it is how the uphill comes back.
	ZIP_TWIST_TURNS = 4,
	ZIP_TWIST_RADIUS = 16,
	ZIP_TWIST_RISE = 0.35,
	-- A fixed count, not a length. Path length varies with the door cell, so
	-- dividing by a target segment length would give a part count that differed
	-- building to building for no reason anyone could confirm was the intended
	-- one. Seventy-two is about sixteen studs a segment and eighteen segments a
	-- rotation, which is smooth enough for a cable this thin, and it makes the
	-- delta over the old three-part zipline exactly +71 per building.
	ZIP_SEGMENTS = 72,

	-- Upgrade shop stall on the plaza. OFFSET runs along the facade from the
	-- door centre, putting the stall beside the spawn pad (which reaches 11
	-- either side of the door) without crowding it; OUT is measured from the
	-- maze footprint edge like ZIP_OUTSET, and 20 keeps the stall inside the
	-- plaza band (the facade face is at 8, the spawn pad ends at 36) and well
	-- clear of the zipline landing at 50.
	SHOP_OFFSET = 26,
	SHOP_OUT = 20,
	-- Studs between pedestal centres. A pedestal is 2.4 across, so this is mostly
	-- the gap a player needs to stand at one prompt without the next one taking
	-- the press. It is what the stall's width is derived from now that the list
	-- of what it sells can grow: five pedestals at this pitch is a 31-stud
	-- counter, which the plaza band takes without reaching the zipline landing.
	SHOP_PITCH = 5,

	-- The egg roost, one per roof deck. Placed by pure geometry off the footprint
	-- so it draws no random numbers (invariant 6) and cost a countable +5
	-- instances per building rather than reshuffling the city. The middle of the
	-- deck is the one part of it nothing else uses: the bounce pads sit at
	-- BOUNCE_PAD_Z_FRAC or nearer the parapet than that, the planters at 0.75,
	-- the sign at 0.92, and the stair hole is
	-- always within about 25 studs of an edge because the stairwell is an edge
	-- cell. It is also where a player stepping off the top of the stairs is
	-- looking, which is the whole reason the summit is where an egg goes.
	ROOST_Z_FRAC = 0.55,
	ROOST_BASE = 3.4,
	ROOST_EGG = 3.2,

	STAIR_RISER = 0.75,
	STAIR_WIDTH_FRAC = 0.48,
	STAIR_RUN_CELLS = 1.8,
	-- Clearance left under the slab where the floor above closes over the
	-- stairs, and how far the opening runs past the treads to either side.
	-- Together these size the hole; the cell around it stays floor.
	--
	-- Headroom is the whole of what makes the flight two-way. It was 6, which
	-- after the treads land on it is 5.75 studs over the last covered step, and a
	-- Roblox character is about 5 tall before any avatar scaling: climbing up
	-- scraped through because the tight span is the last thing before the
	-- opening, and walking back down did not, because it is the first. The
	-- ceiling can only be raised by taking floor off the level above, since the
	-- opening grows inward from the top step, and the limit is the wall line one
	-- cell in: at 8 the opening stops 24.23 studs along a 45 stud run, and the
	-- wall between the stair cell and the next sits across 24 to 26, so nothing
	-- on the maze side of it is left standing over a shaft. Past about 8.1 that
	-- wall gets a pit at its foot on the wrong side and a floor gains a fall
	-- nobody can see coming.
	STAIR_HEADROOM = 8,
	STAIR_HOLE_MARGIN = 1,
	-- How far the stairs up have to be from the stairs the player just came up,
	-- as a fraction of the footprint: at 0.5 on a 10x10 that is 5 cells, 125
	-- studs. Unconstrained, a perpendicular exit near the shared corner put the
	-- next flight a cell or two from the arrival, so a fifth of the possible
	-- pairs let a floor be climbed without entering its maze at all.
	STAIR_MIN_SEPARATION_FRAC = 0.5,

	-- Level 0's slab would otherwise top out at Y = 0, exactly level with the
	-- street Ground part, so the lobby floor read as more asphalt. Lifting it
	-- makes the threshold a visible step in. Kept under 2 so a character walks
	-- up it without jumping.
	GROUND_FLOOR_LIFT = 1.5,

	SLIDE_WIDTH = 14,
	SLIDE_SEGMENT_LEN = 40,
	-- How far past the roof's parapet the chute's head hangs. The east parapet
	-- stands at FACADE_OUTSET and is two studs thick, so a chute starting at
	-- FACADE_OUTSET, as this did, began inside that wall: the mouth of the slide
	-- was a nine-stud parapet with the first segment buried in it, and a rider
	-- shoved off the pad hit the wall rather than the chute. Six clears the far
	-- face by five, which is enough for TraversalService to stand the rider on
	-- the head without any part of them inside the parapet. The parapet stays a
	-- closed ring: the way onto the slide is the pad, and a roof edge a player
	-- could walk off is a fall of 195 studs.
	SLIDE_MOUTH_CLEAR = 6,
	-- Where the slide ends, relative to the next section's origin. X was -140,
	-- which put the 70-stud pad's far half over open void: the next section's
	-- Ground starts at -120. Y was 22, so the pad also floated two storeys up and
	-- needed a ramp down to the street. -80 lands the whole pad on the ground
	-- slab, west of the first plot's facade, and 2 makes it a step rather than a
	-- drop, which is why there is no LandingRamp any more.
	SLIDE_LANDING_X = -80,
	SLIDE_LANDING_Y = 2,

	-- The street maze. Structural, so it lives here; what a playtest moves
	-- (cell target, braid, wall height, how many props and signs) is in
	-- Config.World and lands on these through refreshFromConfig.
	--
	-- The target is not a cell size, it is the size the subdivision aims at.
	-- Gridlines have to fall exactly on every plot boundary or a tower gets a
	-- walkable ring around it that no wall can close, so each strip between two
	-- boundaries is cut into round(width / target) cells and the real sizes come
	-- out between 28.0 and 33.3 at 32. One constant produces all of it and it
	-- survives a change to STREET, FACADE_OUTSET or PLOT_COLS.
	--
	-- Because it sets a lane count per strip rather than a width, it moves in
	-- steps: the 86-stud canyon between two plots is two lanes above a target of
	-- 34 and three below it, which is the whole difference between a street you
	-- walk through and one you read. Config.World.StreetCellTarget has the rest.
	STREET_CELL_TARGET = 32,
	STREET_ENABLED = true,
	STREET_BRAID = 0.5,
	STREET_BLOCK_PROPS = 55,
	STREET_TRIM_PROPS = 70,
	STREET_SIGNPOSTS = 24,
	STREET_SIGN_ARMS = 3,
	STREET_WALL_HEIGHT = 16,
	-- The perimeter ring, and the only street height the slide constrains. It
	-- is its own number rather than the maze's because the two are bounded by
	-- different things and one of the two bounds is tight: the slide from the
	-- previous section crosses the west edge of this ground at Y 14.3 and is a
	-- physics ride, so a ring standing in it stops the rider over the void, and
	-- tools/street asserts the clearance. Nothing in the MAZE stands under that
	-- line: the slide is over the ground for its last forty studs and every one
	-- of them is inside the landing's reserved room, which is why the maze wall
	-- above is free to be as tall as an overlook deck allows.
	STREET_EDGE_HEIGHT = 12,
	STREET_WALL_THICKNESS = 2,
	-- Growth on the reserved apron around each door, applied along the facade
	-- and outward but never inward: the inner edge is pinned to the tower's own
	-- exterior boundary, and a margin inward is a room overlapping the tower.
	STREET_APRON_MARGIN = 6,
	-- How high above the wall top the zip cable is still treated as low, and how
	-- finely it is sampled. The cable descends linearly from 201 to 4 over a
	-- 1100-stud wrap, so its last eight per cent runs along the entry facade
	-- under wall height, which is two or three cells further along than anything
	-- the door alone reserves. A rider is anchored and driven by CFrame: a wall
	-- there is not scenery, they pass through it and step out somewhere else.
	STREET_ZIP_CLEARANCE = 8,
	STREET_ZIP_SAMPLES = 256,
	-- A cable is a line with clearance, not a point. Half a wall plus a stud.
	STREET_CABLE_MARGIN = 3,
	-- The slide's landing, reserved in every section including the first, which
	-- never sees one. Grown from the 70-stud pad because the slide's tail
	-- descends into it across the west edge of the ground.
	STREET_LANDING_MARGIN = 40,

	-- An overlook. Deck well above the wall top so the maze reads from up there,
	-- and glass on every side so it reads and nothing else: one stair up, the
	-- same stair down. The dome is a prism of flat panels rather than a Ball,
	-- which has a sphere collision primitive and ejects a character instead of
	-- containing one.
	STREET_DOME_DECK_Y = 26,
	STREET_DOME_HEIGHT = 13,
	STREET_DOME_INSET = 3,
	STREET_DOME_GLASS = 0.4,
	-- The flight and its hole are the tower stairwell's arrangement at a
	-- different scale, and for the same reason: 26 studs of climb needs more run
	-- than a cell has left over beside a deck, so the flight goes under the deck
	-- and comes up through a hole in it. holeAlong is sized off the headroom
	-- exactly as buildStairs sizes its own, so the covered part of the flight is
	-- the part a player can stand up in.
	STREET_STAIR_RISER = 1.3,
	STREET_STAIR_WIDTH = 8,
	STREET_STAIR_HEADROOM = 8,
	STREET_STAIR_HOLE_MARGIN = 1,

	STREET_PROP_HEIGHT = 15,
	STREET_TRIM_HEIGHT = 7,

	STREET_SIGN_HEIGHT = 11,

	-- The street's own random stream, and the reason every tower in the city
	-- stayed exactly where it was when the street arrived. The streams already
	-- in this file are `seed + section*7919` for a section, `+ k*104729` for
	-- k in 1..6 for a building, `buildingSeed + level*31` for a floor and
	-- `buildingSeed + 61291` for the exterior relief, so the largest offset any
	-- of them reaches is 689665. Colliding with one of those from here needs
	-- (s' - s) * 7919 = 15485863 - d for some d under 689665, so two sections
	-- 1868 apart. Nobody is building 1868 sections.
	STREET_SEED_OFFSET = 15485863,
}

local LEVEL_HEIGHT = CFG.WALL_HEIGHT + CFG.SLAB
local FX = CFG.MAZE_W * CFG.CELL
local FZ = CFG.MAZE_H * CFG.CELL
local PLOT_SPAN_X = FX + 2 * CFG.FACADE_OUTSET + CFG.STREET
local PLOT_SPAN_Z = FZ + 2 * CFG.FACADE_OUTSET + CFG.STREET
local SECTION_SPAN = CFG.PLOT_COLS * PLOT_SPAN_X + CFG.SECTION_GAP
-- How far past the maze footprint slabs run. Half a facade thickness past the
-- outset puts the slab edge inside the facade part, so no two faces are
-- coplanar and nothing z-fights.
local SLAB_APRON = CFG.FACADE_OUTSET + CFG.FACADE_THICKNESS / 2
local ROOF_Y = CFG.LEVELS * LEVEL_HEIGHT

-- Zero is a meaningful setting for every collectible count (turn that kind off),
-- and `or` cannot express it, so the new knobs go through this instead.
local function setting(value, fallback)
	if value == nil then
		return fallback
	end
	return value
end

local function refreshFromConfig()
	local w = Config.World or {}
	CFG.LEVELS = w.Levels or CFG.LEVELS
	CFG.LAMP_BRIGHTNESS = w.LampBrightness or CFG.LAMP_BRIGHTNESS
	CFG.LAMP_RANGE = w.LampRange or CFG.LAMP_RANGE
	CFG.LAMP_GRID = w.LampGrid or CFG.LAMP_GRID
	if w.LampShadows ~= nil then
		CFG.LAMP_SHADOWS = w.LampShadows
	end
	CFG.MOVING_WALL_MIN_LEVEL = w.MovingWallMinLevel or CFG.MOVING_WALL_MIN_LEVEL
	CFG.MOVING_WALL_TWEEN = w.MovingWallTween or CFG.MOVING_WALL_TWEEN
	CFG.MOVING_WALL_DWELL_CLOSED = w.MovingWallDwellClosed or CFG.MOVING_WALL_DWELL_CLOSED
	CFG.MOVING_WALL_DWELL_OPEN = w.MovingWallDwellOpen or CFG.MOVING_WALL_DWELL_OPEN
	CFG.MOVING_WALL_MARK_SHADE = setting(w.MovingWallMarkShade, CFG.MOVING_WALL_MARK_SHADE)
	CFG.MOVING_WALL_MARK_TRANSPARENCY = setting(w.MovingWallMarkTransparency, CFG.MOVING_WALL_MARK_TRANSPARENCY)
	CFG.PHANTOM_PER_LEVEL = w.PhantomWallsPerLevel or CFG.PHANTOM_PER_LEVEL
	CFG.PHANTOM_MAX_SHORTCUT = w.PhantomMaxShortcut or CFG.PHANTOM_MAX_SHORTCUT
	CFG.PHANTOM_TRANSPARENCY = setting(w.PhantomTransparency, CFG.PHANTOM_TRANSPARENCY)
	CFG.COIN_DEAD_END_PER_LEVEL = setting(w.DeadEndCoinsPerLevel, CFG.COIN_DEAD_END_PER_LEVEL)
	CFG.COIN_PATH_PER_LEVEL = setting(w.PathCoinsPerLevel, CFG.COIN_PATH_PER_LEVEL)
	CFG.POWERUPS_PER_LEVEL = setting(w.PowerupsPerLevel, CFG.POWERUPS_PER_LEVEL)
	CFG.ROOF_ARC_COINS = setting(w.RoofArcCoins, CFG.ROOF_ARC_COINS)
	CFG.STREET_ENABLED = setting(w.StreetMazeEnabled, CFG.STREET_ENABLED)
	CFG.STREET_CELL_TARGET = setting(w.StreetCellTarget, CFG.STREET_CELL_TARGET)
	CFG.STREET_BRAID = setting(w.StreetBraidFraction, CFG.STREET_BRAID)
	CFG.STREET_WALL_HEIGHT = setting(w.StreetWallHeight, CFG.STREET_WALL_HEIGHT)
	CFG.STREET_BLOCK_PROPS = setting(w.StreetBlockProps, CFG.STREET_BLOCK_PROPS)
	CFG.STREET_TRIM_PROPS = setting(w.StreetTrimProps, CFG.STREET_TRIM_PROPS)
	CFG.STREET_SIGNPOSTS = setting(w.StreetSignposts, CFG.STREET_SIGNPOSTS)
	CFG.STREET_SIGN_ARMS = setting(w.StreetSignArms, CFG.STREET_SIGN_ARMS)
	CFG.STREET_DOME_DECK_Y = setting(w.StreetDomeDeckHeight, CFG.STREET_DOME_DECK_Y)
	ROOF_Y = CFG.LEVELS * LEVEL_HEIGHT
end

local SIDE_ORDER = { "north", "east", "south", "west" }
local SIDE_INDEX = { north = 1, east = 2, south = 3, west = 4 }
local OPPOSITE = { north = "south", south = "north", east = "west", west = "east" }
local DELTA = { north = { 0, -1 }, south = { 0, 1 }, east = { 1, 0 }, west = { -1, 0 } }

local STYLES = {
	{
		name = "Cobalt",
		wall = Color3.fromRGB(78, 104, 146),
		skin = Color3.fromRGB(58, 78, 112),
		trim = Color3.fromRGB(198, 210, 226),
		glass = Color3.fromRGB(26, 38, 56),
		material = Enum.Material.Concrete,
		windows = "grid",
		crown = "parapet",
		exterior = "archive",
		facadeSkin = Color3.fromRGB(20, 28, 38),
		facadeTrim = Color3.fromRGB(48, 66, 82),
		facadeGlass = Color3.fromRGB(5, 12, 18),
		accent = Color3.fromRGB(92, 190, 255),
		theme = "Drowned Archive",
		enemy = "Drifter",
	},
	{
		name = "Ochre",
		wall = Color3.fromRGB(154, 118, 78),
		skin = Color3.fromRGB(126, 92, 58),
		trim = Color3.fromRGB(232, 214, 180),
		glass = Color3.fromRGB(44, 32, 20),
		material = Enum.Material.Brick,
		windows = "ribbon",
		crown = "setback",
		exterior = "reliquary",
		facadeSkin = Color3.fromRGB(34, 26, 19),
		facadeTrim = Color3.fromRGB(78, 58, 34),
		facadeGlass = Color3.fromRGB(16, 10, 6),
		accent = Color3.fromRGB(255, 176, 72),
		theme = "Buried Reliquary",
		enemy = "Stalker",
	},
	{
		name = "Slate",
		wall = Color3.fromRGB(96, 100, 106),
		skin = Color3.fromRGB(66, 70, 76),
		trim = Color3.fromRGB(180, 186, 194),
		glass = Color3.fromRGB(22, 26, 30),
		material = Enum.Material.Slate,
		windows = "columns",
		crown = "spire",
		exterior = "monolith",
		facadeSkin = Color3.fromRGB(24, 26, 30),
		facadeTrim = Color3.fromRGB(58, 62, 70),
		facadeGlass = Color3.fromRGB(7, 9, 12),
		accent = Color3.fromRGB(172, 208, 228),
		theme = "Silent Monolith",
		enemy = "Sentry",
	},
	{
		name = "Verdigris",
		wall = Color3.fromRGB(84, 132, 118),
		skin = Color3.fromRGB(58, 98, 88),
		trim = Color3.fromRGB(206, 226, 216),
		glass = Color3.fromRGB(20, 40, 36),
		material = Enum.Material.Metal,
		windows = "grid",
		crown = "watertower",
		exterior = "alchemy",
		facadeSkin = Color3.fromRGB(18, 34, 30),
		facadeTrim = Color3.fromRGB(38, 82, 70),
		facadeGlass = Color3.fromRGB(4, 14, 12),
		accent = Color3.fromRGB(92, 255, 184),
		theme = "Alchemist Stack",
		enemy = "Swarmer",
	},
	{
		name = "Bone",
		wall = Color3.fromRGB(196, 190, 176),
		skin = Color3.fromRGB(164, 158, 144),
		trim = Color3.fromRGB(120, 112, 98),
		glass = Color3.fromRGB(52, 50, 46),
		material = Enum.Material.Marble,
		windows = "ribbon",
		crown = "setback",
		exterior = "ossuary",
		facadeSkin = Color3.fromRGB(34, 32, 28),
		facadeTrim = Color3.fromRGB(82, 76, 64),
		facadeGlass = Color3.fromRGB(13, 12, 10),
		accent = Color3.fromRGB(236, 226, 196),
		theme = "Ivory Ossuary",
		enemy = "Lurker",
	},
	{
		name = "Ember",
		wall = Color3.fromRGB(150, 78, 74),
		skin = Color3.fromRGB(116, 56, 54),
		trim = Color3.fromRGB(238, 196, 160),
		glass = Color3.fromRGB(40, 20, 18),
		material = Enum.Material.Concrete,
		windows = "columns",
		crown = "spire",
		exterior = "cinder",
		facadeSkin = Color3.fromRGB(34, 20, 20),
		facadeTrim = Color3.fromRGB(82, 38, 34),
		facadeGlass = Color3.fromRGB(14, 5, 5),
		accent = Color3.fromRGB(255, 92, 52),
		theme = "Cinder Sanctum",
		enemy = "Charger",
	},
}

-- The other half of Lore.towers' check, run from this side because that file is
-- in ReplicatedStorage and this one is not: requiring MazeGenerator from Lore to
-- validate a theme would put the whole of world generation into every client.
-- A warning rather than an error, and one per style: a tower with no Codex line
-- is still a tower, where a server that refuses to start is no city at all.
for _, style in ipairs(STYLES) do
	if Lore.towers[style.theme] == nil then
		warn(string.format("MazeGenerator: style %q has theme %q with no Lore.towers entry", style.name, style.theme))
	end
end

-- ============================================================
-- Geometry helpers
-- ============================================================

local function makePart(parent, name, cf, size, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- makePart plus the one assignment that puts a part in the Wall Walker's
-- collision group. buildWalls has its own `wallPart` closure doing the same
-- thing over `parent`, `origin`, `wallY` and `style`, and it keeps it: that
-- function is invariant 7's machinery and the smallest diff there is the safest
-- one. This is for the street, whose walls are the second family of thing a
-- phasing player may cross.
--
-- What must NOT come through here is a boundary. The street's perimeter ring
-- and every part of an overlook are built by their own functions at Default,
-- deliberately, because past the perimeter is the void between two section
-- grounds and past an overlook's glass is the whole maze seen from above.
local function mazeWallPart(parent, name, cf, size, color, material)
	local part = makePart(parent, name, cf, size, color, material)
	part.CollisionGroup = MazeGenerator.WALL_GROUP
	return part
end

-- Every tagged part must carry Section/Building/Level: runtime services key
-- all of their lookups off those three attributes, so a tag applied without
-- them is invisible to whichever service consumes it. Attributes are set
-- before AddTag because GetInstanceAddedSignal fires on the tag, and a
-- service that reads attributes in its handler would otherwise see nil.
local function tagWithContext(part, tag, section, building, level)
	part:SetAttribute("Section", section)
	part:SetAttribute("Building", building)
	part:SetAttribute("Level", level)
	CollectionService:AddTag(part, tag)
end

-- ============================================================
-- Plates
-- ============================================================

-- The city's signage wears the same chrome the HUD does (docs/HUD_THEME_PLAN.md
-- Slate 5): a dark stone slab, an etched border, moonlight from above, and a
-- rune seam on the plates that mark a door. `src/shared/UiTheme.lua` is the
-- source of truth for every value here; they are copied rather than required
-- because the generator must not depend on a client UI module, so a token
-- retuned there is retuned here by hand. That is the price of the one-way
-- dependency and it is cheaper than a world builder that needs a GUI module
-- loaded before it can draw a wall.
local PLATE = {
	Ink = Color3.fromRGB(8, 11, 20),
	Slab = Color3.fromRGB(17, 22, 34),
	Etch = Color3.fromRGB(74, 86, 108),
	Rune = Color3.fromRGB(92, 230, 208),
	Lantern = Color3.fromRGB(255, 205, 105),
	Text = Color3.fromRGB(228, 233, 242),
	Radius = 6,
	Transparency = 0.25,
	StrokeTransparency = 0.5,
	SeamTransparency = 0.35,
	Display = Font.fromName("GrenzeGotisch", Enum.FontWeight.Bold),
	Body = Font.fromName("GothamSSm", Enum.FontWeight.Bold),
}

-- One plate: a billboard holding a single stone slab. Returns the slab and never
-- the BillboardGui, because a caller reaching past it is a caller drawing its
-- own chrome. `seam` is the teal line along the bottom edge and it means here
-- what it means on a HUD chip: this is a door, something can be done at it.
local function plateGui(parent, width, height, studsUp, maxDistance, seam)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, width, 0, height)
	bb.StudsOffset = Vector3.new(0, studsUp, 0)
	bb.MaxDistance = maxDistance
	bb.Parent = parent

	local slab = Instance.new("Frame")
	slab.Size = UDim2.new(1, 0, 1, 0)
	slab.BackgroundColor3 = PLATE.Slab
	slab.BackgroundTransparency = PLATE.Transparency
	slab.BorderSizePixel = 0
	slab.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, PLATE.Radius)
	corner.Parent = slab

	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(196, 200, 212))
	grad.Parent = slab

	local stroke = Instance.new("UIStroke")
	stroke.Color = PLATE.Etch
	stroke.Transparency = PLATE.StrokeTransparency
	stroke.Parent = slab

	if seam then
		local line = Instance.new("Frame")
		line.Size = UDim2.new(1, -PLATE.Radius * 2, 0, 2)
		line.Position = UDim2.new(0, PLATE.Radius, 1, -3)
		line.BackgroundColor3 = PLATE.Rune
		line.BackgroundTransparency = PLATE.SeamTransparency
		line.BorderSizePixel = 0
		line.Parent = slab
	end

	return slab
end

local function plateLine(slab, size, position, font, textSize, color, text)
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.FontFace = font
	label.TextSize = textSize
	label.TextColor3 = color
	label.Text = text
	label.Parent = slab
	return label
end

-- The other kind of plate: lettering cut into a part's own face with no slab
-- behind it, because there the part is the sign. The two that use it are the
-- two signs somebody in this city actually made, the roof's name board and a
-- climber's signpost, which is why neither gets the HUD's stone frame.
local function carvedPlate(part, canvasWidth, canvasHeight, font, color, text)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(canvasWidth, canvasHeight)
	sg.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.FontFace = font
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = sg
	return label
end

local function cellCenter(x, z)
	return Vector3.new((x - 0.5) * CFG.CELL, 0, (z - 0.5) * CFG.CELL)
end

-- The u of a door along the face it is cut in, and the point on the facade
-- plane it sits at. Both are what buildFacade, buildShop and buildZipline each
-- work out for themselves off the same two values; the street needs them too
-- and gets them here rather than by a fourth derivation.
local function faceU(side, cell)
	local horizontal = (side == "north" or side == "south")
	local centre = cellCenter(cell.x, cell.z)
	return horizontal and centre.X or centre.Z
end

local function doorWorldPoint(origin, side, cell)
	local u = faceU(side, cell)
	local out = CFG.FACADE_OUTSET + CFG.FACADE_THICKNESS
	if side == "north" then
		return origin + Vector3.new(u, 0, -out)
	elseif side == "south" then
		return origin + Vector3.new(u, 0, FZ + out)
	elseif side == "west" then
		return origin + Vector3.new(-out, 0, u)
	end
	return origin + Vector3.new(FX + out, 0, u)
end

local function edgeCell(side, i)
	if side == "north" then
		return { x = i, z = 1 }
	elseif side == "south" then
		return { x = i, z = CFG.MAZE_H }
	elseif side == "west" then
		return { x = 1, z = i }
	end
	return { x = CFG.MAZE_W, z = i }
end

local function rotateSide(side, dir)
	local i = SIDE_INDEX[side] + dir
	if i > 4 then
		i = 1
	end
	if i < 1 then
		i = 4
	end
	return SIDE_ORDER[i]
end

local function outwardVector(side)
	local d = DELTA[side]
	return Vector3.new(d[1], 0, d[2])
end

local function neighborCell(cell, side)
	local d = DELTA[side]
	return { x = cell.x + d[1], z = cell.z + d[2] }
end

local function sideRunLength(side)
	if side == "north" or side == "south" then
		return CFG.MAZE_W
	end
	return CFG.MAZE_H
end

-- Where this level's stairs go, given where the player arrives. Every index on
-- the exit side is a candidate; the ones at least STAIR_MIN_SEPARATION_FRAC of
-- the footprint from the arrival cell are the ones drawn from, so a climb
-- crosses the floor instead of turning a corner. One draw either way, so this
-- costs the stream nothing.
--
-- Straight-line distance, not path distance: the maze is carved after these
-- cells are reserved, so at this point there are no corridors to measure along.
--
-- The filter can never empty on the shipped footprint (the tightest case, an
-- arrival one cell from the corner the two sides share, still leaves four of
-- the eight candidates), but MAZE_W and MAZE_H are constants somebody may
-- shrink, and a floor with no stairs is not a recoverable state. Falling back
-- to the farthest candidate keeps a small footprint building and merely stops
-- honouring the fraction.
local function pickExitIndex(exitSide, entryCell, rng)
	local span = sideRunLength(exitSide)
	local minSep = CFG.STAIR_MIN_SEPARATION_FRAC * math.max(CFG.MAZE_W, CFG.MAZE_H)
	local far = {}
	local best, bestSep = 2, -1
	for i = 2, span - 1 do
		local c = edgeCell(exitSide, i)
		local dx, dz = c.x - entryCell.x, c.z - entryCell.z
		local sep = math.sqrt(dx * dx + dz * dz)
		if sep >= minSep then
			far[#far + 1] = i
		end
		if sep > bestSep then
			best, bestSep = i, sep
		end
	end
	if #far == 0 then
		return best
	end
	return far[rng:NextInteger(1, #far)]
end

-- ============================================================
-- Maze carving (iterative, seeded, honours reserved cells)
-- ============================================================

local function newGrid(reserved)
	local g = {}
	for x = 1, CFG.MAZE_W do
		g[x] = {}
		for z = 1, CFG.MAZE_H do
			g[x][z] = {
				visited = false,
				reserved = false,
				walls = { north = true, south = true, east = true, west = true },
			}
		end
	end
	for _, c in ipairs(reserved) do
		g[c.x][c.z].reserved = true
	end
	return g
end

local function carve(g, start, rng)
	local stack = { { x = start.x, z = start.z } }
	g[start.x][start.z].visited = true

	while #stack > 0 do
		local cur = stack[#stack]
		local options = {}
		for _, side in ipairs(SIDE_ORDER) do
			local d = DELTA[side]
			local nx, nz = cur.x + d[1], cur.z + d[2]
			if nx >= 1 and nx <= CFG.MAZE_W and nz >= 1 and nz <= CFG.MAZE_H then
				local cell = g[nx][nz]
				if not cell.visited and not cell.reserved then
					table.insert(options, { x = nx, z = nz, side = side })
				end
			end
		end

		if #options > 0 then
			local pick = options[rng:NextInteger(1, #options)]
			g[cur.x][cur.z].walls[pick.side] = false
			g[pick.x][pick.z].walls[OPPOSITE[pick.side]] = false
			g[pick.x][pick.z].visited = true
			table.insert(stack, { x = pick.x, z = pick.z })
		else
			table.remove(stack)
		end
	end
end

local function openBetween(g, a, side)
	local b = neighborCell(a, side)
	g[a.x][a.z].walls[side] = false
	if b.x >= 1 and b.x <= CFG.MAZE_W and b.z >= 1 and b.z <= CFG.MAZE_H then
		g[b.x][b.z].walls[OPPOSITE[side]] = false
	end
end

local function sealCell(g, c)
	for _, side in ipairs(SIDE_ORDER) do
		g[c.x][c.z].walls[side] = true
		local n = neighborCell(c, side)
		if n.x >= 1 and n.x <= CFG.MAZE_W and n.z >= 1 and n.z <= CFG.MAZE_H then
			g[n.x][n.z].walls[OPPOSITE[side]] = true
		end
	end
end

local function inBounds(c)
	return c.x >= 1 and c.x <= CFG.MAZE_W and c.z >= 1 and c.z <= CFG.MAZE_H
end

-- One wall is shared by two cells, and each names it by a different side. Naming
-- it by the cell on the north or west of the pair gives both the same key, which
-- is what lets a phantom opened from one side be seen as open from the other.
local function edgeKey(x, z, side)
	if side == "north" then
		return "H_" .. x .. "_" .. z
	elseif side == "south" then
		return "H_" .. x .. "_" .. (z + 1)
	elseif side == "west" then
		return "V_" .. x .. "_" .. z
	end
	return "V_" .. (x + 1) .. "_" .. z
end

-- Breadth-first distance in cells from start, treating any wall listed in
-- extraOpen as passable. Reserved cells are sealed on every side before this
-- runs, so the flood never enters them except through the one opening
-- buildLevel cuts into the stair cell, which is exactly the route being
-- measured. Returns a sparse [x][z] table; nil means unreachable.
local function cellDistances(g, start, extraOpen)
	local dist = {}
	for x = 1, CFG.MAZE_W do
		dist[x] = {}
	end
	dist[start.x][start.z] = 0

	local queue = { { x = start.x, z = start.z } }
	local head = 1
	while head <= #queue do
		local cur = queue[head]
		head = head + 1
		for _, side in ipairs(SIDE_ORDER) do
			local n = neighborCell(cur, side)
			if inBounds(n) and dist[n.x][n.z] == nil then
				local open = not g[cur.x][cur.z].walls[side] or extraOpen[edgeKey(cur.x, cur.z, side)]
				if open then
					dist[n.x][n.z] = dist[cur.x][cur.z] + 1
					table.insert(queue, n)
				end
			end
		end
	end

	return dist
end

-- ============================================================
-- Slabs
-- ============================================================

-- Slabs run out to the facade, not just to the maze footprint. The maze fills
-- 0..FX by 0..FZ while the facade stands SLAB_APRON studs further out, so a
-- slab sized to the maze alone leaves an open ring around every floor: a slot
-- on the roof between the deck and the parapet, and a shaft from there down to
-- the street. Widening the rects rather than adding an apron ring keeps the
-- part count per slab unchanged.
local function buildSlab(parent, origin, topY, hole, color, material, prefix)
	local ax0, ax1 = -SLAB_APRON, FX + SLAB_APRON
	local az0, az1 = -SLAB_APRON, FZ + SLAB_APRON

	local rects
	if not hole then
		rects = { { cx = (ax0 + ax1) / 2, cz = (az0 + az1) / 2, sx = ax1 - ax0, sz = az1 - az0 } }
	else
		local x0 = hole.x - hole.sx / 2
		local x1 = hole.x + hole.sx / 2
		local z0 = hole.z - hole.sz / 2
		local z1 = hole.z + hole.sz / 2
		rects = {
			{ cx = (ax0 + x0) / 2, cz = (az0 + az1) / 2, sx = x0 - ax0, sz = az1 - az0 },
			{ cx = (x1 + ax1) / 2, cz = (az0 + az1) / 2, sx = ax1 - x1, sz = az1 - az0 },
			{ cx = (x0 + x1) / 2, cz = (az0 + z0) / 2, sx = x1 - x0, sz = z0 - az0 },
			{ cx = (x0 + x1) / 2, cz = (z1 + az1) / 2, sx = x1 - x0, sz = az1 - z1 },
		}
	end

	for i, r in ipairs(rects) do
		if r.sx > 0.05 and r.sz > 0.05 then
			makePart(
				parent,
				prefix .. i,
				CFrame.new(origin + Vector3.new(r.cx, topY - CFG.SLAB / 2, r.cz)),
				Vector3.new(r.sx, CFG.SLAB, r.sz),
				color,
				material
			)
		end
	end
end

-- ============================================================
-- Level interior
-- ============================================================

local function buildWalls(parent, origin, baseY, g, style, door)
	local wallY = baseY + CFG.WALL_HEIGHT / 2
	local interior = {}

	-- Walls run CELL + WALL_THICKNESS long rather than exactly CELL. A wall
	-- sized exactly CELL stops at the cell boundary, while the perpendicular
	-- wall meeting it there is centred on that boundary and so extends half a
	-- thickness past it. That leaves an empty WALL_THICKNESS/2 square at every
	-- corner. Overlapping by half a thickness at each end fills it. Openings
	-- narrow from CELL to CELL - WALL_THICKNESS, which is still 23 studs.
	local runLong = CFG.CELL + CFG.WALL_THICKNESS

	-- The facade stands SLAB_APRON studs beyond the maze footprint, and the
	-- slabs run out to meet it, so a boundary wall sized like an interior one
	-- leaves a walkable ring corridor around every floor. On level 0 the front
	-- door opens straight into that ring instead of into the maze. Growing each
	-- boundary wall outward closes it and lands its outer face on the slab
	-- edge, buried inside the facade, so no two faces end up coplanar. A wall
	-- at either end of its run also grows lengthwise, otherwise the square
	-- outside each maze corner stays hollow. No parts added or moved.
	local APRON_FILL = SLAB_APRON - CFG.WALL_THICKNESS / 2

	local function fillApron(x, z, side, pos, size)
		local out = outwardVector(side)
		pos = pos + out * (APRON_FILL / 2)
		size = size + Vector3.new(math.abs(out.X), 0, math.abs(out.Z)) * APRON_FILL

		local along = 0
		if side == "north" or side == "south" then
			if x == 1 then
				along = -1
			elseif x == CFG.MAZE_W then
				along = 1
			end
			pos = pos + Vector3.new(along * APRON_FILL / 2, 0, 0)
			size = size + Vector3.new(math.abs(along) * APRON_FILL, 0, 0)
		else
			if z == 1 then
				along = -1
			elseif z == CFG.MAZE_H then
				along = 1
			end
			pos = pos + Vector3.new(0, 0, along * APRON_FILL / 2)
			size = size + Vector3.new(0, 0, math.abs(along) * APRON_FILL)
		end

		return pos, size
	end

	-- Every wall on a floor goes through here, boundary and doorway panels
	-- included, which is what makes one assignment enough to put the whole maze
	-- in the group and nothing outside it. Interior walls are returned to the
	-- caller and some become MovingWall or PhantomWall later; those are the same
	-- parts, so a moving wall is phaseable too, which is the right answer.
	local function wallPart(name, pos, size)
		local part = makePart(
			parent,
			name,
			CFrame.new(origin + Vector3.new(pos.X, wallY, pos.Z)),
			size,
			style.wall,
			style.material
		)
		part.CollisionGroup = MazeGenerator.WALL_GROUP
		return part
	end

	-- Two panels flanking a DOOR_WIDTH gap centred on the cell, so the opening
	-- lines up with the facade door rather than being the whole cell wide. The
	-- run already carries its apron growth, so the panels are measured off the
	-- grown extent and still reach the slab edge.
	local function placeDoorway(x, z, side, pos, size)
		local horizontal = (side == "north" or side == "south")
		local run = horizontal and size.X or size.Z
		local centre = horizontal and pos.X or pos.Z
		local u0 = centre - run / 2
		local u1 = centre + run / 2
		local gap = cellCenter(x, z)
		local gapU = horizontal and gap.X or gap.Z

		local spans = {
			{ name = "L", a = u0, b = gapU - CFG.DOOR_WIDTH / 2 },
			{ name = "R", a = gapU + CFG.DOOR_WIDTH / 2, b = u1 },
		}
		for _, s in ipairs(spans) do
			local len = s.b - s.a
			if len > 0.1 then
				local u = s.a + len / 2
				local panelPos = horizontal and Vector3.new(u, 0, pos.Z) or Vector3.new(pos.X, 0, u)
				local panelSize = horizontal and Vector3.new(len, size.Y, size.Z) or Vector3.new(size.X, size.Y, len)
				wallPart(string.format("Wall_%d_%d_%s_%s", x, z, side, s.name), panelPos, panelSize)
			end
		end
	end

	local function place(x, z, side, pos, size, boundary)
		if boundary then
			pos, size = fillApron(x, z, side, pos, size)
			if door and door.x == x and door.z == z and door.side == side then
				placeDoorway(x, z, side, pos, size)
				return
			end
		end
		local p = wallPart(string.format("Wall_%d_%d_%s", x, z, side), pos, size)
		if not boundary then
			table.insert(interior, { part = p, x = x, z = z, side = side, size = size })
		end
	end

	for x = 1, CFG.MAZE_W do
		for z = 1, CFG.MAZE_H do
			local cell = g[x][z]
			local c = cellCenter(x, z)

			if cell.walls.north then
				place(
					x,
					z,
					"north",
					Vector3.new(c.X, 0, c.Z - CFG.CELL / 2),
					Vector3.new(runLong, CFG.WALL_HEIGHT, CFG.WALL_THICKNESS),
					z == 1
				)
			end
			if cell.walls.west then
				place(
					x,
					z,
					"west",
					Vector3.new(c.X - CFG.CELL / 2, 0, c.Z),
					Vector3.new(CFG.WALL_THICKNESS, CFG.WALL_HEIGHT, runLong),
					x == 1
				)
			end
			if x == CFG.MAZE_W and cell.walls.east then
				place(
					x,
					z,
					"east",
					Vector3.new(c.X + CFG.CELL / 2, 0, c.Z),
					Vector3.new(CFG.WALL_THICKNESS, CFG.WALL_HEIGHT, runLong),
					true
				)
			end
			if z == CFG.MAZE_H and cell.walls.south then
				place(
					x,
					z,
					"south",
					Vector3.new(c.X, 0, c.Z + CFG.CELL / 2),
					Vector3.new(runLong, CFG.WALL_HEIGHT, CFG.WALL_THICKNESS),
					true
				)
			end
		end
	end

	return interior
end

-- Phantoms are chosen for how much they shorten the run, not uniformly. A wall
-- picked at random usually joins two cells that are already near each other in
-- the spanning tree, so walking through it saves nothing and the player learns
-- to ignore phantoms entirely. Scoring each candidate by the cells it would
-- save makes every one of them worth taking.
--
-- Walls touching a reserved cell are excluded outright. They score highest by
-- construction, since they open straight into the stairwell, so a biased pick
-- would put one on every floor and turn the last leg of every maze into a
-- formality.
local function tagPhantoms(interior, g, blocked, entryCell, stairCell, count, rng, ctx)
	local pool = {}
	for _, w in ipairs(interior) do
		local n = neighborCell({ x = w.x, z = w.z }, w.side)
		if not blocked[w.x .. "_" .. w.z] and not blocked[n.x .. "_" .. n.z] then
			table.insert(pool, w)
		end
	end

	local picked = {}
	local opened = {}
	local shortest
	for _ = 1, math.min(count, #pool) do
		-- Rescored every pick, with the phantoms already placed counted as open,
		-- so the second shortcut is measured against a maze that has the first
		-- one in it. Otherwise the top few candidates are all variations on the
		-- same bypass and only one of them does anything.
		local fromEntry = cellDistances(g, entryCell, opened)
		local toStair = cellDistances(g, stairCell, opened)
		local base = fromEntry[stairCell.x][stairCell.z]
		-- Measured once, off the untouched maze, so the cap is on what the
		-- phantoms do between them rather than on each one separately.
		shortest = shortest or math.ceil(base * (1 - CFG.PHANTOM_MAX_SHORTCUT))
		local allowance = base - shortest

		local ranked = {}
		for i, w in ipairs(pool) do
			local a = { x = w.x, z = w.z }
			local b = neighborCell(a, w.side)
			local gain = 0
			if fromEntry[a.x][a.z] and toStair[b.x][b.z] then
				gain = math.max(gain, base - (fromEntry[a.x][a.z] + 1 + toStair[b.x][b.z]))
			end
			if fromEntry[b.x][b.z] and toStair[a.x][a.z] then
				gain = math.max(gain, base - (fromEntry[b.x][b.z] + 1 + toStair[a.x][a.z]))
			end
			table.insert(ranked, { index = i, gain = gain })
		end
		-- Ties broken on pool index so the order is a pure function of the seed;
		-- table.sort is not stable and equal-gain candidates are common.
		table.sort(ranked, function(p, q)
			if p.gain ~= q.gain then
				return p.gain > q.gain
			end
			return p.index < q.index
		end)

		-- ranked is sorted by gain, so the affordable candidates are a contiguous
		-- run: skip the ones that would overspend the allowance, then take while
		-- the gain is still positive.
		local first = 1
		while first <= #ranked and ranked[first].gain > allowance do
			first = first + 1
		end
		local last = first - 1
		while last < #ranked and ranked[last + 1].gain > 0 do
			last = last + 1
		end

		-- Sample from the strongest affordable handful rather than always taking
		-- the best, so two towers with the same layout still get different
		-- shortcuts. Once the allowance is spent every affordable candidate has
		-- gain 0, and one of those is picked at random: a phantom that only opens
		-- a loop is still a readable wall and a way back. Falling back to the
		-- whole pool here instead is what let the last phantom on a floor spend
		-- an allowance that was already gone.
		local chosen
		if last >= first then
			chosen = ranked[rng:NextInteger(first, math.min(last, first + math.max(2, count) - 1))]
		elseif first <= #ranked then
			chosen = ranked[rng:NextInteger(first, #ranked)]
		else
			chosen = ranked[rng:NextInteger(1, #ranked)]
		end

		local w = pool[chosen.index]
		table.remove(pool, chosen.index)
		opened[edgeKey(w.x, w.z, w.side)] = true

		-- A phantom keeps the wall's own colour and material and changes exactly
		-- one thing: you can see through it. Earlier passes kept reaching for a
		-- louder marker, ForceField and then cyan Neon, and a glowing panel in a
		-- concrete maze reads as a piece of equipment rather than as a wall with
		-- something different about it. Being almost a wall is the point; the
		-- player is meant to notice the odd one out, not be signposted to it.
		--
		-- CastShadow stays off so light carries through as well as sight. A
		-- see-through pane laying down a solid black shadow contradicts the only
		-- cue there is, and the lit corridor behind it is a second, quieter hint
		-- at what the wall is for. Phantoms are never required: the carved maze
		-- is a spanning tree, and making a wall passable only ever adds a
		-- connection.
		-- Collidable, in the group that only enemies collide with. It was CanCollide
		-- false, which is the obvious way to make a wall passable and is also the
		-- only thing the navmesh looks at, so every phantom in the city was a
		-- doorway the enemies had been walking through since before anyone found
		-- it. A player who squeezed through one could be followed through it.
		--
		-- Moving it out of WALL_GROUP is deliberate and costs nothing: that group's
		-- only job is telling the Wall Walker what it may phase through and telling
		-- WallWalkService what it must not go solid inside, and a phantom is
		-- passable to a player in both states, so there is nothing to be stranded
		-- in. It also means an enemy can no longer see through one, the sight ray
		-- respecting CanCollide, which is the right read for something that looks
		-- like a wall to everything except the player who noticed it.
		w.part.CanCollide = true
		w.part.CollisionGroup = MazeGenerator.ENEMY_BLOCK_GROUP
		w.part.Transparency = CFG.PHANTOM_TRANSPARENCY
		w.part.CastShadow = false
		w.part.Name = "PhantomWall"
		tagWithContext(w.part, "PhantomWall", ctx.section, ctx.building, ctx.level)
		picked[w.part] = true
	end
	return picked
end

-- The floor mark under a moving wall. A pure function of the wall part and the
-- attributes just written onto it: it reads what generation has already decided
-- and draws nothing from rng, so adding it left every pre-existing part exactly
-- where it was. The delta is two parts per sliding wall and twice
-- MOVING_WALL_MARK_ARC_SEGMENTS per rotating one, which makes a section's part
-- count depend on the mode rolls where it used to be one part either way; the
-- run-twice identity check is unaffected, but section totals no longer match
-- their neighbours' and a count comparison has to count tracks and arcs.
--
-- Colour and material come off the wall itself, darkened by
-- MOVING_WALL_MARK_SHADE, so the mark reads as wear the mechanism left rather
-- than as a painted hazard stripe, and every style is covered by construction.
--
-- Both shapes are drawn from the wall itself rather than from the cell, because
-- the wall carries its apron growth and is 27 long in a 25 cell. A mark sized to
-- the cell would be a mark that lies by two studs about where the thing sweeps.
--
-- Nothing here is collidable, touchable or queryable. A hint that turns up in
-- PickupService's radius sweep, in the Wall Walker's overlap check or in the
-- enemy sight ray is a hint that has become a game object.
local function markMovingWall(part, mode, travel, axis)
	local size = part.Size
	local markY = part.Position.Y - CFG.WALL_HEIGHT / 2 + CFG.MOVING_WALL_MARK_THICKNESS / 2
	local color = part.Color:Lerp(Color3.new(0, 0, 0), CFG.MOVING_WALL_MARK_SHADE)
	local width = CFG.WALL_THICKNESS * CFG.MOVING_WALL_MARK_RAIL_FRAC
	local marks = {}

	if mode == "rotate" then
		-- The scratches the wall tips drag. MovingWallService opens with
		-- home * CFrame.Angles(0, 90, 0) about the wall's own centre, so each tip
		-- sweeps a quarter arc of known direction: from the long axis, clockwise
		-- in the XZ plane, and the second tip's arc is the first's rotated a half
		-- turn. Each arc is chords whose endpoints sit on the tip's true radius.
		local radius = math.max(size.X, size.Z) / 2
		local sweep = math.rad(90) / CFG.MOVING_WALL_MARK_ARC_SEGMENTS
		local chord = 2 * radius * math.sin(sweep / 2)
		local midRadius = radius * math.cos(sweep / 2)
		local start = (size.X >= size.Z) and 0 or math.rad(90)
		local centre = CFrame.new(part.Position.X, markY, part.Position.Z)
		for tip = 0, 1 do
			for i = 1, CFG.MOVING_WALL_MARK_ARC_SEGMENTS do
				local angle = start + tip * math.rad(180) - (i - 0.5) * sweep
				table.insert(
					marks,
					makePart(
						part.Parent,
						"MovingWallArc",
						centre * CFrame.Angles(0, -angle, 0) * CFrame.new(midRadius, 0, 0),
						Vector3.new(width, CFG.MOVING_WALL_MARK_THICKNESS, chord),
						color,
						part.Material
					)
				)
			end
		end
	else
		-- Two rails flanking the wall, running the whole span it occupies across
		-- a cycle: its length plus its travel. A closed wall shows only the pair
		-- reaching into the cell it will slide into, which is the hint, pointed
		-- where the thing is about to go.
		--
		-- They sit just outside the wall's own thickness, not inside it. Rails
		-- tucked under the wall are covered along their whole length by the thing
		-- they are meant to advertise, and a player standing anywhere sees the
		-- hint only once the wall has already left it.
		local along = (axis == "X")
		local half = (along and size.Z or size.X) / 2 + width / 2
		local length = (along and size.X or size.Z) + travel
		for side = -1, 1, 2 do
			table.insert(
				marks,
				makePart(
					part.Parent,
					"MovingWallTrack",
					CFrame.new(
						part.Position.X + (along and travel / 2 or half * side),
						markY,
						part.Position.Z + (along and half * side or travel / 2)
					),
					along and Vector3.new(length, CFG.MOVING_WALL_MARK_THICKNESS, width)
						or Vector3.new(width, CFG.MOVING_WALL_MARK_THICKNESS, length),
					color,
					part.Material
				)
			)
		end
	end

	for _, mark in ipairs(marks) do
		mark.Transparency = CFG.MOVING_WALL_MARK_TRANSPARENCY
		mark.CanCollide = false
		mark.CanTouch = false
		mark.CanQuery = false
		mark.CastShadow = false
	end
end

local function tagMovingWalls(interior, blocked, used, level, rng, ctx)
	if level < CFG.MOVING_WALL_MIN_LEVEL then
		return
	end

	local quota = CFG.MOVING_WALL_BASE + math.floor((level - CFG.MOVING_WALL_MIN_LEVEL) / 2)

	local pool = {}
	for _, w in ipairs(interior) do
		if not used[w.part] and not blocked[w.x .. "_" .. w.z] then
			table.insert(pool, w)
		end
	end

	for _ = 1, math.min(quota, #pool) do
		local i = rng:NextInteger(1, #pool)
		local w = pool[i]
		table.remove(pool, i)

		local mode = rng:NextNumber() < 0.55 and "slide" or "rotate"
		local p = w.part
		p.Name = "MovingWall"
		p:SetAttribute("Mode", mode)
		p:SetAttribute("Travel", CFG.CELL)
		p:SetAttribute("SlideAxis", (w.side == "north" or w.side == "south") and "X" or "Z")
		p:SetAttribute("TweenTime", rng:NextNumber(CFG.MOVING_WALL_TWEEN[1], CFG.MOVING_WALL_TWEEN[2]))
		p:SetAttribute("DwellOpen", rng:NextNumber(CFG.MOVING_WALL_DWELL_OPEN[1], CFG.MOVING_WALL_DWELL_OPEN[2]))
		p:SetAttribute("DwellClosed", rng:NextNumber(CFG.MOVING_WALL_DWELL_CLOSED[1], CFG.MOVING_WALL_DWELL_CLOSED[2]))
		p:SetAttribute("Phase", rng:NextNumber(0, CFG.MOVING_WALL_PHASE_MAX))
		tagWithContext(p, "MovingWall", ctx.section, ctx.building, level)
		-- After the draws, deliberately: the mark reads what they decided and adds
		-- no draw of its own, so the stream is the same one it was before this
		-- existed and nothing downstream of here moved.
		markMovingWall(p, mode, CFG.CELL, p:GetAttribute("SlideAxis"))
		used[p] = true
	end
end

local function buildStairs(parent, origin, baseY, exitSide, cellB, style)
	local outward = outwardVector(exitSide)
	local cB = cellCenter(cellB.x, cellB.z)

	local runLen = CFG.CELL * CFG.STAIR_RUN_CELLS
	local runStart = cB - outward * (CFG.CELL / 2)
	local steps = math.ceil(LEVEL_HEIGHT / CFG.STAIR_RISER)
	local riser = LEVEL_HEIGHT / steps
	local tread = runLen / steps
	local width = CFG.CELL * CFG.STAIR_WIDTH_FRAC

	local folder = Instance.new("Folder")
	folder.Name = "Stairs"
	folder.Parent = parent

	local along = math.abs(DELTA[exitSide][1]) > 0

	for i = 0, steps - 1 do
		local h = (i + 1) * riser
		local c = runStart + outward * ((i + 0.5) * tread)
		local size = along and Vector3.new(tread, h, width) or Vector3.new(width, h, tread)
		makePart(
			folder,
			"Step" .. i,
			CFrame.new(origin + Vector3.new(c.X, baseY + h / 2, c.Z)),
			size,
			style.trim,
			Enum.Material.Concrete
		)
	end

	-- The barrier that keeps enemies off the flight, in the group only they collide
	-- with. It stands in the one opening cut between the maze and the stair cell,
	-- which is where the flight starts: buildLevel seals cellB and cellE and cuts
	-- exactly two doors, one inward to the maze and one outward between the pair,
	-- and runStart is the inward one. So a full-cell panel there is the whole of
	-- the stairwell's mouth and there is no way around it.
	--
	-- Wall height, not enough-to-not-step-over, because the stuck handler makes an
	-- enemy jump and a barrier it can hop is a barrier for as long as nothing goes
	-- wrong. Placed exactly where a maze wall on that edge would be, in the same
	-- span from baseY, so the navmesh sees the cell as closed the way it sees every
	-- other sealed edge.
	--
	-- CanQuery is off so it stops bodies and paths without stopping rays: the
	-- camera does not pop against a wall that is not there, and an enemy still sees
	-- a player standing in the stairwell. Seeing them and being unable to follow is
	-- the intended read.
	local blockPos = runStart + outward * (CFG.WALL_THICKNESS / 2)
	local block = makePart(
		folder,
		"StairBlock",
		CFrame.new(origin + Vector3.new(blockPos.X, baseY + CFG.WALL_HEIGHT / 2, blockPos.Z)),
		along and Vector3.new(CFG.WALL_THICKNESS, CFG.WALL_HEIGHT, CFG.CELL)
			or Vector3.new(CFG.CELL, CFG.WALL_HEIGHT, CFG.WALL_THICKNESS),
		style.trim,
		Enum.Material.SmoothPlastic
	)
	block.Transparency = 1
	block.CastShadow = false
	block.CanQuery = false
	block.CanTouch = false
	block.CollisionGroup = MazeGenerator.ENEMY_BLOCK_GROUP

	-- The opening in the floor above is sized to the stairs, not to the cell it
	-- sits in. It only has to start far enough back that a climbing player still
	-- clears the slab by STAIR_HEADROOM, and be STAIR_HOLE_MARGIN wider than the
	-- treads. Everything beyond that is floor the level above loses, and losing
	-- it strands the player: a cell-sized hole left a 2 stud ledge down each
	-- side and nothing but boundary wall ahead of the top step, so there was no
	-- way to walk off the stairs and into the maze. Sized this way the top step
	-- lands flush with the far edge of the hole and floor runs all the way
	-- around it.
	--
	-- It grows inward from that far edge and never outward, which is what keeps
	-- the top step reachable however much headroom STAIR_HEADROOM asks for. The
	-- ceiling over the flight and the floor above it are the same slab, so the
	-- two cannot both be had: STAIR_HEADROOM is where that trade sits and why it
	-- stops where it does.
	local holeAlong = math.min(runLen, runLen * (CFG.SLAB + CFG.STAIR_HEADROOM) / LEVEL_HEIGHT)
	local holeWide = width + 2 * CFG.STAIR_HOLE_MARGIN
	local holeCenter = runStart + outward * (runLen - holeAlong / 2)

	return {
		x = holeCenter.X,
		z = holeCenter.Z,
		sx = along and holeAlong or holeWide,
		sz = along and holeWide or holeAlong,
	}
end

local function buildLamps(parent, origin, baseY)
	local folder = Instance.new("Folder")
	folder.Name = "Lamps"
	folder.Parent = parent

	local stepX = FX / (CFG.LAMP_GRID + 1)
	local stepZ = FZ / (CFG.LAMP_GRID + 1)
	local lampY = baseY + CFG.WALL_HEIGHT - 0.8

	for gx = 1, CFG.LAMP_GRID do
		for gz = 1, CFG.LAMP_GRID do
			local base = makePart(
				folder,
				string.format("Lamp_%d_%d", gx, gz),
				CFrame.new(origin + Vector3.new(stepX * gx, lampY, stepZ * gz)),
				Vector3.new(2.5, 0.4, 2.5),
				Color3.fromRGB(255, 244, 214),
				Enum.Material.Neon
			)
			base.CanCollide = false

			-- PointLight, not SpotLight: a downward cone lights the floor and
			-- leaves the wall faces in grazing light, which is what made the
			-- maze unreadable. Omnidirectional light hits vertical surfaces.
			--
			-- Shadows are the switch between two lighting models, not a quality
			-- setting, which is why they are on. Off, light passes through
			-- walls, so anything in the maze is lit by all LAMP_GRID^2 lamps at
			-- once and pale surfaces clip regardless of exposure. On, a corridor
			-- is lit by the one or two lamps that can see into it, which is what
			-- stopped players glowing and gave the walls shape. The cost is
			-- LAMP_GRID^2 shadow-casting lights per visible floor.
			local lamp = Instance.new("PointLight")
			lamp.Brightness = CFG.LAMP_BRIGHTNESS
			lamp.Range = CFG.LAMP_RANGE
			lamp.Color = Color3.fromRGB(255, 240, 208)
			lamp.Shadows = CFG.LAMP_SHADOWS
			lamp.Parent = base
		end
	end
end

-- ============================================================
-- Collectibles
-- ============================================================
-- Every draw in here comes from a sub-stream derived from the building seed,
-- never from the threaded rng, per CLAUDE.md invariant 6. The maze is already
-- carved by the time this runs, so coins have no business moving a wall: taking
-- one number off `rng` would shift every draw after it and reshuffle the whole
-- city for a feature that only ever reads what generation already decided.
--
-- The count is a pure function of the settings rather than of the seed, which is
-- what keeps a part count usable as a determinism check: a fixed number of coins
-- per level and a fixed number of powerups. Only where they land is random.

local COIN_COLOR = Color3.fromRGB(255, 202, 66)

-- One shape for every coin in the game: a Neon cylinder lying on its side, so
-- the disc faces along X and a spin about Y sweeps the face past the player.
-- TimerGui does that spin locally, on the coins near enough to be seen. Nothing
-- on the server ever touches a coin's CFrame.
local function makeCoin(parent, position, ctx, level)
	local coin = makePart(
		parent,
		"Coin",
		CFrame.new(position),
		Vector3.new(CFG.COIN_THICKNESS, CFG.COIN_SIZE, CFG.COIN_SIZE),
		COIN_COLOR,
		Enum.Material.Neon
	)
	coin.Shape = Enum.PartType.Cylinder
	coin.CanCollide = false
	coin.CastShadow = false
	tagWithContext(coin, "Coin", ctx.section, ctx.building, level)
	return coin
end

-- A dead end is a leaf of the spanning tree: three walls out of four. Cells next
-- to the sealed stairwell count too, and correctly so, since the seal is what
-- made them dead ends.
local function isDeadEnd(cell)
	local walls = 0
	for _, side in ipairs(SIDE_ORDER) do
		if cell.walls[side] then
			walls = walls + 1
		end
	end
	return walls >= 3
end

-- The carved maze is a spanning tree, so there is exactly one route from the
-- entry cell to the stairs and walking distances down from the stair cell finds
-- it. Phantoms never enter this: they are tagged onto existing walls and leave
-- `g` untouched, so the route measured here is the one a player who ignores
-- shortcuts actually walks.
local function mainPath(g, entryCell, stairCell)
	local dist = cellDistances(g, entryCell, {})
	local path = {}
	if dist[stairCell.x][stairCell.z] == nil then
		return path
	end

	local cur = stairCell
	while not (cur.x == entryCell.x and cur.z == entryCell.z) do
		table.insert(path, cur)
		local stepped = false
		for _, side in ipairs(SIDE_ORDER) do
			local n = neighborCell(cur, side)
			if inBounds(n) and not g[cur.x][cur.z].walls[side] and dist[n.x][n.z] == dist[cur.x][cur.z] - 1 then
				cur = n
				stepped = true
				break
			end
		end
		if not stepped then
			break
		end
	end
	return path
end

local function buildCollectibles(parent, origin, baseY, g, blocked, entryCell, route, rng, ctx)
	local folder = Instance.new("Folder")
	folder.Name = "Collectibles"
	folder.Parent = parent

	local claimed = {}
	local function eligible(c)
		local key = c.x .. "_" .. c.z
		return not claimed[key]
			and not g[c.x][c.z].reserved
			and not blocked[key]
			and not (c.x == entryCell.x and c.z == entryCell.z)
	end

	local deadEnds = {}
	for x = 1, CFG.MAZE_W do
		for z = 1, CFG.MAZE_H do
			local c = { x = x, z = z }
			if eligible(c) and isDeadEnd(g[x][z]) then
				table.insert(deadEnds, c)
			end
		end
	end

	local onPath = {}
	for _, c in ipairs(route) do
		if eligible(c) then
			table.insert(onPath, c)
		end
	end

	local function anywhere()
		local pool = {}
		for x = 1, CFG.MAZE_W do
			for z = 1, CFG.MAZE_H do
				local c = { x = x, z = z }
				if eligible(c) then
					table.insert(pool, c)
				end
			end
		end
		return pool
	end

	local function draw(pool)
		if #pool == 0 then
			return nil
		end
		local i = rng:NextInteger(1, #pool)
		local c = pool[i]
		table.remove(pool, i)
		claimed[c.x .. "_" .. c.z] = true
		return c
	end

	local function coinAt(c)
		local center = cellCenter(c.x, c.z)
		makeCoin(folder, origin + Vector3.new(center.X, baseY + CFG.COIN_HEIGHT, center.Z), ctx, ctx.level)
	end

	-- No kind is drawn here. PickupService rolls one when the orb is touched, so
	-- what an orb is worth is not a property of the city, and the same orb is a
	-- different prize to the next player to reach it.
	local function orbAt(c)
		local center = cellCenter(c.x, c.z)
		local orbColor = Config.Collectibles.PowerupOrbColor
		local orb = makePart(
			folder,
			"Powerup",
			CFrame.new(origin + Vector3.new(center.X, baseY + CFG.POWERUP_HEIGHT, center.Z)),
			Vector3.new(CFG.POWERUP_SIZE, CFG.POWERUP_SIZE, CFG.POWERUP_SIZE),
			orbColor,
			Enum.Material.Neon
		)
		orb.Shape = Enum.PartType.Ball
		orb.CanCollide = false
		orb.CastShadow = false
		tagWithContext(orb, "Powerup", ctx.section, ctx.building, ctx.level)

		-- Thirty of these per tower now rather than three, against nine hundred and
		-- sixty lamps, so the light is still a rounding error on the level and it
		-- is the only thing that makes an orb findable from the far end of a
		-- corridor.
		local glow = Instance.new("PointLight")
		glow.Brightness = 3
		glow.Range = 26
		glow.Color = orbColor
		glow.Shadows = false
		glow.Parent = orb
	end

	-- Dead ends first, then the route, then anywhere still open. The top-up is
	-- what makes the total per level exact instead of a target: a floor whose
	-- spanning tree happens to have few leaves, or whose route to the stairs is
	-- short, would otherwise quietly place fewer coins and make the part count a
	-- function of the seed rather than of the settings. Every floor pays the
	-- same; only where it pays is drawn.
	local placed = 0
	local target = CFG.COIN_DEAD_END_PER_LEVEL + CFG.COIN_PATH_PER_LEVEL

	for _ = 1, math.min(CFG.COIN_DEAD_END_PER_LEVEL, #deadEnds) do
		coinAt(draw(deadEnds))
		placed = placed + 1
	end
	for _ = 1, math.min(CFG.COIN_PATH_PER_LEVEL, #onPath) do
		coinAt(draw(onPath))
		placed = placed + 1
	end
	if placed < target then
		local rest = anywhere()
		for _ = 1, math.min(target - placed, #rest) do
			coinAt(draw(rest))
		end
	end

	-- Powerups take whatever dead ends the coins left, so the loudest thing on the
	-- floor is still the thing furthest from the route, and they top up from open
	-- maze the same way the coins do. Same reason as the coins, too: every level
	-- places exactly POWERUPS_PER_LEVEL however few leaves its spanning tree
	-- happened to grow, so the part count stays a function of the settings.
	local orbs = 0
	local spare
	while orbs < CFG.POWERUPS_PER_LEVEL do
		local c = draw(deadEnds)
		if not c then
			spare = spare or anywhere()
			c = draw(spare)
		end
		if not c then
			break
		end
		orbAt(c)
		orbs = orbs + 1
	end

	return folder
end

local function buildEnemySpawns(parent, origin, baseY, g, blocked, entryCell, style, rng, ctx)
	local folder = Instance.new("Folder")
	folder.Name = "EnemySpawns"
	folder.Parent = parent

	local pool = {}
	for x = 1, CFG.MAZE_W do
		for z = 1, CFG.MAZE_H do
			local key = x .. "_" .. z
			if not g[x][z].reserved and not blocked[key] and not (x == entryCell.x and z == entryCell.z) then
				table.insert(pool, { x = x, z = z })
			end
		end
	end

	for _ = 1, math.min(CFG.ENEMY_SPAWNS_PER_LEVEL, #pool) do
		local i = rng:NextInteger(1, #pool)
		local c = pool[i]
		table.remove(pool, i)

		local center = cellCenter(c.x, c.z)
		local marker = makePart(
			folder,
			"EnemySpawn",
			CFrame.new(origin + Vector3.new(center.X, baseY + 3, center.Z)),
			Vector3.new(3, 3, 3),
			Color3.fromRGB(255, 0, 0),
			Enum.Material.SmoothPlastic
		)
		marker.Transparency = 1
		marker.CanCollide = false
		marker:SetAttribute("EnemyType", style.enemy)
		tagWithContext(marker, "EnemySpawn", ctx.section, ctx.building, ctx.level)
	end
end

local function buildLevelTrigger(parent, origin, baseY, entryCell, route, ctx)
	local c = cellCenter(entryCell.x, entryCell.z)
	local trigger = makePart(
		parent,
		"LevelTrigger",
		CFrame.new(origin + Vector3.new(c.X, baseY + 4, c.Z)),
		Vector3.new(CFG.CELL - 3, 8, CFG.CELL - 3),
		Color3.fromRGB(0, 255, 0),
		Enum.Material.SmoothPlastic
	)
	trigger.Transparency = 1
	trigger.CanCollide = false
	trigger:SetAttribute("TowerName", ctx.towerName)

	-- The walk from this cell to the stairs, which is what the Reveal powerup
	-- draws. Stored as integer offsets from the trigger's own position rather than
	-- as world points: the trigger sits on the entry cell centre, so a client can
	-- rebuild every point by adding to a position it already has, without knowing
	-- CELL or the plot origin, and offsets are three digits where world
	-- coordinates run to five. mainPath is reversed on the way in so the string
	-- reads in the direction a player walks it.
	--
	-- Costs no parts and draws no random numbers: mainPath is a pure walk of the
	-- spanning tree carve() has already finished, per invariant 6.
	local hops = {}
	for i = #route, 1, -1 do
		local rc = cellCenter(route[i].x, route[i].z)
		table.insert(hops, string.format("%d,%d", math.round(rc.X - c.X), math.round(rc.Z - c.Z)))
	end
	trigger:SetAttribute("Route", table.concat(hops, ";"))

	tagWithContext(trigger, "LevelTrigger", ctx.section, ctx.building, ctx.level)
end

-- ============================================================
-- One level
-- ============================================================

local function buildLevel(buildingFolder, origin, level, entrySide, entryCell, style, rng, ctx)
	local baseY = level * LEVEL_HEIGHT
	ctx.level = level

	local exitSide = rotateSide(entrySide, rng:NextNumber() < 0.5 and 1 or -1)
	local cellE = edgeCell(exitSide, pickExitIndex(exitSide, entryCell, rng))
	local cellB = neighborCell(cellE, OPPOSITE[exitSide])

	local g = newGrid({ cellE, cellB })
	carve(g, entryCell, rng)

	sealCell(g, cellE)
	sealCell(g, cellB)
	openBetween(g, cellB, exitSide)
	openBetween(g, cellB, OPPOSITE[exitSide])

	-- Level 0's entry cell keeps its boundary wall. Dropping it opened the full
	-- 25-stud cell to the apron, so the 16-stud front door led into an alcove
	-- wider than itself; buildWalls splits this one wall around a door-width gap
	-- instead, leaving the facade opening, the apron, and the maze opening the
	-- same width and in line.
	local door = (level == 0) and { x = entryCell.x, z = entryCell.z, side = entrySide } or nil

	local folder = Instance.new("Folder")
	folder.Name = "Level_" .. level
	folder:SetAttribute("Level", level)
	folder:SetAttribute("EntrySide", entrySide)
	folder:SetAttribute("ExitSide", exitSide)
	folder:SetAttribute("Section", ctx.section)
	folder:SetAttribute("Building", ctx.building)
	folder.Parent = buildingFolder

	local blocked = {
		[cellE.x .. "_" .. cellE.z] = true,
		[cellB.x .. "_" .. cellB.z] = true,
	}

	local interior = buildWalls(folder, origin, baseY, g, style, door)
	local used = tagPhantoms(interior, g, blocked, entryCell, cellB, CFG.PHANTOM_PER_LEVEL, rng, ctx)
	tagMovingWalls(interior, blocked, used, level, rng, ctx)

	local hole = buildStairs(folder, origin, baseY, exitSide, cellB, style)
	buildLamps(folder, origin, baseY)

	buildEnemySpawns(folder, origin, baseY, g, blocked, entryCell, style, rng, ctx)
	-- A sub-stream off the building seed rather than the threaded rng. The
	-- closest two building seeds get is 7919 apart and level * 31 never reaches
	-- 255 levels' worth of that, so no two levels in the city share a stream.
	local coinRng = Random.new(ctx.seed + level * 31)
	-- Computed once here and handed to both: the path coins stand on it and the
	-- LevelTrigger carries it for the Reveal powerup. It is a pure function of the
	-- carved grid, so lifting the call out of buildCollectibles moved no draw and
	-- changed no coin's cell.
	local route = mainPath(g, entryCell, cellB)
	buildCollectibles(folder, origin, baseY, g, blocked, entryCell, route, coinRng, ctx)
	buildLevelTrigger(folder, origin, baseY, entryCell, route, ctx)

	return {
		exitSide = exitSide,
		exitCell = cellE,
		hole = hole,
		folder = folder,
	}
end

-- ============================================================
-- Facade
-- ============================================================

local function buildWindows(parent, origin, style, side, doorU)
	local O = CFG.FACADE_OUTSET + CFG.FACADE_THICKNESS
	local horizontal = (side == "north" or side == "south")
	local faceLen = horizontal and FX or FZ
	local glass = style.facadeGlass or style.glass

	local clearHalf = CFG.DOOR_WIDTH / 2 + CFG.DOOR_CLEARANCE
	local clearTop = CFG.DOOR_HEIGHT + CFG.DOOR_CLEARANCE

	local function place(u, y, lenU, height, thick)
		local pos
		if side == "north" then
			pos = Vector3.new(u, y, -O - 0.3)
		elseif side == "south" then
			pos = Vector3.new(u, y, FZ + O + 0.3)
		elseif side == "west" then
			pos = Vector3.new(-O - 0.3, y, u)
		else
			pos = Vector3.new(FX + O + 0.3, y, u)
		end
		local size = horizontal and Vector3.new(lenU, height, thick) or Vector3.new(thick, height, lenU)
		local w = makePart(parent, "Window", CFrame.new(origin + pos), size, glass, Enum.Material.Glass)
		w.Reflectance = 0.12
		w.CanCollide = false
		w.Transparency = 0.22
		if doorU and math.abs(u - doorU) < lenU / 2 + clearHalf and y - height / 2 < clearTop then
			w.Transparency = 1
			w.Reflectance = 0
			w.CanTouch = false
			w.CanQuery = false
		end
	end

	if style.windows == "grid" then
		local cols = 7
		local gap = faceLen / (cols + 1)
		for L = 0, CFG.LEVELS - 1 do
			local y = L * LEVEL_HEIGHT + CFG.WALL_HEIGHT * 0.55
			for c = 1, cols do
				place(gap * c, y, 9, 7.5, 1.2)
			end
		end
	elseif style.windows == "ribbon" then
		for L = 0, CFG.LEVELS - 1 do
			local y = L * LEVEL_HEIGHT + CFG.WALL_HEIGHT * 0.55
			place(faceLen / 2, y, faceLen * 0.86, 5.5, 1.2)
		end
	else
		local cols = 5
		local gap = faceLen / (cols + 1)
		local totalH = CFG.LEVELS * LEVEL_HEIGHT
		for c = 1, cols do
			place(gap * c, totalH / 2, 7, totalH * 0.92, 1.2)
		end
	end
end

local function facePart(parent, origin, name, side, u, y, lenU, height, depth, color, material, offset)
	local O = CFG.FACADE_OUTSET + CFG.FACADE_THICKNESS + (offset or 0.18)
	local pos
	local size
	if side == "north" then
		pos = Vector3.new(u, y, -O)
		size = Vector3.new(lenU, height, depth)
	elseif side == "south" then
		pos = Vector3.new(u, y, FZ + O)
		size = Vector3.new(lenU, height, depth)
	elseif side == "west" then
		pos = Vector3.new(-O, y, u)
		size = Vector3.new(depth, height, lenU)
	else
		pos = Vector3.new(FX + O, y, u)
		size = Vector3.new(depth, height, lenU)
	end

	local part = makePart(parent, name, CFrame.new(origin + pos), size, color, material)
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	return part
end

local function detailColor(base, shade, glow)
	if glow then
		return base:Lerp(Color3.fromRGB(255, 255, 255), shade)
	end
	return base:Lerp(Color3.fromRGB(0, 0, 0), shade)
end

local function facadeSkin(style)
	return style.facadeSkin or style.skin
end

local function facadeTrim(style)
	return style.facadeTrim or style.trim
end

local function facadeMaterial(style)
	return style.facadeMaterial or Enum.Material.Slate
end

local function maybeSkipDoor(side, entrySide, doorU, u, y, lenU, height)
	if side ~= entrySide then
		return false
	end
	local clearHalf = CFG.DOOR_WIDTH / 2 + CFG.DOOR_CLEARANCE + lenU / 2
	local clearTop = CFG.DOOR_HEIGHT + CFG.DOOR_CLEARANCE
	return math.abs(u - doorU) < clearHalf and y - height / 2 < clearTop
end

local function buildExteriorMystery(parent, origin, style, entrySide, entryCell, ctx)
	local rng = Random.new(ctx.seed + 61291)
	local O = CFG.FACADE_OUTSET + CFG.FACADE_THICKNESS
	local height = ROOF_Y + CFG.PARAPET_HEIGHT
	local doorCenter = cellCenter(entryCell.x, entryCell.z)
	local doorU = (entrySide == "north" or entrySide == "south") and doorCenter.X or doorCenter.Z
	local skin = facadeSkin(style)
	local trim = facadeTrim(style)
	local stoneMaterial = facadeMaterial(style)
	local accent = style.accent or style.trim
	local shadow = detailColor(skin, 0.42, false)
	local deep = detailColor(skin, 0.62, false)
	local pale = accent:Lerp(Color3.fromRGB(255, 255, 255), 0.32)

	ctx.exteriorTheme = style.theme
	ctx.exteriorVariant = rng:NextInteger(1000, 9999)

	local function place(side, name, u, y, lenU, h, depth, color, material, offset, neon)
		if maybeSkipDoor(side, entrySide, doorU, u, y, lenU, h) then
			return nil
		end
		local part = facePart(parent, origin, name, side, u, y, lenU, h, depth, color, material, offset)
		if neon then
			part.Material = Enum.Material.Neon
			part.CastShadow = false
		end
		return part
	end

	local function mazeLine(side, name, u0, y0, u1, y1, color, width)
		local du = math.abs(u1 - u0)
		local dy = math.abs(y1 - y0)
		if du >= dy then
			return place(side, name, (u0 + u1) / 2, y0, du + width, width, 0.55, color, Enum.Material.Neon, 1.18, true)
		end
		return place(side, name, u0, (y0 + y1) / 2, width, dy + width, 0.55, color, Enum.Material.Neon, 1.18, true)
	end

	local function buildStoneCourses(side, faceLen)
		local courses = CFG.LEVELS * 2
		for course = 1, courses do
			local y = height * course / (courses + 1) + rng:NextNumber(-0.45, 0.45)
			place(
				side,
				"KeptStoneCourse",
				faceLen / 2,
				y,
				faceLen * rng:NextNumber(0.82, 0.98),
				0.18,
				0.32,
				deep,
				stoneMaterial,
				1.02
			)
		end

		for course = 0, courses - 1 do
			local bandY = height * (course + 0.5) / courses
			local bandH = height / courses
			for _ = 1, rng:NextInteger(3, 5) do
				local u = rng:NextNumber(faceLen * 0.06, faceLen * 0.94)
				place(
					side,
					"KeptStoneJoint",
					u,
					bandY + rng:NextNumber(-bandH * 0.18, bandH * 0.18),
					0.16,
					bandH * rng:NextNumber(0.35, 0.75),
					0.3,
					shadow,
					stoneMaterial,
					1.04
				)
			end
		end
	end

	local function buildMazeTracery(side, faceLen)
		local cols = 9
		local rows = math.max(9, CFG.LEVELS + 3)
		local cellU = faceLen / (cols + 1)
		local cellY = height / (rows + 1)
		local color = accent:Lerp(Color3.fromRGB(255, 255, 255), 0.08)
		local dimColor = accent:Lerp(skin, 0.38)

		for _ = 1, 3 do
			local gx = rng:NextInteger(2, cols - 1)
			local gy = rng:NextInteger(2, rows - 1)
			local steps = rng:NextInteger(9, 15)
			for step = 1, steps do
				local oldX, oldY = gx, gy
				if rng:NextNumber() < 0.5 then
					gx = math.clamp(gx + (rng:NextNumber() < 0.5 and -1 or 1), 1, cols)
				else
					gy = math.clamp(gy + (rng:NextNumber() < 0.5 and -1 or 1), 1, rows)
				end

				local u0 = oldX * cellU + rng:NextNumber(-1.1, 1.1)
				local y0 = oldY * cellY + rng:NextNumber(-0.7, 0.7)
				local u1 = gx * cellU + rng:NextNumber(-1.1, 1.1)
				local y1 = gy * cellY + rng:NextNumber(-0.7, 0.7)
				mazeLine(side, "KeptMazeLine", u0, y0, u1, y1, (step % 3 == 0) and dimColor or color, 0.42)

				if step % 4 == 0 then
					place(side, "KeptMazeNode", u1, y1, 1.8, 1.8, 0.62, color, Enum.Material.Neon, 1.2, true)
				end
			end
		end
	end

	for _, side in ipairs(SIDE_ORDER) do
		local horizontal = (side == "north" or side == "south")
		local faceLen = horizontal and FX or FZ

		buildStoneCourses(side, faceLen)
		buildMazeTracery(side, faceLen)

		local ribCount = rng:NextInteger(3, 5)
		for i = 1, ribCount do
			local u = faceLen * i / (ribCount + 1) + rng:NextNumber(-6, 6)
			local ribH = height * rng:NextNumber(0.72, 0.98)
			local ribY = height - ribH / 2
			place(
				side,
				"MysteryRib",
				u,
				ribY,
				rng:NextNumber(1.6, 3.6),
				ribH,
				rng:NextNumber(2.4, 4.8),
				shadow,
				stoneMaterial,
				0.8
			)
		end

		for _ = 1, rng:NextInteger(2, 4) do
			local level = rng:NextInteger(1, math.max(1, CFG.LEVELS - 1))
			local y = level * LEVEL_HEIGHT + rng:NextNumber(1.2, 4.8)
			place(
				side,
				"MysteryBelt",
				faceLen / 2,
				y,
				faceLen * rng:NextNumber(0.68, 0.96),
				1.1,
				2.2,
				deep,
				stoneMaterial,
				0.55
			)
		end

		if style.exterior == "archive" then
			for _ = 1, rng:NextInteger(5, 8) do
				local u = rng:NextNumber(faceLen * 0.1, faceLen * 0.9)
				local y = rng:NextNumber(LEVEL_HEIGHT * 0.8, height - 12)
				place(
					side,
					"ArchiveGlyph",
					u,
					y,
					rng:NextNumber(2.2, 4.5),
					rng:NextNumber(2.2, 4.5),
					0.45,
					accent,
					Enum.Material.Neon,
					1.0,
					true
				)
				place(
					side,
					"ArchiveGlyphStem",
					u,
					y - 5,
					0.55,
					rng:NextNumber(5, 10),
					0.42,
					accent,
					Enum.Material.Neon,
					1.03,
					true
				)
			end
		elseif style.exterior == "reliquary" then
			local archCount = rng:NextInteger(3, 5)
			for i = 1, archCount do
				local u = faceLen * i / (archCount + 1) + rng:NextNumber(-8, 8)
				local y = rng:NextNumber(LEVEL_HEIGHT * 1.2, height - 28)
				local archH = rng:NextNumber(18, 28)
				local archW = rng:NextNumber(12, 18)
				place(side, "ReliquaryPillar", u - archW / 2, y, 1.3, archH, 1.6, pale, stoneMaterial, 0.7)
				place(side, "ReliquaryPillar", u + archW / 2, y, 1.3, archH, 1.6, pale, stoneMaterial, 0.7)
				place(
					side,
					"ReliquaryLintel",
					u,
					y + archH / 2,
					archW + 3,
					1.8,
					1.8,
					accent,
					Enum.Material.Neon,
					0.9,
					true
				)
			end
		elseif style.exterior == "monolith" then
			for _ = 1, rng:NextInteger(6, 10) do
				local u = rng:NextNumber(faceLen * 0.08, faceLen * 0.92)
				local crackY = rng:NextNumber(LEVEL_HEIGHT, height - 20)
				local crackH = rng:NextNumber(8, 20)
				place(side, "MonolithCrack", u, crackY, 0.75, crackH, 0.5, accent, Enum.Material.Neon, 1.1, true)
				place(
					side,
					"MonolithScar",
					u + rng:NextNumber(-2, 2),
					crackY - crackH * 0.35,
					2.2,
					0.65,
					0.45,
					accent,
					Enum.Material.Neon,
					1.12,
					true
				)
			end
		elseif style.exterior == "alchemy" then
			for _ = 1, rng:NextInteger(4, 7) do
				local u = rng:NextNumber(faceLen * 0.08, faceLen * 0.92)
				local pipeH = rng:NextNumber(height * 0.35, height * 0.78)
				local y = rng:NextNumber(pipeH / 2 + 8, height - pipeH / 2)
				place(side, "AlchemyConduit", u, y, 1.6, pipeH, 1.8, accent:Lerp(skin, 0.35), Enum.Material.Metal, 1.0)
				place(side, "AlchemyValve", u, y + pipeH / 2, 6, 1.6, 2, accent, Enum.Material.Neon, 1.18, true)
			end
		elseif style.exterior == "ossuary" then
			for _ = 1, rng:NextInteger(4, 7) do
				local u = rng:NextNumber(faceLen * 0.08, faceLen * 0.92)
				local y = rng:NextNumber(LEVEL_HEIGHT * 0.7, height - 14)
				place(side, "OssuaryRibLeft", u - 2.4, y, 1.1, 14, 1.2, pale, stoneMaterial, 0.78)
				place(side, "OssuaryRibRight", u + 2.4, y, 1.1, 14, 1.2, pale, stoneMaterial, 0.78)
				place(side, "OssuarySeal", u, y, 5.8, 2.2, 0.55, deep, stoneMaterial, 1.0)
			end
		elseif style.exterior == "cinder" then
			for _ = 1, rng:NextInteger(7, 11) do
				local u = rng:NextNumber(faceLen * 0.08, faceLen * 0.92)
				local y = rng:NextNumber(LEVEL_HEIGHT * 0.6, height - 10)
				local h = rng:NextNumber(5, 15)
				place(
					side,
					"CinderFissure",
					u,
					y,
					rng:NextNumber(0.7, 1.4),
					h,
					0.55,
					accent,
					Enum.Material.Neon,
					1.12,
					true
				)
				place(
					side,
					"CinderSoot",
					u + rng:NextNumber(-3, 3),
					y - h / 2,
					rng:NextNumber(4, 9),
					1.1,
					0.5,
					deep,
					Enum.Material.Slate,
					1.0
				)
			end
		end
	end

	for _, corner in ipairs({
		Vector3.new(-O - 1.8, height / 2, -O - 1.8),
		Vector3.new(FX + O + 1.8, height / 2, -O - 1.8),
		Vector3.new(-O - 1.8, height / 2, FZ + O + 1.8),
		Vector3.new(FX + O + 1.8, height / 2, FZ + O + 1.8),
	}) do
		local cornerHeight = height * rng:NextNumber(0.88, 1.0)
		local p = makePart(
			parent,
			"MysteryCorner",
			CFrame.new(origin + Vector3.new(corner.X, cornerHeight / 2, corner.Z)),
			Vector3.new(3.6, cornerHeight, 3.6),
			trim:Lerp(Color3.fromRGB(0, 0, 0), 0.45),
			stoneMaterial
		)
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
	end
end

-- How far out from the deck centre the crown reaches, at its widest. Every crown
-- is centred and every piece of one is a box or a cylinder about that centre, so
-- one number describes the whole keep-out on both axes. Anything placed on the
-- deck that a player is meant to travel upward through has to clear this.
local function crownHalfSpan(style)
	if style.crown == "setback" then
		return FZ * math.max(CFG.CROWN_SETBACK_BODY, CFG.CROWN_SETBACK_CAP) / 2
	elseif style.crown == "spire" then
		return FZ * CFG.CROWN_SPIRE_BASE / 2
	elseif style.crown == "watertower" then
		return CFG.CROWN_TANK / 2
	end
	return 0
end

local function buildCrown(parent, origin, style)
	local topY = ROOF_Y + CFG.PARAPET_HEIGHT
	local cx, cz = FX / 2, FZ / 2
	local skin = facadeSkin(style)
	local trim = facadeTrim(style)
	local material = facadeMaterial(style)

	if style.crown == "setback" then
		makePart(
			parent,
			"Penthouse",
			CFrame.new(origin + Vector3.new(cx, topY + 14, cz)),
			Vector3.new(FX * CFG.CROWN_SETBACK_BODY, 28, FZ * CFG.CROWN_SETBACK_BODY),
			skin,
			material
		)
		makePart(
			parent,
			"PenthouseCap",
			CFrame.new(origin + Vector3.new(cx, topY + 29, cz)),
			Vector3.new(FX * CFG.CROWN_SETBACK_CAP, 2, FZ * CFG.CROWN_SETBACK_CAP),
			trim,
			Enum.Material.Metal
		)
	elseif style.crown == "spire" then
		local h = 18
		for i = 1, 5 do
			local f = 1 - (i - 1) * 0.17
			makePart(
				parent,
				"Spire" .. i,
				CFrame.new(origin + Vector3.new(cx, topY + (i - 0.5) * h, cz)),
				Vector3.new(FX * CFG.CROWN_SPIRE_BASE * f, h, FZ * CFG.CROWN_SPIRE_BASE * f),
				skin,
				material
			)
		end
		local mast = makePart(
			parent,
			"Mast",
			CFrame.new(origin + Vector3.new(cx, topY + 5 * h + 16, cz)),
			Vector3.new(2, 32, 2),
			style.accent or trim,
			Enum.Material.Neon
		)
		mast.Shape = Enum.PartType.Cylinder
		mast.CFrame = mast.CFrame * CFrame.Angles(0, 0, math.rad(90))
	elseif style.crown == "watertower" then
		for _, off in ipairs({ { -14, -14 }, { 14, -14 }, { -14, 14 }, { 14, 14 } }) do
			makePart(
				parent,
				"TowerLeg",
				CFrame.new(origin + Vector3.new(cx + off[1], topY + 11, cz + off[2])),
				Vector3.new(2, 22, 2),
				trim,
				Enum.Material.Metal
			)
		end
		local tank = makePart(
			parent,
			"Tank",
			CFrame.new(origin + Vector3.new(cx, topY + 36, cz)),
			Vector3.new(CFG.CROWN_TANK, CFG.CROWN_TANK, CFG.CROWN_TANK),
			skin,
			Enum.Material.CorrodedMetal
		)
		tank.Shape = Enum.PartType.Cylinder
		tank.CFrame = tank.CFrame * CFrame.Angles(0, 0, math.rad(90))
	end
end

local function buildFacade(parent, origin, style, entrySide, entryCell, ctx)
	local folder = Instance.new("Folder")
	folder.Name = "Facade"
	folder.Parent = parent

	local towerName = ctx.towerName

	local O = CFG.FACADE_OUTSET
	local T = CFG.FACADE_THICKNESS
	local height = ROOF_Y + CFG.PARAPET_HEIGHT
	local midY = height / 2
	local skin = facadeSkin(style)
	local material = facadeMaterial(style)

	local faces = {
		north = { pos = Vector3.new(FX / 2, midY, -O - T / 2), size = Vector3.new(FX + 2 * (O + T), height, T) },
		south = { pos = Vector3.new(FX / 2, midY, FZ + O + T / 2), size = Vector3.new(FX + 2 * (O + T), height, T) },
		west = { pos = Vector3.new(-O - T / 2, midY, FZ / 2), size = Vector3.new(T, height, FZ + 2 * (O + T)) },
		east = { pos = Vector3.new(FX + O + T / 2, midY, FZ / 2), size = Vector3.new(T, height, FZ + 2 * (O + T)) },
	}

	local doorCenter = cellCenter(entryCell.x, entryCell.z)
	local doorU = (entrySide == "north" or entrySide == "south") and doorCenter.X or doorCenter.Z

	for _, side in ipairs(SIDE_ORDER) do
		local f = faces[side]
		if side ~= entrySide then
			makePart(folder, "Facade_" .. side, CFrame.new(origin + f.pos), f.size, skin, material)
		else
			local horizontal = (side == "north" or side == "south")
			local total = horizontal and f.size.X or f.size.Z
			local uStart = horizontal and (f.pos.X - total / 2) or (f.pos.Z - total / 2)
			local leftLen = (doorU - CFG.DOOR_WIDTH / 2) - uStart
			local rightLen = (uStart + total) - (doorU + CFG.DOOR_WIDTH / 2)

			local function panel(name, uCenter, uLen, y, h)
				local pos, size
				if horizontal then
					pos = Vector3.new(uCenter, y, f.pos.Z)
					size = Vector3.new(uLen, h, T)
				else
					pos = Vector3.new(f.pos.X, y, uCenter)
					size = Vector3.new(T, h, uLen)
				end
				makePart(folder, name, CFrame.new(origin + pos), size, skin, material)
			end

			if leftLen > 0.1 then
				panel("Facade_" .. side .. "_L", uStart + leftLen / 2, leftLen, midY, height)
			end
			if rightLen > 0.1 then
				panel("Facade_" .. side .. "_R", uStart + total - rightLen / 2, rightLen, midY, height)
			end
			panel(
				"Facade_" .. side .. "_Header",
				doorU,
				CFG.DOOR_WIDTH,
				CFG.DOOR_HEIGHT + (height - CFG.DOOR_HEIGHT) / 2,
				height - CFG.DOOR_HEIGHT
			)
		end

		buildWindows(folder, origin, style, side, side == entrySide and doorU or nil)
	end

	buildExteriorMystery(folder, origin, style, entrySide, entryCell, ctx)
	parent:SetAttribute("ExteriorTheme", ctx.exteriorTheme)
	parent:SetAttribute("ExteriorVariant", ctx.exteriorVariant)

	local plazaCenter
	if entrySide == "north" then
		plazaCenter = Vector3.new(doorCenter.X, 0, -O - T - 14)
	elseif entrySide == "south" then
		plazaCenter = Vector3.new(doorCenter.X, 0, FZ + O + T + 14)
	elseif entrySide == "west" then
		plazaCenter = Vector3.new(-O - T - 14, 0, doorCenter.Z)
	else
		plazaCenter = Vector3.new(FX + O + T + 14, 0, doorCenter.Z)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "TowerStart"
	spawn.Anchored = true
	spawn.Size = Vector3.new(CFG.DOOR_WIDTH + 6, 1, 28)
	if entrySide == "west" or entrySide == "east" then
		spawn.Size = Vector3.new(28, 1, CFG.DOOR_WIDTH + 6)
	end
	spawn.CFrame = CFrame.new(origin + plazaCenter + Vector3.new(0, 0.5, 0))
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Color = style.trim
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Neutral = true
	spawn.AllowTeamChangeOnTouch = false
	-- Every tower plaza is a SpawnLocation, but only section 1's are eligible
	-- for the join and death respawn roll. Leaving them all enabled drops
	-- players into lazily built sections they have never reached, and on a
	-- section that has not been generated yet there is nothing to stand on.
	-- TowerTimerService still teleports off these for floor and tower restarts.
	spawn.Enabled = (ctx.section == 1)
	spawn:SetAttribute("TowerName", towerName)
	spawn.Parent = folder
	-- The plaza is at street level, so the spawn belongs to level 0 regardless
	-- of how far up the tower the player has climbed.
	tagWithContext(spawn, "TowerStart", ctx.section, ctx.building, 0)

	-- Two lines rather than one, and wider than it was: the name went from six
	-- characters to about thirty when the towers stopped being called S1-E2, and
	-- a fixed TextSize in a fixed box clips rather than shrinks. The tower is the
	-- thing being pointed at, so it is the larger line and it is the one carved
	-- letter in the plaza; the district is the qualifier, sits under it, and
	-- keeps the building style's own accent, which is world colour and not
	-- chrome. The name is scaled under a ceiling rather than set at a size,
	-- because a blackletter face sets wider than the Gotham this box was
	-- measured for and clipping the tower's name is the one failure this plate
	-- has: the ceiling stops a short name from ballooning to fill the slab.
	local slab = plateGui(spawn, 300, 54, 6.5, 400, true)
	local name =
		plateLine(slab, UDim2.new(1, -14, 0.58, 0), UDim2.new(0, 7, 0, 3), PLATE.Display, 22, PLATE.Text, ctx.shortName)
	name.TextScaled = true
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = 22
	fit.Parent = name

	plateLine(slab, UDim2.new(1, -14, 0.32, 0), UDim2.new(0, 7, 0.6, 0), PLATE.Body, 13, style.accent, ctx.district)

	buildCrown(folder, origin, style)
end

-- ============================================================
-- Roof deck
-- ============================================================

-- The one piece of pet-system geometry, and the only reason it is geometry at
-- all: nothing may be parented into workspace.MazeCity at runtime, so a prompt
-- on the summit has to be built here or not exist. IncubatorService owns what
-- the prompt does, discovered through the EggPedestal tag the way SaveService
-- discovers ShopItem.
--
-- The egg on top is decoration, not the player's egg: the incubator is one slot
-- per player and every roof in the city carries one of these, so a shared world
-- egg would be showing six players someone else's. The client draws the real one
-- over whichever roost its own player is standing at.
local function buildEggRoost(parent, origin, style, ctx)
	local center = Vector3.new(FX / 2, ROOF_Y, FZ * CFG.ROOST_Z_FRAC)

	local pedestal = makePart(
		parent,
		"EggPedestal",
		CFrame.new(origin + center + Vector3.new(0, CFG.ROOST_BASE / 2, 0)),
		Vector3.new(5, CFG.ROOST_BASE, 5),
		style.trim,
		Enum.Material.Marble
	)

	local egg = makePart(
		parent,
		"RoostEgg",
		CFrame.new(origin + center + Vector3.new(0, CFG.ROOST_BASE + CFG.ROOST_EGG * 0.55, 0)),
		Vector3.new(CFG.ROOST_EGG * 0.8, CFG.ROOST_EGG, CFG.ROOST_EGG * 0.8),
		Color3.fromRGB(240, 245, 250),
		Enum.Material.Neon
	)
	egg.Shape = Enum.PartType.Ball
	egg.CanCollide = false
	egg.CastShadow = false

	-- Lantern, the same gold the stall's sign wears, because the two counters in
	-- this city that spend coins are the two counters that spend coins and the
	-- theme gives one colour one meaning. What tells them apart is what they
	-- stand on, not what colour they are.
	local slab = plateGui(pedestal, 160, 34, 5.2, 120, true)
	plateLine(slab, UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), PLATE.Display, 17, PLATE.Lantern, "EGG ROOST")

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Eggs"
	prompt.ObjectText = "Egg Roost"
	prompt.MaxActivationDistance = Config.Pets.PromptDistance
	prompt.HoldDuration = Config.Pets.PromptHoldSeconds
	prompt.RequiresLineOfSight = false
	prompt.Parent = pedestal

	tagWithContext(pedestal, "EggPedestal", ctx.section, ctx.building, CFG.LEVELS)
	return pedestal
end

-- The two ends of a slide, and the only place either is worked out. Three
-- callers need the same line: buildSlide draws the chute along it, the roof
-- stamps its direction onto the SlideEntrance so TraversalService can point a
-- rider down it rather than shoving them whichever way they were facing, and
-- the same attributes tell that service where the chute is when a rider comes
-- off it. A second derivation is how a mouth ends up aimed somewhere the chute
-- does not go, which is invisible in a diff and only findable by riding it.
--
-- Pure maths, and the section N+1 reference is sectionOrigin, which is the only
-- thing invariant 4 allows a section to know about its successor.
local function slideRoute(origin, sectionIndex)
	local start = origin + Vector3.new(FX + CFG.FACADE_OUTSET + CFG.SLIDE_MOUTH_CLEAR, ROOF_Y + 2, FZ / 2)
	local landing = MazeGenerator.sectionOrigin(sectionIndex + 1)
		+ Vector3.new(CFG.SLIDE_LANDING_X, CFG.SLIDE_LANDING_Y, PLOT_SPAN_Z * 0.5)
	return start, landing
end

local function buildRoof(parent, origin, hole, style, isExit, ctx)
	local folder = Instance.new("Folder")
	folder.Name = "Roof"
	folder.Parent = parent

	local towerName = ctx.towerName
	local sectionIndex = ctx.section
	local skin = facadeSkin(style)
	local trim = facadeTrim(style)
	local material = facadeMaterial(style)

	buildSlab(folder, origin, ROOF_Y, hole, skin, material, "RoofSlab")

	local O = CFG.FACADE_OUTSET
	local ring = {
		{
			pos = Vector3.new(FX / 2, ROOF_Y + CFG.PARAPET_HEIGHT / 2, -O),
			size = Vector3.new(FX + 2 * O, CFG.PARAPET_HEIGHT, 2),
		},
		{
			pos = Vector3.new(FX / 2, ROOF_Y + CFG.PARAPET_HEIGHT / 2, FZ + O),
			size = Vector3.new(FX + 2 * O, CFG.PARAPET_HEIGHT, 2),
		},
		{
			pos = Vector3.new(-O, ROOF_Y + CFG.PARAPET_HEIGHT / 2, FZ / 2),
			size = Vector3.new(2, CFG.PARAPET_HEIGHT, FZ + 2 * O),
		},
		{
			pos = Vector3.new(FX + O, ROOF_Y + CFG.PARAPET_HEIGHT / 2, FZ / 2),
			size = Vector3.new(2, CFG.PARAPET_HEIGHT, FZ + 2 * O),
		},
	}
	for i, r in ipairs(ring) do
		makePart(folder, "Parapet" .. i, CFrame.new(origin + r.pos), r.size, trim, material)
	end

	-- Win state. The roof has no LevelTrigger of its own because there is no
	-- level above it. This covers the whole deck rather than just the stair
	-- hole: the deck is open, so a player can step off the top of the stairs in
	-- any direction and a trigger sized to the opening is missable. It reaches
	-- two studs below the deck as well, to catch a player still rising through
	-- the shaft. inSameTower gates the award, so a roof nobody climbed to pays
	-- nothing.
	local arrival = makePart(
		folder,
		"RoofTrigger",
		CFrame.new(origin + Vector3.new(FX / 2, ROOF_Y + 3, FZ / 2)),
		Vector3.new(FX + 2 * O, 10, FZ + 2 * O),
		Color3.fromRGB(0, 200, 255),
		Enum.Material.SmoothPlastic
	)
	arrival.Transparency = 1
	arrival.CanCollide = false
	arrival:SetAttribute("TowerName", towerName)
	-- Where the stairs actually come up, which is not where this part is. The
	-- trigger deliberately covers the whole deck so that arriving anywhere on it
	-- counts, which puts its centre in the middle of the roof while the stairwell
	-- is out at an edge cell. Anything pointing a player at the way up has to aim
	-- here instead: on every other floor that job is done by the next floor's
	-- LevelTrigger, which already sits on the arrival cell, and the roof is the
	-- one storey with no floor above it to carry one.
	if hole then
		arrival:SetAttribute("ArrivalX", origin.X + hole.x)
		arrival:SetAttribute("ArrivalY", ROOF_Y + 3)
		arrival:SetAttribute("ArrivalZ", origin.Z + hole.z)
	end
	tagWithContext(arrival, "RoofTrigger", sectionIndex, ctx.building, CFG.LEVELS)

	local deck = Instance.new("Folder")
	deck.Name = "Deck"
	deck.Parent = folder

	-- The pads launched the player at nothing. Each one now has a helix of coins
	-- standing in its arc, tight enough around the launch axis that going up
	-- through the middle collects the lot. Pure geometry off the pad position,
	-- so it draws no random numbers and adds a fixed, countable number of parts.
	local arcs = Instance.new("Folder")
	arcs.Name = "CoinArcs"
	arcs.Parent = deck

	-- The pads are a row across the deck and the crown stands in the middle of it,
	-- so the two met by construction rather than by chance: the setback's cap is
	-- half the footprint across and sits 38 studs up, which is a lid over the
	-- middle pad and inside the arc all three throw through. The row is therefore
	-- placed at BOUNCE_PAD_Z_FRAC or outboard of whatever the crown actually
	-- occupies, whichever is nearer the parapet, so the launch column is clear on
	-- every style rather than on the ones whose crown happens to be narrow. This
	-- reads a decision generation has already made instead of drawing (invariant
	-- 6): it moves parts without adding, removing or rolling any, so styles with
	-- a spire, a water tower or a bare parapet are exactly where they were.
	local padHalf = CFG.BOUNCE_PAD_SIZE / 2
	local padZ = math.clamp(
		FZ / 2 - crownHalfSpan(style) - padHalf - CFG.BOUNCE_PAD_CLEARANCE,
		padHalf + CFG.BOUNCE_PAD_CLEARANCE,
		FZ * CFG.BOUNCE_PAD_Z_FRAC
	)

	for i = 1, 3 do
		local padCenter = Vector3.new(FX * (0.25 * i), ROOF_Y + 0.6, padZ)
		local pad = makePart(
			deck,
			"BouncePad",
			CFrame.new(origin + padCenter),
			Vector3.new(CFG.BOUNCE_PAD_SIZE, 1.2, CFG.BOUNCE_PAD_SIZE),
			Color3.fromRGB(255, 120, 200),
			Enum.Material.Neon
		)
		pad:SetAttribute("Power", Config.BouncePadPower)
		tagWithContext(pad, "BouncePad", sectionIndex, ctx.building, CFG.LEVELS)

		for k = 0, CFG.ROOF_ARC_COINS - 1 do
			local t = (CFG.ROOF_ARC_COINS > 1) and (k / (CFG.ROOF_ARC_COINS - 1)) or 0
			local angle = t * math.pi * 2
			local y = CFG.ARC_BASE_HEIGHT + (CFG.ARC_TOP_HEIGHT - CFG.ARC_BASE_HEIGHT) * t
			makeCoin(
				arcs,
				origin
					+ Vector3.new(
						padCenter.X + math.cos(angle) * CFG.ARC_RADIUS,
						ROOF_Y + y,
						padCenter.Z + math.sin(angle) * CFG.ARC_RADIUS
					),
				ctx,
				CFG.LEVELS
			)
		end
	end

	for i = 1, 4 do
		makePart(
			deck,
			"Planter",
			CFrame.new(origin + Vector3.new(FX * 0.15 * i, ROOF_Y + 2, FZ * 0.75)),
			Vector3.new(10, 4, 10),
			Color3.fromRGB(96, 128, 84),
			Enum.Material.Grass
		)
	end

	buildEggRoost(deck, origin, style, ctx)

	local sign = makePart(
		deck,
		"RoofSign",
		CFrame.new(origin + Vector3.new(FX / 2, ROOF_Y + 12, FZ * 0.92)),
		Vector3.new(FX * 0.5, 10, 1.5),
		style.trim,
		Enum.Material.Neon
	)
	sign.CanCollide = false

	-- The short name, not the full one. This is TextScaled on a plate 125 studs
	-- wide and 10 tall, so every extra character costs height on a sign read
	-- from the roof of the building three plots over; and a climber standing on
	-- a roof already knows which district they are in. Ink on a neon plate, so
	-- the letters are the unlit part of a lit sign, which is the largest carved
	-- lettering in the game and the one place the Display face gets to be huge
	-- outside a hatch reveal.
	carvedPlate(sign, 600, 120, PLATE.Display, PLATE.Ink, ctx.shortName)

	local amb = Instance.new("PointLight")
	amb.Brightness = 0.8
	amb.Range = 60
	amb.Color = style.trim
	amb.Parent = sign

	if isExit then
		local ent = makePart(
			deck,
			"SlideEntrance",
			CFrame.new(origin + Vector3.new(FX + O - 8, ROOF_Y + 2, FZ / 2)),
			Vector3.new(CFG.SLIDE_WIDTH, 3, CFG.SLIDE_WIDTH),
			Color3.fromRGB(255, 210, 60),
			Enum.Material.Neon
		)
		ent.CanCollide = false
		ent:SetAttribute("FromSection", sectionIndex)
		ent:SetAttribute("ToSection", sectionIndex + 1)

		-- The chute itself, as attributes, which is the same channel the zipline's
		-- curve crosses on and for the same reason: the pad is on the deck and the
		-- chute starts past the parapet, so the rider has to be put on it, and a
		-- service cannot put anybody anywhere it has to guess. Dir is named the way
		-- SlideBooster names it, being the same vector. Stamped before the tag, so a
		-- binder listening on GetInstanceAddedSignal never sees a bare pad.
		local start, landing = slideRoute(origin, sectionIndex)
		local dir = (landing - start).Unit
		ent:SetAttribute("DirX", dir.X)
		ent:SetAttribute("DirY", dir.Y)
		ent:SetAttribute("DirZ", dir.Z)
		ent:SetAttribute("StartX", start.X)
		ent:SetAttribute("StartY", start.Y)
		ent:SetAttribute("StartZ", start.Z)
		ent:SetAttribute("LandingX", landing.X)
		ent:SetAttribute("LandingY", landing.Y)
		ent:SetAttribute("LandingZ", landing.Z)

		tagWithContext(ent, "SlideEntrance", sectionIndex, ctx.building, CFG.LEVELS)
	end

	return folder
end

-- ============================================================
-- Slide to the next section
-- ============================================================

local function buildSlide(parent, startPos, endPos, section, building)
	local folder = Instance.new("Folder")
	folder.Name = "Slide"
	folder.Parent = parent

	local total = (endPos - startPos).Magnitude
	local segments = math.max(4, math.ceil(total / CFG.SLIDE_SEGMENT_LEN))
	local physical = PhysicalProperties.new(0.7, 0, 0, 1, 1)

	for i = 0, segments - 1 do
		local a = startPos:Lerp(endPos, i / segments)
		local b = startPos:Lerp(endPos, (i + 1) / segments)
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		local cf = CFrame.lookAt(mid, b)

		local seg = makePart(
			folder,
			"SlideSurface",
			cf,
			Vector3.new(CFG.SLIDE_WIDTH, 1.5, len),
			Color3.fromRGB(255, 210, 60),
			Enum.Material.SmoothPlastic
		)
		seg.CustomPhysicalProperties = physical
		tagWithContext(seg, "SlideSurface", section, building, CFG.LEVELS)

		for _, s in ipairs({ -1, 1 }) do
			local rail = makePart(
				folder,
				"SlideRail",
				cf * CFrame.new(s * (CFG.SLIDE_WIDTH / 2 + 0.6), 2.2, 0),
				Vector3.new(1.2, 6, len),
				Color3.fromRGB(60, 60, 70),
				Enum.Material.Metal
			)
			rail.CustomPhysicalProperties = physical
		end

		if i % 3 == 0 then
			local boost = makePart(
				folder,
				"SlideBooster",
				cf * CFrame.new(0, 4, 0),
				Vector3.new(CFG.SLIDE_WIDTH, 6, 4),
				Color3.fromRGB(0, 255, 255),
				Enum.Material.Neon
			)
			boost.Transparency = 1
			boost.CanCollide = false
			boost:SetAttribute("Speed", Config.SlideBoostSpeed)
			boost:SetAttribute("DirX", (b - a).Unit.X)
			boost:SetAttribute("DirY", (b - a).Unit.Y)
			boost:SetAttribute("DirZ", (b - a).Unit.Z)
			tagWithContext(boost, "SlideBooster", section, building, CFG.LEVELS)
		end
	end

	local pad = makePart(
		folder,
		"SlideExit",
		CFrame.new(endPos + Vector3.new(0, -2, 0)),
		Vector3.new(70, 3, 70),
		Color3.fromRGB(255, 210, 60),
		Enum.Material.Neon
	)
	tagWithContext(pad, "SlideExit", section, building, CFG.LEVELS)

	return folder
end

-- ============================================================
-- Zipline from the roof to the plaza
-- ============================================================
-- Topping out was a dead end on the five buildings in six that get no section
-- slide: the only ways down were ten floors of maze in reverse or a 195-stud
-- drop. The cable boards at a corner of the entry facade, wraps the tower the
-- long way round at ZIP_OUTSET, and lands on the street outside the door the
-- player came in by, so the climb ends where it started.
--
-- It was one straight run along the entry facade, which was a way down and
-- nothing else: two and a half seconds in a straight line, facing one way. The
-- shape is now ZipPath's, a lap of the building corkscrewed about itself, and
-- the reason the whole curve lives in that module rather than here is that
-- TraversalService has to put the rider on the same one.
--
-- It draws no random numbers, deliberately. It reads entrySide and entryCell,
-- which the maze has already fixed, so every part that existed before this did
-- keeps the exact position it had and the part-count delta is exactly
-- ZIP_SEGMENTS + 2 per building. Drawing from the threaded rng here would
-- reshuffle every building in the city and retire the M4 baseline for a feature
-- that does not need it.
-- ============================================================
-- Upgrade shop
-- ============================================================
-- One stall per plaza, a pure function of the door position and Config.Shop
-- (invariant 6: no random numbers, so adding it moved nothing that already
-- existed). The stall sits on the opposite side of the door from the zipline's
-- boarding corner, so the plaza reads as: spawn pad at the door, shop one way,
-- zip landing straight out. Generation builds the pedestals, prompts and price
-- boards; SaveService owns what a purchase does, discovered through the
-- ShopItem tag like every other service.

local function buildShop(parent, origin, style, entrySide, entryCell, ctx)
	local folder = Instance.new("Folder")
	folder.Name = "Shop"
	folder.Parent = parent

	local horizontal = (entrySide == "north" or entrySide == "south")
	local span = horizontal and FX or FZ
	local doorCenter = cellCenter(entryCell.x, entryCell.z)
	local doorU = horizontal and doorCenter.X or doorCenter.Z

	-- The zipline boards from whichever facade corner is farther from the door,
	-- so the stall goes toward the nearer one.
	local dir = (doorU > span / 2) and 1 or -1
	local shopU = doorU + dir * CFG.SHOP_OFFSET

	local function at(u, v, y)
		if entrySide == "north" then
			return origin + Vector3.new(u, y, -v)
		elseif entrySide == "south" then
			return origin + Vector3.new(u, y, FZ + v)
		elseif entrySide == "west" then
			return origin + Vector3.new(-v, y, u)
		end
		return origin + Vector3.new(FX + v, y, u)
	end

	local function sized(uLen, h, vLen)
		if horizontal then
			return Vector3.new(uLen, h, vLen)
		end
		return Vector3.new(vLen, h, uLen)
	end

	-- The stall is sized to what it sells rather than to a constant, because the
	-- shop stopped being three pedestals wide when the abilities joined the
	-- passives on it. Pitch is unchanged, so the pedestals sit exactly where they
	-- always did relative to each other and only the counter under them grew;
	-- the floor keeps the old 16 so a short list does not read as a table with
	-- the ends sawn off. It grows along the facade, where the street leaves
	-- STREET studs before the neighbouring plot, and not outward, where
	-- SHOP_OUT is holding it clear of the spawn pad and the zipline landing.
	--
	-- This is geometry from a list length, so it is the one part of buildShop
	-- that moves when Config.Shop.Order or Config.Abilities.Order does. It draws
	-- no random numbers either way (invariant 6): every part here is placed off
	-- the door position the maze already fixed.
	local pedestals = Config.shopOrder()
	local baseWidth = math.max(16, #pedestals * CFG.SHOP_PITCH + 6)

	makePart(
		folder,
		"ShopBase",
		CFrame.new(at(shopU, CFG.SHOP_OUT, 0.25)),
		sized(baseWidth, 0.5, 9),
		style.trim,
		Enum.Material.SmoothPlastic
	)
	for _, side in ipairs({ -1, 1 }) do
		makePart(
			folder,
			"ShopPost",
			CFrame.new(at(shopU + side * (baseWidth / 2 - 1), CFG.SHOP_OUT + 3.5, 4.75)),
			sized(0.8, 8.5, 0.8),
			style.skin,
			style.material
		)
	end
	local canopy = makePart(
		folder,
		"ShopCanopy",
		CFrame.new(at(shopU, CFG.SHOP_OUT, 9.35)),
		sized(baseWidth + 2, 0.7, 11),
		style.trim,
		style.material
	)

	-- Wider than it was by ten pixels, which is the blackletter face setting
	-- wider than the Gotham the old box was measured for; the plate above the
	-- roost took the same ten for the same reason.
	local signSlab = plateGui(canopy, 180, 34, 3, 300, true)
	plateLine(signSlab, UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), PLATE.Display, 18, PLATE.Lantern, "UPGRADE SHOP")

	for i, key in ipairs(pedestals) do
		local def = Config.Shop.Upgrades[key]
		local u = shopU + (i - (#pedestals + 1) / 2) * CFG.SHOP_PITCH

		local pedestal = makePart(
			folder,
			"ShopItem_" .. key,
			CFrame.new(at(u, CFG.SHOP_OUT, 2)),
			sized(2.4, 3, 2.4),
			style.skin,
			Enum.Material.SmoothPlastic
		)

		local orb = makePart(
			folder,
			"ShopOrb_" .. key,
			CFrame.new(at(u, CFG.SHOP_OUT, 4.4)),
			Vector3.new(1.6, 1.6, 1.6),
			def.Color,
			Enum.Material.Neon
		)
		orb.Shape = Enum.PartType.Ball
		orb.CanCollide = false

		-- No seam: a pedestal is a row inside the stall, and the sign over the
		-- counter is what marks the door. The two lines were one string with a
		-- newline in it, which meant the price wore the upgrade's accent; the
		-- name keeps that accent, because it is the orb's colour and semantic,
		-- and the ladder underneath it goes Lantern like every other coin
		-- number in the game.
		local boardSlab = plateGui(pedestal, 140, 42, 4.4, 90, false)
		plateLine(boardSlab, UDim2.new(1, 0, 0.5, 0), UDim2.new(0, 0, 0, 3), PLATE.Body, 13, def.Color, def.Label)
		plateLine(
			boardSlab,
			UDim2.new(1, 0, 0.4, 0),
			UDim2.new(0, 0, 0.52, 0),
			PLATE.Body,
			12,
			PLATE.Lantern,
			table.concat(def.Costs, " / ")
		)

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Buy"
		prompt.ObjectText = def.Label
		prompt.MaxActivationDistance = Config.Shop.PromptDistance
		prompt.HoldDuration = Config.Shop.PromptHoldSeconds
		prompt.RequiresLineOfSight = false
		prompt.Parent = pedestal

		-- The second price on the same pedestal (docs/ROBUX_PLAN.md R4), named so
		-- SaveService can tell the two apart. A pure function of the pedestal that
		-- already exists, no draw (invariant 6), so the delta is countable: one
		-- instance here, five pedestals per building, +30 per section. Its own key
		-- on both input families, because the engine shows one prompt per key at a
		-- time, and lifted above the coin prompt so the two read as a stack.
		-- Enabled is the storefront switch doing its job at the door; the instance
		-- always exists, so the part count never depends on the flag.
		local robuxPrompt = Instance.new("ProximityPrompt")
		robuxPrompt.Name = "RobuxPrompt"
		robuxPrompt.ActionText = "Buy with Robux"
		robuxPrompt.ObjectText = def.Label
		robuxPrompt.KeyboardKeyCode = Enum.KeyCode.R
		robuxPrompt.GamepadKeyCode = Enum.KeyCode.ButtonY
		robuxPrompt.UIOffset = Vector2.new(0, -56)
		robuxPrompt.MaxActivationDistance = Config.Shop.PromptDistance
		robuxPrompt.HoldDuration = Config.Shop.PromptHoldSeconds
		robuxPrompt.RequiresLineOfSight = false
		robuxPrompt.Enabled = Config.Robux.Enabled
		robuxPrompt.Parent = pedestal

		pedestal:SetAttribute("Upgrade", key)
		tagWithContext(pedestal, "ShopItem", ctx.section, ctx.building, 0)
	end

	-- Where the counter actually ended up and how wide it actually is, handed
	-- back rather than recomputed by the street. `baseWidth` is a function of
	-- how many things the shop sells, which CLAUDE.md calls the only place a
	-- config edit changes geometry: a street that reserved a literal 31 studs
	-- would run a wall through the counter the day a fourth ability shipped.
	return folder, shopU, (baseWidth + 2) / 2
end

local function buildZipline(parent, origin, entrySide, entryCell, ctx)
	local folder = Instance.new("Folder")
	folder.Name = "Zipline"
	folder.Parent = parent

	local horizontal = (entrySide == "north" or entrySide == "south")
	local span = horizontal and FX or FZ
	local doorCenter = cellCenter(entryCell.x, entryCell.z)
	local doorU = horizontal and doorCenter.X or doorCenter.Z

	-- u runs along the entry-side facade, v out away from it. Boarding starts at
	-- whichever end of that facade is farther from the door, which is now what
	-- decides the direction of the lap rather than the length of the ride: the
	-- long way round from there to the door is always at least half the wrap.
	local startU = (doorU > span / 2) and CFG.ZIP_END_MARGIN or (span - CFG.ZIP_END_MARGIN)

	local function at(u, v, y)
		if entrySide == "north" then
			return origin + Vector3.new(u, y, -v)
		elseif entrySide == "south" then
			return origin + Vector3.new(u, y, FZ + v)
		elseif entrySide == "west" then
			return origin + Vector3.new(-v, y, u)
		end
		return origin + Vector3.new(FX + v, y, u)
	end

	local box = {
		minX = origin.X,
		maxX = origin.X + FX,
		minZ = origin.Z,
		maxZ = origin.Z + FZ,
		outset = CFG.ZIP_OUTSET,
	}
	local startS = ZipPath.arcLengthOfFacePoint(box, entrySide, startU)
	local endS = ZipPath.arcLengthOfFacePoint(box, entrySide, doorU)
	local dir, length = ZipPath.route(box, startS, endS)

	local path = ZipPath.new({
		minX = box.minX,
		maxX = box.maxX,
		minZ = box.minZ,
		maxZ = box.maxZ,
		outset = box.outset,
		startS = startS,
		dir = dir,
		length = length,
		topY = origin.Y + ROOF_Y + CFG.ZIP_START_LIFT,
		endY = origin.Y + CFG.ZIP_END_Y,
		turns = CFG.ZIP_TWIST_TURNS,
		radius = CFG.ZIP_TWIST_RADIUS,
		rise = CFG.ZIP_TWIST_RISE,
	})

	-- A run of segments now, where the old straight cable was a single part: the
	-- spine wraps the tower and corkscrews about itself, so there is no one line
	-- to draw. The chord between two samples is the part, exactly as buildSlide
	-- does it, and the count is fixed rather than derived from the length so the
	-- part-count delta stays the same on every building in the city.
	--
	-- On an exit building this crosses the section slide, which leaves the same
	-- roof heading east: two lines meeting over a street, both of them scenery
	-- to a rider who is anchored to a tween. Left as a crossing rather than
	-- routed around, because routing around it would make one building in six
	-- ride a different shape.
	local previous = ZipPath.pointAt(path, 0)
	for i = 1, CFG.ZIP_SEGMENTS do
		local point = ZipPath.pointAt(path, i / CFG.ZIP_SEGMENTS)
		local chord = (point - previous).Magnitude
		local cable = makePart(
			folder,
			"ZipCable",
			CFrame.lookAt((previous + point) / 2, point),
			Vector3.new(CFG.ZIP_CABLE_THICKNESS, CFG.ZIP_CABLE_THICKNESS, chord),
			Color3.fromRGB(48, 50, 58),
			Enum.Material.Metal
		)
		cable.CanCollide = false
		previous = point
	end

	local board = makePart(
		folder,
		"ZipEntrance",
		CFrame.new(at(startU, -CFG.ZIP_DECK_INSET, ROOF_Y + 0.6)),
		Vector3.new(CFG.ZIP_PAD, 1.2, CFG.ZIP_PAD),
		Color3.fromRGB(120, 220, 255),
		Enum.Material.Neon
	)
	-- The whole curve, as attributes, because the rider has to be on the same
	-- one the cable was drawn from. The pad has to be inside the parapet to be
	-- stood on and the cable has to be outside it to clear the facade, so the
	-- ride still opens by carrying the rider from here out to point zero.
	ZipPath.stamp(board, path)
	tagWithContext(board, "ZipEntrance", ctx.section, ctx.building, CFG.LEVELS)

	local finish = ZipPath.pointAt(path, 1)
	local landing = makePart(
		folder,
		"ZipExit",
		CFrame.new(Vector3.new(finish.X, origin.Y + 0.6, finish.Z)),
		Vector3.new(CFG.ZIP_PAD + 8, 1.2, CFG.ZIP_PAD + 8),
		Color3.fromRGB(120, 220, 255),
		Enum.Material.Neon
	)
	tagWithContext(landing, "ZipExit", ctx.section, ctx.building, 0)

	-- The curve goes back out with the folder. The street has to reserve the
	-- ground under the last stretch of it, and reading the curve generation
	-- already fixed is the only way to do that without drawing anything
	-- (invariant 6): the alternative is approximating a corkscrewed wrap from
	-- the door position, which is wrong on exactly the doors near a corner.
	return folder, path
end

-- ============================================================
-- Building
-- ============================================================

local function buildBuilding(sectionFolder, origin, sectionIndex, buildingIndex, isExit, seed)
	local rng = Random.new(seed)
	local style = STYLES[((sectionIndex + buildingIndex) % #STYLES) + 1]

	-- A tower is named for what it was before the Maze took it, qualified by the
	-- district it stands in. Style index is ((section + building) % 6) + 1 and
	-- building runs 1..6, so all six themes appear exactly once in every
	-- section: the short name alone is unambiguous to somebody standing in the
	-- district, which is why a signpost arm and the roof sign can use it. The
	-- full name is for the plaza billboard, where it has to be unambiguous
	-- across the whole city.
	local district = Lore.districts[((sectionIndex - 1) % #Lore.districts) + 1]
	local shortName = "The " .. style.theme
	local towerName = shortName .. ", " .. district

	local folder = Instance.new("Folder")
	folder.Name = "Building_" .. buildingIndex
	folder:SetAttribute("Section", sectionIndex)
	folder:SetAttribute("Building", buildingIndex)
	folder:SetAttribute("Style", style.name)
	folder:SetAttribute("TowerName", towerName)
	folder:SetAttribute("TowerShortName", shortName)
	folder:SetAttribute("TowerTheme", style.theme)
	folder:SetAttribute("District", district)
	folder:SetAttribute("IsExit", isExit)
	folder:SetAttribute("EnemyType", style.enemy)
	folder:SetAttribute("CompletionLightColor", style.accent)
	folder:SetAttribute("ExteriorOriginX", origin.X)
	folder:SetAttribute("ExteriorOriginY", origin.Y)
	folder:SetAttribute("ExteriorOriginZ", origin.Z)
	folder:SetAttribute("ExteriorMinX", -CFG.FACADE_OUTSET - CFG.FACADE_THICKNESS)
	folder:SetAttribute("ExteriorMaxX", FX + CFG.FACADE_OUTSET + CFG.FACADE_THICKNESS)
	folder:SetAttribute("ExteriorMinZ", -CFG.FACADE_OUTSET - CFG.FACADE_THICKNESS)
	folder:SetAttribute("ExteriorMaxZ", FZ + CFG.FACADE_OUTSET + CFG.FACADE_THICKNESS)
	folder:SetAttribute("ExteriorBaseY", 0)
	folder:SetAttribute("ExteriorTopY", ROOF_Y + CFG.PARAPET_HEIGHT)
	folder.Parent = sectionFolder

	local ctx = {
		section = sectionIndex,
		building = buildingIndex,
		towerName = towerName,
		shortName = shortName,
		district = district,
		level = 0,
		-- Carried so anything added after the maze baseline can derive its own
		-- random stream instead of drawing from `rng` and moving the city.
		seed = seed,
	}

	local entrySide = SIDE_ORDER[rng:NextInteger(1, 4)]
	local entryCell = edgeCell(entrySide, rng:NextInteger(2, sideRunLength(entrySide) - 1))

	buildFacade(folder, origin, style, entrySide, entryCell, ctx)
	local _, shopCentreU, shopHalfU = buildShop(folder, origin, style, entrySide, entryCell, ctx)

	-- The level loop below reassigns both of these as it spirals up, so the
	-- ground entry has to be kept if anything after the loop wants it. The
	-- zipline does: it lands at the door the player came in by.
	local groundEntrySide, groundEntryCell = entrySide, entryCell

	local pendingHole = nil
	for level = 0, CFG.LEVELS - 1 do
		local levelHole = (level == 0) and nil or pendingHole
		local result = buildLevel(folder, origin, level, entrySide, entryCell, style, rng, ctx)

		local slabTop = level * LEVEL_HEIGHT + ((level == 0) and CFG.GROUND_FLOOR_LIFT or 0)
		buildSlab(result.folder, origin, slabTop, levelHole, style.skin, Enum.Material.Slate, "Floor")

		pendingHole = result.hole
		entrySide = result.exitSide
		entryCell = result.exitCell
	end

	buildRoof(folder, origin, pendingHole, style, isExit, ctx)
	local _, zipPath = buildZipline(folder, origin, groundEntrySide, groundEntryCell, ctx)

	folder:SetAttribute("DoorSide", groundEntrySide)
	local doorPoint = doorWorldPoint(origin, groundEntrySide, groundEntryCell)
	folder:SetAttribute("DoorWorldX", doorPoint.X)
	folder:SetAttribute("DoorWorldZ", doorPoint.Z)

	-- The record is generation talking to itself inside one module, so it is a
	-- return value rather than an attribute: CLAUDE.md's attribute rule governs
	-- the generation-to-runtime line, and no service reads any of this. The
	-- attributes above are for a human with an explorer open during a Play
	-- session, which is the only way to eyeball generated geometry at all.
	return folder,
		style,
		{
			index = buildingIndex,
			name = shortName,
			origin = origin,
			doorSide = groundEntrySide,
			doorCell = groundEntryCell,
			door = doorPoint,
			shopCentreU = shopCentreU,
			shopHalfU = shopHalfU,
			zipPath = zipPath,
		}
end

-- ============================================================
-- Street
-- ============================================================
-- The ground between the towers, which until now was one asphalt slab and
-- nothing else. StreetPlan decides the shape; everything here draws it.
--
-- Three things are worth knowing before changing any of it.
--
-- **It adds no tag, no prompt and no service.** Nothing in this section is read
-- at runtime by anything. A signpost is a painted plate, a house is a box, an
-- overlook is a stair and some glass. The instinct on reading it will be to tag
-- the overlooks; there is nothing that would consume the tag.
--
-- **Nothing here sells anything.** The only counter in the city that trades is
-- the lit one buildShop makes, with its canopy, its neon orbs and its billboard.
-- A shuttered shopfront gets none of the three, and that is the whole of the
-- distinction a player has to read at a glance. docs/LORE.MD Section 10 states
-- it as a rule because it is one.
--
-- **Containment is split three ways** and invariant 7 is why. Street walls go
-- through mazeWallPart into the Wall Walker's group, because phasing across a
-- street strands nobody. The perimeter ring and every part of an overlook are
-- built by their own functions at Default: past the perimeter is 380 studs of
-- void between two section grounds, and past an overlook's glass is the maze
-- seen from above, which is the one thing an overlook must never be a way into.

local function streetWallColor(style)
	return style.skin:Lerp(Color3.fromRGB(150, 150, 156), 0.35)
end

local function buildStreetWalls(parent, origin, plan, style)
	local color = streetWallColor(style)
	for _, w in ipairs(plan.walls) do
		mazeWallPart(
			parent,
			"StreetWall",
			CFrame.new(origin + Vector3.new(w.x, CFG.STREET_WALL_HEIGHT / 2, w.z)),
			Vector3.new(w.sizeX, CFG.STREET_WALL_HEIGHT, w.sizeZ),
			color,
			Enum.Material.Concrete
		)
	end
end

-- Default collision group, deliberately, and its own function so that stays a
-- property of what built it rather than of a flag somebody has to remember.
-- Four parts rather than one per cell edge: it is a boundary, not a maze.
--
-- STREET_EDGE_HEIGHT and not the maze's height, which is the second thing this
-- function's separateness buys: the ring is what the incoming slide crosses, so
-- the ring is what the slide's clearance caps, and the maze inside it is not
-- held to a bound nothing in it stands under.
local function buildStreetPerimeter(parent, origin, plan, style)
	for _, w in ipairs(plan.perimeter) do
		local part = makePart(
			parent,
			"StreetEdge",
			CFrame.new(origin + Vector3.new(w.x, CFG.STREET_EDGE_HEIGHT / 2, w.z)),
			Vector3.new(w.sizeX, CFG.STREET_EDGE_HEIGHT, w.sizeZ),
			style.skin:Lerp(Color3.fromRGB(20, 20, 24), 0.5),
			Enum.Material.Slate
		)
		part.CastShadow = false
	end
end

-- One overlook per tower: a flight up, a deck, and glass on every side. The
-- plan has already made its cell a leaf with exactly one way in, so the seal
-- here is the visible half of a rule the graph already enforces.
--
-- What holds is a box of flat glass panels, not the Ball on top of it. A Ball
-- part has a sphere collision primitive: half-sink a collidable one into a deck
-- and it ejects whoever stands there rather than containing them, which is the
-- opposite of what it is for. So the sphere is scenery and the box is the seal.
--
-- The flight and the hole it comes up through are the tower stairwell's own
-- arrangement, for the same reason it exists there: 26 studs of climb needs
-- more run than one cell has left over beside a deck, so the flight goes under
-- the deck and the hole is sized off headroom.
local function buildOverlook(parent, origin, dome, style)
	local folder = Instance.new("Folder")
	folder.Name = "Overlook_" .. dome.building
	folder.Parent = parent

	local cx = (dome.minX + dome.maxX) / 2
	local cz = (dome.minZ + dome.maxZ) / 2
	local deckY = CFG.STREET_DOME_DECK_Y
	-- Square, off the narrower of the two cell dimensions, so an overlook is the
	-- same object wherever the grid put it rather than one stretched by whichever
	-- strip its cell fell in.
	local span = math.min(dome.maxX - dome.minX, dome.maxZ - dome.minZ) - CFG.STREET_DOME_INSET * 2

	-- `a` runs along the flight, +a at the entrance edge where it starts on the
	-- ground and -a at the far edge where it arrives at deck height. `l` is
	-- across it. The entrance side is the one edge the plan left unsealed, so
	-- the way in from the street and the way up are the same opening.
	local dirX = (dome.entranceSide == "east") and 1 or ((dome.entranceSide == "west") and -1 or 0)
	local dirZ = (dome.entranceSide == "south") and 1 or ((dome.entranceSide == "north") and -1 or 0)
	local function place(a, l)
		if dirX ~= 0 then
			return Vector3.new(cx + dirX * a, 0, cz + l)
		end
		return Vector3.new(cx + l, 0, cz + dirZ * a)
	end
	local function extent(alongLen, acrossLen)
		if dirX ~= 0 then
			return Vector3.new(alongLen, 1, acrossLen)
		end
		return Vector3.new(acrossLen, 1, alongLen)
	end

	local steps = math.ceil(deckY / CFG.STREET_STAIR_RISER)
	local riser = deckY / steps
	local tread = span / steps

	-- Solid blocks from the ground to each step's top, the way buildStairs makes
	-- them, so there is nothing to fall through underneath.
	for i = 0, steps - 1 do
		local h = (i + 1) * riser
		local a = span / 2 - (i + 0.5) * tread
		local at = place(a, 0)
		local size = (dirX ~= 0) and Vector3.new(tread, h, CFG.STREET_STAIR_WIDTH)
			or Vector3.new(CFG.STREET_STAIR_WIDTH, h, tread)
		makePart(
			folder,
			"OverlookStep" .. i,
			CFrame.new(origin + Vector3.new(at.X, h / 2, at.Z)),
			size,
			style.skin,
			Enum.Material.Slate
		)
	end

	-- The deck, and the hole the flight comes up through. Sized off headroom the
	-- same way the tower's stairwell hole is: the flight is covered for exactly
	-- as long as a player can stand up under it, and open from there to the top.
	local holeAlong = math.min(span, span * (1 + CFG.STREET_STAIR_HEADROOM) / deckY)
	local holeWide = CFG.STREET_STAIR_WIDTH + 2 * CFG.STREET_STAIR_HOLE_MARGIN
	local flank = (span - holeWide) / 2

	local function slab(name, aCentre, alongLen, lCentre, acrossLen)
		if alongLen <= 0 or acrossLen <= 0 then
			return
		end
		local at = place(aCentre, lCentre)
		makePart(
			folder,
			name,
			CFrame.new(origin + Vector3.new(at.X, deckY, at.Z)),
			extent(alongLen, acrossLen),
			style.trim,
			Enum.Material.Slate
		)
	end

	slab("OverlookDeck", span / 2 - (span - holeAlong) / 2, span - holeAlong, 0, span)
	slab("OverlookDeckFlank", -span / 2 + holeAlong / 2, holeAlong, -(holeWide + flank) / 2, flank)
	slab("OverlookDeckFlank", -span / 2 + holeAlong / 2, holeAlong, (holeWide + flank) / 2, flank)

	-- Glass on every side and a lid. Default collision group, all of it: this is
	-- the seal on "you may see the way out, you may not take it from up there",
	-- and a Wall Walker phasing through it would be the one way to break that.
	-- Flat panels rather than a Ball, which has a sphere collision primitive and
	-- ejects whoever stands in it instead of containing them.
	local half = span / 2
	local glass = CFG.STREET_DOME_GLASS
	local panels = {
		{ x = cx, z = cz - half, sx = span + glass, sz = glass },
		{ x = cx, z = cz + half, sx = span + glass, sz = glass },
		{ x = cx - half, z = cz, sx = glass, sz = span + glass },
		{ x = cx + half, z = cz, sx = glass, sz = span + glass },
	}
	for _, pane in ipairs(panels) do
		local panel = makePart(
			folder,
			"OverlookGlass",
			CFrame.new(origin + Vector3.new(pane.x, deckY + CFG.STREET_DOME_HEIGHT / 2 + 0.5, pane.z)),
			Vector3.new(pane.sx, CFG.STREET_DOME_HEIGHT, pane.sz),
			style.glass,
			Enum.Material.Glass
		)
		panel.Transparency = 0.6
		panel.Reflectance = 0.15
		panel.CastShadow = false
	end

	local lid = makePart(
		folder,
		"OverlookCap",
		CFrame.new(origin + Vector3.new(cx, deckY + CFG.STREET_DOME_HEIGHT + 0.8, cz)),
		Vector3.new(span + 1.6, 0.6, span + 1.6),
		style.trim,
		Enum.Material.Metal
	)
	lid.CastShadow = false

	-- The dome the thing is named for, and the one part of it that is only a
	-- silhouette: not collidable, so it can never be the surface somebody stands
	-- on or the one a phasing player is stopped by. The glass box below is what
	-- actually holds.
	local cupolaSize = span * 0.45
	local cupola = makePart(
		folder,
		"OverlookDome",
		-- Resting on the lid rather than wrapped around the box. A sphere wide
		-- enough to envelop the glass reaches below the deck it is standing on.
		CFrame.new(origin + Vector3.new(cx, deckY + CFG.STREET_DOME_HEIGHT + 1.1 + cupolaSize / 2, cz)),
		Vector3.new(cupolaSize, cupolaSize, cupolaSize),
		style.glass,
		Enum.Material.Glass
	)
	cupola.Shape = Enum.PartType.Ball
	cupola.CanCollide = false
	cupola.CanQuery = false
	cupola.CanTouch = false
	cupola.Transparency = 0.72
	cupola.Reflectance = 0.2
	cupola.CastShadow = false

	return folder
end

-- Homes and shuttered shopfronts. A block prop fills its cell, which is why the
-- plan draws no wall on a blocked cell's edge: the house is the boundary. No
-- light, no billboard, no prompt, no name.
local function buildBlockProp(parent, origin, prop, style, rng)
	local width = prop.maxX - prop.minX
	local depth = prop.maxZ - prop.minZ
	local cx = (prop.minX + prop.maxX) / 2
	local cz = (prop.minZ + prop.maxZ) / 2
	local height = CFG.STREET_PROP_HEIGHT + prop.variant * 2

	local body = makePart(
		parent,
		"StreetHouse",
		CFrame.new(origin + Vector3.new(cx, height / 2, cz)),
		Vector3.new(width, height, depth),
		style.skin:Lerp(Color3.fromRGB(110, 104, 96), 0.4 + prop.variant * 0.08),
		(prop.variant % 2 == 0) and Enum.Material.Brick or Enum.Material.Concrete
	)
	body.CollisionGroup = "Default"

	-- A roof course and a sealed door, which is the whole of what makes it read
	-- as somewhere people used to live rather than as a block.
	local roof = makePart(
		parent,
		"StreetHouseRoof",
		CFrame.new(origin + Vector3.new(cx, height + 0.9, cz)),
		Vector3.new(width + 2, 1.8, depth + 2),
		style.trim:Lerp(Color3.fromRGB(60, 58, 62), 0.5),
		Enum.Material.Slate
	)
	roof.CastShadow = false

	local side = rng:NextInteger(0, 3)
	local ax = (side == 0 and 1) or (side == 2 and -1) or 0
	local az = (side == 1 and 1) or (side == 3 and -1) or 0
	local door = makePart(
		parent,
		"StreetHouseDoor",
		CFrame.new(origin + Vector3.new(cx + ax * (width / 2 + 0.1), 4.5, cz + az * (depth / 2 + 0.1))),
		(ax ~= 0) and Vector3.new(0.4, 9, 6) or Vector3.new(6, 9, 0.4),
		Color3.fromRGB(52, 42, 34),
		Enum.Material.WoodPlanks
	)
	door.CanCollide = false
	door.CastShadow = false
end

-- Lamp posts, planters and crates. Unlike a house these stand in an open cell,
-- so they narrow a street rather than closing it and nothing has to be
-- re-checked for connectivity.
local function buildTrimProp(parent, origin, prop, style)
	if prop.variant == 1 then
		local post = makePart(
			parent,
			"StreetLampPost",
			CFrame.new(origin + Vector3.new(prop.x, CFG.STREET_TRIM_HEIGHT / 2, prop.z)),
			Vector3.new(0.6, CFG.STREET_TRIM_HEIGHT, 0.6),
			Color3.fromRGB(42, 44, 50),
			Enum.Material.Metal
		)
		post.CastShadow = false
		local head = makePart(
			parent,
			"StreetLamp",
			CFrame.new(origin + Vector3.new(prop.x, CFG.STREET_TRIM_HEIGHT + 0.6, prop.z)),
			Vector3.new(1.8, 1.2, 1.8),
			Color3.fromRGB(255, 226, 170),
			Enum.Material.Neon
		)
		head.CastShadow = false
		local light = Instance.new("PointLight")
		light.Brightness = 0.7
		light.Range = 34
		light.Color = Color3.fromRGB(255, 226, 170)
		-- Off, and not negotiable at this count. Config.World.LampShadows governs
		-- the per-floor lamps, which light one enclosed room each; a street lamp
		-- is in line of sight of most of a district.
		light.Shadows = false
		light.Parent = head
	elseif prop.variant == 2 then
		makePart(
			parent,
			"StreetPlanter",
			CFrame.new(origin + Vector3.new(prop.x, 1.2, prop.z)),
			Vector3.new(5, 2.4, 5),
			style.trim:Lerp(Color3.fromRGB(80, 78, 74), 0.55),
			Enum.Material.Concrete
		)
		local growth = makePart(
			parent,
			"StreetPlanterGrowth",
			CFrame.new(origin + Vector3.new(prop.x, 3, prop.z)),
			Vector3.new(4.2, 1.2, 4.2),
			Color3.fromRGB(74, 104, 62),
			Enum.Material.Grass
		)
		growth.CastShadow = false
	elseif prop.variant == 3 then
		makePart(
			parent,
			"StreetCrates",
			CFrame.new(origin + Vector3.new(prop.x, 1.6, prop.z)) * CFrame.Angles(0, math.rad(prop.rotation), 0),
			Vector3.new(4, 3.2, 3.4),
			Color3.fromRGB(96, 74, 50),
			Enum.Material.WoodPlanks
		)
	else
		local bench = makePart(
			parent,
			"StreetBench",
			CFrame.new(origin + Vector3.new(prop.x, 1.5, prop.z)) * CFrame.Angles(0, math.rad(prop.rotation), 0),
			Vector3.new(6, 0.5, 2),
			Color3.fromRGB(88, 68, 46),
			Enum.Material.WoodPlanks
		)
		bench.CastShadow = false
	end
end

-- A climber put these up, which is the lore and also the reason they are plain:
-- a post and one plate per tower named, each plate turned to face the way it
-- points. The arrow is in the text rather than in geometry, so a plate is one
-- part and one SurfaceGui however many towers a post names.
local SIGN_TURN = { north = 180, south = 0, east = 270, west = 90 }

local function buildSignpost(parent, origin, sign, style)
	local post = makePart(
		parent,
		"Signpost",
		CFrame.new(origin + Vector3.new(sign.x, CFG.STREET_SIGN_HEIGHT / 2, sign.z)),
		Vector3.new(0.7, CFG.STREET_SIGN_HEIGHT, 0.7),
		Color3.fromRGB(58, 46, 34),
		Enum.Material.WoodPlanks
	)
	post.CastShadow = false

	for i, arm in ipairs(sign.arms) do
		local height = CFG.STREET_SIGN_HEIGHT - 1.4 - (i - 1) * 2.6
		local turn = math.rad(SIGN_TURN[arm.side] or 0)
		local plate = makePart(
			parent,
			"SignPlate",
			CFrame.new(origin + Vector3.new(sign.x, height, sign.z)) * CFrame.Angles(0, turn, 0) * CFrame.new(0, 0, -5),
			Vector3.new(11, 2.2, 0.3),
			style.trim:Lerp(Color3.fromRGB(228, 216, 188), 0.6),
			Enum.Material.WoodPlanks
		)
		plate.CastShadow = false

		-- Body, not the Display face the roof board wears: a climber painted
		-- this, and a direction read at a walking pace is legibility work.
		carvedPlate(plate, 440, 88, PLATE.Body, PLATE.Ink, arm.label)
	end
end

-- The apron: the spawn pad, the shop counter and the zipline's landing are all
-- on one face, so they are one reserved room and not three. The inner edge is
-- pinned to the tower's exterior boundary rather than given the margin, because
-- a margin inward is a room that overlaps the tower.
local function apronRect(record)
	local u = faceU(record.doorSide, record.doorCell)
	local padHalf = (CFG.DOOR_WIDTH + 6) / 2
	local zipHalf = (CFG.ZIP_PAD + 8) / 2

	local uMin = math.min(u - padHalf, record.shopCentreU - record.shopHalfU, u - zipHalf) - CFG.STREET_APRON_MARGIN
	local uMax = math.max(u + padHalf, record.shopCentreU + record.shopHalfU, u + zipHalf) + CFG.STREET_APRON_MARGIN
	local vMin = CFG.FACADE_OUTSET + CFG.FACADE_THICKNESS
	local vMax = CFG.ZIP_OUTSET + zipHalf + CFG.STREET_APRON_MARGIN

	local ox, oz = record.origin.X, record.origin.Z
	if record.doorSide == "north" then
		return { minX = ox + uMin, maxX = ox + uMax, minZ = oz - vMax, maxZ = oz - vMin }
	elseif record.doorSide == "south" then
		return { minX = ox + uMin, maxX = ox + uMax, minZ = oz + FZ + vMin, maxZ = oz + FZ + vMax }
	elseif record.doorSide == "west" then
		return { minX = ox - vMax, maxX = ox - vMin, minZ = oz + uMin, maxZ = oz + uMax }
	end
	return { minX = ox + FX + vMin, maxX = ox + FX + vMax, minZ = oz + uMin, maxZ = oz + uMax }
end

-- Every sample of the zip curve that runs below wall height plus clearance. A
-- pure read of a curve generation has already fixed, which is what lets the
-- street reserve the ground under it without drawing anything (invariant 6).
local function zipLowSamples(path)
	local ceiling = CFG.STREET_WALL_HEIGHT + CFG.STREET_ZIP_CLEARANCE
	local points = {}
	for i = 0, CFG.STREET_ZIP_SAMPLES do
		local p = ZipPath.pointAt(path, i / CFG.STREET_ZIP_SAMPLES)
		if p.Y < ceiling then
			points[#points + 1] = { x = p.X, z = p.Z }
		end
	end
	return points
end

local function buildStreet(sectionFolder, sectionOrigin, sectionIndex, records, seed)
	local folder = Instance.new("Folder")
	folder.Name = "Street"
	folder:SetAttribute("Section", sectionIndex)
	folder.Parent = sectionFolder

	local groundW = CFG.PLOT_COLS * PLOT_SPAN_X + 240
	local groundD = CFG.PLOT_ROWS * PLOT_SPAN_Z + 240

	local plots, buildings = {}, {}
	for _, record in ipairs(records) do
		local ox, oz = record.origin.X - sectionOrigin.X, record.origin.Z - sectionOrigin.Z
		local box = {
			minX = ox - CFG.FACADE_OUTSET - CFG.FACADE_THICKNESS,
			maxX = ox + FX + CFG.FACADE_OUTSET + CFG.FACADE_THICKNESS,
			minZ = oz - CFG.FACADE_OUTSET - CFG.FACADE_THICKNESS,
			maxZ = oz + FZ + CFG.FACADE_OUTSET + CFG.FACADE_THICKNESS,
		}
		plots[#plots + 1] = box

		local apron = apronRect(record)
		local cable = {}
		for _, p in ipairs(zipLowSamples(record.zipPath)) do
			cable[#cable + 1] = { x = p.x - sectionOrigin.X, z = p.z - sectionOrigin.Z }
		end

		buildings[#buildings + 1] = {
			index = record.index,
			name = record.name,
			plot = box,
			door = { x = record.door.X - sectionOrigin.X, z = record.door.Z - sectionOrigin.Z },
			apron = {
				minX = apron.minX - sectionOrigin.X,
				maxX = apron.maxX - sectionOrigin.X,
				minZ = apron.minZ - sectionOrigin.Z,
				maxZ = apron.maxZ - sectionOrigin.Z,
			},
			lowCable = cable,
		}
	end

	-- The street's own stream, and the reason every tower stayed where it was.
	-- See CFG.STREET_SEED_OFFSET for why it cannot collide with any other.
	local rng = Random.new(seed + sectionIndex * 7919 + CFG.STREET_SEED_OFFSET)

	local plan = StreetPlan.build({
		rng = rng,
		cellTarget = CFG.STREET_CELL_TARGET,
		wallThickness = CFG.STREET_WALL_THICKNESS,
		cableMargin = CFG.STREET_CABLE_MARGIN,
		braid = CFG.STREET_BRAID,
		plots = plots,
		buildings = buildings,
		groundMinX = -120,
		groundMaxX = groundW - 120,
		groundMinZ = -120,
		groundMaxZ = groundD - 120,
		-- Derived from the same constants buildSection targets the slide with,
		-- which is the pure-maths channel invariant 4 already sanctions for the
		-- one thing a section knows about its neighbour.
		slideLanding = {
			minX = -120,
			maxX = CFG.SLIDE_LANDING_X + CFG.STREET_LANDING_MARGIN,
			minZ = PLOT_SPAN_Z * 0.5 - CFG.STREET_LANDING_MARGIN,
			maxZ = PLOT_SPAN_Z * 0.5 + CFG.STREET_LANDING_MARGIN,
		},
		blockProps = CFG.STREET_BLOCK_PROPS,
		trimProps = CFG.STREET_TRIM_PROPS,
		signposts = CFG.STREET_SIGNPOSTS,
		signArms = CFG.STREET_SIGN_ARMS,
	})

	-- The style the district reads as, taken from the first plot so a section
	-- is one place rather than six palettes meeting in the middle of a street.
	local style = STYLES[((sectionIndex + 1) % #STYLES) + 1]

	buildStreetWalls(folder, sectionOrigin, plan, style)
	buildStreetPerimeter(folder, sectionOrigin, plan, style)

	for _, dome in ipairs(plan.domes) do
		buildOverlook(folder, sectionOrigin, dome, STYLES[((sectionIndex + dome.building) % #STYLES) + 1])
	end

	for _, prop in ipairs(plan.props) do
		if prop.kind == "block" then
			buildBlockProp(folder, sectionOrigin, prop, style, rng)
		else
			buildTrimProp(folder, sectionOrigin, prop, style)
		end
	end

	for _, sign in ipairs(plan.signs) do
		buildSignpost(folder, sectionOrigin, sign, style)
	end

	-- Stamped so a Studio check is a read rather than a #GetDescendants(), and
	-- so the one count that is not a function of the settings (the walls, which
	-- move with where the six doors landed) is written down somewhere.
	folder:SetAttribute("StreetWallCount", plan.counts.walls)
	folder:SetAttribute("StreetPropCount", plan.counts.blockProps + plan.counts.trimProps)
	folder:SetAttribute("StreetSignCount", plan.counts.signs)
	folder:SetAttribute("StreetOverlookCount", plan.counts.domes)

	return folder
end

-- ============================================================
-- Public API
-- ============================================================

function MazeGenerator.sectionOrigin(sectionIndex)
	return Vector3.new((sectionIndex - 1) * SECTION_SPAN, 0, 0)
end

function MazeGenerator.buildSection(root, sectionIndex, seed)
	refreshFromConfig()

	local rng = Random.new(seed + sectionIndex * 7919)
	local sectionOrigin = MazeGenerator.sectionOrigin(sectionIndex)

	local folder = Instance.new("Folder")
	folder.Name = "Section_" .. sectionIndex
	folder:SetAttribute("SectionIndex", sectionIndex)
	folder.Parent = root

	local groundW = CFG.PLOT_COLS * PLOT_SPAN_X + 240
	local groundD = CFG.PLOT_ROWS * PLOT_SPAN_Z + 240

	local ground = makePart(
		folder,
		"Ground",
		CFrame.new(sectionOrigin + Vector3.new(groundW / 2 - 120, -2, groundD / 2 - 120)),
		Vector3.new(groundW, 4, groundD),
		Color3.fromRGB(72, 74, 78),
		Enum.Material.Asphalt
	)
	ground:SetAttribute("Section", sectionIndex)

	-- Exit plots come from the last column only. A slide leaves the roof heading
	-- east at Y ~185 and the facades it crosses stand 206 studs tall, so a slide
	-- starting anywhere but the last column passes through one or two buildings
	-- on its way out of the section.
	local exitCount = (sectionIndex % 3 == 0) and 2 or 1
	local exitPlots = {}
	local pool = {}
	for row = 0, CFG.PLOT_ROWS - 1 do
		table.insert(pool, row * CFG.PLOT_COLS + CFG.PLOT_COLS)
	end
	exitCount = math.min(exitCount, #pool)
	for _ = 1, exitCount do
		local i = rng:NextInteger(1, #pool)
		exitPlots[pool[i]] = true
		table.remove(pool, i)
	end

	local records = {}
	for row = 0, CFG.PLOT_ROWS - 1 do
		for col = 0, CFG.PLOT_COLS - 1 do
			local index = row * CFG.PLOT_COLS + col + 1
			local origin = sectionOrigin + Vector3.new(col * PLOT_SPAN_X, 0, row * PLOT_SPAN_Z)
			local isExit = exitPlots[index] == true
			-- Section index is in the building seed, not just the plot index, or
			-- plot 4 of every section is the same building down to the wall. Both
			-- multipliers are prime and far apart, so no (section, plot) pair
			-- collides with another within any city anyone will build. Still a
			-- pure function of (Seed, section, plot), which is what lets a lazily
			-- built section come out identical to a pregenerated one.
			local buildingSeed = seed + sectionIndex * 7919 + index * 104729
			local buildingFolder, _, record = buildBuilding(folder, origin, sectionIndex, index, isExit, buildingSeed)
			records[#records + 1] = record

			if isExit then
				local start, landing = slideRoute(origin, sectionIndex)
				local slide = buildSlide(folder, start, landing, sectionIndex, index)
				slide.Name = "Slide_To_Section_" .. (sectionIndex + 1)
				slide:SetAttribute("FromSection", sectionIndex)
				slide:SetAttribute("ToSection", sectionIndex + 1)
				buildingFolder:SetAttribute("HasSlide", true)
			end

			task.wait()
		end
	end

	-- After the plot loop, and from its own stream. Both halves matter: the
	-- street reads where the six doors, counters and cables ended up, and it
	-- draws none of its randomness from `rng` or from any building's, so every
	-- part that existed before the street did keeps the exact position it had
	-- and the per-section delta is one countable number. Setting
	-- Config.World.StreetMazeEnabled to false restores the old count exactly,
	-- which is the sharpest check available that no draw leaked (invariant 6).
	if CFG.STREET_ENABLED then
		buildStreet(folder, sectionOrigin, sectionIndex, records, seed)
		task.wait()
	end

	return folder
end

return MazeGenerator
