-- MazeGenerator (ModuleScript) -> ServerScriptService.MazeGenerator
-- All world generation. Runs on the server at startup, driven by
-- WorldBootstrap. Deterministic: same seed and settings produce an
-- identical world. Never call math.random in this file.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))

local MazeGenerator = {}

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

	PHANTOM_PER_LEVEL = 4,
	LAMP_GRID = 3,
	LAMP_BRIGHTNESS = 2.6,
	-- Lamps sit on a LAMP_GRID square grid, so spacing is FX/(LAMP_GRID+1) = 62.5
	-- studs. Range must exceed that or the coverage circles leave dark bands
	-- between them. 2.6 * CELL = 65.
	LAMP_RANGE_MULT = 2.6,

	MOVING_WALL_MIN_LEVEL = 4,
	MOVING_WALL_BASE = 2,

	ENEMY_SPAWNS_PER_LEVEL = 3,

	PLOT_COLS = 3,
	PLOT_ROWS = 2,
	STREET = 90,
	SECTION_GAP = 620,

	STAIR_RISER = 0.75,
	STAIR_WIDTH_FRAC = 0.84,
	STAIR_RUN_CELLS = 1.9,

	-- Level 0's slab would otherwise top out at Y = 0, exactly level with the
	-- street Ground part, so the lobby floor read as more asphalt. Lifting it
	-- makes the threshold a visible step in. Kept under 2 so a character walks
	-- up it without jumping.
	GROUND_FLOOR_LIFT = 1.5,

	SLIDE_WIDTH = 14,
	SLIDE_SEGMENT_LEN = 40,
	SLIDE_LANDING_Y = 22,
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

local function refreshFromConfig()
	local w = Config.World or {}
	CFG.LEVELS = w.Levels or CFG.LEVELS
	CFG.LAMP_BRIGHTNESS = w.LampBrightness or CFG.LAMP_BRIGHTNESS
	CFG.MOVING_WALL_MIN_LEVEL = w.MovingWallMinLevel or CFG.MOVING_WALL_MIN_LEVEL
	CFG.PHANTOM_PER_LEVEL = w.PhantomWallsPerLevel or CFG.PHANTOM_PER_LEVEL
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

local function buildWalls(parent, origin, baseY, g, style)
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

	local function place(x, z, side, pos, size, boundary)
		if boundary then
			pos, size = fillApron(x, z, side, pos, size)
		end
		local p = makePart(
			parent,
			string.format("Wall_%d_%d_%s", x, z, side),
			CFrame.new(origin + Vector3.new(pos.X, wallY, pos.Z)),
			size,
			style.wall,
			style.material
		)
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

