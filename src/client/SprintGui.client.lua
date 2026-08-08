-- SprintGui (LocalScript) -> StarterPlayer/StarterPlayerScripts
-- The key and the meter for Sprint. Hold Shift, or the on-screen button, and the
-- server speeds you up; the meter drains while you are actually moving and comes
-- back a moment after you let go.
--
-- ContextActionService rather than UserInputService, for the reason WallWalkGui
-- gives: it hands over the touch button for free, and the same binding covers a
-- gamepad shoulder. ButtonR1 here because WallWalkGui already holds L1.
--
-- Shift is the key players reach for, so StarterPlayer.EnableMouseLockOption is
-- false in default.project.json. Left on, every sprint would also toggle the
-- shift-lock camera for anyone who has that switch enabled.
--
-- Unlike the Wall Walker chip this one never hides. Sprint is not bought, so
-- there is no unowned state and no capacity of zero to key visibility off.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local remote = ReplicatedStorage:WaitForChild("SprintUpdate")
local intents = ReplicatedStorage:WaitForChild("SprintIntent")
local player = Players.LocalPlayer

local ACTION = "Sprint"
local COLOR = Config.Sprint.Color
local SPENT = Color3.fromRGB(230, 80, 80)
local ACTIVE = Color3.fromRGB(255, 240, 150)

local gui = Instance.new("ScreenGui")
gui.Name = "SprintHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

-- Fifth chip down the right edge, under WallWalkGui's. Same 40px pitch as
-- TimerGui's score, coins and powerup above it.
local chip = Instance.new("Frame")
chip.Size = UDim2.fromOffset(178, 34)
chip.Position = UDim2.new(1, -194, 0, 176)
chip.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
chip.BackgroundTransparency = 0.25
chip.BorderSizePixel = 0
chip.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = chip

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 16)
title.Position = UDim2.new(0, 10, 0, 3)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextColor3 = COLOR
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "HOLD [SHIFT]"
title.Parent = chip

local track = Instance.new("Frame")
track.Size = UDim2.new(1, -20, 0, 6)
track.Position = UDim2.new(0, 10, 0, 22)
track.BackgroundColor3 = Color3.fromRGB(50, 52, 62)
track.BorderSizePixel = 0
track.Parent = chip

local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = COLOR
fill.BorderSizePixel = 0
fill.Parent = track

-- Server truth, plus the clock it arrived on. Seeded full rather than empty so
-- the chip is correct on the frame it is drawn, before the first push lands.
local stamina = Config.Sprint.Seconds
local capacity = Config.Sprint.Seconds
local sprinting = false
local regenIn = 0
local sampledAt = os.clock()

local function playSound(assetId, volume, speed)
	local sound = Instance.new("Sound")
	sound.SoundId = assetId
	sound.Volume = volume
	sound.PlaybackSpeed = speed or 1
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, sound.TimeLength > 0 and sound.TimeLength + 1 or 5)
end

-- The same test the server drains on. Reading it locally is what lets the bar
-- hold still while the player stands on the key instead of falling and being
-- snapped back up by the next push.
local function walking()
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.MoveDirection.Magnitude > Config.Sprint.MoveThreshold
end

local function shown()
	local elapsed = os.clock() - sampledAt
	if sprinting then
		if not walking() then
			return stamina
		end
		return math.max(0, stamina - elapsed)
	end
	local recovering = elapsed - regenIn
	if recovering <= 0 then
		return stamina
	end
	return math.min(capacity, stamina + recovering * Config.Sprint.RegenPerSecond)
end

RunService.RenderStepped:Connect(function()
	if capacity <= 0 then
		return
	end
	local left = shown()
	fill.Size = UDim2.fromScale(math.clamp(left / capacity, 0, 1), 1)
	if sprinting then
		fill.BackgroundColor3 = ACTIVE
		title.Text = string.format("SPRINTING  %.1fs", left)
		title.TextColor3 = ACTIVE
	elseif left < Config.Sprint.MinimumToStart then
		fill.BackgroundColor3 = SPENT
		-- The key name stays in the text on every branch, the lesson WallWalkGui's
		-- loop learned the hard way: a label written once at build time is a hint
		-- nobody ever sees, because the first visible frame overwrites it.
		title.Text = "HOLD [SHIFT]  winded"
		title.TextColor3 = SPENT
	else
		fill.BackgroundColor3 = COLOR
		title.Text = string.format("HOLD [SHIFT]  %.1fs", left)
		title.TextColor3 = COLOR
	end
end)

local function handleAction(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		intents:FireServer({ kind = "start" })
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		intents:FireServer({ kind = "stop" })
	end
	return Enum.ContextActionResult.Pass
end

-- Bound once and never unbound: everyone owns this. Both shift keys, because a
-- player who has moved their hand to the arrows is holding the wrong one.
ContextActionService:BindAction(
	ACTION,
	handleAction,
	true,
	Enum.KeyCode.LeftShift,
	Enum.KeyCode.RightShift,
	Enum.KeyCode.ButtonR1
)
ContextActionService:SetTitle(ACTION, "RUN")

remote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or payload.kind ~= "state" then
		return
	end

	stamina = payload.stamina or 0
	capacity = payload.capacity or Config.Sprint.Seconds
	sprinting = payload.sprinting == true
	regenIn = payload.regenIn or 0
	sampledAt = os.clock()

	local event = payload.event
	if not event then
		return
	end
	if event.kind == "spent" then
		playSound(Config.Sounds.CoinPickup, Config.Juice.CoinVolume, Config.Juice.ShopDeniedPitch)
	elseif event.kind == "ready" then
		-- A flash rather than a chime. The meter refills after every sprint, so a
		-- sound here would be the most repeated noise in the game.
		chip.BackgroundTransparency = 0.05
		task.delay(0.25, function()
			chip.BackgroundTransparency = 0.25
		end)
	end
end)
