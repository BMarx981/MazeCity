-- WallWalkGui (LocalScript) -> StarterPlayer/StarterPlayerScripts
-- The key and the meter for the Wall Walker upgrade. Hold Q, or the on-screen
-- button, and the server phases you; the meter drains while you hold it.
--
-- ContextActionService rather than UserInputService, because it hands over the
-- touch button for free and a game aimed at a young player cannot be
-- keyboard-only. It also means the same binding covers a gamepad shoulder.
--
-- The chip hides itself when the upgrade is unowned, which is how a player who
-- has not bought it never learns there is a key. The server decides that, by
-- sending a capacity of zero.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local remote = ReplicatedStorage:WaitForChild("WallWalkUpdate")
local intents = ReplicatedStorage:WaitForChild("WallWalkIntent")
local player = Players.LocalPlayer

local ACTION = "WallWalk"
local COLOR = Config.Shop.Upgrades.WallWalker.Color
local EMPTY = Color3.fromRGB(230, 80, 80)
local GRACE = Color3.fromRGB(255, 190, 90)

local gui = Instance.new("ScreenGui")
gui.Name = "WallWalkHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

-- Fourth chip down the right edge, under TimerGui's score, coins and powerup.
local chip = Instance.new("Frame")
chip.Size = UDim2.fromOffset(178, 34)
chip.Position = UDim2.new(1, -194, 0, 136)
chip.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
chip.BackgroundTransparency = 0.25
chip.BorderSizePixel = 0
chip.Visible = false
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
title.Text = "HOLD [Q]"
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

-- Server truth, plus the clock it arrived on. Between pushes the bar is drawn by
-- subtracting elapsed time from the last fuel figure, so it moves at frame rate
-- off numbers the server owns rather than off a count the client keeps.
local fuel = 0
local capacity = 0
local phasing = false
local grace = false
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

local function shown()
	local drained = phasing and math.max(0, fuel - (os.clock() - sampledAt)) or fuel
	return drained
end

RunService.RenderStepped:Connect(function()
	if not chip.Visible or capacity <= 0 then
		return
	end
	local left = shown()
	fill.Size = UDim2.fromScale(math.clamp(left / capacity, 0, 1), 1)
	if grace then
		fill.BackgroundColor3 = GRACE
		title.Text = "SQUEEZE OUT!"
		title.TextColor3 = GRACE
	elseif left <= 0 then
		fill.BackgroundColor3 = EMPTY
		title.Text = "HOLD [Q]  empty"
		title.TextColor3 = EMPTY
	else
		fill.BackgroundColor3 = COLOR
		-- The key stays in the text rather than only in the label this loop
		-- overwrote on its first frame: an owner never saw the static hint, so the
		-- upgrade had a HUD chip and no discoverable way to fire it.
		title.Text = string.format("HOLD [Q]  %.1fs", left)
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

local bound = false

local function setBound(active)
	if active == bound then
		return
	end
	bound = active
	if active then
		ContextActionService:BindAction(ACTION, handleAction, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
		ContextActionService:SetTitle(ACTION, "PHASE")
	else
		ContextActionService:UnbindAction(ACTION)
	end
end

remote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or payload.kind ~= "state" then
		return
	end

	fuel = payload.fuel or 0
	capacity = payload.capacity or 0
	phasing = payload.phasing == true
	grace = payload.grace == true
	sampledAt = os.clock()

	-- Capacity is the whole of "do you own this": unowned is zero, and a chip
	-- nobody can use is a key nobody has to be told about.
	chip.Visible = capacity > 0
	setBound(capacity > 0)

	local event = payload.event
	if not event then
		return
	end
	if event.kind == "started" then
		playSound(Config.Sounds.PhantomPass, Config.Juice.PhantomSparkleVolume, 0.8)
	elseif event.kind == "empty" then
		playSound(Config.Sounds.CoinPickup, Config.Juice.CoinVolume, Config.Juice.ShopDeniedPitch)
	elseif event.kind == "refilled" and capacity > 0 then
		chip.BackgroundTransparency = 0.05
		task.delay(0.25, function()
			chip.BackgroundTransparency = 0.25
		end)
	end
end)
