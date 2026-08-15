-- StreetPlan (ModuleScript) -> ServerScriptService.StreetPlan
-- The shape of a section's street maze, and the only file that knows it.
-- MazeGenerator draws what this returns; nothing else reads it.
--
-- Pure. No instances, no yielding, no services, no world state, and never
-- math.random: the rng arrives in the spec, so tools/street can run every plan
-- the city can contain under the luau CLI outside Roblox. Nothing is defaulted.
-- A missing spec field is a caller that forgot, and a silent default here is a
-- wall standing in the slide's landing.
--
-- ============================================================
-- The grid
-- ============================================================
--
-- Not a uniform grid. The gridlines *include every plot boundary exactly*, so a
-- blocked cell's edge is the facade plane. A uniform grid whose lines fell
-- wherever they liked would leave a walkable ring of up to one cell around each
-- tower, which is a corridor all the way round the building that no wall can
-- close and that makes the whole street maze optional.
--
-- So each strip between two plot boundaries is subdivided into
-- `math.round(width / cellTarget)` cells, at least one. At the shipped numbers
-- that is 41 x 30 = 1230 cells, 384 of them under the six towers, and every
-- cell between 28.0 and 33.3 studs across. One constant produces all of it and
-- it survives a change to STREET, FACADE_OUTSET or PLOT_COLS, which is the same
-- bargain MazeGenerator's derived spans strike.
--
-- The target sets a LANE COUNT per strip rather than a width, so it moves in
-- steps, and the step that decides whether any of this reads as a maze is the
-- 86-stud canyon between two plots: two lanes of 43 at a target above 34, three
-- of 28.7 below it. It shipped at 44, where a 43-stud lane between 12-stud
-- walls is a plaza with some walls standing in it and you can see across the
-- whole district. 32 puts a street lane within a few studs of the tower's own
-- 25 and the same braid produces a street that has to be read.
--
-- ============================================================
-- Three cell states, and one rule about the third
-- ============================================================
--
-- `blocked`  a tower, a house, a shopfront. Not in the graph, and no wall is
--            ever drawn on its edges: the thing standing there is its own
--            boundary. This is why a block prop must fill its cell.
-- `open`     ordinary street.
-- `room`     a reserved rectangle whose cells are fused into ONE graph node.
--
-- **A room is a node before the carve, never an opening after it.** That is
-- MazeGenerator's invariant 2 generalised, and it is the whole reason there is
-- no "now connect the spawn pad to the maze" pass: the carve is a spanning tree
-- over nodes, every room is a node, so every room is connected by construction.
-- Post-hoc wall opening on a spanning tree orphans regions, indoors and out.
--
-- Rooms are what keep the street off everything generation already put on it:
-- the spawn pad, the shop counter, the zipline's landing, the slide's landing,
-- and the last hundred studs of zip cable, which run below wall height and are
-- the one piece of this that is not obvious from a plan view.
--
-- ============================================================
-- Counts are a function of the settings, not of the seed
-- ============================================================
--
-- Invariant 9 generalised. Exactly `blockProps` block props, `trimProps` trim
-- props, `signposts` signposts and one dome per building, topping up from a
-- wider pool when the preferred one runs short, the way buildCollectibles does.
-- Without that a section could differ from its neighbour for no reason anybody
-- could confirm was the intended one.
--
-- The wall count is the exception and deliberately so: it moves with where the
-- six doors landed, which the maze had already decided. It is reported in
-- `plan.counts` rather than claimed as a constant.

local StreetPlan = {}

local EPS = 1e-6

-- Fixed iteration order everywhere. A plan that depended on pairs() ordering
-- would be a different city on a different Luau build, which is a determinism
-- bug that only ever shows up on somebody else's machine.
local STEP = {
	{ dx = 1, dz = 0, side = "east" },
	{ dx = -1, dz = 0, side = "west" },
	{ dx = 0, dz = 1, side = "south" },
	{ dx = 0, dz = -1, side = "north" },
}

local function need(spec, key)
	local value = spec[key]
	if value == nil then
		error("StreetPlan: spec is missing " .. key, 0)
	end
	return value
end

