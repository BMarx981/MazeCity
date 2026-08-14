-- Builds street plans for every door configuration the city can contain, and
-- checks each one against the things generation had already put on the ground.
--
-- The constants below are duplicated from MazeGenerator.CFG deliberately. This
-- file is a check on the maths, not a second copy of the generator, and a
-- constant that changed in CFG without changing here should fail loudly. The
-- same discipline tools/zipline/driver.lua states for itself.
--
-- The rng is an LCG, not Roblox's, so what is asserted is what must hold for
-- EVERY plan: no wall in the slide's landing, no wall under the low end of a
-- zip cable, every reserved room reachable from every other, every overlook a
-- leaf with one way in. The literal city is what a double build in Studio
-- verifies; this verifies that no seed can produce a broken one.

local CELL = 25
local MAZE = 10
local FX = CELL * MAZE
local FACADE_OUT = 8 -- FACADE_OUTSET + FACADE_THICKNESS
local PLOT_SPAN = 352
local PLOT_COLS = 3
local PLOT_ROWS = 2
local SECTION_GAP = 620
local ROOF_Y = 195

local CELL_TARGET = 44
local WALL_THICKNESS = 2
local WALL_HEIGHT = 12
local APRON_MARGIN = 6
local ZIP_CLEARANCE = 8
local ZIP_SAMPLES = 256
local CABLE_MARGIN = 3 -- half a wall plus clearance: the cable is a line, not a point

local PAD_HALF_U = 11 -- (DOOR_WIDTH + 6) / 2
local PAD_V0, PAD_V1 = 8, 36
local SHOP_OFFSET = 26
local SHOP_HALF_U = 16.5 -- (baseWidth + 2) / 2 at five pedestals
local SHOP_V0, SHOP_V1 = 14.5, 25.5
local ZIP_PAD_HALF_U = 10
local ZIP_V0, ZIP_V1 = 40, 60

local ZIP_OUTSET = 50
local ZIP_END_MARGIN = 14
local ZIP_START_LIFT = 6
local ZIP_END_Y = 4
local ZIP_TURNS = 4
local ZIP_RADIUS = 16
local ZIP_RISE = 0.35

local SLIDE_LANDING_X = -80
local SLIDE_LANDING_Y = 2

local BLOCK_PROPS = 30
local TRIM_PROPS = 50
local SIGNPOSTS = 16
local SIGN_ARMS = 3
local BRAID = 0.8

local GROUND_MIN_X = -120
local GROUND_MAX_X = PLOT_COLS * PLOT_SPAN + 120
local GROUND_MIN_Z = -120
local GROUND_MAX_Z = PLOT_ROWS * PLOT_SPAN + 120

local SIDES = { "north", "east", "south", "west" }

local failures = 0
local function check(ok, message)
	if not ok then
		failures = failures + 1
		print("FAIL " .. message)
	end
end

-- ============================================================
-- Spec construction, mirroring what MazeGenerator will hand over
-- ============================================================

local function plotBox(col, row)
	local ox, oz = col * PLOT_SPAN, row * PLOT_SPAN
	return {
		minX = ox - FACADE_OUT,
		maxX = ox + FX + FACADE_OUT,
		minZ = oz - FACADE_OUT,
		maxZ = oz + FX + FACADE_OUT,
		ox = ox,
		oz = oz,
	}
end

