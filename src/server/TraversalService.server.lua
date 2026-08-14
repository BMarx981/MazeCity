-- TraversalService (Script) -> ServerScriptService
-- Slide between sections, the roof zipline down to the plaza, and the roof deck
-- bounce pads.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local ZipPath = require(script.Parent:WaitForChild("ZipPath"))

-- Two remotes, the shape every other service here uses: one table argument
-- discriminated by a `kind` field. Updates carries the ride's own numbers out
-- so the client can draw a camera off them without asking for a frame-by-frame
-- feed; Intents carries the one thing the rider decides, which is letting go.
local Updates = Instance.new("RemoteEvent")
Updates.Name = "TraversalUpdate"
Updates.Parent = ReplicatedStorage

local Intents = Instance.new("RemoteEvent")
Intents.Name = "TraversalIntent"
Intents.Parent = ReplicatedStorage

local riding = {}
local bounceCooldown = {}
local bounceCombo = {}
local dismountAt = {}

-- Effects hang off the rider's own character, never off the tagged part that
-- triggered them: those parts live inside workspace.MazeCity, which is generator
-- output and stays exactly as it was built.
local function playOnce(parent, assetId, volume, pitch)
	local sound = Instance.new("Sound")
	sound.SoundId = assetId
	sound.Volume = volume
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, sound.TimeLength > 0 and sound.TimeLength + 1 or 5)
end

local function puffDust(root, count)
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, -2.6, 0)
	attachment.Parent = root

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = Config.Juice.BounceDustTexture
	emitter.Color = ColorSequence.new(Config.Juice.BounceDustColor)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new(1.2, 3.4)
	emitter.Lifetime = NumberRange.new(0.35, 0.6)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(count or Config.Juice.BounceDustParticles)

	Debris:AddItem(attachment, 2)
end

local function playerFrom(hit)
	local char = hit:FindFirstAncestorOfClass("Model")
	if not char then
		return nil, nil, nil
	end
	local player = Players:GetPlayerFromCharacter(char)
	if not player then
		return nil, nil, nil
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	return player, humanoid, root
end

-- Every exit from a ride goes through here, including the failure paths. The
-- zipline anchors the rider and drives their CFrame from a Heartbeat, and an
-- anchored player left in mid-air has no way out on their own, so releasing has
-- to be the one thing that cannot be skipped. Everything the zipline hangs off
-- the character is torn down here for the same reason and not by whichever
-- branch happened to finish: landing, letting go, the safety release and dying
-- are four ways out and there is one door.
local function endRide(player, humanoid, reason)
	local ride = riding[player]
	if not ride then
		return
	end
	riding[player] = nil
	if ride.connection then
		ride.connection:Disconnect()
	end
	if ride.whoosh then
		ride.whoosh:Destroy()
	end
	if ride.tween then
		ride.tween:Cancel()
	end
	if ride.emitter then
		ride.emitter.Rate = 0
	end
	for _, inst in ipairs(ride.effects or {}) do
		-- Given to Debris rather than destroyed outright so a trail already
		-- drawn fades out behind the rider instead of vanishing with them.
		Debris:AddItem(inst, Config.Juice.ZipTrailSeconds + 0.5)
	end
	if ride.root then
		ride.root.Anchored = false
	end
	local hum = humanoid or ride.humanoid
	if hum then
		hum.PlatformStand = false
	end

	if ride.zip then
		if reason == "landed" and ride.root and ride.root.Parent then
			playOnce(ride.root, Config.Sounds.ZipLand, Config.Juice.ZipLandVolume, Config.Juice.ZipLandPitch)
			puffDust(ride.root, Config.Juice.ZipLandDustParticles)
		end
		Updates:FireClient(player, { kind = "zipEnd", reason = reason or "released" })
	end
end

local function bindEntrance(part)
	if not part:IsA("BasePart") then
		return
	end
	part.Touched:Connect(function(hit)
		local player, humanoid, root = playerFrom(hit)
		if not player or not humanoid or not root then
			return
		end
		if riding[player] then
			return
		end

		local whoosh = Instance.new("Sound")
		whoosh.SoundId = Config.Sounds.SlideWhoosh
		whoosh.Volume = Config.Juice.SlideWhooshVolume
		whoosh.Looped = true
		whoosh.Parent = root
		whoosh:Play()

		riding[player] = { startedAt = os.clock(), whoosh = whoosh }
		humanoid.PlatformStand = true
		root.AssemblyLinearVelocity = root.CFrame.LookVector * Config.SlideEntrySpeed

		task.delay(Config.SlideMaxSeconds, function()
			local ride = riding[player]
			if ride and os.clock() - ride.startedAt >= Config.SlideMaxSeconds - 0.1 then
				endRide(player, humanoid)
			end
		end)
	end)
