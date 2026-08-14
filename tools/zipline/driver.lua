-- Checks ZipPath outside Roblox, over every door cell on every entry side: the
-- 32 curves the city can actually contain. What it is looking for is the set of
-- things that are invisible in a diff and cost a Studio session to find.
--
--  * the ride ends at the landing pad, on the spine, at street height
--  * it never re-enters the building, and never crosses the street into the
--    neighbouring plot
--  * it descends the whole way and is never level enough to read as a walkway
--  * it takes the long way round, so it is a wrap and not the straight run it
--    used to be
--  * consecutive cable segments meet, and no one segment is long enough for the
--    corkscrew to read as a polygon
--
-- Numbers here mirror MazeGenerator.CFG. They are duplicated deliberately: this
-- file is a check on the maths, not a second copy of the generator, and a
-- constant that changed in CFG without changing here should fail loudly.

-- ZipPath is concatenated in ahead of this file by check.sh, the same way the
-- pet look check loads its generator: the module is pure, so it needs no
-- services and no stub beyond Vector3.

local CELL = 25
local MAZE = 10
local FX, FZ = CELL * MAZE, CELL * MAZE
local OUTSET = 50
local END_MARGIN = 14
local ROOF_Y = 195
local START_LIFT = 6
local END_Y = 4
local TURNS = 4
local RADIUS = 16
local RISE = 0.35
local SEGMENTS = 72

-- The facade face, and the neighbouring plot's facade face, both measured from
-- our own footprint edge. The cable has to stay in the band between them.
local FACADE_OUT = 8
local STREET_FACADE = 94

local failures = 0
local function check(ok, message)
	if not ok then
		failures = failures + 1
		print("FAIL " .. message)
	end
end

-- How far outside the footprint a point is, on whichever face it is nearest.
-- Negative means inside the building.
local function clearance(point)
	local dx = math.max(0 - point.X, point.X - FX)
	local dz = math.max(0 - point.Z, point.Z - FZ)
	if dx > 0 and dz > 0 then
		return math.sqrt(dx * dx + dz * dz)
	end
	return math.max(dx, dz)
end

local sides = { "north", "east", "south", "west" }

-- Reported at the end rather than per curve: what is worth reading is the range
-- the city spans, because the door cell is what varies and it is the extremes of
-- it that either fit in the street or do not.
local shortest, longest = math.huge, 0
local widestSegment, tightest, widest = 0, math.huge, 0

