-- TraversalService (Script) -> ServerScriptService
-- Slide between sections, the roof zipline down to the plaza, and the roof deck
-- bounce pads.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))

local riding = {}
local bounceCooldown = {}

-- Effects hang off the rider's own character, never off the tagged part that
-- triggered them: those parts live inside workspace.MazeCity, which is generator
-- output and stays exactly as it was built.
local function playOnce(parent, assetId, volume)
	local sound = Instance.new("Sound")
	sound.SoundId = assetId
	sound.Volume = volume
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, sound.TimeLength > 0 and sound.TimeLength + 1 or 5)
end

local function puffDust(root)
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
	emitter:Emit(Config.Juice.BounceDustParticles)

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
-- zipline anchors the rider, and an anchored player left in mid-air has no way
-- out on their own, so releasing has to be the one thing that cannot be skipped.
local function endRide(player, humanoid)
	local ride = riding[player]
	if not ride then
		return
	end
	riding[player] = nil
	if ride.whoosh then
		ride.whoosh:Destroy()
	end
	if ride.tween then
		ride.tween:Cancel()
	end
	if ride.root then
		ride.root.Anchored = false
	end
	local hum = humanoid or ride.humanoid
	if hum then
		hum.PlatformStand = false
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
		endRide(player, humanoid)
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

		local last = bounceCooldown[player] or 0
		if os.clock() - last < Config.BouncePadCooldown then
			return
		end
		bounceCooldown[player] = os.clock()

		-- A Humanoid standing on something is in the Running state, and that
		-- state's controller holds the character down: an upward velocity set
		-- underneath it is cancelled within a frame. Touched only fires on the
		-- transition into contact, so a player who walks onto a pad and stays
		-- there never gets a second attempt, which is why the pads read as
		-- decoration. Handing the state to Jumping releases the ground
		-- controller first, and the velocity then survives.
		--
		-- The slide does not need this because its entrance sets PlatformStand,
		-- which switches the controller off outright. A pad cannot: the player
		-- has to keep control of their character all the way up and back down.
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

		local power = part:GetAttribute("Power") or Config.BouncePadPower
		root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, power, root.AssemblyLinearVelocity.Z)

		playOnce(root, Config.Sounds.BouncePad, Config.Juice.BouncePadVolume)
		puffDust(root)
	end)
end

-- The zipline is a tween along the cable rather than physics on a rope. The
-- descent is 195 studs onto a street, and a rider who clips off a physics line
-- halfway down lands wherever the simulation drops them, which on the edge plots
-- is the void between section ground slabs. A tween cannot miss.
local function rideZip(player, humanoid, root, cableStart, cableEnd)
	local whoosh = Instance.new("Sound")
	whoosh.SoundId = Config.Sounds.ZipWhoosh
	whoosh.Volume = Config.Juice.ZipWhooshVolume
	whoosh.Looped = true
	whoosh.Parent = root
	whoosh:Play()

	local ride = { startedAt = os.clock(), whoosh = whoosh, root = root, humanoid = humanoid }
	riding[player] = ride

	humanoid.PlatformStand = true
	root.Anchored = true

	local heading = (cableEnd - cableStart).Unit
	-- Two legs: the boarding hop from the deck pad out to the cable, which has to
	-- happen outside the parapet or the line would run through the facade, then
	-- the descent itself at a constant speed.
	local board = TweenService:Create(
		root,
		TweenInfo.new(Config.ZipBoardSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = CFrame.lookAt(cableStart, cableStart + heading) }
	)
	ride.tween = board
	board:Play()

	board.Completed:Connect(function(state)
		if riding[player] ~= ride or state ~= Enum.PlaybackState.Completed then
			return
		end
		local seconds = (cableEnd - cableStart).Magnitude / Config.ZipSpeed
		local descend = TweenService:Create(
			root,
			TweenInfo.new(seconds, Enum.EasingStyle.Linear),
			{ CFrame = CFrame.lookAt(cableEnd, cableEnd + heading) }
		)
		ride.tween = descend
		descend:Play()
		descend.Completed:Connect(function()
			if riding[player] == ride then
				endRide(player, humanoid)
			end
		end)
	end)

	task.delay(Config.ZipMaxSeconds, function()
		if riding[player] == ride then
			endRide(player, humanoid)
		end
	end)
end

local function attrPoint(part, prefix)
	local x = part:GetAttribute(prefix .. "X")
	local y = part:GetAttribute(prefix .. "Y")
	local z = part:GetAttribute(prefix .. "Z")
	if x == nil or y == nil or z == nil then
		return nil
	end
	return Vector3.new(x, y, z)
end

local function bindZipEntrance(part)
	if not part:IsA("BasePart") then
		return
	end

	local cableStart = attrPoint(part, "Start")
	local cableEnd = attrPoint(part, "End")
	if not cableStart or not cableEnd then
		warn(
			string.format(
				"TraversalService: ZipEntrance %s is missing its Start/End attributes, so it stays inert",
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
		rideZip(player, humanoid, root, cableStart, cableEnd)
	end)
end

local binders = {
	SlideEntrance = bindEntrance,
	SlideBooster = bindBooster,
	SlideExit = bindExit,
	BouncePad = bindBouncePad,
	ZipEntrance = bindZipEntrance,
	-- Landing on the pad releases the rider too. The descent tween normally gets
	-- there first, so this is the belt to that braces.
	ZipExit = bindExit,
}

for tag, binder in pairs(binders) do
	for _, part in ipairs(CollectionService:GetTagged(tag)) do
		binder(part)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(binder)
end

Players.PlayerRemoving:Connect(function(player)
	endRide(player, nil)
	bounceCooldown[player] = nil
end)