end

local function bindBooster(part)
	if not part:IsA("BasePart") then
		return
	end
	part.Touched:Connect(function(hit)
		local player, _, root = playerFrom(hit)
		if not player or not root or not riding[player] then
			return
		end

		local dir =
			Vector3.new(part:GetAttribute("DirX") or 0, part:GetAttribute("DirY") or 0, part:GetAttribute("DirZ") or 0)
		if dir.Magnitude < 0.01 then
			return
		end

		local speed = part:GetAttribute("Speed") or Config.SlideBoostSpeed
		root.AssemblyLinearVelocity = dir.Unit * speed
	end)
end

local function bindExit(part)
	if not part:IsA("BasePart") then
		return
	end
	part.Touched:Connect(function(hit)
		local player, humanoid = playerFrom(hit)
		if not player then
			return
		end
		-- Reaching an exit pad is landing however you got there, and a zipline
		-- rider can touch the plaza a moment before the curve runs out. A slide
		-- ride has no reason to give, and endRide reads one off zip rides only.
		endRide(player, humanoid, "landed")
	end)
end

local function bindBouncePad(part)
	if not part:IsA("BasePart") then
		return
	end
	part.Touched:Connect(function(hit)
		local player, humanoid, root = playerFrom(hit)
		if not player or not humanoid or not root then
			return
		end

		local now = os.clock()
		local last = bounceCooldown[player] or 0
		if now - last < Config.BouncePadCooldown then
			return
		end

		local arriving = root.AssemblyLinearVelocity

		-- A pad returns a share of the speed it was hit with, so bouncing in place
		-- climbs on its own until the ceiling: land harder, go higher, which is the
		-- one rule a trampoline has to teach and the one it can teach without a
		-- word of text. A standing start has no downward speed and gets the base
		-- launch, which is what the roof coin arc was sized against.
		local base = part:GetAttribute("Power") or Config.BouncePadPower
		local impact = math.max(0, -arriving.Y)
		local power = math.min(Config.BouncePadMaxPower, base + impact * Config.BouncePadMomentumGain)

		local combo = ((now - last < Config.BouncePadComboSeconds) and (bounceCombo[player] or 0) or 0) + 1
		bounceCombo[player] = combo
		bounceCooldown[player] = now

		local horizontal = Config.BouncePadForwardKeep
		local launch = Vector3.new(arriving.X * horizontal, power, arriving.Z * horizontal)

		-- A Humanoid standing on something is in the Running state, and that
		-- state's controller holds the character down: an upward velocity set
		-- underneath it is cancelled within a frame. Handing the state to Jumping
		-- releases that controller. What it does not do is leave the velocity
		-- alone: the Jumping state applies the humanoid's own jump on the next
		-- physics step, which overwrote the pad's launch with a plain JumpPower and
		-- is why the pads still read as an ordinary jump after the ground
		-- controller was dealt with. So the pad sets its velocity twice, once now
		-- and once after that step has been and gone, and drops the humanoid into
		-- Freefall so nothing else is queued up behind it.
		--
		-- The slide does not need any of this because its entrance sets
		-- PlatformStand, which switches the controller off outright. A pad cannot:
		-- the player has to keep control of their character all the way up and back
		-- down, which is most of what makes a pad a toy and a slide a ride.
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		root.AssemblyLinearVelocity = launch

		task.spawn(function()
			RunService.Heartbeat:Wait()
			if root.Parent and humanoid.Parent and humanoid.Health > 0 then
				root.AssemblyLinearVelocity = launch
				humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
			end
		end)

		local pitch = math.min(Config.BouncePadPitchMax, 1 + (combo - 1) * Config.BouncePadPitchStep)
		playOnce(root, Config.Sounds.BouncePad, Config.Juice.BouncePadVolume, pitch)
		puffDust(root)
	end)
end

-- The zipline is carried along the cable rather than hung off physics on a
-- rope. The descent is 195 studs onto a street, and a rider who clips off a
-- physics line halfway down lands wherever the simulation drops them, which on
-- the edge plots is the void between section ground slabs. A carried rider
-- cannot miss.
--
-- It was two tweens, which was right while the cable was a straight line. The
-- cable now wraps the tower and corkscrews about itself, and the ride now has a
-- speed that changes, so the descent is integrated on Heartbeat instead: a
-- tween interpolates between two CFrames and there is no pair of CFrames whose
-- interpolation is this curve. The boarding hop is still a tween, because that
-- one genuinely is a straight line.
--
-- Nothing in here is the shape of the cable. That is ZipPath's, and both this
-- and the generator ask it rather than each having an opinion.
local function zipSpeedAt(seconds)
	return math.min(Config.ZipSpeedMax, Config.ZipSpeedStart + Config.ZipAccel * seconds)
