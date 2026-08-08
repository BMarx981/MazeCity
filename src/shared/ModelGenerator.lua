-- ModelGenerator (ModuleScript) -> ReplicatedStorage.ModelGenerator
-- Builds an enemy rig out of Parts, from the `look` recipe on its
-- EnemyDefinitions row. Geometry only: nothing here knows what an enemy does.
--
-- Shared rather than server-side because the bestiary portraits build their own
-- models on the client from these same recipes. That is the whole reason a
-- portrait costs the server nothing and needs no replicated template folder.
-- Two consequences: this module never touches ServerStorage (ensureTemplates
-- takes the parent it should build into) and it never assigns a collision
-- group, because a group registered on the server does not exist on a client.
-- EnemyService puts the rig in its group after it clones one.
--
-- ============================================================
-- The rig
-- ============================================================
-- A hovering shade: a translucent hood around a dark head with lit eyes, an
-- ember at the chest, hands with no arms between them, and tapering segments
-- trailing into smoke. No legs anywhere, which is the point. A walk cycle needs
-- art or a skeleton and foot-slides without both, and the rig before this one
-- was a box with a ball on it precisely because neither was available.
--
-- The shape is a recipe, not a hardcoded body. DEFAULT_LOOK is the whole
-- baseline and each row's `look` is merged over it, so the types differ by
-- silhouette rather than by tint: they used to be one rig in six colours, which
-- at corridor distance is one rig. Optional groups (crown, horns, plates, motes)
-- are absent unless a type asks for them, and any size of 0 leaves that part off
-- entirely. A row with no `look` at all is the baseline, which is what the
-- Drifter is and what the thirteen types still waiting on phase E4 get.
--
-- Everything cosmetic hangs off Motor6Ds rather than welds so one Heartbeat loop
-- can animate it. Structure and skin stay separate: the Humanoid drives an
-- invisible root and torso, the skin never touches physics.
--
-- build writes the rig and rigOf reads it back, and they are the only two
-- functions that know the joint names. Nothing else may reach into the rig by
-- name: a caller that hunts for "Tail3Joint" itself is a caller that keeps
-- working after a recipe stops making one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local EnemyDefinitions = require(ReplicatedStorage:WaitForChild("EnemyDefinitions"))

local ModelGenerator = {}

-- Studs of daylight kept under the lowest part of a rig at the bottom of its
-- bob. Small, because a shade is supposed to skim the floor.
local FLOOR_MARGIN = 0.35

local DEFAULT_LOOK = {
	scale = 1,
	bobScale = 1,
	bobRate = 1,
	-- Resting hover, and only a floor: the builder raises it to clear whatever
	-- the type's tail and tendrils actually hang down to.
	hover = 2.4,
	head = 1.5,
	headOffset = 1.6,
	hood = 2.35,
	hoodOffset = 1.52,
	hoodTransparency = 0.34,
	core = 0.9,
	coreOffset = Vector3.new(0, 0.35, -0.18),
	hands = 0.52,
	handSpread = 1.35,
	handHeight = 0.5,
	tail = {
		{ size = 1.6, y = -0.45 },
		{ size = 1.15, y = -1.2 },
		{ size = 0.72, y = -1.85 },
	},
	-- The head is 1.5 across, so the eyes sit just proud of its front face.
	-- Anything smaller stops reading as a face down a corridor.
	eyeCount = 2,
	eyeSize = 0.34,
	eyeSpread = 0.3,
	eyeHeight = 0.16,
	eyeDepth = 0.62,
	crown = nil,
	horns = nil,
	plates = nil,
	motes = nil,
}

-- The symmetric rigid pairs, in the order build makes them. rigOf reads them
-- back by this list rather than by scanning, so a plate and a horn cannot swap
-- places between one clone and the next.
local RIGID_NAMES = { "PlateLeft", "PlateRight", "HornLeft", "HornRight" }

-- Shallow on purpose. The nested tables (tail, crown, motes) are replaced whole
-- rather than merged key by key, because a type that overrides its tail means a
-- different tail and not a three-segment one with the first entry edited.
function ModelGenerator.lookFor(typeName)
	local look = table.clone(DEFAULT_LOOK)
	for key, value in pairs(EnemyDefinitions.get(typeName).look or {}) do
		look[key] = value
	end
	return look
end

