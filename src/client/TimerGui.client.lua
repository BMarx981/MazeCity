-- TimerGui (LocalScript) -> StarterPlayer/StarterPlayerScripts
-- Floor HUD, celebrations, and the compass arrow. The HUD and the celebrations
-- read the single TimerUpdate payload the server already pushes at 4 Hz, so
-- nothing here needs a remote of its own.
--
-- The compass and the phantom sparkle are the two places a client reads tags
-- directly. Both are hints, not authority: the server owns progression, and a
-- section that has not replicated yet just means no arrow for a moment.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local remote = ReplicatedStorage:WaitForChild("TimerUpdate")
local player = Players.LocalPlayer

local GREEN = Color3.fromRGB(90, 200, 140)
local AMBER = Color3.fromRGB(235, 180, 70)
local RED = Color3.fromRGB(230, 80, 80)
local WHITE = Color3.fromRGB(255, 255, 255)
local GOLD = Color3.fromRGB(255, 214, 110)
local CONFETTI_COLORS = { GREEN, AMBER, GOLD, WHITE, Color3.fromRGB(120, 180, 255), Color3.fromRGB(235, 120, 200) }
local CONFETTI_WIDTH, CONFETTI_HEIGHT = 9, 14

local gui = Instance.new("ScreenGui")
gui.Name = "FloorTimer"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function rounded(inst, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = inst
	return inst
end

local function label(parent, size, position, font, textSize, color)
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextSize = textSize
	l.TextColor3 = color
	l.Text = ""
	l.Parent = parent
	return l
end

-- Timer panel. The floor number is the biggest thing on screen and the only
-- thing that has to be read at a glance; the tower's "S1-C3" code came off
-- because the billboards on the towers already carry it and it is noise to
-- anyone still learning to read.
local holder = Instance.new("Frame")
holder.Size = UDim2.new(0, 220, 0, 86)
holder.Position = UDim2.new(0.5, -110, 0, 16)
holder.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
holder.BackgroundTransparency = 0.25
holder.BorderSizePixel = 0
holder.Visible = false
holder.Parent = gui
rounded(holder, 8)

local floorLabel = label(holder, UDim2.new(1, -16, 0, 40), UDim2.new(0, 8, 0, 6), Enum.Font.GothamBlack, 34, WHITE)
local timeLabel = label(
	holder,
	UDim2.new(1, -16, 0, 26),
	UDim2.new(0, 8, 0, 48),
	Enum.Font.GothamBold,
	22,
	Color3.fromRGB(190, 200, 215)
)
timeLabel.Text = "0:00"

-- The bar fills toward par, and par is now worth points and nothing else, so it
-- never turns red and the clock never changes colour. Amber near the end is the
-- whole remaining signal: hurry if you want the speed bonus.
local bar = Instance.new("Frame")
bar.Size = UDim2.new(0, 0, 0, 4)
bar.Position = UDim2.new(0, 0, 1, -4)
bar.BackgroundColor3 = GREEN
bar.BorderSizePixel = 0
bar.Parent = holder

-- Score chip. Stays up when the timer is hidden, so a player on the street
-- still sees what the run is worth.
local scoreChip = Instance.new("Frame")
scoreChip.Size = UDim2.new(0, 132, 0, 34)
scoreChip.Position = UDim2.new(1, -148, 0, 16)
scoreChip.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
scoreChip.BackgroundTransparency = 0.25
scoreChip.BorderSizePixel = 0
scoreChip.Parent = gui
rounded(scoreChip, 8)

local scoreLabel = label(scoreChip, UDim2.new(1, -12, 1, 0), UDim2.new(0, 6, 0, 0), Enum.Font.GothamBold, 18, WHITE)
scoreLabel.Text = "0"
scoreLabel.TextXAlignment = Enum.TextXAlignment.Right

label(scoreChip, UDim2.new(0, 60, 1, 0), UDim2.new(0, 10, 0, 0), Enum.Font.Gotham, 12, Color3.fromRGB(150, 160, 175)).Text =
	"SCORE"

-- Coin chip, under the score. A gold disc rather than the word "COINS": the
-- reason coins exist is that a floor should reward looking around, and the
-- player being designed for is still learning to read.
local coinChip = Instance.new("Frame")
coinChip.Size = UDim2.new(0, 132, 0, 34)
coinChip.Position = UDim2.new(1, -148, 0, 56)
coinChip.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
coinChip.BackgroundTransparency = 0.25
coinChip.BorderSizePixel = 0
coinChip.Parent = gui
rounded(coinChip, 8)

local coinIcon = Instance.new("Frame")
coinIcon.Size = UDim2.fromOffset(16, 16)
coinIcon.Position = UDim2.new(0, 12, 0.5, -8)
coinIcon.BackgroundColor3 = GOLD
coinIcon.BorderSizePixel = 0
coinIcon.Parent = coinChip
rounded(coinIcon, 8)

local coinLabel = label(coinChip, UDim2.new(1, -12, 1, 0), UDim2.new(0, 6, 0, 0), Enum.Font.GothamBold, 18, WHITE)
coinLabel.Text = "0"
coinLabel.TextXAlignment = Enum.TextXAlignment.Right

-- Powerup chip, hidden until one is picked up. Nothing else on screen says how
-- long an effect has left, and an effect that ends without warning reads as one
-- that broke.
local powerChip = Instance.new("Frame")
powerChip.Size = UDim2.new(0, 178, 0, 34)
powerChip.Position = UDim2.new(1, -194, 0, 96)
powerChip.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
powerChip.BackgroundTransparency = 0.25
powerChip.BorderSizePixel = 0
powerChip.Visible = false
powerChip.Parent = gui
rounded(powerChip, 8)

local powerLabel = label(powerChip, UDim2.new(1, -20, 1, 0), UDim2.new(0, 10, 0, 0), Enum.Font.GothamBold, 16, WHITE)
powerLabel.TextXAlignment = Enum.TextXAlignment.Left

-- Celebration banner
local banner = Instance.new("Frame")
banner.Size = UDim2.new(0, 460, 0, 108)
banner.Position = UDim2.new(0.5, -230, 0.34, 0)
banner.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
banner.BackgroundTransparency = 1
banner.BorderSizePixel = 0
banner.Visible = false
banner.Parent = gui
rounded(banner, 10)

local bannerTitle = label(banner, UDim2.new(1, 0, 0, 52), UDim2.new(0, 0, 0, 14), Enum.Font.GothamBlack, 38, WHITE)
local bannerSub = label(banner, UDim2.new(1, 0, 0, 28), UDim2.new(0, 0, 0, 66), Enum.Font.GothamBold, 22, GOLD)

-- Confetti is screen frames rather than world particles: it cannot be swallowed
-- by the wall the player happens to be facing, and it adds nothing to workspace.
local confettiLayer = Instance.new("Frame")
confettiLayer.Size = UDim2.fromScale(1, 1)
confettiLayer.BackgroundTransparency = 1
confettiLayer.ZIndex = 5
confettiLayer.Parent = gui

local function format(seconds)
	local m = math.floor(seconds / 60)
	local s = math.floor(seconds % 60)
	return string.format("%d:%02d", m, s)
end

local function tween(inst, time, props)
	TweenService:Create(inst, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function playSound(assetId, volume, playbackSpeed)
	local sound = Instance.new("Sound")
	sound.SoundId = assetId
	sound.Volume = volume
	sound.PlaybackSpeed = playbackSpeed or 1
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, sound.TimeLength > 0 and sound.TimeLength + 1 or 5)
end

local function confetti(count)
	local seconds = Config.Juice.ConfettiSeconds
	for i = 1, count do
		local piece = Instance.new("Frame")
		piece.Size = UDim2.fromOffset(CONFETTI_WIDTH, CONFETTI_HEIGHT)
		piece.Position = UDim2.new(math.random(), 0, -0.08, 0)
		piece.BackgroundColor3 = CONFETTI_COLORS[(i % #CONFETTI_COLORS) + 1]
		piece.BorderSizePixel = 0
		piece.Rotation = math.random(0, 359)
		piece.ZIndex = 5
		piece.Parent = confettiLayer

		local fall = seconds * (0.55 + math.random() * 0.7)
		local drift = piece.Position.X.Scale + (math.random() - 0.5) * 0.2
		TweenService:Create(piece, TweenInfo.new(fall, Enum.EasingStyle.Linear), {
			Position = UDim2.new(drift, 0, 1.1, 0),
			Rotation = piece.Rotation + math.random(180, 720),
			BackgroundTransparency = 1,
		}):Play()
		Debris:AddItem(piece, fall + 0.5)
	end
end

-- A token guards the sequence: a second celebration landing mid-fade takes the
-- banner over rather than letting the first one's fade-out finish on top of it.
local bannerToken = 0

local function showBanner(title, subtitle, titleColor, hold, big)
	bannerToken = bannerToken + 1
	local token = bannerToken

	bannerTitle.Text = title
	bannerTitle.TextColor3 = titleColor
	bannerTitle.TextSize = big and 52 or 38
	bannerSub.Text = subtitle

	banner.Visible = true
	banner.BackgroundTransparency = 1
	banner.Position = UDim2.new(0.5, -230, 0.34, 18)
	bannerTitle.TextTransparency = 1
	bannerSub.TextTransparency = 1

	tween(banner, 0.22, { BackgroundTransparency = 0.25, Position = UDim2.new(0.5, -230, 0.34, 0) })
	tween(bannerTitle, 0.22, { TextTransparency = 0 })
	tween(bannerSub, 0.22, { TextTransparency = 0 })

	task.delay(hold, function()
		if token ~= bannerToken then
			return
		end
		tween(banner, 0.45, { BackgroundTransparency = 1, Position = UDim2.new(0.5, -230, 0.34, -18) })
		tween(bannerTitle, 0.45, { TextTransparency = 1 })
		tween(bannerSub, 0.45, { TextTransparency = 1 })
		task.delay(0.5, function()
			if token == bannerToken then
				banner.Visible = false
			end
		end)
	end)
end

local function pulseScore(times)
	task.spawn(function()
		for i = 1, times do
			scoreLabel.TextColor3 = GOLD
			scoreLabel.TextSize = 24
			task.wait(0.18)
			scoreLabel.TextColor3 = WHITE
			scoreLabel.TextSize = 18
			if i < times then
				task.wait(0.12)
			end
		end
	end)
end

local function playEvent(event)
	local juice = Config.Juice
	if event.kind == "floor" then
		local delta = event.par - event.elapsed
		local pace = delta >= 0 and string.format("%s under par", format(delta))
			or string.format("%s over par", format(-delta))
		showBanner(
			string.format("Floor %d clear", event.level + 1),
			string.format("+%d  |  %s", event.gained, pace),
			GREEN,
			2,
			false
		)
		for _, note in ipairs(Config.Sounds.FloorClearArpeggio) do
			task.delay(note[1], function()
				playSound(Config.Sounds.FloorClear, juice.FloorClearVolume, note[2])
			end)
		end
		confetti(juice.ConfettiFloor)
		pulseScore(1)
	elseif event.kind == "tower" then
		showBanner(event.tower .. " topped out", string.format("+%d  |  roof reached", event.gained), GOLD, 4, true)
		for _, note in ipairs(Config.Sounds.TowerClearArpeggio) do
			task.delay(note[1], function()
				playSound(Config.Sounds.TowerClear, juice.TowerClearVolume, note[2])
			end)
		end
		confetti(juice.ConfettiTower)
		pulseScore(3)
	elseif event.kind == "death" then
		local where = event.restart == "tower" and "Back to the tower entrance" or "Back to the start of this floor"
		showBanner("Caught", where, RED, 1.6, false)
		playSound(Config.Sounds.Death, juice.DeathVolume)
	end
end

-- ============================================================
-- Compass arrow
-- ============================================================
-- By generation invariant 3 the stairs up from floor N arrive at floor N+1's
-- LevelTrigger cell, so "which way are the stairs" is "where is the trigger one
-- level up". The top floor has none, and falls back to the RoofTrigger. Either
-- lookup can come back empty (a section still generating, geometry not yet
-- replicated), and empty just hides the arrow.

local compass = Instance.new("BillboardGui")
compass.Name = "Compass"
compass.Size = UDim2.fromOffset(Config.Compass.Size, Config.Compass.Size)
compass.StudsOffsetWorldSpace = Vector3.new(0, Config.Compass.HeightOffset, 0)
compass.AlwaysOnTop = true
compass.Enabled = false
-- A BillboardGui is its own LayerCollector and renders from PlayerGui, not from
-- inside the ScreenGui above; ResetOnSpawn keeps it across a death respawn the
-- way the HUD is kept.
compass.ResetOnSpawn = false
compass.Parent = player.PlayerGui

local arrow =
	label(compass, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Enum.Font.GothamBlack, 1, Config.Compass.Color)
arrow.Text = "▲"
arrow.TextScaled = true
arrow.TextStrokeTransparency = 0.4

local floorContext = nil
local compassTarget = nil

local function matches(part, section, building)
	return part:GetAttribute("Section") == section and part:GetAttribute("Building") == building
end

-- A trigger's centre is not always the place it wants a player sent. The
-- RoofTrigger covers the whole deck so that arriving anywhere on it counts,
-- which puts its centre in the middle of the roof while the stairs come up at
-- an edge, so on the top floor the arrow was pointing at open floor in the
-- middle of the room and the storey read as having no staircase at all. Parts
-- that know better carry an explicit arrival point.
local function aimPoint(part)
	local x = part:GetAttribute("ArrivalX")
	local z = part:GetAttribute("ArrivalZ")
	if x and z then
		return Vector3.new(x, part:GetAttribute("ArrivalY") or part.Position.Y, z)
	end
	return part.Position
end

local function findTarget(context)
	if not context then
		return nil
	end
	for _, part in ipairs(CollectionService:GetTagged("LevelTrigger")) do
		if matches(part, context.section, context.building) and part:GetAttribute("Level") == context.level + 1 then
			return part
		end
	end
	for _, part in ipairs(CollectionService:GetTagged("RoofTrigger")) do
		if matches(part, context.section, context.building) then
			return part
		end
	end
	return nil
end

task.spawn(function()
	while true do
		compassTarget = findTarget(floorContext)
		task.wait(Config.Compass.RetargetSeconds)
	end
end)

RunService.RenderStepped:Connect(function()
	if not Config.Compass.Enabled or not compassTarget or not compassTarget.Parent then
		compass.Enabled = false
		return
	end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not root or not camera then
		compass.Enabled = false
		return
	end

	local to = aimPoint(compassTarget) - root.Position
	local flat = Vector3.new(to.X, 0, to.Z)
	local camFlat = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
	local camRight = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z)
	if flat.Magnitude < 1 or camFlat.Magnitude < 0.01 or camRight.Magnitude < 0.01 then
		compass.Enabled = false
		return
	end

	compass.Adornee = root
	-- Screen-space angle from camera-forward, so the arrow reads as a top-down
	-- compass: straight up means walk the way you are looking.
	arrow.Rotation = math.deg(math.atan2(camRight.Unit:Dot(flat.Unit), camFlat.Unit:Dot(flat.Unit)))
	compass.Enabled = true
end)

-- ============================================================
-- Phantom wall sparkle
-- ============================================================
-- The one genuine discovery mechanic in the game, and until now walking through
-- a phantom felt like a bug. Client-side because only the player who found it
-- needs to see it, and because the tagged wall lives in generated geometry that
-- nothing is allowed to parent effects into.

local sparkleCooldown = setmetatable({}, { __mode = "k" })

-- Shared by the phantom sparkle and the coin ding. It emits from the character
-- rather than from the thing that was touched, because the thing that was
-- touched lives in generated geometry and nothing is allowed to parent effects
-- into that.
local function emitBurst(color, count, seconds)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Parent = root

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = Config.Juice.PhantomSparkleTexture
	emitter.Color = ColorSequence.new(color)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new(0.9, 0.1)
	emitter.Lifetime = NumberRange.new(seconds * 0.5, seconds)
	emitter.Speed = NumberRange.new(3, 9)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(count)

	Debris:AddItem(attachment, seconds + 1)
end

local function sparkle()
	local juice = Config.Juice
	emitBurst(juice.PhantomSparkleColor, juice.PhantomSparkleParticles, juice.PhantomSparkleSeconds)
	playSound(Config.Sounds.PhantomPass, juice.PhantomSparkleVolume)
end

local function bindPhantom(part)
	if not part:IsA("BasePart") then
		return
	end
	part.Touched:Connect(function(hit)
		local char = player.Character
		if not char or not hit:IsDescendantOf(char) then
			return
		end
		local last = sparkleCooldown[part] or 0
		if os.clock() - last < Config.Juice.PhantomSparkleCooldown then
			return
		end
		sparkleCooldown[part] = os.clock()
		sparkle()
	end)
end

for _, part in ipairs(CollectionService:GetTagged("PhantomWall")) do
	bindPhantom(part)
end
CollectionService:GetInstanceAddedSignal("PhantomWall"):Connect(bindPhantom)

-- ============================================================
-- Coins and powerups
-- ============================================================
-- The count itself is the replicated leaderstats value, so a client that
-- connects late reads the right number rather than starting at zero. The
-- PickupUpdate remote carries only the things that are events: the ding, the
-- sparkle, and which powerup just started.

local pickupRemote = ReplicatedStorage:WaitForChild("PickupUpdate")

task.spawn(function()
	local stats = player:WaitForChild("leaderstats", 20)
	local coins = stats and stats:WaitForChild("Coins", 20)
	if not coins then
		return
	end
	coinLabel.Text = string.format("%d", coins.Value)
	coins.Changed:Connect(function(value)
		coinLabel.Text = string.format("%d", value)
	end)
end)

-- Coins spin on the client and only near the player: it is a visual on an
-- anchored part that the server never moves again after generation, so the
-- rotation stays on this machine and the coin's hitbox never leaves where the
-- generator put it. The whole city's worth of coins is far too many to touch
-- every frame, hence the nearby list, refreshed on a slow timer.
local nearbyCoins = {}

task.spawn(function()
	local collectibles = Config.Collectibles
	while true do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local list = {}
		if root and collectibles.SpinDegreesPerSecond > 0 then
			for _, coin in ipairs(CollectionService:GetTagged("Coin")) do
				if coin.Transparency < 1 and (coin.Position - root.Position).Magnitude < collectibles.SpinRange then
					table.insert(list, coin)
				end
			end
		end
		nearbyCoins = list
		task.wait(collectibles.SpinRefreshSeconds)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	local step = math.rad(Config.Collectibles.SpinDegreesPerSecond * dt)
	for _, coin in ipairs(nearbyCoins) do
		if coin.Parent then
			coin.CFrame = coin.CFrame * CFrame.Angles(0, step, 0)
		end
	end
end)

-- Coins taken in quick succession ring a step higher each time, which is most
-- of what makes a room full of them feel like a run rather than a list. The
-- streak lapses on its own, so the pitch never creeps up over a whole floor.
local streakPitch = Config.Juice.CoinPitchBase
local streakAt = 0

local function coinPickup()
	local juice = Config.Juice
	local now = os.clock()
	if now - streakAt > juice.CoinStreakSeconds then
		streakPitch = juice.CoinPitchBase
	else
		streakPitch = math.min(juice.CoinPitchMax, streakPitch + juice.CoinPitchStep)
	end
	streakAt = now

	playSound(Config.Sounds.CoinPickup, juice.CoinVolume, streakPitch)
	emitBurst(juice.CoinSparkleColor, juice.CoinSparkleParticles, juice.PhantomSparkleSeconds)
	coinIcon.Size = UDim2.fromOffset(22, 22)
	coinIcon.Position = UDim2.new(0, 9, 0.5, -11)
	tween(coinIcon, 0.22, { Size = UDim2.fromOffset(16, 16), Position = UDim2.new(0, 12, 0.5, -8) })
end

local powerUntil = 0
local powerName = nil

local function powerupStarted(payload)
	local juice = Config.Juice
	local profile = Config.getPowerupKind(payload.powerup)

	powerName = payload.powerup
	powerUntil = os.clock() + payload.duration
	powerChip.Visible = true

	showBanner(payload.label or profile.label, "", profile.color, juice.PowerupBannerSeconds, false)
	for _, note in ipairs(Config.Sounds.PowerupArpeggio) do
		task.delay(note[1], function()
			playSound(Config.Sounds.PowerupPickup, juice.PowerupVolume, note[2])
		end)
	end
	emitBurst(profile.color, juice.CoinSparkleParticles * 2, juice.PhantomSparkleSeconds)
end

task.spawn(function()
	while true do
		if powerName then
			local left = powerUntil - os.clock()
			if left <= 0 then
				powerName = nil
				powerChip.Visible = false
			else
				local profile = Config.getPowerupKind(powerName)
				powerLabel.Text = string.format("%s  %ds", profile.label, math.ceil(left))
				powerLabel.TextColor3 = profile.color
			end
		end
		task.wait(0.1)
	end
end)

pickupRemote.OnClientEvent:Connect(function(payload)
	if not payload then
		return
	end
	if payload.kind == "coin" then
		coinPickup()
	elseif payload.kind == "powerup" then
		powerupStarted(payload)
	elseif payload.kind == "powerupEnded" then
		-- The countdown above hides the chip on its own; this only matters when
		-- the server ended an effect early, by handing out a different one.
		if powerName == payload.powerup then
			powerName = nil
			powerChip.Visible = false
		end
	end
end)

-- ============================================================

remote.OnClientEvent:Connect(function(payload)
	if not payload then
		holder.Visible = false
		floorContext = nil
		return
	end

	if payload.score then
		scoreLabel.Text = string.format("%d", payload.score)
	end

	if payload.level then
		holder.Visible = true
		floorLabel.Text = string.format("Floor %d", payload.level + 1)
		timeLabel.Text = format(payload.elapsed)

		local ratio = math.clamp(payload.elapsed / math.max(1, payload.par), 0, 1)
		bar.Size = UDim2.new(ratio, 0, 0, 4)
		bar.BackgroundColor3 = ratio > 0.7 and AMBER or GREEN

		if
			floorContext == nil
			or floorContext.level ~= payload.level
			or floorContext.section ~= payload.section
			or floorContext.building ~= payload.building
		then
			floorContext = { section = payload.section, building = payload.building, level = payload.level }
			compassTarget = findTarget(floorContext)
		end
	else
		holder.Visible = false
		floorContext = nil
		compassTarget = nil
	end

	if payload.event then
		playEvent(payload.event)
	end
end)
