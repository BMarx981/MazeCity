-- PetModelGenerator (ModuleScript) -> ReplicatedStorage.PetModelGenerator
-- Builds a pet rig out of Parts, from the `look` recipe on its PetCatalog entry
-- and the stage that entry evolved into. Geometry only: nothing here knows what
-- a pet does. See docs/PET_LOOKS_PLAN.md.
--
-- Shared rather than server-side for the reason ModelGenerator is: PetGui builds
-- the same model on the client for its portraits, so a portrait costs the server
-- nothing and needs no replicated template folder. Two consequences follow and
-- both are load-bearing. This module never touches ServerStorage, and it never
-- assigns a collision group, because a group registered on the server does not
-- exist on a client.
--
-- ============================================================
-- Why this is not ModelGenerator
-- ============================================================
-- The enemies are one silhouette family: dark translucent hoods, lit eyes, hands
-- with no arms, segments trailing into smoke. A pet is the opposite of that on
-- every axis that reads down a corridor, and the table below is the whole art
-- direction:
--
--   Enemy                        Pet
--   translucent, tapering        opaque, rounded
--   Neon everywhere              SmoothPlastic, lit by the world
--   lit eyes on a dark head      dark pupils on a bright eye
--   smoke, tendrils, horns       ears, wings, tails, antennae
--   one dark colour per type     primary, secondary, and one small accent
--
-- The rule underneath it is that a pet must never be mistakable for a threat,
-- and the Ward Hound is why that is a rule rather than a taste: it is the pet
-- whose whole job is standing near enemies, and a silhouette that reads as a
-- seventh Kept type is a player running away from their own defence.
--
-- Neon appears only as accents, and an accent always means something: the
-- Firefly's lantern is its Glow, the Ward Hound's collar is its ward, the Coin
-- Bat's coin is its magnet. That is also what makes an evolution legible without
-- a label, because a stronger ability is a bigger or brighter accent.
--
-- No legs, for the reason ModelGenerator's header gives: a walk cycle needs art
-- or a skeleton and foot-slides without both. Every pet hovers, which the
-- follower was already doing at Config.Pets.FollowHeight.
--
-- ============================================================
-- The rig
-- ============================================================
-- A follower is anchored and moved by PivotTo (PetService sterilises it), so
-- unlike an enemy there is no Humanoid, no HipHeight and no physics. An
-- invisible Root is the PrimaryPart and every skin part is positioned by CFrame
-- against it, which is what PivotTo carries rigidly.
--
-- Each skin part is *also* given a Motor6D whose C0 is the offset it was placed
-- at, and since the motion set those motors are live: PetService sterilises the
-- root anchored and leaves the skin unanchored on them, so the rig is one
-- anchored assembly that PivotTo carries and the joints pose. PetRigDriver is
-- what poses them, the way EnemyRig drives ModelGenerator's output.
--
-- It writes Motor6D.Transform and never C0, which is what keeps rigOf's bases
-- honest forever: C0 is the as-built offset and stays it, so a driver cannot
-- leave drift behind in the thing the next readback measures from.
--
-- build writes the rig and rigOf reads it back, and they are the only two
-- functions that know the part and joint names. An accessory lands on one of the
-- four slot Attachments and an effect lands on the rig or its root; nothing
-- outside this file may hunt for "WingLeft" by name.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetCatalog = require(ReplicatedStorage:WaitForChild("PetCatalog"))

local PetModelGenerator = {}

-- These are the friendly default eye colours. Individual pets can override
-- them, because faces are where the animal read is strongest; the default still
-- keeps a new pet away from the Kept's dark-head-neon-eye language.
local EYE_WHITE = Color3.fromRGB(250, 250, 252)
local PUPIL_DARK = Color3.fromRGB(26, 26, 34)

