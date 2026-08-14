-- ZipPath (ModuleScript) -> ServerScriptService.ZipPath
-- The shape of a roof zipline, and the only file that knows it. MazeGenerator
-- draws cable segments along this curve; TraversalService moves a rider along
-- the same curve. Two callers, one set of maths: a cable the rider does not
-- hang from is the one bug a spiral zipline can have that a straight one
-- cannot, and it is invisible until somebody plays it.
--
-- Pure. No instances, no yielding, no randomness, no world state. Everything it
-- needs arrives in the params table, which TraversalService rebuilds out of the
-- attributes MazeGenerator stamped on the ZipEntrance part, so the curve crosses
-- the generation/runtime line the way every other feature does: as attributes on
-- a tagged part.
--
-- The curve is two things composed.
--
-- The *spine* is the constant-distance offset of the building footprint: four
-- straight runs at `outset` from each face, joined by quarter-circle arcs of
-- radius `outset` centred on the footprint corners. That shape rather than an
-- offset rectangle with square corners, and rather than a circle, for two
-- reasons: it holds the same clearance from the facade the whole way round, and
-- its tangent is continuous, so the twist below has a frame that does not snap
-- through 90 degrees at every corner.
--
-- The *twist* is a corkscrew about that spine: `turns` rotations, radius
-- tapering linearly from `radius` at the roof to zero at the landing pad. The
-- taper is what keeps the low end honest. The last fifth of the ride runs along
-- the entry facade at street height, where the plaza, the spawn pad and the
-- shop stall are; by then the corkscrew is a few studs wide and by the pad it
-- is nothing, so the rider arrives on the spine exactly where the landing is.
--
-- The corkscrew is an ellipse and not a circle, and `rise` is why. A circular
-- one of radius R over n turns climbs 2*pi*n*R over the ride, against a drop of
-- only 197: at four turns of sixteen studs that is 402 against 197, so the
-- cable would genuinely go uphill through part of every turn. Uphill is the one
-- thing a zipline cannot do, whatever is carrying the rider. So the swing keeps
-- its full width sideways, which is what the rider feels and what the camera is
-- dragged through, and is squashed vertically to `rise` of it, which is what
-- keeps every point on the curve lower than the one before it. tools/zipline
-- checks exactly that, over all thirty-two curves the city can contain.

local ZipPath = {}

local HALF_PI = math.pi / 2
local TWO_PI = math.pi * 2

-- Where the ride's speed and feel are tuned is MazeConfig. Where its *shape* is
-- tuned is MazeGenerator.CFG, alongside every other structural constant, and it
-- arrives here in params. Nothing is defaulted in this file: a missing field is
-- a caller that forgot, and a silent default would put the rider beside the
-- cable rather than on it.

-- The eight pieces of the spine, in order, each with its arc length. Built once
-- per params table and cached on it, because a rider samples this sixty times a
-- second and the generator seventy-odd times per building.
local function segments(p)
	if p._segments then
		return p._segments, p._perimeter
	end

	local w = p.maxX - p.minX
	local h = p.maxZ - p.minZ
	local d = p.outset
	local arc = d * HALF_PI

	-- A straight run is { kind = "line", from, to }; an arc is
	-- { kind = "arc", centre, a0 }, sweeping a quarter turn from a0.
	-- Angles use offset(a) = (sin a, -cos a) in (x, z), so a = 0 is the -z face
	-- and a = 90 is the +x face, and the tangent is (cos a, sin a).
	local list = {
		{ kind = "line", len = w, x0 = p.minX, z0 = p.minZ - d, dx = 1, dz = 0 },
		{ kind = "arc", len = arc, cx = p.maxX, cz = p.minZ, a0 = 0 },
		{ kind = "line", len = h, x0 = p.maxX + d, z0 = p.minZ, dx = 0, dz = 1 },
		{ kind = "arc", len = arc, cx = p.maxX, cz = p.maxZ, a0 = HALF_PI },
		{ kind = "line", len = w, x0 = p.maxX, z0 = p.maxZ + d, dx = -1, dz = 0 },
		{ kind = "arc", len = arc, cx = p.minX, cz = p.maxZ, a0 = math.pi },
		{ kind = "line", len = h, x0 = p.minX - d, z0 = p.maxZ, dx = 0, dz = -1 },
		{ kind = "arc", len = arc, cx = p.minX, cz = p.minZ, a0 = math.pi + HALF_PI },
	}

	local total = 0
	for _, seg in ipairs(list) do
		seg.s0 = total
		total = total + seg.len
	end

	p._segments = list
	p._perimeter = total
	return list, total
end

-- Position and unit tangent on the spine at arc length s, in the XZ plane. The
-- caller supplies Y; the spine itself is flat, because a zipline's descent is a
-- property of the ride and not of the shape it is wrapped around.
local function spineAt(p, s)
	local list, perimeter = segments(p)
	s = s % perimeter

	for _, seg in ipairs(list) do
		local local_s = s - seg.s0
		if local_s >= 0 and local_s <= seg.len then
			if seg.kind == "line" then
				return seg.x0 + seg.dx * local_s, seg.z0 + seg.dz * local_s, seg.dx, seg.dz
			end
			local a = seg.a0 + local_s / p.outset
			return seg.cx + p.outset * math.sin(a), seg.cz - p.outset * math.cos(a), math.cos(a), math.sin(a)
		end
	end

	-- Unreachable while perimeter is the sum of the pieces, which it is by
	-- construction two functions up. Falling back to the start beats returning
	-- nil into a Vector3 constructor.
	local first = list[1]
	return first.x0, first.z0, first.dx, first.dz
