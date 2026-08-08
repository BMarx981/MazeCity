-- MazeGenerator (ModuleScript) -> ServerScriptService.MazeGenerator
-- All world generation. Runs on the server at startup, driven by
-- WorldBootstrap. Deterministic: same seed and settings produce an
-- identical world. Never call math.random in this file.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))

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
	-- DwellOpen, tween shut. Only the closed half is time the player can be
	-- stuck, and arriving just as one shuts costs the full dwell plus a tween
	-- before the gap is passable again. That sum, not either range on its own,
	-- is the number to tune: it was 25s and is now 10. The open range stays
	-- long enough that arriving at an open wall usually means walking through.
	MOVING_WALL_TWEEN = { 3, 5 },
	MOVING_WALL_DWELL_CLOSED = { 2.5, 5 },
	MOVING_WALL_DWELL_OPEN = { 7, 14 },
	-- Spread over the cycle so neighbouring walls are not in lockstep.
	MOVING_WALL_PHASE_MAX = 12,

	ENEMY_SPAWNS_PER_LEVEL = 3,

	COIN_DEAD_END_PER_LEVEL = 10,
	COIN_PATH_PER_LEVEL = 3,
	POWERUP_EVERY_N_LEVELS = 3,
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

	PLOT_COLS = 3,
	PLOT_ROWS = 2,
	STREET = 90,
	SECTION_GAP = 620,

	-- Zipline off the roof. OUTSET is measured from the maze footprint edge, so
	-- it has to clear the facade face at FACADE_OUTSET + FACADE_THICKNESS = 8 and
	-- the plaza, which reaches 36, without running into the neighbouring plot's
	-- facade at STREET + 8 = 98. Fifty puts it a little past the middle of the
	-- street with room for the landing pad either side.
	ZIP_OUTSET = 50,
	ZIP_DECK_INSET = 8, -- how far inside the parapet the boarding pad sits
	ZIP_END_MARGIN = 14, -- how far in from the facade corner the cable starts
	ZIP_START_LIFT = 6, -- cable height above the roof slab
	ZIP_END_Y = 4, -- cable height where it meets the street
	ZIP_CABLE_THICKNESS = 0.6,
	ZIP_PAD = 12,

	-- Upgrade shop stall on the plaza. OFFSET runs along the facade from the
	-- door centre, putting the stall beside the spawn pad (which reaches 11
	-- either side of the door) without crowding it; OUT is measured from the
	-- maze footprint edge like ZIP_OUTSET, and 20 keeps the stall inside the
	-- plaza band (the facade face is at 8, the spawn pad ends at 36) and well
	-- clear of the zipline landing at 50.
	SHOP_OFFSET = 26,
	SHOP_OUT = 20,

	-- The egg roost, one per roof deck. Placed by pure geometry off the footprint
	-- so it draws no random numbers (invariant 6) and cost a countable +5
	-- instances per building rather than reshuffling the city. The middle of the
	-- deck is the one part of it nothing else uses: the bounce pads sit at
	-- Z = FZ * 0.3, the planters at 0.75, the sign at 0.92, and the stair hole is
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
	-- Where the slide ends, relative to the next section's origin. X was -140,
	-- which put the 70-stud pad's far half over open void: the next section's
	-- Ground starts at -120. Y was 22, so the pad also floated two storeys up and
	-- needed a ramp down to the street. -80 lands the whole pad on the ground
	-- slab, west of the first plot's facade, and 2 makes it a step rather than a
	-- drop, which is why there is no LandingRamp any more.
	SLIDE_LANDING_X = -80,
	SLIDE_LANDING_Y = 2,
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
	CFG.PHANTOM_PER_LEVEL = w.PhantomWallsPerLevel or CFG.PHANTOM_PER_LEVEL
	CFG.PHANTOM_MAX_SHORTCUT = w.PhantomMaxShortcut or CFG.PHANTOM_MAX_SHORTCUT
	CFG.PHANTOM_TRANSPARENCY = setting(w.PhantomTransparency, CFG.PHANTOM_TRANSPARENCY)
	CFG.COIN_DEAD_END_PER_LEVEL = setting(w.DeadEndCoinsPerLevel, CFG.COIN_DEAD_END_PER_LEVEL)
	CFG.COIN_PATH_PER_LEVEL = setting(w.PathCoinsPerLevel, CFG.COIN_PATH_PER_LEVEL)
	CFG.POWERUP_EVERY_N_LEVELS = setting(w.PowerupEveryNLevels, CFG.POWERUP_EVERY_N_LEVELS)
	CFG.ROOF_ARC_COINS = setting(w.RoofArcCoins, CFG.ROOF_ARC_COINS)
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
		enemy = "Charger",
	},
}

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

