-- EnemyService (Script) -> ServerScriptService
-- Spawns one enemy per EnemySpawn marker that somebody is standing near. Enemy
-- type comes from the marker's EnemyType attribute (set by building style)
-- unless the section overrides it.
--
-- Drop your own rigs in ServerStorage/Enemies/<TypeName>. If a rig is missing a
-- procedural shade is used, so the game is fully playable from a cold rojo
-- build. An artist rig keeps its own look and skips the joint animation below;
-- everything about how it behaves is identical.
--
-- Three things here are worth knowing before changing any of it.
--
-- A rig is transient, its marker is not. Generation tags 180 markers per
-- section and they live forever; the rig is built when a player comes within
-- Config.EnemySpawnRange and torn down past Config.EnemyDespawnRange. The old
-- service built all 180 at world build time and gated only the pathfinding, so
-- a two-section city carried 360 idle Humanoid state machines and the server
-- had no frame left to move the handful that mattered.
--
-- Nothing ever blocks on MoveToFinished. MoveTo carries an eight second
-- internal timeout, so waiting on it meant an enemy that clipped a corner stood
-- still for eight seconds with its replan check sitting unreachable underneath.
-- The think loop re-issues MoveTo every tick and decides arrival itself.
--
-- Behaviour is per type, selected by profile.behavior. Six types separated only
-- by a stud of walkSpeed is one enemy wearing six colours.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))

-- Enemies do not collide with each other. Three of them meeting in a corridor
-- used to wedge into a shoving match none of them could path out of, which was
-- most of what "they just stand there" turned out to be. They still collide
-- with everything else, so nothing about containment changes: the maze walls
-- are in their own group and this one is not made non-collidable with it.
local ENEMY_GROUP = "Enemy"
local function ensureCollisionGroup(name)
	for _, group in ipairs(PhysicsService:GetRegisteredCollisionGroups()) do
		if group.name == name then
			return
		end
	end
	PhysicsService:RegisterCollisionGroup(name)
end
ensureCollisionGroup(ENEMY_GROUP)
PhysicsService:CollisionGroupSetCollidable(ENEMY_GROUP, ENEMY_GROUP, false)

-- Loop mechanics. Gameplay-facing numbers live in MazeConfig; these are the
-- shape of the update itself and mean nothing to a designer.
local THINK_INTERVAL = 0.12
local SCAN_INTERVAL = 0.5

-- How stale a plan may get. Both matter: the timer covers a moving wall closing
-- across a path that was clear when it was drawn, the drift covers the player
-- rounding a corner, and neither alone caught both.
local REPLAN_SECONDS = 0.7
local REPLAN_DRIFT = 8
local WAYPOINT_REACHED = 4

-- Stuck means "supposed to be moving and did not". The give-up count ends in a
-- teleport home, which is ugly and almost never reached, but an enemy welded
-- into a corner for the rest of the session is worse and is what used to happen.
local STUCK_EPSILON = 1.5
local STUCK_SECONDS = 0.9
local STUCK_GIVE_UP = 4

-- Once acquired, a target is held to a slightly wider leash than it took to
-- acquire, so a player standing on the boundary is not picked up and dropped
-- several times a second.
local TARGET_RETAIN = 1.25

local SEARCH_SECONDS = 3.5
local HOME_RADIUS = 5
-- Spawn markers sit at cell centres and CELL is 25, so a wander this tight
-- cannot cross a wall and needs no pathfinding to stay honest.
local IDLE_WANDER_RADIUS = 8
local IDLE_WANDER_MIN = 2.5
local IDLE_WANDER_MAX = 5.5

local PACK_ALERT_SECONDS = 6
local PACK_ALERT_LEASH = 1.6

local CHARGE_WINDUP = 0.45
local CHARGE_SECONDS = 1.6
local CHARGE_RECOVER = 0.8
local CHARGE_STALL_SPEED = 4

local AMBUSH_REHIDE_SECONDS = 6

local enemyFolder = ServerStorage:FindFirstChild("Enemies")

local liveFolder = workspace:FindFirstChild("LiveEnemies")
if not liveFolder then
	liveFolder = Instance.new("Folder")
	liveFolder.Name = "LiveEnemies"
	liveFolder.Parent = workspace
end

-- marker -> entry, and the set of every marker whether or not it holds one.
local live = {}
local markers = {}
local deadUntil = {}

-- ============================================================
-- The rig
-- ============================================================
-- A hovering shade: a translucent hood around a dark head with lit eyes, an
-- ember at the chest, hands with no arms between them, and tapering segments
-- trailing into smoke. No legs anywhere, which is the point. A walk cycle needs
-- art or a skeleton and foot-slides without both, and the rig before this one
-- was a box with a ball on it precisely because neither was available.
--
-- The shape is a recipe, not a hardcoded body. DEFAULT_LOOK below is the whole
-- baseline and each profile's `look` is merged over it, so the six types differ
-- by silhouette rather than by tint: they used to be one rig in six colours,
-- which at corridor distance is one rig. Optional groups (crown, horns, plates,
-- motes) are absent unless a type asks for them, and any size of 0 leaves that
-- part off entirely.
--
-- Everything cosmetic hangs off Motor6Ds rather than welds so one Heartbeat
-- loop can animate it. Structure and skin stay separate: the Humanoid drives an
-- invisible root and torso, the skin never touches physics.

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