for _, side in ipairs(sides) do
	local horizontal = (side == "north" or side == "south")
	local span = horizontal and FX or FZ

	for cellIndex = 2, MAZE - 1 do
		local doorU = (cellIndex - 0.5) * CELL
		local startU = (doorU > span / 2) and END_MARGIN or (span - END_MARGIN)
		local label = string.format("%s door %d", side, cellIndex)

		local box = { minX = 0, maxX = FX, minZ = 0, maxZ = FZ, outset = OUTSET }
		local startS = ZipPath.arcLengthOfFacePoint(box, side, startU)
		local endS = ZipPath.arcLengthOfFacePoint(box, side, doorU)
		local dir, length = ZipPath.route(box, startS, endS)

		local path = ZipPath.new({
			minX = 0,
			maxX = FX,
			minZ = 0,
			maxZ = FZ,
			outset = OUTSET,
			startS = startS,
			dir = dir,
			length = length,
			topY = ROOF_Y + START_LIFT,
			endY = END_Y,
			turns = TURNS,
			radius = RADIUS,
			rise = RISE,
		})

		local perimeter = ZipPath.perimeter(box)
		check(length >= perimeter / 2, label .. ": takes the short way round (" .. math.floor(length) .. ")")
		check(length <= perimeter, label .. ": longer than a lap (" .. math.floor(length) .. ")")

		-- The end of the curve is where the landing pad is built, so any drift
		-- between them is a rider dropped beside the pad rather than on it.
		local finish = ZipPath.pointAt(path, 1)
		local doorPoint
		if side == "north" then
			doorPoint = { X = doorU, Z = -OUTSET }
		elseif side == "south" then
			doorPoint = { X = doorU, Z = FZ + OUTSET }
		elseif side == "west" then
			doorPoint = { X = -OUTSET, Z = doorU }
		else
			doorPoint = { X = FX + OUTSET, Z = doorU }
		end
		check(math.abs(finish.X - doorPoint.X) < 0.01, label .. ": lands off the pad in X")
		check(math.abs(finish.Z - doorPoint.Z) < 0.01, label .. ": lands off the pad in Z")
		check(math.abs(finish.Y - END_Y) < 0.01, label .. ": lands at the wrong height")

		local previous = ZipPath.pointAt(path, 0)
		local maxChord = 0
		for i = 1, SEGMENTS do
			local point = ZipPath.pointAt(path, i / SEGMENTS)
			local chord = (point - previous).Magnitude
			if chord > maxChord then
				maxChord = chord
			end
			previous = point
		end
		check(maxChord < 30, label .. ": segment too long (" .. string.format("%.1f", maxChord) .. ")")

		-- Sampled far finer than the cable is drawn: the parts are chords and
		-- the rider is on the curve, so the curve is what has to descend and
		-- what has to stay in the street.
		local minGap, maxGap, worstRise = math.huge, 0, 0
		local last = ZipPath.pointAt(path, 0)
		for i = 1, 2000 do
			local point = ZipPath.pointAt(path, i / 2000)
			local gap = clearance(point)
			minGap = math.min(minGap, gap)
			maxGap = math.max(maxGap, gap)
			worstRise = math.max(worstRise, point.Y - last.Y)

			-- The swing reaches in toward the building, and low down that is
			-- where the spawn pad, the shop counter and its price boards are.
			-- The taper is supposed to have closed the swing by the time the
			-- ride is that low; this is the assertion that it has.
			if point.Y < 20 then
				check(gap > 40, label .. string.format(": swings in to %.1f at %.0f studs up", gap, point.Y))
			end
			last = point
		end

		check(worstRise <= 0.001, label .. string.format(": climbs %.2f studs", worstRise))
		check(minGap > FACADE_OUT, label .. ": reaches the facade (" .. string.format("%.1f", minGap) .. ")")
		check(maxGap < STREET_FACADE, label .. ": reaches the next plot (" .. string.format("%.1f", maxGap) .. ")")

		shortest = math.min(shortest, length)
		longest = math.max(longest, length)
		widestSegment = math.max(widestSegment, maxChord)
		tightest = math.min(tightest, minGap)
		widest = math.max(widest, maxGap)
	end
end

local drop = ROOF_Y + START_LIFT - END_Y
print(
	string.format(
		"lap %.0f to %.0f studs, drop %.0f, slope %.1f to %.1f deg",
		shortest,
		longest,
		drop,
		math.deg(math.atan(drop / longest)),
		math.deg(math.atan(drop / shortest))
	)
)
print(
	string.format(
		"segment at most %.1f studs, clearance %.1f to %.1f from the footprint",
		widestSegment,
		tightest,
		widest
	)
)

-- The heading has to be usable everywhere, because the rider is turned by it
-- sixty times a second and a zero-length one would face them at the origin.
do
	local box = { minX = 0, maxX = FX, minZ = 0, maxZ = FZ, outset = OUTSET }
	local startS = ZipPath.arcLengthOfFacePoint(box, "north", FX - END_MARGIN)
	local endS = ZipPath.arcLengthOfFacePoint(box, "north", 62.5)
	local dir, length = ZipPath.route(box, startS, endS)
	local path = ZipPath.new({
		minX = 0,
		maxX = FX,
		minZ = 0,
		maxZ = FZ,
		outset = OUTSET,
		startS = startS,
		dir = dir,
		length = length,
		topY = ROOF_Y + START_LIFT,
		endY = END_Y,
		turns = TURNS,
		radius = RADIUS,
		rise = RISE,
	})
	for i = 0, 1000 do
		local heading = ZipPath.headingAt(path, i / 1000)
		check(math.abs(heading.Magnitude - 1) < 0.001, "heading not unit at t=" .. i / 1000)
		local bank = ZipPath.bankAt(path, i / 1000)
		check(bank >= -1.001 and bank <= 1.001, "bank out of range at t=" .. i / 1000)
	end
	check(math.abs(ZipPath.bankAt(path, 1)) < 0.001, "bank does not flatten into the landing")
end

if failures > 0 then
	-- Level 0 so the message is the message rather than a stack trace, and so
	-- the CLI exits non-zero: this is meant to be runnable as a check, not only
	-- read.
	error(failures .. " failures", 0)
end
print("ZipPath: all 32 curves clean")