local function cellCenter(x, z)
	return Vector3.new((x - 0.5) * CFG.CELL, 0, (z - 0.5) * CFG.CELL)
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
-- per level, and a powerup on fixed levels. Only where they land is random.

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

	-- A powerup goes in whatever dead end is left over, so the loudest thing on
	-- the floor is also the thing furthest from the route. Only if the level has
	-- run out of them does it fall back to open maze.
	if CFG.POWERUP_EVERY_N_LEVELS > 0 and (ctx.level + 1) % CFG.POWERUP_EVERY_N_LEVELS == 0 then
		-- No kind is drawn here any more. PickupService rolls one when the orb is
		-- touched, so what an orb is worth is not a property of the city, and the
		-- same orb is a different prize to the next player to reach it.
		local pool = deadEnds
		if #pool == 0 then
			pool = anywhere()
		end

		local c = draw(pool)
		if c then
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

			-- Three of these per tower against nine hundred and sixty lamps, so
			-- the light is affordable and it is the only thing that makes an orb
			-- findable from the far end of a corridor.
			local glow = Instance.new("PointLight")
			glow.Brightness = 3
			glow.Range = 26
			glow.Color = orbColor
			glow.Shadows = false
			glow.Parent = orb
		end
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
		local w = makePart(parent, "Window", CFrame.new(origin + pos), size, style.glass, Enum.Material.Glass)
		w.Reflectance = 0.28
		w.CanCollide = false
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

local function buildCrown(parent, origin, style)
	local topY = ROOF_Y + CFG.PARAPET_HEIGHT
	local cx, cz = FX / 2, FZ / 2

	if style.crown == "setback" then
		makePart(
			parent,
			"Penthouse",
			CFrame.new(origin + Vector3.new(cx, topY + 14, cz)),
			Vector3.new(FX * 0.45, 28, FZ * 0.45),
			style.skin,
			style.material
		)
		makePart(
			parent,
			"PenthouseCap",
			CFrame.new(origin + Vector3.new(cx, topY + 29, cz)),
			Vector3.new(FX * 0.5, 2, FZ * 0.5),
			style.trim,
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
				Vector3.new(FX * 0.22 * f, h, FZ * 0.22 * f),
				style.skin,
				style.material
			)
		end
		local mast = makePart(
			parent,
			"Mast",
			CFrame.new(origin + Vector3.new(cx, topY + 5 * h + 16, cz)),
			Vector3.new(2, 32, 2),
			style.trim,
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
				style.trim,
				Enum.Material.Metal
			)
		end
		local tank = makePart(
			parent,
			"Tank",
			CFrame.new(origin + Vector3.new(cx, topY + 36, cz)),
			Vector3.new(34, 34, 34),
			style.skin,
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
			makePart(folder, "Facade_" .. side, CFrame.new(origin + f.pos), f.size, style.skin, style.material)
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
				makePart(folder, name, CFrame.new(origin + pos), size, style.skin, style.material)
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

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 190, 0, 42)
	bb.StudsOffset = Vector3.new(0, 6, 0)
	bb.MaxDistance = 400
	bb.Parent = spawn

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.Text = towerName
	label.Parent = bb

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

	local board = Instance.new("BillboardGui")
	board.Size = UDim2.new(0, 150, 0, 34)
	board.StudsOffset = Vector3.new(0, 5.2, 0)
	board.MaxDistance = 120
	board.Parent = pedestal

	local boardLabel = Instance.new("TextLabel")
	boardLabel.Size = UDim2.new(1, 0, 1, 0)
	boardLabel.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
	boardLabel.BackgroundTransparency = 0.35
	boardLabel.TextColor3 = Color3.fromRGB(215, 235, 255)
	boardLabel.Font = Enum.Font.GothamBold
	boardLabel.TextSize = 15
	boardLabel.Text = "EGG ROOST"
	boardLabel.Parent = board

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