-- The apron: the spawn pad, the shop counter and the zipline's landing are all
-- on the same face, so they are one room and not three. The inner edge is
-- pinned at the exterior boundary rather than given the margin, because a
-- margin inward is a room that overlaps the tower.
local function apronRect(plot, side, doorU, shopU)
	local uMin = math.min(doorU - PAD_HALF_U, shopU - SHOP_HALF_U, doorU - ZIP_PAD_HALF_U) - APRON_MARGIN
	local uMax = math.max(doorU + PAD_HALF_U, shopU + SHOP_HALF_U, doorU + ZIP_PAD_HALF_U) + APRON_MARGIN
	local vMin = math.min(PAD_V0, SHOP_V0, ZIP_V0)
	local vMax = math.max(PAD_V1, SHOP_V1, ZIP_V1) + APRON_MARGIN

	if side == "north" then
		return { minX = plot.ox + uMin, maxX = plot.ox + uMax, minZ = plot.oz - vMax, maxZ = plot.oz - vMin }
	elseif side == "south" then
		return { minX = plot.ox + uMin, maxX = plot.ox + uMax, minZ = plot.oz + FX + vMin, maxZ = plot.oz + FX + vMax }
	elseif side == "west" then
		return { minX = plot.ox - vMax, maxX = plot.ox - vMin, minZ = plot.oz + uMin, maxZ = plot.oz + uMax }
	end
	return { minX = plot.ox + FX + vMin, maxX = plot.ox + FX + vMax, minZ = plot.oz + uMin, maxZ = plot.oz + uMax }
end

local function doorPoint(plot, side, doorU)
	if side == "north" then
		return { x = plot.ox + doorU, z = plot.oz - FACADE_OUT }
	elseif side == "south" then
		return { x = plot.ox + doorU, z = plot.oz + FX + FACADE_OUT }
	elseif side == "west" then
		return { x = plot.ox - FACADE_OUT, z = plot.oz + doorU }
	end
	return { x = plot.ox + FX + FACADE_OUT, z = plot.oz + doorU }
end