-- Front is -Z, matching ModelGenerator.
local DEFAULT_LOOK = {
	scale = 1,

	-- primary is the body, secondary the soft parts (belly, wings, muzzle,
	-- beak), accent the one neon group that is the ability made visible. Every
	-- common part below takes its colour from exactly one of the three, while
	-- eyes and details may name their own colour when the animal read needs it.
	primary = Color3.fromRGB(235, 235, 240),
	secondary = Color3.fromRGB(255, 255, 255),
	accent = Color3.fromRGB(255, 236, 150),
	primaryMaterial = "SmoothPlastic",
	secondaryMaterial = "SmoothPlastic",
	accentMaterial = "Neon",

	-- A number is a sphere, a Vector3 is an ellipsoid. Same rule as the enemy
	-- recipes, and it is what keeps most lines here to one number.
	body = Vector3.new(1.8, 1.6, 2.1),
	belly = nil,

	-- 0 leaves the head off entirely, for the one-ball pets whose face sits on
	-- the body.
	head = 1.2,
	headOffset = Vector3.new(0, 0.55, -0.95),

	eyeCount = 2,
	eyeSize = 0.34,
	eyeSpread = 0.24,
	eyeHeight = 0.1,
	eyeDepth = 0.46,
	-- How far an eye is pressed into the head surface. The depth above is still
	-- useful as an artistic limit, but this keeps a wide-set eye from floating
	-- off the curved cheek of a small ellipsoid head.
	eyeEmbed = 0.05,
	pupilSize = 0.17,
	eyeColor = EYE_WHITE,
	pupilColor = PUPIL_DARK,
	eyeTilt = 0,
	eyePitch = 0,
	eyeYaw = 0,
	eyeRim = nil,
	catchlight = nil,

	-- Symmetric pairs. Each is { size, spread, height, z, tilt, sweep, pitch,
	-- forward }, all but size optional.
	ears = nil,
	wings = nil,
	antennae = nil,

	-- Single forward parts on the head.
	beak = nil,
	muzzle = nil,

	-- One solid part, not the enemy's fading segment chain: a pet tail is a tail
	-- rather than a thing trailing into smoke.
	tail = nil,
	crest = nil,

	-- Rings, all three the same builder: { count, radius, size, height, z, tilt,
	-- upright }. Flat by default, which is a halo or a dial; `upright` stands the
	-- ring in the XY plane, which is a collar around a neck. The plane is the
	-- whole difference between an accent that reads and one that is buried: a
	-- flat ring big enough to clear the chest at the sides puts its rear beads
	-- inside the ribs, where they read as parts coming loose rather than as a
	-- collar. Nothing turns yet; the motion set is what makes motes different
	-- from halo.
	collar = nil,
	halo = nil,
	motes = nil,

	-- Accent props a pet carries rather than wears: the Firefly's lantern, the
	-- Coin Bat's coin. A list, so a stage can add a second one.
	charms = nil,

	-- Static surface details: wing spots, paws, fangs, stripes and other little
	-- animal tells that would be too specific to make first-class groups.
	details = nil,

	-- How the rig moves, read by PetRigDriver: flapRate, flapAngle, swayRate,
	-- swayAngle, twitchEvery, ringRate, blinkEvery and the rest of that module's
	-- DEFAULT_MOTION. The numbers live there for the same reason the geometry
	-- baseline lives here, next to the code that spends it.
	--
	-- The one group merged key by key rather than replaced whole (see lookFor),
	-- and the one whose defaults are not here: an absent key is PetRigDriver's
	-- baseline, which is where every number it spends already lives.
	motion = nil,
}

-- The evolution stage's own overrides, resolved here rather than through
-- PetInventory.stageData because that module lives in ServerScriptService and
-- this one has to build on a client. Two lines duplicated to keep the portrait
-- path server-free.
local function stageData(petConfig, stage)
	if stage and stage > 0 then
		return petConfig.evolutions[stage]
	end
	return nil
end

-- Shallow, and deliberately so. The nested groups (wings, ears, motes, charms)
-- are replaced whole rather than merged key by key, because a stage that
-- overrides its wings means different wings and not the old ones with one field
-- edited.
--
-- `motion` is the one exception and it is exempt at every level: it holds only
-- scalars, so a stage naming a flap rate means that rate and the rest of what the
-- pet already was. Replacing it whole would silently drop every other number the
-- pet had tuned, which is a bug that looks like a pet reverting to the baseline
-- the moment it evolves.
function PetModelGenerator.lookFor(petId, stage)
	local petConfig = PetCatalog[petId]
	if not petConfig then
		return nil
	end

	local look = table.clone(DEFAULT_LOOK)
	local motion = nil

	local function merge(source)
		for key, value in pairs(source) do
			if key == "motion" then
				motion = motion or {}
				for name, number in pairs(value) do
					motion[name] = number
				end
			else
				look[key] = value
			end
		end
	end

	merge(petConfig.look or {})
	local evolution = stageData(petConfig, stage)
	merge((evolution and evolution.look) or {})

	look.motion = motion
	return look