local function buildRoof(parent, origin, hole, style, isExit, ctx)
	local folder = Instance.new("Folder")
	folder.Name = "Roof"
	folder.Parent = parent

	local towerName = ctx.towerName
	local sectionIndex = ctx.section

	buildSlab(folder, origin, ROOF_Y, hole, style.skin, style.material, "RoofSlab")

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
		makePart(folder, "Parapet" .. i, CFrame.new(origin + r.pos), r.size, style.trim, Enum.Material.Concrete)
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

	for i = 1, 3 do
		local padCenter = Vector3.new(FX * (0.25 * i), ROOF_Y + 0.6, FZ * 0.3)
		local pad = makePart(
			deck,
			"BouncePad",
			CFrame.new(origin + padCenter),
			Vector3.new(12, 1.2, 12),
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

	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(600, 120)
	sg.Parent = sign
	local st = Instance.new("TextLabel")
	st.Size = UDim2.new(1, 0, 1, 0)
	st.BackgroundTransparency = 1
	st.Font = Enum.Font.GothamBlack
	st.TextScaled = true
	st.TextColor3 = Color3.fromRGB(20, 20, 24)
	st.Text = towerName
	st.Parent = sg

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
-- drop. The cable runs along the entry-side facade at ZIP_OUTSET and lands on
-- the street outside the door the player came in by, so the climb ends where it
-- started.
--
-- It draws no random numbers, deliberately. It reads entrySide and entryCell,
-- which the maze has already fixed, so every part that existed before this did
-- keeps the exact position it had and the part-count delta is exactly three per
-- building. Drawing from the threaded rng here would reshuffle every building
-- in the city and retire the M4 baseline for a feature that does not need it.
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

	makePart(
		folder,
		"ShopBase",
		CFrame.new(at(shopU, CFG.SHOP_OUT, 0.25)),
		sized(16, 0.5, 9),
		style.trim,
		Enum.Material.SmoothPlastic
	)
	for _, side in ipairs({ -1, 1 }) do
		makePart(
			folder,
			"ShopPost",
			CFrame.new(at(shopU + side * 7, CFG.SHOP_OUT + 3.5, 4.75)),
			sized(0.8, 8.5, 0.8),
			style.skin,
			style.material
		)
	end
	local canopy = makePart(
		folder,
		"ShopCanopy",
		CFrame.new(at(shopU, CFG.SHOP_OUT, 9.35)),
		sized(18, 0.7, 11),
		style.trim,
		style.material
	)

	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.new(0, 170, 0, 34)
	sign.StudsOffset = Vector3.new(0, 3, 0)
	sign.MaxDistance = 300
	sign.Parent = canopy

	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.new(1, 0, 1, 0)
	signLabel.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
	signLabel.BackgroundTransparency = 0.25
	signLabel.TextColor3 = Color3.fromRGB(255, 224, 130)
	signLabel.Font = Enum.Font.GothamBold
	signLabel.TextSize = 18
	signLabel.Text = "UPGRADE SHOP"
	signLabel.Parent = sign

	for i, key in ipairs(Config.Shop.Order) do
		local def = Config.Shop.Upgrades[key]
		local u = shopU + (i - (#Config.Shop.Order + 1) / 2) * 5

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

		local board = Instance.new("BillboardGui")
		board.Size = UDim2.new(0, 130, 0, 40)
		board.StudsOffset = Vector3.new(0, 4.4, 0)
		board.MaxDistance = 90
		board.Parent = pedestal

		local boardLabel = Instance.new("TextLabel")
		boardLabel.Size = UDim2.new(1, 0, 1, 0)
		boardLabel.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
		boardLabel.BackgroundTransparency = 0.35
		boardLabel.TextColor3 = def.Color
		boardLabel.Font = Enum.Font.GothamBold
		boardLabel.TextSize = 13
		boardLabel.Text = def.Label .. "\n" .. table.concat(def.Costs, " / ")
		boardLabel.Parent = board

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Buy"
		prompt.ObjectText = def.Label
		prompt.MaxActivationDistance = Config.Shop.PromptDistance
		prompt.HoldDuration = Config.Shop.PromptHoldSeconds
		prompt.RequiresLineOfSight = false
		prompt.Parent = pedestal

		pedestal:SetAttribute("Upgrade", key)
		tagWithContext(pedestal, "ShopItem", ctx.section, ctx.building, 0)
	end

	return folder
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
	-- whichever end of that facade is farther from the door, so the run is never
	-- short enough for the cable to read as a fire pole: the shortest it can get
	-- is 111 studs of travel against 197 of drop.
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

	local padPos = at(startU, -CFG.ZIP_DECK_INSET, ROOF_Y + 0.6)
	local cableStart = at(startU, CFG.ZIP_OUTSET, ROOF_Y + CFG.ZIP_START_LIFT)
	local cableEnd = at(doorU, CFG.ZIP_OUTSET, CFG.ZIP_END_Y)

	-- One part, not a run of segments like the slide: a cable is a straight line
	-- and has no boosters to hang along it.
	local cable = makePart(
		folder,
		"ZipCable",
		CFrame.lookAt((cableStart + cableEnd) / 2, cableEnd),
		Vector3.new(CFG.ZIP_CABLE_THICKNESS, CFG.ZIP_CABLE_THICKNESS, (cableEnd - cableStart).Magnitude),
		Color3.fromRGB(48, 50, 58),
		Enum.Material.Metal
	)
	cable.CanCollide = false

	local board = makePart(
		folder,
		"ZipEntrance",
		CFrame.new(padPos),
		Vector3.new(CFG.ZIP_PAD, 1.2, CFG.ZIP_PAD),
		Color3.fromRGB(120, 220, 255),
		Enum.Material.Neon
	)
	-- The rider is carried to the cable before the descent starts, because the
	-- pad has to be inside the parapet to be stood on and the cable has to be
	-- outside it to clear the facade. TraversalService reads both points.
	board:SetAttribute("StartX", cableStart.X)
	board:SetAttribute("StartY", cableStart.Y)
	board:SetAttribute("StartZ", cableStart.Z)
	board:SetAttribute("EndX", cableEnd.X)
	board:SetAttribute("EndY", cableEnd.Y)
	board:SetAttribute("EndZ", cableEnd.Z)
	tagWithContext(board, "ZipEntrance", ctx.section, ctx.building, CFG.LEVELS)

	local landing = makePart(
		folder,
		"ZipExit",
		CFrame.new(cableEnd - Vector3.new(0, CFG.ZIP_END_Y - 0.6, 0)),
		Vector3.new(CFG.ZIP_PAD + 8, 1.2, CFG.ZIP_PAD + 8),
		Color3.fromRGB(120, 220, 255),
		Enum.Material.Neon
	)
	tagWithContext(landing, "ZipExit", ctx.section, ctx.building, 0)

	return folder
end

-- ============================================================
-- Building
-- ============================================================

local function buildBuilding(sectionFolder, origin, sectionIndex, buildingIndex, isExit, seed)
	local rng = Random.new(seed)
	local style = STYLES[((sectionIndex + buildingIndex) % #STYLES) + 1]
	local towerName = string.format("S%d-%s%d", sectionIndex, style.name:sub(1, 1), buildingIndex)

	local folder = Instance.new("Folder")
	folder.Name = "Building_" .. buildingIndex
	folder:SetAttribute("Section", sectionIndex)
	folder:SetAttribute("Building", buildingIndex)
	folder:SetAttribute("Style", style.name)
	folder:SetAttribute("TowerName", towerName)
	folder:SetAttribute("IsExit", isExit)
	folder:SetAttribute("EnemyType", style.enemy)
	folder.Parent = sectionFolder

	local ctx = {
		section = sectionIndex,
		building = buildingIndex,
		towerName = towerName,
		level = 0,
		-- Carried so anything added after the maze baseline can derive its own
		-- random stream instead of drawing from `rng` and moving the city.
		seed = seed,
	}

	local entrySide = SIDE_ORDER[rng:NextInteger(1, 4)]
	local entryCell = edgeCell(entrySide, rng:NextInteger(2, sideRunLength(entrySide) - 1))

	buildFacade(folder, origin, style, entrySide, entryCell, ctx)
	buildShop(folder, origin, style, entrySide, entryCell, ctx)

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
	buildZipline(folder, origin, groundEntrySide, groundEntryCell, ctx)
	return folder, style
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
			local buildingFolder = buildBuilding(folder, origin, sectionIndex, index, isExit, buildingSeed)

			if isExit then
				local start = origin + Vector3.new(FX + CFG.FACADE_OUTSET, ROOF_Y + 2, FZ / 2)
				local nextOrigin = MazeGenerator.sectionOrigin(sectionIndex + 1)
				local landing = nextOrigin + Vector3.new(CFG.SLIDE_LANDING_X, CFG.SLIDE_LANDING_Y, PLOT_SPAN_Z * 0.5)
				local slide = buildSlide(folder, start, landing, sectionIndex, index)
				slide.Name = "Slide_To_Section_" .. (sectionIndex + 1)
				slide:SetAttribute("FromSection", sectionIndex)
				slide:SetAttribute("ToSection", sectionIndex + 1)
				buildingFolder:SetAttribute("HasSlide", true)
			end

			task.wait()
		end
	end

	return folder
end

return MazeGenerator