end

-- The arc length of a point known to sit on one of the four straight runs. Both
-- ends of a ride are mid-face by construction (the boarding corner is
-- ZIP_END_MARGIN in from a corner, the landing is at a door cell), so the arcs
-- never have to be inverted.
function ZipPath.arcLengthOfFacePoint(p, side, u)
	local list = segments(p)
	if side == "north" then
		return list[1].s0 + (p.minX + u - list[1].x0)
	elseif side == "east" then
		return list[3].s0 + (p.minZ + u - list[3].z0)
	elseif side == "south" then
		return list[5].s0 + (list[5].x0 - (p.minX + u))
	end
	return list[7].s0 + (list[7].z0 - (p.minZ + u))
end

function ZipPath.perimeter(p)
	local _, total = segments(p)
	return total
end

-- Which way round the tower, and how far. Always the long way: boarding and
-- landing are both on the entry facade, so the short way is the straight run
-- the ride used to be. Taking the long way is what makes it a wrap, and it is a
-- lap of at least half the perimeter whatever the door cell turned out to be.
function ZipPath.route(p, startS, endS)
	local perimeter = ZipPath.perimeter(p)
	local forward = (endS - startS) % perimeter
	if forward >= perimeter / 2 then
		return 1, forward
	end
	return -1, perimeter - forward
end

-- The ridden point at t in [0, 1]: spine, plus descent, plus corkscrew.
function ZipPath.pointAt(p, t)
	t = math.clamp(t, 0, 1)
	local s = p.startS + p.dir * t * p.length
	local x, z, tx, tz = spineAt(p, s)
	local y = p.topY + (p.endY - p.topY) * t

	local radius = p.radius * (1 - t)
	if radius <= 0 then
		return Vector3.new(x, y, z)
	end

	local phase = TWO_PI * p.turns * t
	-- The tangent turned a right angle about Y. Composed with world up, that is
	-- the plane the corkscrew turns in.
	local rightX, rightZ = tz, -tx
	local lateral = radius * math.cos(phase)
	local lift = radius * p.rise * math.sin(phase)

	return Vector3.new(x + rightX * lateral, y + lift, z + rightZ * lateral)
end

-- Unit heading of the ridden curve, by finite difference rather than by
-- differentiating the corkscrew: the twist, the descent and the spine's own
-- curvature all contribute, and one of the three is piecewise, so a closed form
-- would be three chances to drop a term. Sampling cannot disagree with
-- pointAt, which is what the rider is actually on.
function ZipPath.headingAt(p, t)
	local step = 1 / 512
	local a = ZipPath.pointAt(p, math.max(0, t - step))
	local b = ZipPath.pointAt(p, math.min(1, t + step))
	local d = b - a
	if d.Magnitude < 1e-4 then
		return Vector3.new(0, 0, -1)
	end
	return d.Unit
end

-- How far the rider leans, as a signed fraction of the bank the config allows.
-- The corkscrew's lateral offset is radius * cos(phase), so its lateral
-- acceleration runs with -cos(phase): the rider leans into the swing, hardest
-- at the sides of each turn and level at the top and bottom of it. Tapered by
-- the same factor the radius is, so the lean flattens out into the landing
-- rather than stopping dead at it.
function ZipPath.bankAt(p, t)
	t = math.clamp(t, 0, 1)
	if p.radius <= 0 then
		return 0
	end
	local phase = TWO_PI * p.turns * t
	return -math.cos(phase) * (1 - t)
end

-- Every field of a params table, written once. It is the argument list of
-- ZipPath.new and it is the set of attributes MazeGenerator stamps onto the
-- ZipEntrance part for TraversalService to read back, so the two cannot drift
-- apart in files that never see each other.
local FIELDS = {
	"minX",
	"maxX",
	"minZ",
	"maxZ",
	"outset",
	"startS",
	"dir",
	"length",
	"topY",
	"endY",
	"turns",
	"radius",
	"rise",
}

local function attrName(field)
	return "Path" .. field:sub(1, 1):upper() .. field:sub(2)
end

-- One constructor, and nothing in it is optional: a field left out is a caller
-- that forgot, and a silent default would put the rider beside the cable rather
-- than on it.
function ZipPath.new(spec)
	local p = {}
	for _, field in ipairs(FIELDS) do
		if spec[field] == nil then
			error("ZipPath.new: missing " .. field, 2)
		end
		p[field] = spec[field]
	end
	return p
end

function ZipPath.stamp(part, p)
	for _, field in ipairs(FIELDS) do
		part:SetAttribute(attrName(field), p[field])
	end
end

-- Returns nil rather than erroring on a part built before this shipped, or one
-- an artist copied by hand: the caller warns and leaves the pad inert, which is
-- how every other missing-attribute path in TraversalService behaves.
function ZipPath.read(part)
	local spec = {}
	for _, field in ipairs(FIELDS) do
		local value = part:GetAttribute(attrName(field))
		if value == nil then
			return nil
		end
		spec[field] = value
	end
	return ZipPath.new(spec)
end

return ZipPath