-- A size is a number for a sphere or a Vector3 for an ellipsoid, which is what
-- keeps the recipes short: most parts are round and say so in one number.
local function sizeOf(value, scale)
	if typeof(value) == "Vector3" then
		return value * scale
	end
	return Vector3.new(value, value, value) * scale
end

local function weld(a, b)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

-- Block parts wearing a Sphere SpecialMesh rather than Shape = Ball, because a
-- Ball part will not stretch and half these silhouettes are ellipsoids: the
-- Stalker is a tall thin one, the Lurker's cowl is a wide flat one, the
-- Charger's horns are long thin ones. The mesh fills the part's Size, so a
-- Vector3 in a recipe is the shape it draws.
local function skinPart(model, name, size, color, transparency, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.Neon
	part.Transparency = transparency
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

local function joint(parent, part0, part1, name, c0)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = c0
	motor.Parent = parent
	return motor
end

function ModelGenerator.build(typeName)
	local row = EnemyDefinitions.get(typeName)
	local juice = Config.Juice
	local model = Instance.new("Model")
	model.Name = typeName

	local look = ModelGenerator.lookFor(typeName)
	local scale = look.scale
	local dark = row.color:Lerp(Color3.new(0, 0, 0), 0.72)

	-- The collider scales with the silhouette. A Swarmer drawn at 0.62 around a
	-- full size root is a small thing you bump into from a stud and a half away,
	-- which reads as the hit detection being broken rather than as the enemy
	-- being small.
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1) * scale
	root.Transparency = 1
	root.CanQuery = false
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model

	-- R6 wants a part called Torso and the Humanoid is happier having one. It
	-- carries no geometry: it is the frame the skin is animated against.
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1) * scale
	torso.Transparency = 1
	torso.CanCollide = false
	torso.CanTouch = false
	torso.CanQuery = false
	torso.Massless = true
	torso.Parent = model

	local head = skinPart(model, "Head", sizeOf(look.head, scale), dark, 0, Enum.Material.SmoothPlastic)
	joint(root, root, torso, "RootJoint", CFrame.new())
	joint(torso, torso, head, "Neck", CFrame.new(0, look.headOffset * scale, 0))

	if look.hood ~= 0 then
		local hood = skinPart(model, "Hood", sizeOf(look.hood, scale), row.color, look.hoodTransparency)
		joint(torso, torso, hood, "HoodJoint", CFrame.new(0, look.hoodOffset * scale, 0.06 * scale))
	end
	if look.core ~= 0 then
		local core = skinPart(model, "Core", sizeOf(look.core, scale), row.color, 0)
		joint(torso, torso, core, "CoreJoint", CFrame.new(look.coreOffset * scale))
	end
	if look.hands ~= 0 then
		local size = sizeOf(look.hands, scale)
		for _, side in ipairs({ -1, 1 }) do
			local name = side < 0 and "HandLeft" or "HandRight"
			local hand = skinPart(model, name, size, row.color, 0.12)
			local c0 = CFrame.new(side * look.handSpread * scale, look.handHeight * scale, -0.28 * scale)
			joint(torso, torso, hand, name .. "Joint", c0)
		end
	end

	-- Tracked as the rig is built and spent on HipHeight at the end, so a type
	-- that grows a longer tail floats higher to suit instead of dragging it
	-- through the slab. Hand tuned hover per type is a number somebody edits a
	-- tail without, and the failure is silent: the enemy looks fine standing still
	-- and scrapes the floor on the down beat of every bob.
	local lowestSkin = 0

	-- Transparency climbs down the chain so the last segment reads as smoke rather
	-- than as a part, however many segments a type asked for.
	local trailing = head
	for index, segment in ipairs(look.tail) do
		local fade = 0.45 + 0.33 * ((index - 1) / math.max(#look.tail - 1, 1))
		local size = sizeOf(segment.size, scale)
		local part = skinPart(model, "Tail" .. index, size, row.color, fade)
		joint(torso, torso, part, "Tail" .. index .. "Joint", CFrame.new(0, segment.y * scale, 0))
		lowestSkin = math.min(lowestSkin, segment.y * scale - size.Y / 2)
		trailing = part
	end

	-- One radial ring, drawn upward as a crown or downward as tendrils depending
	-- on the sign of `height`. The Sentry and the Lurker are the same code.
	if look.crown then
		local crown = look.crown
		local size = sizeOf(crown.size, scale)
		for index = 1, crown.count do
			local angle = (index - 1) / crown.count * math.pi * 2
			local part = skinPart(model, "Crown" .. index, size, row.color, 0.1)
			local c0 = CFrame.new(
				math.sin(angle) * crown.radius * scale,
				crown.height * scale,
				math.cos(angle) * crown.radius * scale
			) * CFrame.Angles(math.cos(angle) * crown.tilt, 0, -math.sin(angle) * crown.tilt)
			joint(torso, torso, part, "Crown" .. index .. "Joint", c0)
		end
		lowestSkin = math.min(lowestSkin, crown.height * scale - size.Y / 2)
	end

	-- Symmetric pairs. Plates sit at the shoulders, horns sweep off the brow; both
	-- are rigid and ride whatever the torso is doing.
	--
	-- The order matters: anchor at the mount point, orient, then push out along
	-- the part's own axis by `forward`. Offsetting before rotating leaves a 1.9
	-- stud horn centred on the brow, which is half a horn poking backward out of
	-- the head.
	local function symmetricPair(spec, name)
		local size = sizeOf(spec.size, scale)
		local tilt = spec.tilt or 0
		for _, side in ipairs({ -1, 1 }) do
			local partName = name .. (side < 0 and "Left" or "Right")
			local part = skinPart(model, partName, size, row.color, 0.05)
			local c0 = CFrame.new(side * spec.spread * scale, spec.height * scale, -0.1 * scale)
				* CFrame.Angles(tilt, 0, side * 0.12)
				* CFrame.new(0, 0, -(spec.forward or 0) * scale)
			joint(torso, torso, part, partName .. "Joint", c0)
		end
	end
	if look.plates then
		symmetricPair(look.plates, "Plate")
	end
	if look.horns then
		symmetricPair(look.horns, "Horn")
	end

	-- Satellites, orbited in the animation loop. Parented to the torso rather than
	-- the head so they keep their circle while the head tracks the player.
	if look.motes then
		local motes = look.motes
		local size = sizeOf(motes.size, scale)
		for index = 1, motes.count do
			local part = skinPart(model, "Mote" .. index, size, row.color, 0.05)
			-- Seeded onto the ring rather than at the origin, so the first frame
			-- before Heartbeat takes over is not three motes stacked in the chest.
			local angle = (index - 1) / motes.count * math.pi * 2
			local c0 = CFrame.new(
				math.sin(angle) * motes.radius * scale,
				motes.height * scale,
				math.cos(angle) * motes.radius * scale
			)
			joint(torso, torso, part, "Mote" .. index .. "Joint", c0)
		end
	end

	-- Eyes are most of what "a real rig" was going to buy: a blank ball is
	-- scenery, the same ball with eyes is looking at you. Laid out in a row and
	-- centred, so one is a cyclops and four are a thing that is not a person.
	-- Front is -Z. Welded rather than jointed: they belong to the head.
	for index = 1, look.eyeCount do
		local offset = (index - (look.eyeCount + 1) / 2) * look.eyeSpread * 2 * scale
		local eye =
			skinPart(model, "Eye" .. index, sizeOf(look.eyeSize, scale), juice.EnemyEyeColor, 0, Enum.Material.Neon)
		eye.CFrame = head.CFrame * CFrame.new(offset, look.eyeHeight * scale, -look.eyeDepth * scale)
		weld(head, eye)
	end

	local wisp = Instance.new("ParticleEmitter")
	wisp.Name = "Wisp"
	wisp.Texture = juice.EnemyWispTexture
	wisp.Rate = juice.EnemyWispRate
	wisp.Lifetime = NumberRange.new(0.7, 1.3)
	wisp.Speed = NumberRange.new(0.4, 1.1)
	wisp.SpreadAngle = Vector2.new(28, 28)
	wisp.Color = ColorSequence.new(row.color)
	wisp.LightEmission = 0.6
	wisp.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	wisp.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	wisp.Acceleration = Vector3.new(0, -2, 0)
	-- The lowest part the type actually has. A Sentry has no tail at all, and a
	-- wisp emitter on a destroyed reference is an error at build time.
	wisp.Parent = trailing

	-- Parented last, so it finds a complete rig and picks up the root part on its
	-- first pass rather than on a later one.
	--
	-- Hover is whichever is greater: the type's own resting height, or enough to
	-- keep the lowest thing hanging off it clear of the slab at the bottom of the
	-- bob. The bob is the part that is easy to forget, and it is worth 0.42 studs
	-- times bobScale on every frame.
	local swing = juice.EnemyBobHeight * look.bobScale
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.HipHeight = math.max(look.hover * scale, -lowestSkin + swing + FLOOR_MARGIN)
	humanoid.Parent = model

	model.PrimaryPart = root
	model:SetAttribute("EnemyType", typeName)

	return model
end

-- The joints and their as-built C0s, read back off a rig that build made or off
-- a clone of one. Nil for anything that is not one of ours, which is how a
-- hand-made rig from ServerStorage/Enemies skips joint animation: it has its own
-- look and its own idea of how it moves, and nothing here should be driving it.
--
-- The bases are read here rather than captured at build time so that a clone
-- carries its own, which matters because the animation loop writes C0 every
-- frame and a base captured off the template would be whatever the last frame
-- of some other enemy left behind.
function ModelGenerator.rigOf(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	local torso = model:FindFirstChild("Torso")
	if not root or not torso then
		return nil
	end

	local rootJoint = root:FindFirstChild("RootJoint")
	local neck = torso:FindFirstChild("Neck")
	if not rootJoint or not neck then
		return nil
	end

	local joints = {
		root = rootJoint,
		neck = neck,
		hood = torso:FindFirstChild("HoodJoint"),
		core = torso:FindFirstChild("CoreJoint"),
		handL = torso:FindFirstChild("HandLeftJoint"),
		handR = torso:FindFirstChild("HandRightJoint"),
		tails = {},
		crown = {},
		motes = {},
		rigid = {},
	}

	-- Counted up from 1 rather than read off GetChildren, because child order is
	-- not build order and a tail animated out of sequence swings from the wrong
	-- end.
	local function collect(list, prefix)
		local index = 1
		local motor = torso:FindFirstChild(prefix .. index .. "Joint")
		while motor do
			list[index] = motor
			index = index + 1
			motor = torso:FindFirstChild(prefix .. index .. "Joint")
		end
	end
	collect(joints.tails, "Tail")
	collect(joints.crown, "Crown")
	collect(joints.motes, "Mote")
	for _, name in ipairs(RIGID_NAMES) do
		local motor = torso:FindFirstChild(name .. "Joint")
		if motor then
			table.insert(joints.rigid, motor)
		end
	end

	local bases = {
		neck = neck.C0,
		hood = joints.hood and joints.hood.C0,
		core = joints.core and joints.core.C0,
		handL = joints.handL and joints.handL.C0,
		handR = joints.handR and joints.handR.C0,
		tails = {},
		crown = {},
	}
	for index, motor in ipairs(joints.tails) do
		bases.tails[index] = motor.C0
	end
	for index, motor in ipairs(joints.crown) do
		bases.crown[index] = motor.C0
	end

	return { joints = joints, bases = bases, look = ModelGenerator.lookFor(model:GetAttribute("EnemyType")) }
end

-- Recorded when a rig goes live so hiding a Lurker and revealing it again returns
-- each part to the transparency it was authored with, hand-made rig or shade.
function ModelGenerator.readSkin(model)
	local skin = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			table.insert(skin, { part = part, transparency = part.Transparency, color = part.Color })
		end
	end
	return skin
end

-- Builds one template per type into a GeneratedEnemyModels folder under `parent`,
-- replacing whatever was there. `parent` is an argument rather than ServerStorage
-- so this module stays callable from a client.
--
-- Idempotent by replacement rather than by patching: a recipe edit changes which
-- parts a rig has, so updating one in place means diffing two part trees, and
-- rebuilding twenty models costs a few hundred instances once at startup.
-- Clones already handed out are untouched, being clones.
function ModelGenerator.ensureTemplates(parent)
	local folder = parent:FindFirstChild("GeneratedEnemyModels")
	if folder then
		folder:ClearAllChildren()
	else
		folder = Instance.new("Folder")
		folder.Name = "GeneratedEnemyModels"
		folder.Parent = parent
	end
	for typeName in pairs(EnemyDefinitions.types) do
		local model = ModelGenerator.build(typeName)
		model.Parent = folder
	end
	return folder
end

return ModelGenerator