end

local function zipSparks(root)
	local attachment = Instance.new("Attachment")
	-- At the pulley, not at the rider: sparks anywhere else read as the player
	-- being on fire rather than as metal on metal. The pulley is wherever the
	-- cable is, which is ZipHangOffset above the root at the top and closing to
	-- nothing by the pad, so the ride moves this as the hang tapers.
	attachment.Position = Vector3.new(0, Config.ZipHangOffset, 0)
	attachment.Parent = root

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = Config.Juice.ZipSparkTexture
	emitter.Color = ColorSequence.new(Config.Juice.ZipSparkColor)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new(0.6, 0.05)
	emitter.Lifetime = NumberRange.new(0.15, 0.4)
	emitter.Speed = NumberRange.new(4, 14)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Acceleration = Vector3.new(0, -60, 0)
	emitter.Rate = Config.Juice.ZipSparkRateSlow
	emitter.Parent = attachment
	return attachment, emitter
end

local function zipTrail(root)
	local top = Instance.new("Attachment")
	top.Name = "ZipTrailTop"
	top.Position = Vector3.new(0, 1.4, 0)
	top.Parent = root

	local bottom = Instance.new("Attachment")
	bottom.Name = "ZipTrailBottom"
	bottom.Position = Vector3.new(0, -1.4, 0)
	bottom.Parent = root

	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(Config.Juice.ZipTrailColor)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = Config.Juice.ZipTrailSeconds
	trail.LightEmission = 0.6
	trail.Parent = root
	return { top, bottom, trail }
end

local function rideZip(player, humanoid, root, path)
	local whoosh = Instance.new("Sound")
	whoosh.SoundId = Config.Sounds.ZipWhoosh
	whoosh.Volume = Config.Juice.ZipWhooshVolume
	whoosh.Looped = true
	whoosh.Parent = root
	whoosh:Play()

	local sparkAttachment, sparks = zipSparks(root)
	local trailParts = zipTrail(root)

	local ride = {
		startedAt = os.clock(),
		whoosh = whoosh,
		root = root,
		humanoid = humanoid,
		path = path,
		zip = true,
		speed = Config.ZipSpeedStart,
		heading = ZipPath.headingAt(path, 0),
		effects = { sparkAttachment },
		emitter = sparks,
		pulley = sparkAttachment,
	}
	for _, inst in ipairs(trailParts) do
		table.insert(ride.effects, inst)
	end
	riding[player] = ride

	humanoid.PlatformStand = true
	root.Anchored = true

	playOnce(root, Config.Sounds.ZipLaunch, Config.Juice.ZipLaunchVolume, Config.Juice.ZipLaunchPitch)

	-- Hang under the cable rather than on it. The root part is the middle of the
	-- torso, so putting it at the cable's own position ran the line through the
	-- rider's chest lengthwise, which is what read as being impaled. The offset is
	-- applied at the top and not at the bottom, so it tapers away over the ride:
	-- the cable ends four studs above the street and the landing pad is directly
	-- under it, meaning the cable's own end point is already almost exactly where
	-- a standing character's root belongs. Holding the offset all the way down
	-- would instead finish the ride a stud inside the pavement.
	local function riderCFrame(t)
		local point = ZipPath.pointAt(path, t)
		local heading = ZipPath.headingAt(path, t)
		-- Face along the line but stay upright. Aiming the root part down the
		-- heading itself pitched the rider forward by the cable's own slope, and
		-- the corkscrew would now add another twenty degrees of it either way.
		local flat = Vector3.new(heading.X, 0, heading.Z)
		local facing = (flat.Magnitude > 0.01) and flat.Unit or Vector3.new(0, 0, -1)
		local hang = point - Vector3.new(0, Config.ZipHangOffset * (1 - t), 0)
		local roll = math.rad(Config.ZipBankDegrees) * ZipPath.bankAt(path, t)
		return CFrame.lookAt(hang, hang + facing) * CFrame.Angles(0, 0, roll), heading
	end

	local boardCFrame = riderCFrame(0)
	local board = TweenService:Create(
		root,
		TweenInfo.new(Config.ZipBoardSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = boardCFrame }
	)
	ride.tween = board
	board:Play()

	board.Completed:Connect(function(state)
		if riding[player] ~= ride or state ~= Enum.PlaybackState.Completed then
			return
		end
		ride.tween = nil
		ride.boarded = true
		Updates:FireClient(player, {
			kind = "zipStart",
			length = path.length,
			speedStart = Config.ZipSpeedStart,
			speedMax = Config.ZipSpeedMax,
			accel = Config.ZipAccel,
		})

		local travelled = 0
		local descendingSince = os.clock()
		ride.connection = RunService.Heartbeat:Connect(function(dt)
			if riding[player] ~= ride or not root.Parent or humanoid.Health <= 0 then
				endRide(player, humanoid)
				return
			end

			ride.speed = zipSpeedAt(os.clock() - descendingSince)
			travelled = travelled + ride.speed * dt
			local t = math.min(1, travelled / path.length)

			local cf, heading = riderCFrame(t)
			root.CFrame = cf
			ride.heading = heading
			ride.pulley.Position = Vector3.new(0, Config.ZipHangOffset * (1 - t), 0)

			local pace = (ride.speed - Config.ZipSpeedStart) / math.max(1, Config.ZipSpeedMax - Config.ZipSpeedStart)
			whoosh.PlaybackSpeed = Config.Juice.ZipWhooshPitchSlow
				+ (Config.Juice.ZipWhooshPitchFast - Config.Juice.ZipWhooshPitchSlow) * pace
			sparks.Rate = Config.Juice.ZipSparkRateSlow
				+ (Config.Juice.ZipSparkRateFast - Config.Juice.ZipSparkRateSlow) * pace

			if t >= 1 then
				endRide(player, humanoid, "landed")
			end
		end)
	end)

	task.delay(Config.ZipMaxSeconds, function()
		if riding[player] == ride then
			endRide(player, humanoid, "timeout")
		end
	end)