-- ============================================================
-- Gridlines
-- ============================================================

local function subdivide(out, lo, hi, target)
	local n = math.max(1, math.round((hi - lo) / target))
	for i = 1, n do
		-- The last line is `hi` itself rather than lo + (hi-lo)*n/n, which is
		-- the same number in algebra and not always the same float. It has to be
		-- exact: this line is a plot boundary, and a cell edge a millionth of a
		-- stud off one is a cell that overlaps a tower.
		out[#out + 1] = (i == n) and hi or (lo + (hi - lo) * i / n)
	end
end

local function buildLines(lo, hi, cuts, target)
	local sorted = {}
	for _, c in ipairs(cuts) do
		if c > lo + EPS and c < hi - EPS then
			sorted[#sorted + 1] = c
		end
	end
	table.sort(sorted)

	local lines = { lo }
	local at = lo
	for _, c in ipairs(sorted) do
		-- Duplicates fall out here: three plot columns produce six cut values,
		-- and the second copy of each is not greater than where we already are.
		if c > at + EPS then
			subdivide(lines, at, c, target)
			at = c
		end
	end
	subdivide(lines, at, hi, target)
	return lines
end

-- ============================================================
-- Cells
-- ============================================================

local function idOf(plan, cx, cz)
	if cx < 1 or cx > plan.cols or cz < 1 or cz > plan.rows then
		return nil
	end
	return (cx - 1) * plan.rows + cz
end

local function cellAt(plan, cx, cz)
	local id = idOf(plan, cx, cz)
	return id and plan.cells[id] or nil
end

-- Every cell a rect strictly overlaps. Strict, so a rect that stops exactly on
-- a gridline claims nothing past it, which is what lets a room rect start on a
-- tower's facade plane and take no cell of the tower.
local function cellsIn(plan, minX, maxX, minZ, maxZ)
	local out = {}
	for cx = 1, plan.cols do
		local cell = plan.cells[idOf(plan, cx, 1)]
		if cell.maxX > minX + EPS and cell.minX < maxX - EPS then
			for cz = 1, plan.rows do
				local c = plan.cells[idOf(plan, cx, cz)]
				if c.maxZ > minZ + EPS and c.minZ < maxZ - EPS then
					out[#out + 1] = c
				end
			end
		end
	end
	return out
end

-- ============================================================
-- Rooms
-- ============================================================

-- Claim a set of cells into a room, merging with any room they already touch.
-- Merging matters: a south-facing door on one plot and a north-facing door on
-- the plot behind it share the 86-stud row gap, and two overlapping fused sets
-- would leave the carve with two nodes covering one piece of ground.
local function claimRoom(plan, cells, kind, building)
	local target = nil
	for _, c in ipairs(cells) do
		if c.room and (target == nil or c.room < target) then
			target = c.room
		end
	end

	if target == nil then
		target = #plan.rooms + 1
		plan.rooms[target] = { id = target, kinds = { kind }, building = building, cells = {} }
	else
		local room = plan.rooms[target]
		room.kinds[#room.kinds + 1] = kind
		room.building = room.building or building
	end

	-- A blocked cell is skipped rather than claimed: a tower already stands
	-- there, and a room is reserved ground rather than a licence to unbuild
	-- something. In practice the gridlines make that unreachable for an apron,
	-- which starts on the facade plane; the guard is for a caller with a
	-- sloppier rect.
	for _, c in ipairs(cells) do
		if c.state == "room" and c.room ~= target then
			-- Fold the whole of the other room in, not just this cell, or the
			-- fused set stops being one connected piece of ground.
			local from = plan.rooms[c.room]
			for _, other in ipairs(from.cells) do
				other.room = target
				table.insert(plan.rooms[target].cells, other)
			end
			for _, k in ipairs(from.kinds) do
				table.insert(plan.rooms[target].kinds, k)
			end
			plan.rooms[target].building = plan.rooms[target].building or from.building
			from.cells = {}
			from.merged = target
		elseif c.state == "open" then
			c.state = "room"
			c.room = target
			table.insert(plan.rooms[target].cells, c)
		end
	end

	return target
end

local function roomBounds(plan)
	for _, room in ipairs(plan.rooms) do
		if #room.cells > 0 then
			local minX, maxX = math.huge, -math.huge
			local minZ, maxZ = math.huge, -math.huge
			for _, c in ipairs(room.cells) do
				minX = math.min(minX, c.minX)
				maxX = math.max(maxX, c.maxX)
				minZ = math.min(minZ, c.minZ)
				maxZ = math.max(maxZ, c.maxZ)
			end
			room.minX, room.maxX, room.minZ, room.maxZ = minX, maxX, minZ, maxZ
		end
	end
end

-- ============================================================
-- Graph
-- ============================================================

local function nodeOf(cell)
	-- A room is one node however many cells it spans. Negative so a room id can
	-- never collide with a cell id.
	return cell.room and -cell.room or cell.id
end

local function walkable(cell)
	return cell ~= nil and cell.state ~= "blocked"
end

-- Reachability over everything not blocked, ignoring what has been carved.
-- Used as a guard before a prop or a dome is allowed to stand: thirty blocked
-- cells can form a cut, and a carve over a disconnected grid is a forest with
-- a spawn pad in one component and the door it serves in another.
local function allReachable(plan, blockedExtra)
	local start = nil
	for id = 1, plan.cols * plan.rows do
		local c = plan.cells[id]
		if walkable(c) and not (blockedExtra and blockedExtra[id]) then
			start = c
			break
		end
	end
	if start == nil then
		return false
	end

	local seen = { [start.id] = true }
	local queue = { start }
	local head = 1
	local count = 1
	while head <= #queue do
		local cell = queue[head]
		head = head + 1
		for _, step in ipairs(STEP) do
			local n = cellAt(plan, cell.cx + step.dx, cell.cz + step.dz)
			if n and walkable(n) and not seen[n.id] and not (blockedExtra and blockedExtra[n.id]) then
				-- The dome's own seal is respected here, or a dome placed early
				-- would look like a cut to every prop considered after it.
				if not (cell.domeSealed and cell.domeSealed[n.id]) and not (n.domeSealed and n.domeSealed[cell.id]) then
					seen[n.id] = true
					count = count + 1
					queue[#queue + 1] = n
				end
			end
		end
	end

	local total = 0
	for id = 1, plan.cols * plan.rows do
		if walkable(plan.cells[id]) and not (blockedExtra and blockedExtra[id]) then
			total = total + 1
		end
	end
	return count == total
end

-- ============================================================
-- Randomness helpers
-- ============================================================

local function shuffle(list, rng)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

-- ============================================================
-- Build
-- ============================================================

function StreetPlan.build(spec)
	local rng = need(spec, "rng")
	local cellTarget = need(spec, "cellTarget")
	local wallThickness = need(spec, "wallThickness")
	local cableMargin = need(spec, "cableMargin")
	local braidFraction = need(spec, "braid")
	local plots = need(spec, "plots")
	local buildings = need(spec, "buildings")
	local slideLanding = need(spec, "slideLanding")
	local groundMinX = need(spec, "groundMinX")
	local groundMaxX = need(spec, "groundMaxX")
	local groundMinZ = need(spec, "groundMinZ")
	local groundMaxZ = need(spec, "groundMaxZ")
	local blockPropCount = need(spec, "blockProps")
	local trimPropCount = need(spec, "trimProps")
	local signpostCount = need(spec, "signposts")
	local signArms = need(spec, "signArms")

	local plan = {
		walls = {},
		perimeter = {},
		rooms = {},
		props = {},
		signs = {},
		domes = {},
		cells = {},
		counts = {},
	}

	-- ---------- gridlines ----------
	local xCuts, zCuts = {}, {}
	for _, p in ipairs(plots) do
		xCuts[#xCuts + 1] = p.minX
		xCuts[#xCuts + 1] = p.maxX
		zCuts[#zCuts + 1] = p.minZ
		zCuts[#zCuts + 1] = p.maxZ
	end
	plan.xLines = buildLines(groundMinX, groundMaxX, xCuts, cellTarget)
	plan.zLines = buildLines(groundMinZ, groundMaxZ, zCuts, cellTarget)
	plan.cols = #plan.xLines - 1
	plan.rows = #plan.zLines - 1

	for cx = 1, plan.cols do
		for cz = 1, plan.rows do
			local id = (cx - 1) * plan.rows + cz
			plan.cells[id] = {
				id = id,
				cx = cx,
				cz = cz,
				minX = plan.xLines[cx],
				maxX = plan.xLines[cx + 1],
				minZ = plan.zLines[cz],
				maxZ = plan.zLines[cz + 1],
				state = "open",
			}
		end
	end

	-- ---------- towers ----------
	for _, p in ipairs(plots) do
		for _, c in ipairs(cellsIn(plan, p.minX, p.maxX, p.minZ, p.maxZ)) do
			c.state = "blocked"
			c.plot = true
		end
	end

	-- ---------- rooms ----------
	-- The slide's landing is reserved in every section including the first,
	-- which never sees one. Six cells, and every section's plan comes out the
	-- same shape, which is worth more than the six cells.
	claimRoom(
		plan,
		cellsIn(plan, slideLanding.minX, slideLanding.maxX, slideLanding.minZ, slideLanding.maxZ),
		"landing"
	)

	for _, b in ipairs(buildings) do
		local cells = cellsIn(plan, b.apron.minX, b.apron.maxX, b.apron.minZ, b.apron.maxZ)
		-- The zip cable's last stretch runs below wall height along this same
		-- facade and, for a door near either end of its face, wraps onto a
		-- corner arc two cells outside anything the door alone would reserve.
		-- A rider is anchored and driven by CFrame, so a wall there is not
		-- scenery: they pass through it and step out somewhere they did not
		-- choose. These points are read off the curve generation already fixed.
		-- A box around each sample, not the cell the sample sits in. A cable that
		-- clips a cell by half a stud would otherwise reserve that cell and
		-- leave the wall on its boundary standing half a stud away, which is
		-- inside the wall: the cable is a line with clearance, not a point.
		for _, point in ipairs(b.lowCable) do
			for _, c in
				ipairs(
					cellsIn(
						plan,
						point.x - cableMargin,
						point.x + cableMargin,
						point.z - cableMargin,
						point.z + cableMargin
					)
				)
			do
				cells[#cells + 1] = c
			end
		end
		b.roomId = claimRoom(plan, cells, "apron", b.index)
	end

	roomBounds(plan)

	-- ---------- domes ----------
	-- One per tower, and it draws nothing: candidates are ordered, filtered and
	-- taken. A dome is ONE cell, entered from exactly one side, with its other
	-- three edges sealed. That makes it a leaf in the graph, so it can never be
	-- a cut, and it is also the whole of "you may see the way out, you may not
	-- take it from up there": the deck sits over one cell and reaches no other.
	local domeSeal = {}
	for _, b in ipairs(buildings) do
		-- One stud of expansion, not an epsilon: this has to reach the cells
		-- that touch the tower, and cellsIn tests for strict overlap, so an
		-- expansion small enough to be rounding is an expansion that finds
		-- nothing. The tower's own cells come back too and are filtered below.
		local ring = cellsIn(plan, b.plot.minX - 1, b.plot.maxX + 1, b.plot.minZ - 1, b.plot.maxZ + 1)
		local candidates = {}
		for _, c in ipairs(ring) do
			if c.state == "open" and not c.dome then
				local exits = {}
				local adjacentDome = false
				for _, step in ipairs(STEP) do
					local n = cellAt(plan, c.cx + step.dx, c.cz + step.dz)
					if n and n.dome then
						adjacentDome = true
					end
					if n and walkable(n) and not n.dome then
						exits[#exits + 1] = { cell = n, side = step.side }
					end
				end
				if not adjacentDome and #exits > 0 then
					-- Farthest from the door, so the overlook is a walk rather
					-- than a thing you trip over stepping off the spawn pad.
					-- Ties by cell index, never by a draw.
					local dx = (c.minX + c.maxX) / 2 - b.door.x
					local dz = (c.minZ + c.maxZ) / 2 - b.door.z
					candidates[#candidates + 1] = {
						cell = c,
						exits = exits,
						score = dx * dx + dz * dz,
					}
				end
			end
		end

		table.sort(candidates, function(a, b2)
			if math.abs(a.score - b2.score) > EPS then
				return a.score > b2.score
			end
			return a.cell.id < b2.cell.id
		end)

		for _, cand in ipairs(candidates) do
			local c = cand.cell
			-- Whichever single neighbour the entrance uses, chosen by cell index
			-- so it is a property of the grid and not of the seed.
			local entrance = cand.exits[1]
			for _, e in ipairs(cand.exits) do
				if e.cell.id < entrance.cell.id then
					entrance = e
				end
			end

			local seal = {}
			for _, e in ipairs(cand.exits) do
				if e.cell.id ~= entrance.cell.id then
					seal[e.cell.id] = true
				end
			end
			c.domeSealed = seal
			c.dome = true

			if allReachable(plan) then
				domeSeal[#domeSeal + 1] = c
				plan.domes[#plan.domes + 1] = {
					building = b.index,
					cell = c,
					minX = c.minX,
					maxX = c.maxX,
					minZ = c.minZ,
					maxZ = c.maxZ,
					entranceSide = entrance.side,
				}
				break
			end

			c.domeSealed = nil
			c.dome = nil
		end
	end

	-- ---------- block props ----------
	-- Homes and shuttered shopfronts. Each fills its cell, which is why no wall
	-- is ever drawn on a blocked cell's edge: the house is the boundary. Guarded
	-- one at a time, because thirty of them can wall a district in half.
	local propPool = {}
	for id = 1, plan.cols * plan.rows do
		local c = plan.cells[id]
		if c.state == "open" and not c.dome then
			propPool[#propPool + 1] = c
		end
	end
	shuffle(propPool, rng)

	local blockPlaced = 0
	for _, c in ipairs(propPool) do
		if blockPlaced >= blockPropCount then
			break
		end
		c.state = "blocked"
		if allReachable(plan) then
			blockPlaced = blockPlaced + 1
			c.prop = true
			plan.props[#plan.props + 1] = {
				kind = "block",
				cell = c,
				minX = c.minX,
				maxX = c.maxX,
				minZ = c.minZ,
				maxZ = c.maxZ,
				variant = rng:NextInteger(1, 4),
				rotation = rng:NextInteger(0, 3) * 90,
			}
		else
			c.state = "open"
		end
	end

	-- ---------- edges ----------
	-- One entry per boundary between two cells neither of which is blocked. An
	-- edge onto a blocked cell is not here at all and gets no wall: the tower's
	-- facade, or the house's own wall, is already that boundary, and a part on
	-- that line would z-fight the exterior relief that reaches past it.
	local edges = {}
	local adjacency = {}
	local function link(a, b, axis)
		local index = #edges + 1
		local sealed = (a.domeSealed and a.domeSealed[b.id]) or (b.domeSealed and b.domeSealed[a.id]) or false
		edges[index] = { a = a, b = b, axis = axis, carved = false, sealed = sealed }
		if not sealed then
			adjacency[a.id] = adjacency[a.id] or {}
			adjacency[b.id] = adjacency[b.id] or {}
			table.insert(adjacency[a.id], index)
			table.insert(adjacency[b.id], index)
		end
	end

	for cx = 1, plan.cols do
		for cz = 1, plan.rows do
			local c = plan.cells[idOf(plan, cx, cz)]
			if walkable(c) then
				local east = cellAt(plan, cx + 1, cz)
				if walkable(east) then
					link(c, east, "x")
				end
				local south = cellAt(plan, cx, cz + 1)
				if walkable(south) then
					link(c, south, "z")
				end
			end
		end
	end

	-- ---------- carve ----------
	-- Randomised Kruskal over nodes, with each room's cells pre-unioned so a
	-- room joins the tree as one thing. Rooms are never opened afterwards.
	local parent = {}
	local function find(n)
		local root = n
		while parent[root] ~= root do
			root = parent[root]
		end
		while parent[n] ~= root do
			local next_ = parent[n]
			parent[n] = root
			n = next_
		end
		return root
	end
	local function union(a, b)
		local ra, rb = find(a), find(b)
		if ra == rb then
			return false
		end
		parent[ra] = rb
		return true
	end

	for id = 1, plan.cols * plan.rows do
		local c = plan.cells[id]
		if walkable(c) then
			local n = nodeOf(c)
			parent[n] = parent[n] or n
		end
	end

	local order = {}
	for i = 1, #edges do
		if not edges[i].sealed then
			order[#order + 1] = i
		end
	end
	shuffle(order, rng)

	for _, i in ipairs(order) do
		local e = edges[i]
		local na, nb = nodeOf(e.a), nodeOf(e.b)
		if na == nb then
			-- Both ends are the same room. There was never a wall between them.
			e.carved = true
			e.interior = true
		elseif union(na, nb) then
			e.carved = true
		end
	end

	-- ---------- braid ----------
	-- The fraction of DEAD ENDS removed, not the fraction of walls opened. At 1
	-- there are no dead ends and it is still a maze; "open every candidate" is
	-- no maze at all. This is the knob a playtest moves, and it is the whole of
	-- what makes the street easier than a tower.
	local function nodeDegree(cell)
		local n = nodeOf(cell)
		local count = 0
		local nodes = {}
		if n < 0 then
			for _, c in ipairs(plan.rooms[-n].cells) do
				nodes[#nodes + 1] = c
			end
		else
			nodes[1] = cell
		end
		local seen = {}
		for _, c in ipairs(nodes) do
			for _, i in ipairs(adjacency[c.id] or {}) do
				local e = edges[i]
				if e.carved and not e.interior and not seen[i] then
					seen[i] = true
					count = count + 1
				end
			end
		end
		return count
	end

	local deadEnds = {}
	for id = 1, plan.cols * plan.rows do
		local c = plan.cells[id]
		if walkable(c) and c.room == nil and not c.dome and nodeDegree(c) == 1 then
			deadEnds[#deadEnds + 1] = c
		end
	end
	plan.counts.deadEndsBeforeBraid = #deadEnds

	shuffle(deadEnds, rng)
	local target = math.floor(#deadEnds * braidFraction + 0.5)
	local braided = 0
	for _, c in ipairs(deadEnds) do
		if braided >= target then
			break
		end
		if nodeDegree(c) == 1 then
			local options = {}
			for _, i in ipairs(adjacency[c.id] or {}) do
				if not edges[i].carved then
					options[#options + 1] = i
				end
			end
			if #options > 0 then
				edges[options[rng:NextInteger(1, #options)]].carved = true
				braided = braided + 1
			end
		end
	end
	plan.counts.braided = braided

	-- ---------- walls ----------
	for _, e in ipairs(edges) do
		if not e.carved then
			local a, b = e.a, e.b
			if e.axis == "x" then
				local lo, hi = math.max(a.minZ, b.minZ), math.min(a.maxZ, b.maxZ)
				plan.walls[#plan.walls + 1] = {
					aId = a.id,
					bId = b.id,
					x = a.maxX,
					z = (lo + hi) / 2,
					sizeX = wallThickness,
					-- Grown by a thickness so two runs meeting at a corner
					-- actually meet, rather than leaving a square hole a player
					-- can see daylight through.
					sizeZ = (hi - lo) + wallThickness,
				}
			else
				local lo, hi = math.max(a.minX, b.minX), math.min(a.maxX, b.maxX)
				plan.walls[#plan.walls + 1] = {
					aId = a.id,
					bId = b.id,
					x = (lo + hi) / 2,
					z = a.maxZ,
					sizeX = (hi - lo) + wallThickness,
					sizeZ = wallThickness,
				}
			end
		end
	end

	-- ---------- perimeter ----------
	-- Four parts, not one per cell edge. It is a boundary rather than a maze, so
	-- nothing needs per-cell granularity, and past it is the void between
	-- section grounds. MazeGenerator builds these from a different function than
	-- the street walls, which is what keeps them out of the Wall Walker's
	-- collision group: containment is a property of which function built a part.
	local width = groundMaxX - groundMinX
	local depth = groundMaxZ - groundMinZ
	plan.perimeter = {
		{ x = (groundMinX + groundMaxX) / 2, z = groundMinZ, sizeX = width + wallThickness, sizeZ = wallThickness },
		{ x = (groundMinX + groundMaxX) / 2, z = groundMaxZ, sizeX = width + wallThickness, sizeZ = wallThickness },
		{ x = groundMinX, z = (groundMinZ + groundMaxZ) / 2, sizeX = wallThickness, sizeZ = depth + wallThickness },
		{ x = groundMaxX, z = (groundMinZ + groundMaxZ) / 2, sizeX = wallThickness, sizeZ = depth + wallThickness },
	}

	-- ---------- distance fields ----------
	-- One BFS per tower over the carved graph, which is what a signpost arm
	-- points along. Six floods over 444 cells; the cost is not worth caching.
	local function flood(fromCells)
		local dist = {}
		local queue = {}
		local head = 1
		for _, c in ipairs(fromCells) do
			dist[c.id] = 0
			queue[#queue + 1] = c
		end
		while head <= #queue do
			local cell = queue[head]
			head = head + 1
			for _, i in ipairs(adjacency[cell.id] or {}) do
				local e = edges[i]
				if e.carved then
					local other = (e.a.id == cell.id) and e.b or e.a
					if dist[other.id] == nil then
						-- Crossing a room costs nothing: it is one node, and a
						-- sign pointing "through the plaza" should not be beaten
						-- by one pointing the long way round it.
						dist[other.id] = dist[cell.id] + ((other.room and other.room == cell.room) and 0 or 1)
						queue[#queue + 1] = other
					end
				end
			end
		end
		return dist
	end

	local fields = {}
	for _, b in ipairs(buildings) do
		local room = plan.rooms[b.roomId]
		while room and room.merged do
			room = plan.rooms[room.merged]
		end
		fields[b.index] = flood(room and room.cells or {})
	end

	-- ---------- signs ----------
	-- Junctions only, spread out, and count-exact: the preferred pool is degree
	-- three or more, and if the braid left too few of those the spacing relaxes
	-- rather than the count dropping.
	local junctions = {}
	local corridors = {}
	for id = 1, plan.cols * plan.rows do
		local c = plan.cells[id]
		if c.state == "open" and not c.dome then
			local degree = nodeDegree(c)
			if degree >= 3 then
				junctions[#junctions + 1] = c
			elseif degree == 2 then
				corridors[#corridors + 1] = c
			end
		end
	end
	shuffle(junctions, rng)
	shuffle(corridors, rng)
	-- The junctions are the preferred pool, because a sign is worth reading
	-- where there is a choice to make. A heavy braid can leave too few of them,
	-- so plain corridor cells are the top-up: the count is a function of the
	-- settings and it is the placement that gives, not the number.
	for _, c in ipairs(corridors) do
		junctions[#junctions + 1] = c
	end

	-- Which way to walk from this cell to reach that tower: the neighbour across
	-- a carved edge whose distance to it is lowest. Nil when the tower is not
	-- reachable from here, which the carve makes impossible and which is
	-- returned rather than asserted anyway.
	local function armFor(cell, building)
		local here = fields[building.index][cell.id]
		if here == nil then
			return nil
		end
		local best, bestSide = nil, nil
		for _, step in ipairs(STEP) do
			local n = cellAt(plan, cell.cx + step.dx, cell.cz + step.dz)
			if n then
				local open = false
				for _, i in ipairs(adjacency[cell.id] or {}) do
					local e = edges[i]
					if e.carved and (e.a.id == n.id or e.b.id == n.id) then
						open = true
					end
				end
				local d = open and fields[building.index][n.id] or nil
				if d and (best == nil or d < best) then
					best, bestSide = d, step.side
				end
			end
		end
		if bestSide == nil then
			return nil
		end
		return { building = building.index, label = building.name, side = bestSide, hops = here }
	end

	local function rankedFrom(cell)
		local ranked = {}
		for _, b in ipairs(buildings) do
			local d = fields[b.index][cell.id]
			if d then
				ranked[#ranked + 1] = { building = b, dist = d }
			end
		end
		table.sort(ranked, function(a, b2)
			if a.dist ~= b2.dist then
				return a.dist < b2.dist
			end
			return a.building.index < b2.building.index
		end)
		return ranked
	end

	local function armsFor(cell)
		local arms = {}
		for _, entry in ipairs(rankedFrom(cell)) do
			if #arms >= signArms then
				break
			end
			local arm = armFor(cell, entry.building)
			if arm then
				arms[#arms + 1] = arm
			end
		end
		return arms
	end

	local minSpacing = 3
	while #plan.signs < signpostCount and minSpacing >= 0 do
		for _, c in ipairs(junctions) do
			if #plan.signs >= signpostCount then
				break
			end
			if not c.sign then
				local ok = true
				for _, s in ipairs(plan.signs) do
					if math.abs(s.cell.cx - c.cx) + math.abs(s.cell.cz - c.cz) < minSpacing then
						ok = false
						break
					end
				end
				if ok then
					local arms = armsFor(c)
					if #arms > 0 then
						c.sign = true
						plan.signs[#plan.signs + 1] = {
							cell = c,
							x = (c.minX + c.maxX) / 2,
							z = (c.minZ + c.maxZ) / 2,
							arms = arms,
						}
					end
				end
			end
		end
		minSpacing = minSpacing - 1
	end

	-- Every tower is named by at least one sign in the district. Each sign
	-- carries the `signArms` nearest towers, and with six towers and three arms
	-- that leaves one unnamed anywhere on some layouts, which is a player
	-- following signs to a tower the signs have never heard of. So the sign
	-- closest to an unnamed tower gains one extra arm for it.
	--
	-- Coverage rather than a bigger `signArms`: four arms on every post to fix
	-- one post is three hundred plates a section nobody reads.
	for _, b in ipairs(buildings) do
		local named = false
		for _, sign in ipairs(plan.signs) do
			for _, arm in ipairs(sign.arms) do
				if arm.building == b.index then
					named = true
				end
			end
		end
		if not named then
			local best, bestDist = nil, nil
			for _, sign in ipairs(plan.signs) do
				local d = fields[b.index][sign.cell.id]
				if d and (bestDist == nil or d < bestDist) then
					best, bestDist = sign, d
				end
			end
			local arm = best and armFor(best.cell, b)
			if arm then
				best.arms[#best.arms + 1] = arm
			end
		end
	end

	-- ---------- trim props ----------
	-- Lamp posts, planters, crates. They stand in a corner of an open cell with
	-- clearance, so unlike a block prop they narrow the street rather than
	-- closing it, and nothing has to be re-checked for connectivity.
	local trimPool = {}
	for id = 1, plan.cols * plan.rows do
		local c = plan.cells[id]
		if c.state == "open" and not c.dome and not c.sign then
			trimPool[#trimPool + 1] = c
		end
	end
	shuffle(trimPool, rng)

	for _, c in ipairs(trimPool) do
		if #plan.props - blockPlaced >= trimPropCount then
			break
		end
		local corner = rng:NextInteger(1, 4)
		local inset = 6
		local x = ((corner == 1 or corner == 4) and (c.minX + inset) or (c.maxX - inset))
		local z = ((corner <= 2) and (c.minZ + inset) or (c.maxZ - inset))
		plan.props[#plan.props + 1] = {
			kind = "trim",
			cell = c,
			x = x,
			z = z,
			variant = rng:NextInteger(1, 4),
			rotation = rng:NextInteger(0, 3) * 90,
		}
	end

	plan.counts.cells = plan.cols * plan.rows
	plan.counts.walls = #plan.walls
	plan.counts.perimeter = #plan.perimeter
	plan.counts.rooms = 0
	for _, room in ipairs(plan.rooms) do
		if #room.cells > 0 then
			plan.counts.rooms = plan.counts.rooms + 1
		end
	end
	plan.counts.domes = #plan.domes
	plan.counts.blockProps = blockPlaced
	plan.counts.trimProps = #plan.props - blockPlaced
	plan.counts.signs = #plan.signs

	plan.edges = edges
	plan.adjacency = adjacency
	return plan
end

return StreetPlan