-- The low end of the zip cable, read off the same curve MazeGenerator draws
-- rather than approximated. This is the check's whole reason for wrapping
-- ZipPath: the tail runs along the entry facade under wall height and, for a
-- door near either end of its face, wraps onto a corner arc.
local function lowCable(plot, side, doorU)
	local span = FX
	local startU = (doorU > span / 2) and ZIP_END_MARGIN or (span - ZIP_END_MARGIN)
	local box = {
		minX = plot.ox,
		maxX = plot.ox + FX,
		minZ = plot.oz,
		maxZ = plot.oz + FX,
		outset = ZIP_OUTSET,
	}
	local startS = ZipPath.arcLengthOfFacePoint(box, side, startU)
	local endS = ZipPath.arcLengthOfFacePoint(box, side, doorU)
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
		topY = ROOF_Y + ZIP_START_LIFT,
		endY = ZIP_END_Y,
		turns = ZIP_TURNS,
		radius = ZIP_RADIUS,
		rise = ZIP_RISE,
	})

	local ceiling = WALL_HEIGHT + ZIP_CLEARANCE
	local points = {}
	for i = 0, ZIP_SAMPLES do
		local p = ZipPath.pointAt(path, i / ZIP_SAMPLES)
		if p.Y < ceiling then
			points[#points + 1] = { x = p.X, z = p.Z, y = p.Y }
		end
	end
	return points
end

local function makeSpec(seed, doorPicker)
	local plots, buildings = {}, {}
	for row = 0, PLOT_ROWS - 1 do
		for col = 0, PLOT_COLS - 1 do
			local index = row * PLOT_COLS + col + 1
			local plot = plotBox(col, row)
			plots[#plots + 1] = plot

			local side, cellIndex = doorPicker(index)
			local doorU = (cellIndex - 0.5) * CELL
			local shopU = doorU + ((doorU > FX / 2) and SHOP_OFFSET or -SHOP_OFFSET)

			buildings[#buildings + 1] = {
				index = index,
				name = "Tower " .. index,
				plot = plot,
				door = doorPoint(plot, side, doorU),
				apron = apronRect(plot, side, doorU, shopU),
				lowCable = lowCable(plot, side, doorU),
			}
		end
	end

	return {
		rng = Random.new(seed),
		cellTarget = CELL_TARGET,
		wallThickness = WALL_THICKNESS,
		cableMargin = CABLE_MARGIN,
		braid = BRAID,
		plots = plots,
		buildings = buildings,
		groundMinX = GROUND_MIN_X,
		groundMaxX = GROUND_MAX_X,
		groundMinZ = GROUND_MIN_Z,
		groundMaxZ = GROUND_MAX_Z,
		-- The pad is 70 square at (-80, 176); the reservation runs west to the
		-- ground edge because the slide's tail descends into it.
		slideLanding = {
			minX = GROUND_MIN_X,
			maxX = SLIDE_LANDING_X + 40,
			minZ = PLOT_SPAN * 0.5 - 40,
			maxZ = PLOT_SPAN * 0.5 + 40,
		},
		blockProps = BLOCK_PROPS,
		trimProps = TRIM_PROPS,
		signposts = SIGNPOSTS,
		signArms = SIGN_ARMS,
	}
end

-- ============================================================
-- Assertions
-- ============================================================

local function overlaps(aMinX, aMaxX, aMinZ, aMaxZ, bMinX, bMaxX, bMinZ, bMaxZ)
	return aMaxX > bMinX + 1e-6 and aMinX < bMaxX - 1e-6 and aMaxZ > bMinZ + 1e-6 and aMinZ < bMaxZ - 1e-6
end

local function reachableNodes(plan)
	-- Flood over carved edges from the first walkable cell.
	local start = nil
	for id = 1, plan.cols * plan.rows do
		if plan.cells[id].state ~= "blocked" then
			start = plan.cells[id]
			break
		end
	end
	local seen = { [start.id] = true }
	local queue = { start }
	local head = 1
	while head <= #queue do
		local cell = queue[head]
		head = head + 1
		-- Cells of one room are one node: they are connected to each other by
		-- being the same node, not by a carved edge.
		if cell.room then
			for _, c in ipairs(plan.rooms[cell.room].cells) do
				if not seen[c.id] then
					seen[c.id] = true
					queue[#queue + 1] = c
				end
			end
		end
		for _, i in ipairs(plan.adjacency[cell.id] or {}) do
			local e = plan.edges[i]
			if e.carved then
				local other = (e.a.id == cell.id) and e.b or e.a
				if not seen[other.id] then
					seen[other.id] = true
					queue[#queue + 1] = other
				end
			end
		end
	end
	return seen
end

local function verify(label, plan, spec)
	-- 1. Cell sizes stay in a range a street reads as a street.
	for cx = 1, plan.cols do
		local w = plan.xLines[cx + 1] - plan.xLines[cx]
		check(w >= 30 and w <= 55, label .. ": x cell " .. cx .. " is " .. string.format("%.2f", w) .. " studs")
	end
	for cz = 1, plan.rows do
		local d = plan.zLines[cz + 1] - plan.zLines[cz]
		check(d >= 30 and d <= 55, label .. ": z cell " .. cz .. " is " .. string.format("%.2f", d) .. " studs")
	end

	-- 2. Gridlines land exactly on every plot boundary, which is the whole
	-- reason a tower has no walkable ring around it.
	for _, p in ipairs(spec.plots) do
		for _, want in ipairs({ p.minX, p.maxX }) do
			local hit = false
			for _, line in ipairs(plan.xLines) do
				if math.abs(line - want) < 1e-9 then
					hit = true
				end
			end
			check(hit, label .. ": no x gridline at plot boundary " .. want)
		end
		for _, want in ipairs({ p.minZ, p.maxZ }) do
			local hit = false
			for _, line in ipairs(plan.zLines) do
				if math.abs(line - want) < 1e-9 then
					hit = true
				end
			end
			check(hit, label .. ": no z gridline at plot boundary " .. want)
		end
	end

	-- 3. No wall inside a room, and no wall onto a blocked cell.
	for _, w in ipairs(plan.walls) do
		local a, b = plan.cells[w.aId], plan.cells[w.bId]
		check(a.state ~= "blocked" and b.state ~= "blocked", label .. ": wall on a blocked cell")
		check(not (a.room and a.room == b.room), label .. ": wall inside room " .. tostring(a.room))
		for _, p in ipairs(spec.plots) do
			check(
				not (w.x > p.minX + 1e-6 and w.x < p.maxX - 1e-6 and w.z > p.minZ + 1e-6 and w.z < p.maxZ - 1e-6),
				label .. ": wall centre inside a tower"
			)
		end
	end

	-- 4. Nothing stands in the slide's landing or on the low end of a cable.
	local land = spec.slideLanding
	for _, w in ipairs(plan.walls) do
		check(
			not overlaps(
				w.x - w.sizeX / 2,
				w.x + w.sizeX / 2,
				w.z - w.sizeZ / 2,
				w.z + w.sizeZ / 2,
				land.minX,
				land.maxX,
				land.minZ,
				land.maxZ
			),
			label .. ": wall in the slide landing"
		)
	end
	for _, b in ipairs(spec.buildings) do
		for _, point in ipairs(b.lowCable) do
			-- Only the samples that are actually below the wall top can hit one.
			-- The reservation reaches higher than that on purpose, so the cells
			-- between the wall top and the clearance ceiling are margin rather
			-- than a collision the check should be asserting on.
			if point.y < WALL_HEIGHT then
				for _, w in ipairs(plan.walls) do
					check(
						not (
							point.x > w.x - w.sizeX / 2
							and point.x < w.x + w.sizeX / 2
							and point.z > w.z - w.sizeZ / 2
							and point.z < w.z + w.sizeZ / 2
						),
						label .. ": wall under the low zip cable of tower " .. b.index
					)
				end
			end
			for _, prop in ipairs(plan.props) do
				if prop.kind == "block" then
					check(
						not (
							point.x > prop.minX
							and point.x < prop.maxX
							and point.z > prop.minZ
							and point.z < prop.maxZ
						),
						label .. ": block prop under the low zip cable of tower " .. b.index
					)
				end
			end
			for _, dome in ipairs(plan.domes) do
				check(
					not (point.x > dome.minX and point.x < dome.maxX and point.z > dome.minZ and point.z < dome.maxZ),
					label .. ": overlook under the low zip cable of tower " .. b.index
				)
			end
		end
	end

	-- 5. Everything not blocked is one connected place. A second component is a
	-- spawn pad in one half of the district and the door it serves in the other.
	local seen = reachableNodes(plan)
	local unreached = 0
	for id = 1, plan.cols * plan.rows do
		if plan.cells[id].state ~= "blocked" and not seen[id] then
			unreached = unreached + 1
		end
	end
	check(unreached == 0, label .. ": " .. unreached .. " cells unreachable")

	-- 6. An overlook is a leaf with exactly one way in, which is what makes it
	-- impossible to cross the maze from up there.
	check(#plan.domes == #spec.buildings, label .. ": " .. #plan.domes .. " overlooks for " .. #spec.buildings .. " towers")
	for _, dome in ipairs(plan.domes) do
		local carved = 0
		for _, i in ipairs(plan.adjacency[dome.cell.id] or {}) do
			if plan.edges[i].carved then
				carved = carved + 1
			end
		end
		check(carved == 1, label .. ": overlook of tower " .. dome.building .. " has " .. carved .. " ways in")
		for _, other in ipairs(plan.domes) do
			if other ~= dome then
				local gap = math.abs(other.cell.cx - dome.cell.cx) + math.abs(other.cell.cz - dome.cell.cz)
				check(gap > 1, label .. ": two overlooks share an edge")
			end
		end
	end

	-- 7. Counts are a function of the settings, not of the seed.
	check(plan.counts.blockProps == BLOCK_PROPS, label .. ": " .. plan.counts.blockProps .. " block props")
	check(plan.counts.trimProps == TRIM_PROPS, label .. ": " .. plan.counts.trimProps .. " trim props")
	check(plan.counts.signs == SIGNPOSTS, label .. ": " .. plan.counts.signs .. " signposts")

	-- 8. Every signpost points somewhere, and every tower is pointed at by at
	-- least one sign in the district.
	local pointedAt = {}
	for _, sign in ipairs(plan.signs) do
		check(#sign.arms > 0, label .. ": a signpost with no arms")
		for _, arm in ipairs(sign.arms) do
			pointedAt[arm.building] = true
		end
	end
	for _, b in ipairs(spec.buildings) do
		check(pointedAt[b.index] == true, label .. ": no sign points at tower " .. b.index)
	end
end

-- ============================================================
-- Run
-- ============================================================

-- The slide crosses the west ground boundary on its way into the next section,
-- and it is a physics ride: a perimeter wall standing in it stops the rider
-- dead over the void between two grounds. This is the one assertion that is
-- pure arithmetic over the constants, and it is here so that raising the street
-- wall height in a playtest fails loudly rather than in a lazily generated
-- section nobody was watching.
do
	local startX = (PLOT_COLS - 1) * PLOT_SPAN + FX + 6
	local startY = ROOF_Y + 2
	local endX = PLOT_COLS * PLOT_SPAN + SECTION_GAP + SLIDE_LANDING_X
	local endY = SLIDE_LANDING_Y
	local t = (endX + GROUND_MIN_X - startX) / (endX - startX)
	local crossingY = startY + (endY - startY) * t
	check(
		crossingY > WALL_HEIGHT + 1,
		string.format("slide crosses the west perimeter at Y %.2f against a wall top of %d", crossingY, WALL_HEIGHT)
	)
end

local pickers = {
	{
		name = "all north, mid face",
		fn = function()
			return "north", 5
		end,
	},
	{
		name = "all east, high u",
		fn = function()
			return "east", 9
		end,
	},
	{
		name = "all south, low u",
		fn = function()
			return "south", 2
		end,
	},
	{
		name = "all west, high u",
		fn = function()
			return "west", 8
		end,
	},
	{
		name = "facing pairs across the row gap",
		fn = function(index)
			return (index <= 3) and "south" or "north", 6
		end,
	},
	{
		name = "rotating sides",
		fn = function(index)
			return SIDES[(index - 1) % 4 + 1], 2 + (index % 8)
		end,
	},
}

local seeds = 0
for _, picker in ipairs(pickers) do
	for seed = 1, 34 do
		local spec = makeSpec(seed * 7919, picker.fn)
		local plan = StreetPlan.build(spec)
		verify(picker.name .. " seed " .. seed, plan, spec)
		seeds = seeds + 1
	end
end

-- Same spec and same seed is the same street, which is what lets a lazily
-- generated section come out identical to a pregenerated one.
do
	local a = StreetPlan.build(makeSpec(4242, pickers[6].fn))
	local b = StreetPlan.build(makeSpec(4242, pickers[6].fn))
	check(#a.walls == #b.walls, "determinism: wall counts differ")
	local same = #a.walls == #b.walls
	if same then
		for i = 1, #a.walls do
			if a.walls[i].x ~= b.walls[i].x or a.walls[i].z ~= b.walls[i].z then
				same = false
			end
		end
	end
	check(same, "determinism: same seed produced a different street")
end

do
	local plan = StreetPlan.build(makeSpec(1, pickers[1].fn))
	print(
		string.format(
			"StreetPlan: %d cells, %d walls, %d rooms, %d dead ends before braid, %d braided",
			plan.counts.cells,
			plan.counts.walls,
			plan.counts.rooms,
			plan.counts.deadEndsBeforeBraid,
			plan.counts.braided
		)
	)
end

if failures > 0 then
	-- Level 0 so the message is the message rather than a stack trace, and so
	-- the CLI exits non-zero: this is meant to be runnable as a check, not only
	-- read.
	error(failures .. " failures", 0)
end

print("StreetPlan: " .. seeds .. " plans clean")
