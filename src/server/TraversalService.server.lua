-- TraversalService (Script) -> ServerScriptService
-- Slide between sections, plus the roof deck bounce pads.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local function endRide(player, humanoid)
	local ride = riding[player]
	if not ride then
		return
	end
	riding[player] = nil
	if ride.whoosh then
		ride.whoosh:Destroy()
	end
	if humanoid then
		humanoid.PlatformStand = false
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
		local player, _, root = playerFrom(hit)
		if not player or not root then
			return
		end

		local last = bounceCooldown[player] or 0
		if os.clock() - last < Config.BouncePadCooldown then
			return
		end
		bounceCooldown[player] = os.clock()

		local power = part:GetAttribute("Power") or Config.BouncePadPower
		root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, power, root.AssemblyLinearVelocity.Z)

		playOnce(root, Config.Sounds.BouncePad, Config.Juice.BouncePadVolume)
		puffDust(root)
	end)
end

local binders = {
	SlideEntrance = bindEntrance,
	SlideBooster = bindBooster,
	SlideExit = bindExit,
	BouncePad = bindBouncePad,
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