end

local function sizeOf(value, scale)
	if typeof(value) == "Vector3" then
		return value * scale
	end
	return Vector3.new(value, value, value) * scale
end

-- Block parts wearing a Sphere SpecialMesh rather than Shape = Ball, because a
-- Ball part will not stretch and most of these silhouettes are ellipsoids: a
-- moth wing is a wide flat one, a compass needle is a long thin one, a coin is a
-- flat disc. The mesh fills the part's Size, so a Vector3 in a recipe is the
-- shape it draws.
local function skinPart(model, name, size, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = 0
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	part.Parent = model

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

function PetModelGenerator.build(petId, stage)
	local petConfig = PetCatalog[petId]
	if not petConfig then
		return nil
	end

	local look = PetModelGenerator.lookFor(petId, stage)
	local scale = look.scale
	local model = Instance.new("Model")
	model.Name = petConfig.id

	local bodySize = sizeOf(look.body, scale)

	-- Sized to the body rather than to a fixed 2x2x1, so GetPivot stays honest
	-- for a rig that is mostly wing and the follow loop's teleport check measures
	-- from something that is actually the pet.
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = bodySize
	root.Transparency = 1
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.CastShadow = false
	root.Massless = true
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model
	model.PrimaryPart = root

	-- The extent of everything actually built, spent on the slot attachments at
	-- the end. Tracked rather than derived from `body`, because a Lumen Moth is
	-- three times wider than its body and a crown placed at its body's top would
	-- sit inside the wings.
	local lowest, highest = -bodySize.Y / 2, bodySize.Y / 2

	local function noteBounds(offsetY, height)
		lowest = math.min(lowest, offsetY - height / 2)
		highest = math.max(highest, offsetY + height / 2)
	end

	local function materialNamed(name)
		if name == "Fabric" then
			return Enum.Material.Fabric
		elseif name == "Pebble" then
			return Enum.Material.Pebble
		elseif name == "Slate" then
			return Enum.Material.Slate
		elseif name == "Plastic" then
			return Enum.Material.Plastic
		elseif name == "Neon" then
			return Enum.Material.Neon
		end
		return Enum.Material.SmoothPlastic
	end

	local body = skinPart(model, "Body", bodySize, look.primary, materialNamed(look.primaryMaterial))
	body.CFrame = root.CFrame
	local bodyJoint = Instance.new("Motor6D")
	bodyJoint.Name = "BodyJoint"
	bodyJoint.Part0 = root
	bodyJoint.Part1 = body
	bodyJoint.C0 = CFrame.new()
	bodyJoint.Parent = root

	-- Every motor is parented to the body whatever it joins, so rigOf reads them
	-- all back out of one place: a Motor6D poses its Part1 from wherever it is
	-- parented, and the alternative is a readback that has to know which part
	-- each joint hangs off before it can look for it.
	local function joint(name, part0, part1, c0)
		local motor = Instance.new("Motor6D")
		motor.Name = name .. "Joint"
		motor.Part0 = part0
		motor.Part1 = part1
		motor.C0 = c0
		motor.Parent = body
		return motor
	end

	-- Everything else joints to the body rather than to the root, so the motion
	-- set can lean or bounce one part and carry the whole pet with it.
	local function place(name, size, color, offset, angles, material)
		local part = skinPart(model, name, size, color, material)
		local c0 = CFrame.new(offset) * (angles or CFrame.new())
		part.CFrame = body.CFrame * c0
		joint(name, body, part, c0)

		noteBounds(offset.Y, size.Y)
		return part
	end

	local function colorOf(spec, fallback)
		if spec.color then
			return spec.color
		end
		if spec.colorKey == "primary" then
			return look.primary
		elseif spec.colorKey == "secondary" then
			return look.secondary
		elseif spec.colorKey == "accent" then
			return look.accent
		end
		return fallback
	end

	local function materialOf(spec, fallback)
		if spec.material then
			return materialNamed(spec.material)
		end
		return fallback
	end

	if look.belly then
		local spec = look.belly
		place(
			"Belly",
			sizeOf(spec.size, scale),
			look.secondary,
			(spec.offset or Vector3.zero) * scale,
			nil,
			materialOf(spec, materialNamed(look.secondaryMaterial))
		)
	end

	local face = body
	if look.head ~= 0 then
		face = place(
			"Head",
			sizeOf(look.head, scale),
			look.primary,
			look.headOffset * scale,
			nil,
			materialNamed(look.primaryMaterial)
		)
	end
	local faceOffset = look.head ~= 0 and look.headOffset * scale or Vector3.zero

	-- Anchored at the mount point, then oriented, then pushed out along the
	-- part's own axis by `forward`. Offsetting before rotating is what leaves a
	-- long ear centred on the skull with half of it inside the head.
	local function symmetricPair(spec, name)
		local size = sizeOf(spec.size, scale)
		for _, side in ipairs({ -1, 1 }) do
			local partName = name .. (side < 0 and "Left" or "Right")
			local offset = Vector3.new(side * spec.spread * scale, spec.height * scale, (spec.z or 0) * scale)
			local angles = CFrame.Angles(spec.pitch or 0, side * (spec.sweep or 0), side * (spec.tilt or 0))
				* CFrame.new(0, 0, -(spec.forward or 0) * scale)
			place(
				partName,
				size,
				spec.color or look.secondary,
				offset,
				angles,
				materialOf(spec, materialNamed(look.secondaryMaterial))
			)
		end
	end

	if look.ears then
		symmetricPair(look.ears, "Ear")
	end
	if look.wings then
		symmetricPair(look.wings, "Wing")
	end
	if look.antennae then
		symmetricPair(look.antennae, "Antenna")
	end

	local function forwardPart(spec, name)
		local offset = faceOffset + Vector3.new(0, (spec.height or 0) * scale, -(spec.forward or 0) * scale)
		place(
			name,
			sizeOf(spec.size, scale),
			spec.color or look.secondary,
			offset,
			spec.tilt and CFrame.Angles(spec.tilt, 0, 0) or nil,
			materialOf(spec, materialNamed(look.secondaryMaterial))
		)
	end

	if look.muzzle then
		forwardPart(look.muzzle, "Muzzle")
	end
	if look.beak then
		forwardPart(look.beak, "Beak")
	end

	if look.tail then
		local spec = look.tail
		place(
			"Tail",
			sizeOf(spec.size, scale),
			spec.color or look.primary,
			(spec.offset or Vector3.zero) * scale,
			spec.tilt and CFrame.Angles(spec.tilt, 0, 0) or nil,
			materialOf(spec, materialNamed(look.primaryMaterial))
		)
	end

	for index, spec in ipairs(look.details or {}) do
		local angles = CFrame.Angles(spec.pitch or 0, spec.yaw or 0, spec.roll or 0)
		if spec.mirrored then
			for _, side in ipairs({ -1, 1 }) do
				local offset = spec.offset * scale
				offset = Vector3.new(offset.X * side, offset.Y, offset.Z)
				local mirroredAngles = CFrame.Angles(spec.pitch or 0, side * (spec.yaw or 0), side * (spec.roll or 0))
				place(
					(spec.name or "Detail") .. (side < 0 and "Left" or "Right") .. index,
					sizeOf(spec.size, scale),
					colorOf(spec, look.secondary),
					offset,
					mirroredAngles,
					materialOf(spec, nil)
				)
			end
		else
			place(
				(spec.name or "Detail") .. index,
				sizeOf(spec.size, scale),
				colorOf(spec, look.secondary),
				spec.offset * scale,
				angles,
				materialOf(spec, nil)
			)
		end
	end

	if look.crest then
		local spec = look.crest
		local offset = faceOffset + Vector3.new(0, (spec.height or 0) * scale, (spec.z or 0) * scale)
		place(
			"Crest",
			sizeOf(spec.size, scale),
			spec.color or look.accent,
			offset,
			nil,
			materialNamed(look.accentMaterial)
		)
	end

	-- One ring, three uses. Seeded around the circle at build time rather than at
	-- the origin, so a rig is a ring on its first frame instead of becoming one
	-- once something starts driving it.
	local function ringGroup(spec, name)
		local size = sizeOf(spec.size, scale)
		for index = 1, spec.count do
			local angle = (index - 1) / spec.count * math.pi * 2
			local swing = math.cos(angle) * spec.radius * scale
			local offset = Vector3.new(
				math.sin(angle) * spec.radius * scale,
				spec.height * scale + (spec.upright and swing or 0),
				(spec.z or 0) * scale + (spec.upright and 0 or swing)
			)
			local angles = spec.tilt and CFrame.Angles(math.cos(angle) * spec.tilt, 0, -math.sin(angle) * spec.tilt)
				or nil
			place(name .. index, size, spec.color or look.accent, offset, angles, materialNamed(look.accentMaterial))
		end
	end

	if look.collar then
		ringGroup(look.collar, "Collar")
	end
	if look.halo then
		ringGroup(look.halo, "Halo")
	end
	if look.motes then
		ringGroup(look.motes, "Mote")
	end

	for index, spec in ipairs(look.charms or {}) do
		place(
			"Charm" .. index,
			sizeOf(spec.size, scale),
			spec.color or look.accent,
			spec.offset * scale,
			nil,
			materialOf(spec, materialNamed(look.accentMaterial))
		)
	end

	-- How far the front surface of an ellipsoid reaches at a local X/Y point.
	-- Eyes sit out toward each cheek, where a round head is shallower than it is
	-- at the centre. Placing them against this curve, rather than one flat plane,
	-- makes the rear of every eye overlap the head instead of looking suspended
	-- just in front of it.
	local faceSize = look.head ~= 0 and sizeOf(look.head, scale) or bodySize
	local function faceDepthAt(offset)
		local halfX = faceSize.X / 2
		local halfY = faceSize.Y / 2
		local halfZ = faceSize.Z / 2
		local x = offset.X / halfX
		local y = offset.Y / halfY
		return halfZ * math.sqrt(math.max(0, 1 - x * x - y * y))
	end

	-- Laid out in a row and centred, so one is a cyclops and four are a thing
	-- that is not a pet. Jointed to the face, whether that is a head or the body
	-- of a pet that has none, and jointed rather than welded because the joint is
	-- the blink: the driver sinks the eye back into the skull for a tenth of a
	-- second, and a pet with no eyelids blinks by taking its eyes away.
	for index = 1, look.eyeCount do
		local offset = Vector3.new(
			(index - (look.eyeCount + 1) / 2) * look.eyeSpread * 2 * scale,
			look.eyeHeight * scale,
			-look.eyeDepth * scale
		)
		local side = offset.X < 0 and -1 or 1
		local eyeAngles = CFrame.Angles((look.eyePitch or 0), side * (look.eyeYaw or 0), side * (look.eyeTilt or 0))
		local eyeSize = sizeOf(look.eyeSize, scale)
		local attachedDepth = faceDepthAt(offset) + eyeSize.Z / 2 - (look.eyeEmbed or 0) * scale
		offset = Vector3.new(offset.X, offset.Y, -math.min(look.eyeDepth * scale, attachedDepth))
		if look.eyeRim then
			local rim = look.eyeRim
			local rimOffset = offset + Vector3.new(0, 0, (rim.inset or 0.03) * scale)
			local part = skinPart(
				model,
				"EyeRim" .. index,
				sizeOf(rim.size, scale),
				colorOf(rim, look.primary),
				materialOf(rim, nil)
			)
			local c0 = CFrame.new(rimOffset) * eyeAngles
			part.CFrame = face.CFrame * c0
			joint("EyeRim" .. index, face, part, c0)
		end

		local eye = skinPart(model, "Eye" .. index, eyeSize, look.eyeColor)
		local eyeC0 = CFrame.new(offset) * eyeAngles
		eye.CFrame = face.CFrame * eyeC0
		joint("Eye" .. index, face, eye, eyeC0)

		-- Proud of the eye rather than inside it. A pupil flush with the sphere
		-- is a pupil that disappears at every angle but dead on. On the eye's own
		-- joint, so it goes in with it when the eye blinks.
		local pupilOffset = Vector3.new(0, 0, -eyeSize.Z * 0.34)
		local pupil = skinPart(model, "Pupil" .. index, sizeOf(look.pupilSize, scale), look.pupilColor)
		pupil.CFrame = eye.CFrame * CFrame.new(pupilOffset)
		joint("Pupil" .. index, eye, pupil, CFrame.new(pupilOffset))

		if look.catchlight then
			local spec = look.catchlight
			local catchOffset = spec.offset or Vector3.new(-eyeSize.X * 0.16, eyeSize.Y * 0.14, -eyeSize.Z * 0.58)
			catchOffset = Vector3.new(catchOffset.X * side, catchOffset.Y, catchOffset.Z)
			local catchlight = skinPart(
				model,
				"Catchlight" .. index,
				sizeOf(spec.size, scale),
				colorOf(spec, Color3.fromRGB(255, 255, 255)),
				materialOf(spec, nil)
			)
			catchlight.CFrame = eye.CFrame * CFrame.new(catchOffset)
			joint("Catchlight" .. index, eye, catchlight, CFrame.new(catchOffset))
		end
	end

	-- The four accessory slots, placed against what the rig actually came out as
	-- rather than against its body. PET_ACCESSORIES_PLAN prefers an authored
	-- attachment over its computed-from-bounding-box fallback; a generated rig
	-- authors its own, so the fallback is only ever for an artist's model.
	local centre = (lowest + highest) / 2
	local slots = {
		HeadAttachment = Vector3.new(0, highest, 0),
		NeckAttachment = Vector3.new(0, lowest + (highest - lowest) * 0.4, -bodySize.Z / 2),
		BackAttachment = Vector3.new(0, centre, bodySize.Z / 2),
		AuraAttachment = Vector3.new(0, centre, 0),
	}
	for name, position in pairs(slots) do
		local attachment = Instance.new("Attachment")
		attachment.Name = name
		attachment.Position = position
		attachment.Parent = root
	end

	model:SetAttribute("PetId", petId)
	model:SetAttribute("PetStage", stage or 0)

	return model
end

-- The joints and their as-built C0s, read back off a rig this module made or off
-- a clone of one. Nil for anything that is not one of ours, which is how an
-- artist's model from ServerStorage/Pets skips joint animation: it has its own
-- look and its own idea of how it moves, and nothing here should be driving it.
--
-- The bases are read here rather than captured at build time so a clone carries
-- its own, which is what stops a driver writing C0 every frame from inheriting
-- whatever the last frame of some other pet left behind.
function PetModelGenerator.rigOf(model)
	local petId = model:GetAttribute("PetId")
	local root = model:FindFirstChild("Root")
	local body = model:FindFirstChild("Body")
	if not petId or not root or not body then
		return nil
	end

	local bodyJoint = root:FindFirstChild("BodyJoint")
	if not bodyJoint then
		return nil
	end

	local joints = {
		body = bodyJoint,
		head = body:FindFirstChild("HeadJoint"),
		tail = body:FindFirstChild("TailJoint"),
		crest = body:FindFirstChild("CrestJoint"),
		wingL = body:FindFirstChild("WingLeftJoint"),
		wingR = body:FindFirstChild("WingRightJoint"),
		earL = body:FindFirstChild("EarLeftJoint"),
		earR = body:FindFirstChild("EarRightJoint"),
		antennaL = body:FindFirstChild("AntennaLeftJoint"),
		antennaR = body:FindFirstChild("AntennaRightJoint"),
		collar = {},
		halo = {},
		motes = {},
		charms = {},
		eyes = {},
	}

	-- Counted up from 1 rather than read off GetChildren, because child order is
	-- not build order and a ring driven out of sequence turns in pieces.
	local function collect(list, prefix)
		local index = 1
		local motor = body:FindFirstChild(prefix .. index .. "Joint")
		while motor do
			list[index] = motor
			index = index + 1
			motor = body:FindFirstChild(prefix .. index .. "Joint")
		end
	end
	collect(joints.collar, "Collar")
	collect(joints.halo, "Halo")
	collect(joints.motes, "Mote")
	collect(joints.charms, "Charm")
	collect(joints.eyes, "Eye")

	local bases = { collar = {}, halo = {}, motes = {}, charms = {}, eyes = {} }
	for key, motor in pairs(joints) do
		if typeof(motor) == "Instance" then
			bases[key] = motor.C0
		end
	end
	for _, key in ipairs({ "collar", "halo", "motes", "charms", "eyes" }) do
		for index, motor in ipairs(joints[key]) do
			bases[key][index] = motor.C0
		end
	end

	return {
		joints = joints,
		bases = bases,
		look = PetModelGenerator.lookFor(petId, model:GetAttribute("PetStage")),
	}
end

return PetModelGenerator