end

-- Letting go. The one thing on a zipline the rider decides, and the reason the
-- wrap is a choice rather than a six-second cutscene: bail over a roof you like
-- the look of, or hold on to the door. It is the bounce pad's problem exactly
-- once removed, so it borrows the bounce pad's fix: unanchoring hands the
-- character back to a Humanoid whose Running controller cancels an upward
-- velocity set underneath it, so the launch is set, the state is pushed to
-- Freefall, and the velocity is set again a step later once the controller has
-- had its say.
local function dismount(player)
	local ride = riding[player]
	if not ride or not ride.zip or not ride.boarded then
		return
	end

	local now = os.clock()
	if now - (dismountAt[player] or 0) < Config.ZipDismountCooldown then
		return
	end
	dismountAt[player] = now

	local root, humanoid = ride.root, ride.humanoid
	local flat = Vector3.new(ride.heading.X, 0, ride.heading.Z)
	local facing = (flat.Magnitude > 0.01) and flat.Unit or Vector3.new(0, 0, -1)
	local launch = facing * ride.speed * Config.ZipDismountKeep + Vector3.new(0, Config.ZipDismountLift, 0)

	endRide(player, humanoid, "dismount")

	if root.Parent and humanoid and humanoid.Health > 0 then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		root.AssemblyLinearVelocity = launch
		task.spawn(function()
			RunService.Heartbeat:Wait()
			if root.Parent and humanoid.Parent and humanoid.Health > 0 then
				root.AssemblyLinearVelocity = launch
				humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
			end
		end)
	end
end

local function bindZipEntrance(part)
	if not part:IsA("BasePart") then
		return
	end

	local path = ZipPath.read(part)
	if not path then
		warn(
			string.format(
				"TraversalService: ZipEntrance %s is missing its Path attributes, so it stays inert",
				part:GetFullName()
			)
		)
		return
	end

	part.Touched:Connect(function(hit)
		local player, humanoid, root = playerFrom(hit)
		if not player or not humanoid or not root then
			return
		end
		if riding[player] then
			return
		end
		rideZip(player, humanoid, root, path)
	end)
end

local binders = {
	SlideEntrance = bindEntrance,
	SlideBooster = bindBooster,
	SlideExit = bindExit,
	BouncePad = bindBouncePad,
	ZipEntrance = bindZipEntrance,
	-- Landing on the pad releases the rider too. The descent normally reaches
	-- the end of the curve first, so this is the belt to that braces. It is also
	-- what catches a rider who let go over the plaza and came down on it.
	ZipExit = bindExit,
}

for tag, binder in pairs(binders) do
	for _, part in ipairs(CollectionService:GetTagged(tag)) do
		binder(part)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(binder)
end

-- The client asks; the server decides. Everything a dismount needs (whether
-- they are riding, whether they have boarded, how fast they were going, which
-- way they were pointing) is already here, so the intent carries no numbers and
-- there is nothing in it to lie about.
Intents.OnServerEvent:Connect(function(player, payload)
	if typeof(payload) ~= "table" then
		return
	end
	if payload.kind == "dismount" then
		dismount(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	endRide(player, nil)
	bounceCooldown[player] = nil
	bounceCombo[player] = nil
	dismountAt[player] = nil
end)