-- Shallow on purpose. The nested tables (tail, crown, motes) are replaced whole
-- rather than merged key by key, because a type that overrides its tail means a
-- different tail and not a three-segment one with the first entry edited.
local function resolveLook(profile)
	local look = table.clone(DEFAULT_LOOK)
	for key, value in pairs(profile.look or {}) do
		look[key] = value
	end
	return look
end

-- A size is a number for a sphere or a Vector3 for an ellipsoid, which is what
-- keeps the profile tables short: most parts are round and say so in one number.
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
-- Vector3 in a profile is the shape it draws.
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

local function makeShade(enemyType)
	local profile = Config.getProfile(enemyType)
	local juice = Config.Juice
	local model = Instance.new("Model")
	model.Name = enemyType

	local look = resolveLook(profile)
	local scale = look.scale
	local dark = profile.color:Lerp(Color3.new(0, 0, 0), 0.72)

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
	root.CollisionGroup = ENEMY_GROUP
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
	local joints = {
		root = joint(root, root, torso, "RootJoint", CFrame.new()),
		neck = joint(torso, torso, head, "Neck", CFrame.new(0, look.headOffset * scale, 0)),
		tails = {},
		crown = {},
		motes = {},
		rigid = {},
	}

	if look.hood ~= 0 then
		local hood = skinPart(model, "Hood", sizeOf(look.hood, scale), profile.color, look.hoodTransparency)
		joints.hood = joint(torso, torso, hood, "HoodJoint", CFrame.new(0, look.hoodOffset * scale, 0.06 * scale))
	end
	if look.core ~= 0 then
		local core = skinPart(model, "Core", sizeOf(look.core, scale), profile.color, 0)
		joints.core = joint(torso, torso, core, "CoreJoint", CFrame.new(look.coreOffset * scale))
	end
	if look.hands ~= 0 then
		local size = sizeOf(look.hands, scale)
		for _, side in ipairs({ -1, 1 }) do
			local name = side < 0 and "HandLeft" or "HandRight"
			local hand = skinPart(model, name, size, profile.color, 0.12)
			local c0 = CFrame.new(side * look.handSpread * scale, look.handHeight * scale, -0.28 * scale)
			local motor = joint(torso, torso, hand, name .. "Joint", c0)
			if side < 0 then
				joints.handL = motor
			else
				joints.handR = motor
			end
		end
	end

	-- Tracked as the rig is built and spent on HipHeight at the end, so a type
	-- that grows a longer tail floats higher to suit instead of dragging it
	-- through the slab. Hand tuned hover per type is a number somebody edits a
	-- tail without, and the failure is silent: the enemy looks fine standing
	-- still and scrapes the floor on the down beat of every bob.
	local lowestSkin = 0

	-- Transparency climbs down the chain so the last segment reads as smoke
	-- rather than as a part, however many segments a type asked for.
	local trailing = head
	for index, segment in ipairs(look.tail) do
		local fade = 0.45 + 0.33 * ((index - 1) / math.max(#look.tail - 1, 1))
		local size = sizeOf(segment.size, scale)
		local part = skinPart(model, "Tail" .. index, size, profile.color, fade)
		table.insert(
			joints.tails,
			joint(torso, torso, part, "Tail" .. index .. "Joint", CFrame.new(0, segment.y * scale, 0))
		)
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
			local part = skinPart(model, "Crown" .. index, size, profile.color, 0.1)
			local c0 = CFrame.new(
				math.sin(angle) * crown.radius * scale,
				crown.height * scale,
				math.cos(angle) * crown.radius * scale
			) * CFrame.Angles(math.cos(angle) * crown.tilt, 0, -math.sin(angle) * crown.tilt)
			table.insert(joints.crown, joint(torso, torso, part, "Crown" .. index .. "Joint", c0))
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
			local part = skinPart(model, partName, size, profile.color, 0.05)
			local c0 = CFrame.new(side * spec.spread * scale, spec.height * scale, -0.1 * scale)
				* CFrame.Angles(tilt, 0, side * 0.12)
				* CFrame.new(0, 0, -(spec.forward or 0) * scale)
			table.insert(joints.rigid, joint(torso, torso, part, partName .. "Joint", c0))
		end
	end
	if look.plates then
		symmetricPair(look.plates, "Plate")
	end
	if look.horns then
		symmetricPair(look.horns, "Horn")
	end

	-- Satellites, orbited in the animation loop. Parented to the torso rather
	-- than the head so they keep their circle while the head tracks the player.
	if look.motes then
		local motes = look.motes
		local size = sizeOf(motes.size, scale)
		for index = 1, motes.count do
			local part = skinPart(model, "Mote" .. index, size, profile.color, 0.05)
			-- Seeded onto the ring rather than at the origin, so the first frame
			-- before Heartbeat takes over is not three motes stacked in the chest.
			local angle = (index - 1) / motes.count * math.pi * 2
			local c0 = CFrame.new(
				math.sin(angle) * motes.radius * scale,
				motes.height * scale,
				math.cos(angle) * motes.radius * scale
			)
			table.insert(joints.motes, joint(torso, torso, part, "Mote" .. index .. "Joint", c0))
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
	wisp.Color = ColorSequence.new(profile.color)
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
	local swing = Config.Juice.EnemyBobHeight * look.bobScale
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.HipHeight = math.max(look.hover * scale, -lowestSkin + swing + FLOOR_MARGIN)
	humanoid.Parent = model

	model.PrimaryPart = root

	-- Base C0s captured here rather than rebuilt by the caller, because only this
	-- function knows which optional groups a type ended up with.
	local bases = {
		neck = joints.neck.C0,
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

	return model, { joints = joints, bases = bases, look = look }
end

local function templateFor(enemyType)
	if enemyFolder then
		local template = enemyFolder:FindFirstChild(enemyType)
		if template and template:IsA("Model") then
			return template:Clone(), nil
		end
	end
	return makeShade(enemyType)
end

-- Recorded at build time so hiding a Lurker and revealing it again returns each
-- part to the transparency it was authored with, artist rig or shade.
local function readSkin(model)
	local skin = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			table.insert(skin, { part = part, transparency = part.Transparency, color = part.Color })
		end
	end
	return skin
end

-- ============================================================
-- Sensing
-- ============================================================

-- The Ghost powerup. PickupService sets Unseen on the character and clears it
-- when the effect ends, so "invisible to enemies" costs one attribute read here
-- and nothing anywhere else. It is deliberately not walk-through-walls: in a
-- game with no combat, not being chased is the whole of what a ghost needs to
-- be, and it cannot strand a player outside the maze.
local function isVisible(char, hum)
	return hum ~= nil and hum.Health > 0 and not char:GetAttribute("Unseen")
end

-- The Freeze powerup, stored as a deadline rather than a flag so two players
-- freezing overlapping crowds extend the thaw instead of ending it early.
local function frozen()
	local until_ = workspace:GetAttribute("EnemyFreezeUntil")
	return until_ ~= nil and os.clock() < until_
end

-- One shared RaycastParams rewritten per call. Safe for the same reason
-- PickupService's taken guard is: nothing between writing the filter and firing
-- the ray yields, so no other enemy's think loop can interleave and read a
-- filter meant for somebody else. RespectCanCollide keeps coins and triggers,
-- which are all CanCollide false, out of the answer.
local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.RespectCanCollide = true

local function hasLineOfSight(from, toPart)
	local char = toPart.Parent
	local filter = { liveFolder, char }
	local pets = workspace:FindFirstChild("LivePets")
	if pets then
		table.insert(filter, pets)
	end
	losParams.FilterDescendantsInstances = filter

	local delta = toPart.Position - from
	local hit = workspace:Raycast(from, delta, losParams)
	return hit == nil
end

-- Leash is measured from the marker, never from the enemy. Measuring from the
-- enemy let a chase drag the whole floor along behind the player one enemy at a
-- time and meant leaving somewhere never actually shook anything off. From the
-- marker, an enemy owns a patch of maze and the player can leave it.
local function nearestTarget(entry)
	local profile = entry.profile
	local leash = profile.leash
	if entry.target then
		leash = leash * TARGET_RETAIN
	end
	if entry.alertUntil and os.clock() < entry.alertUntil then
		leash = leash * PACK_ALERT_LEASH
	end

	local best, bestDist = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hum and isVisible(char, hum) then
			if math.abs(hrp.Position.Y - entry.homeY) < Config.EnemyFloorBand then
				local d = (hrp.Position - entry.home).Magnitude
				if d <= leash and d < bestDist then
					best, bestDist = hrp, d
				end
			end
		end
	end
	return best
end

local function isWatched(entry, hrp)
	local toEnemy = entry.root.Position - hrp.Position
	if toEnemy.Magnitude < 1 then
		return true
	end
	return hrp.CFrame.LookVector:Dot(toEnemy.Unit) > 0.45
end

-- ============================================================
-- Presentation
-- ============================================================

local function playOnce(root, soundId, volume, pitch)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.PlaybackSpeed = pitch or 1
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.RollOffMaxDistance = Config.Juice.EnemyGrowlRange
	sound.Parent = root
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	task.delay(4, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

-- Repaints the skin for the length of the windup and puts the original colours
-- back. Reading them off the recorded skin rather than off the parts means a
-- second flash landing inside the first cannot make the first one's restore
-- write the flash colour back permanently, which is a thing that could happen
-- when the colours were sampled live. Eyes are excluded so there is still
-- something legible on a rig that has gone entirely red.
local function flashRig(entry, seconds)
	if entry.flashing then
		return
	end
	entry.flashing = true
	for _, item in ipairs(entry.skin) do
		if not string.find(item.part.Name, "Eye") then
			item.part.Color = Config.Juice.EnemyTellColor
		end
	end
	task.delay(seconds, function()
		entry.flashing = false
		if not entry.alive then
			return
		end
		for _, item in ipairs(entry.skin) do
			if item.part.Parent then
				item.part.Color = item.color
			end
		end
	end)
end

local function setHidden(entry, hidden)
	entry.hidden = hidden
	for _, item in ipairs(entry.skin) do
		if item.part.Parent then
			local base = item.transparency
			item.part.Transparency = hidden and math.max(base, Config.Juice.EnemyLurkerHiddenTransparency) or base
		end
	end
	local wisp = entry.model:FindFirstChild("Wisp", true)
	if wisp then
		wisp.Enabled = not hidden
	end
end

-- ============================================================
-- Movement
-- ============================================================

local function stopMoving(entry)
	entry.humanoid.WalkSpeed = 0
	entry.humanoid:MoveTo(entry.root.Position)
	entry.waypoints = nil
end

local function goHomeNow(entry)
	entry.model:PivotTo(CFrame.new(entry.home))
	entry.waypoints = nil
	entry.target = nil
	entry.lastSeen = nil
	entry.stuckCount = 0
	entry.state = "Idle"
end

local function repath(entry, goal)
	local ok = pcall(function()
		entry.path:ComputeAsync(entry.root.Position, goal)
	end)
	entry.replanAt = os.clock() + REPLAN_SECONDS
	entry.blocked = false
	if ok and entry.path.Status == Enum.PathStatus.Success then
		entry.waypoints = entry.path:GetWaypoints()
		entry.wpIndex = 2
		entry.plannedFor = goal
		return true
	end
	entry.waypoints = nil
	return false
end

-- One step of "walk toward goal". Returns true while there is still a plan to
-- follow. Nothing here yields and nothing waits on MoveToFinished: arrival is a
-- distance test on the horizontal plane, because a waypoint's Y sits on the
-- navmesh and the enemy's sits at HipHeight above it.
local function follow(entry, goal)
	local now = os.clock()
	local needPlan = entry.waypoints == nil
		or entry.blocked
		or now >= (entry.replanAt or 0)
		or (entry.plannedFor and (goal - entry.plannedFor).Magnitude > REPLAN_DRIFT)

	if needPlan and not repath(entry, goal) then
		-- No route. Face the goal and hold rather than walking the straight line
		-- into whatever wall is in the way, which is what the old fallback did
		-- and what made a blocked enemy look brain dead instead of blocked.
		entry.humanoid:MoveTo(entry.root.Position)
		return false
	end

	local waypoints = entry.waypoints
	if not waypoints then
		return false
	end

	while entry.wpIndex <= #waypoints do
		local point = waypoints[entry.wpIndex].Position
		local flat = Vector3.new(point.X - entry.root.Position.X, 0, point.Z - entry.root.Position.Z)
		if flat.Magnitude > WAYPOINT_REACHED then
			entry.humanoid:MoveTo(point)
			return true
		end
		entry.wpIndex = entry.wpIndex + 1
	end

	entry.waypoints = nil
	entry.humanoid:MoveTo(goal)
	return true
end

local function checkStuck(entry)
	local now = os.clock()
	local moved = (entry.root.Position - entry.stuckPos).Magnitude
	if moved > STUCK_EPSILON then
		entry.stuckPos = entry.root.Position
		entry.stuckAt = now
		entry.stuckCount = 0
		return
	end
	if now - entry.stuckAt < STUCK_SECONDS then
		return
	end

	entry.stuckAt = now
	entry.stuckCount = entry.stuckCount + 1
	entry.waypoints = nil
	entry.humanoid.Jump = true
	if entry.stuckCount >= STUCK_GIVE_UP then
		goHomeNow(entry)
	end
end

-- ============================================================
-- Attacking
-- ============================================================

local function tryAttack(entry, char, targetHum)
	local now = os.clock()
	if entry.windingUp or now - entry.lastAttack < entry.profile.attackCooldown then
		return
	end
	-- Both powerups have to hold here as well as in the think loop, or an enemy
	-- the player walked into while it was frozen, or while they were unseen,
	-- still hits them and the powerup reads as broken.
	if frozen() or not isVisible(char, targetHum) then
		return
	end
	if entry.hidden then
		return
	end

	entry.windingUp = true
	entry.lastAttack = now
	flashRig(entry, Config.Juice.EnemyTellSeconds)

	task.delay(Config.Juice.EnemyTellSeconds, function()
		entry.windingUp = false
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp or targetHum.Health <= 0 or not entry.alive then
			return
		end
		-- Damage is delayed by the length of the flash and only lands if the
		-- player is still within reach when it ends, so a hit is something they
		-- saw coming and could still walk out of.
		if (hrp.Position - entry.root.Position).Magnitude <= Config.Juice.EnemyTellReach then
			targetHum:TakeDamage(entry.profile.damage)
		end
	end)
end

-- ============================================================
-- Behaviours
-- ============================================================

local function alertPack(entry, target)
	local radius = entry.profile.packRadius or 0
	local deadline = os.clock() + PACK_ALERT_SECONDS
	for _, other in pairs(live) do
		if other ~= entry and other.alive and other.profile.behavior == "Pack" then
			if
				math.abs(other.homeY - entry.homeY) < Config.EnemyFloorBand
				and (other.home - entry.home).Magnitude <= radius
			then
				other.alertUntil = deadline
				-- searchUntil as well as lastSeen, or the alerted Swarmer clears
				-- the position on its very next tick without ever walking to it:
				-- the search branch is what consumes lastSeen, and it is gated on
				-- searchUntil. The inflated leash then lets it pick the player up
				-- for itself on the way over.
				other.lastSeen = target.Position
				other.searchUntil = deadline
			end
		end
	end
end

-- Walk speed for this tick. Stalk is the only type that changes it from moment
-- to moment; Charge owns the humanoid outright while it is running and never
-- reaches here.
local function chaseSpeed(entry, target)
	local profile = entry.profile
	if profile.behavior == "Stalk" then
		if isWatched(entry, target) then
			return profile.walkSpeed
		end
		return profile.unwatchedSpeed
	end
	return profile.walkSpeed
end

local function canCharge(entry, target)
	local profile = entry.profile
	if os.clock() < (entry.chargeReadyAt or 0) then
		return false
	end
	local delta = target.Position - entry.root.Position
	local flat = Vector3.new(delta.X, 0, delta.Z)
	if flat.Magnitude < 18 or flat.Magnitude > profile.chargeRange then
		return false
	end
	return hasLineOfSight(entry.root.Position + Vector3.new(0, 1, 0), target)
end

-- Windup, sprint, recover. The windup yields, which is fine: the think loop is
-- a wait-driven thread and the tick after this one simply starts later.
local function beginCharge(entry, target)
	local profile = entry.profile
	entry.state = "Charging"
	entry.chargeReadyAt = os.clock() + profile.chargeCooldown

	stopMoving(entry)
	flashRig(entry, CHARGE_WINDUP)
	playOnce(entry.root, Config.Sounds.EnemyCharge, Config.Juice.EnemyChargeVolume, 0.55)

	local aim = target.Position
	local delta = Vector3.new(aim.X - entry.root.Position.X, 0, aim.Z - entry.root.Position.Z)
	if delta.Magnitude < 0.1 then
		entry.state = "Chase"
		return
	end
	entry.root.CFrame = CFrame.lookAt(entry.root.Position, entry.root.Position + delta.Unit)

	task.wait(CHARGE_WINDUP)
	if not entry.alive then
		return
	end

	-- Locked to the line the player was shown. Re-aiming mid-charge would make
	-- the telegraph a lie and the sidestep pointless, which is the whole of the
	-- interaction this type exists for.
	entry.chargeDir = delta.Unit
	entry.chargeFrom = os.clock()
	entry.chargeUntil = entry.chargeFrom + CHARGE_SECONDS
	entry.humanoid.WalkSpeed = profile.chargeSpeed
	entry.waypoints = nil
end

local function stepCharging(entry)
	local now = os.clock()
	-- Hitting a wall ends the charge early, which is the recovery beat: a
	-- sidestep leaves it eating the corner it was aimed down. The grace before
	-- the stall test is there because it is not moving yet on the first tick.
	local speed = entry.root.AssemblyLinearVelocity.Magnitude
	local stalled = speed < CHARGE_STALL_SPEED and now - entry.chargeFrom > 0.35

	if now >= entry.chargeUntil or stalled then
		entry.state = "Recovering"
		entry.recoverUntil = now + CHARGE_RECOVER
		stopMoving(entry)
		return
	end
	entry.humanoid:MoveTo(entry.root.Position + entry.chargeDir * 24)
end

local function stepIdle(entry)
	local profile = entry.profile
	entry.humanoid.WalkSpeed = profile.walkSpeed

	if profile.behavior ~= "Patrol" then
		stopMoving(entry)
		return
	end

	local now = os.clock()
	if not entry.wanderGoal or now >= (entry.wanderAt or 0) then
		local angle = math.random() * math.pi * 2
		local radius = math.random() * IDLE_WANDER_RADIUS
		entry.wanderGoal = entry.home + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		entry.wanderAt = now + IDLE_WANDER_MIN + math.random() * (IDLE_WANDER_MAX - IDLE_WANDER_MIN)
	end
	entry.humanoid.WalkSpeed = profile.walkSpeed * 0.45
	entry.humanoid:MoveTo(entry.wanderGoal)
end

-- ============================================================
-- The think loop
-- ============================================================

local function acquire(entry, target)
	local hadNone = entry.target == nil
	entry.target = target
	entry.lastSeen = target.Position
	entry.searchUntil = nil

	if hadNone then
		playOnce(entry.root, Config.Sounds.EnemyAlert, Config.Juice.EnemyAlertVolume, 0.8)
		if entry.profile.behavior == "Pack" then
			alertPack(entry, target)
		end
	end
end

local function think(entry)
	local now = os.clock()
	local profile = entry.profile
	local juice = Config.Juice

	if frozen() then
		-- Stopped where it stands, silent, and with the animation held, because a
		-- growl or a bob coming off something that cannot move is the wrong read.
		entry.state = "Frozen"
		entry.frozen = true
		stopMoving(entry)
		entry.growl.Playing = false
		return
	end
	entry.frozen = false

	if entry.state == "Charging" then
		stepCharging(entry)
		checkStuck(entry)
		return
	end
	if entry.state == "Recovering" then
		if now < entry.recoverUntil then
			stopMoving(entry)
			return
		end
		entry.state = "Chase"
	end

	-- Fell down a stairwell, or was shoved off its floor before enemies stopped
	-- colliding with each other. Either way it is no longer where it belongs and
	-- pathing back up a spiral it has no business on is not worth trying.
	if math.abs(entry.root.Position.Y - entry.homeY) > Config.EnemyFloorBand then
		goHomeNow(entry)
		return
	end

	local target = nearestTarget(entry)

	-- A Lurker is scenery until somebody is close enough, and goes back to being
	-- scenery once it has given up and gone home.
	if profile.behavior == "Ambush" and not entry.revealed then
		local close = target
			and (target.Position - entry.root.Position).Magnitude <= profile.ambushRange
			and hasLineOfSight(entry.root.Position + Vector3.new(0, 1, 0), target)
		if close then
			entry.revealed = true
			setHidden(entry, false)
			flashRig(entry, juice.EnemyTellSeconds)
			playOnce(entry.root, Config.Sounds.EnemyAlert, juice.EnemyAlertVolume, 1.25)
		else
			target = nil
		end
	elseif profile.behavior == "Ambush" and not target and entry.state == "Idle" then
		if now >= (entry.rehideAt or 0) then
			entry.revealed = false
			setHidden(entry, true)
		end
	end

	if target then
		acquire(entry, target)
	elseif entry.target then
		entry.target = nil
		entry.searchUntil = now + SEARCH_SECONDS
		entry.rehideAt = now + AMBUSH_REHIDE_SECONDS
	end

	-- Growl tracks whether there is something to growl at, and pitches up as it
	-- closes. Silent otherwise: a city holds thousands of these and a permanent
	-- drone off every one of them is not atmosphere, it is noise.
	if entry.target then
		local closeness = 1 - math.clamp((entry.target.Position - entry.root.Position).Magnitude / profile.leash, 0, 1)
		entry.growl.Playing = true
		entry.growl.PlaybackSpeed = juice.EnemyGrowlPitchFar
			+ (juice.EnemyGrowlPitchNear - juice.EnemyGrowlPitchFar) * closeness
	else
		entry.growl.Playing = false
	end

	if entry.target then
		local hrp = entry.target
		local char = hrp.Parent
		local hum = char and char:FindFirstChildOfClass("Humanoid")

		if profile.behavior == "Charge" and canCharge(entry, hrp) then
			beginCharge(entry, hrp)
			return
		end

		entry.state = "Chase"
		entry.humanoid.WalkSpeed = chaseSpeed(entry, hrp)

		-- Down a straight corridor the path and the straight line are the same
		-- thing, and skipping ComputeAsync there is both cheaper and sharper: an
		-- enemy that has you in view walks at you rather than around the navmesh
		-- corner it planned two ticks ago.
		if hasLineOfSight(entry.root.Position + Vector3.new(0, 1, 0), hrp) then
			entry.humanoid:MoveTo(hrp.Position)
			entry.waypoints = nil
		else
			follow(entry, hrp.Position)
		end

		-- Touched is the zero-latency path and this is the one that cannot be
		-- missed. An enemy standing inside a player fires Touched once and then
		-- never again while neither of them crosses a boundary, which is how a
		-- cornered player used to take no damage at all from something pressed
		-- against them.
		if hum and (hrp.Position - entry.root.Position).Magnitude <= juice.EnemyTellReach * 0.7 then
			tryAttack(entry, char, hum)
		end

		checkStuck(entry)
		return
	end

	if entry.lastSeen and now < (entry.searchUntil or 0) then
		entry.state = "Search"
		entry.humanoid.WalkSpeed = profile.walkSpeed
		local flat = Vector3.new(entry.lastSeen.X - entry.root.Position.X, 0, entry.lastSeen.Z - entry.root.Position.Z)
		if flat.Magnitude > HOME_RADIUS then
			follow(entry, entry.lastSeen)
			checkStuck(entry)
			return
		end
		entry.searchUntil = nil
	end
	entry.lastSeen = nil

	local homeFlat = Vector3.new(entry.home.X - entry.root.Position.X, 0, entry.home.Z - entry.root.Position.Z)
	if homeFlat.Magnitude > HOME_RADIUS + IDLE_WANDER_RADIUS then
		entry.state = "Return"
		entry.humanoid.WalkSpeed = profile.walkSpeed
		follow(entry, entry.home)
		checkStuck(entry)
		return
	end

	entry.state = "Idle"
	-- The stuck window is reset here and not just cleared, because it is only
	-- sampled while moving. Left stale through a long idle, the first tick of the
	-- next chase compares against a position from minutes ago and reads as stuck
	-- immediately, so every enemy jumped on the spot the moment it saw anybody.
	entry.stuckCount = 0
	entry.stuckPos = entry.root.Position
	entry.stuckAt = os.clock()
	stepIdle(entry)
end

-- ============================================================
-- Animation
-- ============================================================

local function animate(entry, dt)
	local anim = entry.anim
	if not anim then
		return
	end
	-- Held while frozen, so a frozen enemy is frozen rather than a frozen enemy
	-- doing its idle bob.
	if entry.frozen then
		return
	end

	local juice = Config.Juice
	local joints, bases, look = anim.joints, anim.bases, anim.look
	entry.animClock = entry.animClock + dt
	-- bobRate and bobScale are the motion half of a type's identity: a Sentry
	-- barely moves at rest and a Swarmer never stops, which is legible further
	-- down a corridor than any of the geometry is.
	local phase = entry.animClock * juice.EnemyBobRate * look.bobRate + entry.phase
	local moving = math.clamp(entry.root.AssemblyLinearVelocity.Magnitude / 16, 0, 1)

	local bob = math.sin(phase) * juice.EnemyBobHeight * look.bobScale * (1 - moving * 0.4)
	joints.root.C0 = CFrame.new(0, bob, 0) * CFrame.Angles(-juice.EnemyLeanAngle * moving, 0, 0)

	-- Hands drift counter-phase to the body, which is what stops the whole rig
	-- reading as one rigid object going up and down.
	local orbit = math.sin(phase + math.pi) * juice.EnemyHandOrbit
	if joints.handL then
		joints.handL.C0 = bases.handL * CFrame.new(0, orbit, -orbit * 0.5)
		joints.handR.C0 = bases.handR * CFrame.new(0, -orbit, -orbit * 0.5)
	end
	if joints.core then
		joints.core.C0 = bases.core * CFrame.new(0, bob * 0.25, 0)
	end
	if joints.hood then
		joints.hood.C0 = bases.hood * CFrame.Angles(0, 0, math.sin(phase * 0.7) * 0.08)
	end

	local tailCount = #joints.tails
	for i, tail in ipairs(joints.tails) do
		local lag = i * 0.55
		local swing = math.sin(phase - lag) * juice.EnemyTailSway * (i / tailCount)
		tail.C0 = CFrame.Angles(0, 0, swing) * CFrame.Angles(swing * 0.4 * moving, 0, 0) * bases.tails[i]
	end

	-- A crown ripples around its ring rather than swaying as one piece, which is
	-- what makes the Lurker's tendrils read as hanging and the Sentry's spikes as
	-- idling rather than as a hat.
	for i, spike in ipairs(joints.crown) do
		local ripple = math.sin(phase * 0.8 - i * 0.9) * 0.12
		spike.C0 = bases.crown[i] * CFrame.Angles(ripple, 0, ripple * 0.5)
	end

	-- Motes orbit on their own clock. Evenly spaced around the ring and bobbing
	-- out of phase with each other, so three of them never line up into one blob.
	if look.motes and #joints.motes > 0 then
		local motes = look.motes
		local spin = entry.animClock * (motes.rate or 1.5)
		for i, mote in ipairs(joints.motes) do
			local angle = spin + (i - 1) / #joints.motes * math.pi * 2
			mote.C0 = CFrame.new(
				math.sin(angle) * motes.radius * look.scale,
				(motes.height + math.sin(phase + i) * 0.3) * look.scale,
				math.cos(angle) * motes.radius * look.scale
			)
		end
	end

	-- The head keeps the player in view independently of which way the body is
	-- walking, so a shade retreating to its post is still watching you go.
	local watching = entry.target
	if watching and watching.Parent then
		local dir = (watching.Position - entry.root.Position)
		if dir.Magnitude > 0.5 then
			local localDir = entry.torso.CFrame:VectorToObjectSpace(dir.Unit)
			local yaw = math.clamp(math.atan2(-localDir.X, -localDir.Z), -juice.EnemyLookYaw, juice.EnemyLookYaw)
			local pitch =
				math.clamp(math.asin(math.clamp(localDir.Y, -1, 1)), -juice.EnemyLookPitch, juice.EnemyLookPitch)
			joints.neck.C0 = bases.neck * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		end
	else
		joints.neck.C0 = bases.neck * CFrame.Angles(0, math.sin(phase * 0.35) * 0.4, 0)
	end
end

RunService.Heartbeat:Connect(function(dt)
	for _, entry in pairs(live) do
		if entry.alive and entry.root.Parent then
			animate(entry, dt)
		end
	end
end)

-- ============================================================
-- Spawning and despawning
-- ============================================================

local function makeGrowl(root)
	local growl = Instance.new("Sound")
	growl.Name = "Growl"
	growl.SoundId = Config.Sounds.EnemyGrowl
	growl.Volume = Config.Juice.EnemyGrowlVolume
	growl.Looped = true
	growl.RollOffMode = Enum.RollOffMode.Linear
	growl.RollOffMinDistance = Config.Juice.EnemyGrowlNearRange
	growl.RollOffMaxDistance = Config.Juice.EnemyGrowlRange
	growl.PlaybackSpeed = Config.Juice.EnemyGrowlPitchFar
	growl.Parent = root
	return growl
end

local function despawn(marker)
	local entry = live[marker]
	if not entry then
		return
	end
	live[marker] = nil
	entry.alive = false
	if entry.blockedConn then
		entry.blockedConn:Disconnect()
	end
	if entry.model.Parent then
		entry.model:Destroy()
	end
end

local function spawnFromMarker(marker)
	if not marker:IsA("BasePart") or live[marker] then
		return
	end

	local section = marker:GetAttribute("Section") or 1
	local level = marker:GetAttribute("Level") or 0
	local enemyType = Config.resolveEnemyType(section, marker:GetAttribute("EnemyType"))
	local profile = Config.getProfile(enemyType)

	local model, anim = templateFor(enemyType)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	local torso = model:FindFirstChild("Torso") or root
	if not humanoid or not root then
		warn("EnemyService: rig for " .. enemyType .. " has no Humanoid or HumanoidRootPart")
		model:Destroy()
		return
	end

	humanoid.MaxHealth = Config.EnemyHealthBase + level * Config.EnemyHealthPerLevel
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = profile.walkSpeed
	-- Nothing damages an enemy, so a health bar over one is a promise the game
	-- does not keep.
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	-- A maze floor is flat and every one of these is a way for a rig to end up
	-- on its side in a corridor with no way back onto its feet.
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.CanCollide then
			part.CollisionGroup = ENEMY_GROUP
		end
	end

	model:PivotTo(marker.CFrame)
	model.Parent = liveFolder
	model:SetAttribute("Section", section)
	model:SetAttribute("Level", level)

	local entry = {
		marker = marker,
		model = model,
		humanoid = humanoid,
		root = root,
		torso = torso,
		anim = anim,
		profile = profile,
		enemyType = enemyType,
		skin = readSkin(model),
		home = marker.Position,
		homeY = marker.Position.Y,
		growl = makeGrowl(root),
		alive = true,
		state = "Idle",
		windingUp = false,
		lastAttack = 0,
		stuckPos = root.Position,
		stuckAt = os.clock(),
		stuckCount = 0,
		animClock = 0,
		-- Runtime randomness, deliberately not seeded off the world seed: this is
		-- the same call PickupService makes when it rolls a powerup. It only has
		-- to stop six shades in a room bobbing in lockstep, and a rig is not part
		-- of what a seed is supposed to reproduce.
		phase = math.random() * math.pi * 2,
	}

	entry.path = PathfindingService:CreatePath({
		AgentRadius = 2.5,
		AgentHeight = 6,
		-- A maze floor is flat. Jump waypoints only ever appeared because the
		-- planner found a lip somewhere, and an enemy hopping down a corridor
		-- reads as a bug. The stuck handler still jumps deliberately.
		AgentCanJump = false,
	})
	-- The engine's own answer to a moving wall closing across a plan that was
	-- clear when it was drawn. The replan timer would catch it too, half a second
	-- later and after the enemy had already walked into it.
	entry.blockedConn = entry.path.Blocked:Connect(function()
		entry.blocked = true
	end)

	if profile.behavior == "Ambush" then
		entry.revealed = false
		setHidden(entry, true)
	end

	root.Touched:Connect(function(hit)
		if not entry.alive then
			return
		end
		local char = hit:FindFirstAncestorOfClass("Model")
		local targetHum = char and char:FindFirstChildOfClass("Humanoid")
		if not targetHum or not Players:GetPlayerFromCharacter(char) then
			return
		end
		tryAttack(entry, char, targetHum)
	end)

	-- Guarded on alive because Destroy fires Died too, and an ordinary walk-away
	-- despawn must not arm the respawn timer: a player who steps off a floor and
	-- comes straight back would find it empty for the next 25 seconds.
	humanoid.Died:Connect(function()
		if not entry.alive then
			return
		end
		deadUntil[marker] = os.clock() + Config.EnemyRespawnSeconds
		despawn(marker)
	end)

	live[marker] = entry

	task.spawn(function()
		while entry.alive and entry.model.Parent do
			-- pcall so one enemy that trips over a destroyed target does not end
			-- its own thread and leave a rig standing there forever, which is
			-- indistinguishable from the stuck bug this file exists to fix.
			local ok, err = pcall(think, entry)
			if not ok then
				warn("EnemyService: think failed for " .. entry.enemyType .. ": " .. tostring(err))
			end
			task.wait(THINK_INTERVAL)
		end
	end)
end

local function trackMarker(marker)
	if marker:IsA("BasePart") then
		markers[marker] = true
	end
end

for _, marker in ipairs(CollectionService:GetTagged("EnemySpawn")) do
	trackMarker(marker)
end
CollectionService:GetInstanceAddedSignal("EnemySpawn"):Connect(trackMarker)
CollectionService:GetInstanceRemovedSignal("EnemySpawn"):Connect(function(marker)
	markers[marker] = nil
	deadUntil[marker] = nil
	despawn(marker)
end)

-- One flat sweep rather than a spatial index. A five section city is about 900
-- markers, so this is 3600 magnitude tests a second at four players, which is
-- nothing next to a single Humanoid. If section count ever grows far enough for
-- that to matter, bucket markers by position here; do not put the cost back
-- into keeping the rigs alive.
local function nearestPlayerDistance(positions, pos)
	local best = math.huge
	for _, p in ipairs(positions) do
		local d = (p - pos).Magnitude
		if d < best then
			best = d
		end
	end
	return best
end

task.spawn(function()
	local positions = {}
	while true do
		task.wait(SCAN_INTERVAL)
		local now = os.clock()

		table.clear(positions)
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hrp and hum and hum.Health > 0 then
				table.insert(positions, hrp.Position)
			end
		end

		for marker in pairs(markers) do
			if not marker.Parent then
				markers[marker] = nil
				despawn(marker)
			elseif not live[marker] and now >= (deadUntil[marker] or 0) then
				if nearestPlayerDistance(positions, marker.Position) <= Config.EnemySpawnRange then
					spawnFromMarker(marker)
				end
			end
		end

		-- Despawn is measured from the rig, not the marker, so an enemy that
		-- chased somebody to the far side of the floor is not deleted mid chase.
		for marker, entry in pairs(live) do
			local gone = not entry.root.Parent
			if gone or nearestPlayerDistance(positions, entry.root.Position) > Config.EnemyDespawnRange then
				despawn(marker)
			end
		end
	end
end)