local function tagPhantoms(interior, blocked, count, rng, ctx)
	local pool = {}
	for _, w in ipairs(interior) do
		if not blocked[w.x .. "_" .. w.z] then
			table.insert(pool, w)
		end
	end

	local picked = {}
	for _ = 1, math.min(count, #pool) do
		local i = rng:NextInteger(1, #pool)
		local w = pool[i]
		table.remove(pool, i)
		-- A phantom is a shortcut the player is meant to spot and choose. At the
		-- old 0.12 it was 88% opaque and read as solid, so it got walked into
		-- rather than through. Phantoms are never required: the carved maze is a
		-- spanning tree, and making a wall passable only ever adds a connection.
		w.part.CanCollide = false
		w.part.Transparency = 0.62
		w.part.Material = Enum.Material.ForceField
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
		p:SetAttribute("TweenTime", rng:NextNumber(4.5, 7.5))
		p:SetAttribute("DwellOpen", rng:NextNumber(6, 14))
		p:SetAttribute("DwellClosed", rng:NextNumber(8, 18))
		p:SetAttribute("Phase", rng:NextNumber(0, 12))
		tagWithContext(p, "MovingWall", ctx.section, ctx.building, level)
		used[p] = true
	end
end

local function buildStairs(parent, origin, baseY, exitSide, cellB, cellE, style)
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

	local cE = cellCenter(cellE.x, cellE.z)
	local holeAlong = CFG.CELL * 0.9
	return {
		x = cE.X,
		z = cE.Z,
		sx = along and holeAlong or width,
		sz = along and width or holeAlong,
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
			-- Shadows stay off so walls cannot occlude their own lighting into
			-- black corridors, and so the per-floor light budget stays cheap.
			local lamp = Instance.new("PointLight")
			lamp.Brightness = CFG.LAMP_BRIGHTNESS
			lamp.Range = CFG.CELL * CFG.LAMP_RANGE_MULT
			lamp.Color = Color3.fromRGB(255, 240, 208)
			lamp.Shadows = false
			lamp.Parent = base
		end
	end
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

local function buildLevelTrigger(parent, origin, baseY, entryCell, ctx)
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
	tagWithContext(trigger, "LevelTrigger", ctx.section, ctx.building, ctx.level)
end

-- ============================================================
-- One level
-- ============================================================

local function buildLevel(buildingFolder, origin, level, entrySide, entryCell, style, rng, ctx)
	local baseY = level * LEVEL_HEIGHT
	ctx.level = level

	local exitSide = rotateSide(entrySide, rng:NextNumber() < 0.5 and 1 or -1)
	local span = sideRunLength(exitSide)
	local exitIndex = rng:NextInteger(2, span - 1)
	local cellE = edgeCell(exitSide, exitIndex)
	local cellB = neighborCell(cellE, OPPOSITE[exitSide])

	local g = newGrid({ cellE, cellB })
	carve(g, entryCell, rng)

	sealCell(g, cellE)
	sealCell(g, cellB)
	openBetween(g, cellB, exitSide)
	openBetween(g, cellB, OPPOSITE[exitSide])

	if level == 0 then
		g[entryCell.x][entryCell.z].walls[entrySide] = false
	end

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

	local interior = buildWalls(folder, origin, baseY, g, style)
	local used = tagPhantoms(interior, blocked, CFG.PHANTOM_PER_LEVEL, rng, ctx)
	tagMovingWalls(interior, blocked, used, level, rng, ctx)

	local hole = buildStairs(folder, origin, baseY, exitSide, cellB, cellE, style)
	buildLamps(folder, origin, baseY)

	buildEnemySpawns(folder, origin, baseY, g, blocked, entryCell, style, rng, ctx)
	buildLevelTrigger(folder, origin, baseY, entryCell, ctx)

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

local function buildWindows(parent, origin, style, side)
	local O = CFG.FACADE_OUTSET + CFG.FACADE_THICKNESS
	local horizontal = (side == "north" or side == "south")
	local faceLen = horizontal and FX or FZ

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

		buildWindows(folder, origin, style, side)
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
	-- hole: the top step stops 1.25 studs short of the hole's far edge, so
	-- arrival is a small hop and a cell-sized trigger is missable. It reaches
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
	tagWithContext(arrival, "RoofTrigger", sectionIndex, ctx.building, CFG.LEVELS)

	local deck = Instance.new("Folder")
	deck.Name = "Deck"
	deck.Parent = folder

	for i = 1, 3 do
		local pad = makePart(
			deck,
			"BouncePad",
			CFrame.new(origin + Vector3.new(FX * (0.25 * i), ROOF_Y + 0.6, FZ * 0.3)),
			Vector3.new(12, 1.2, 12),
			Color3.fromRGB(255, 120, 200),
			Enum.Material.Neon
		)
		pad:SetAttribute("Power", 140)
		tagWithContext(pad, "BouncePad", sectionIndex, ctx.building, CFG.LEVELS)
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
			boost:SetAttribute("Speed", 105)
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

	local rampLen = 60
	local rampCF = CFrame.lookAt(
		endPos + Vector3.new(0, -CFG.SLIDE_LANDING_Y / 2 - 2, 40),
		endPos + Vector3.new(0, -CFG.SLIDE_LANDING_Y, 70)
	)
	makePart(
		folder,
		"LandingRamp",
		rampCF,
		Vector3.new(40, 2, rampLen),
		Color3.fromRGB(120, 120, 128),
		Enum.Material.Concrete
	)

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
	}

	local entrySide = SIDE_ORDER[rng:NextInteger(1, 4)]
	local entryCell = edgeCell(entrySide, rng:NextInteger(2, sideRunLength(entrySide) - 1))

	buildFacade(folder, origin, style, entrySide, entryCell, ctx)

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

	local totalPlots = CFG.PLOT_COLS * CFG.PLOT_ROWS
	local exitCount = (sectionIndex % 3 == 0) and 2 or 1
	local exitPlots = {}
	local pool = {}
	for i = 1, totalPlots do
		table.insert(pool, i)
	end
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
			local buildingFolder = buildBuilding(folder, origin, sectionIndex, index, isExit, seed + index * 104729)

			if isExit then
				local start = origin + Vector3.new(FX + CFG.FACADE_OUTSET, ROOF_Y + 2, FZ / 2)
				local nextOrigin = MazeGenerator.sectionOrigin(sectionIndex + 1)
				local landing = nextOrigin + Vector3.new(-140, CFG.SLIDE_LANDING_Y, PLOT_SPAN_Z * 0.5)
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
