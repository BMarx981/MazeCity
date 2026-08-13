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
-- there is no unowned state and no capacity of zero to key visibility off. That
-- is also why it sits in its own corner rather than in the right column: the
-- column is readouts and bought things, and the ability bar now holds the slot
-- this chip used to.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local UiTheme = require(ReplicatedStorage:WaitForChild("UiTheme"))
local remote = ReplicatedStorage:WaitForChild("SprintUpdate")
local intents = ReplicatedStorage:WaitForChild("SprintIntent")
local player = Players.LocalPlayer

local ACTION = "Sprint"
local LABEL = "Sprint gauge"
-- Ready is the rune teal, running is the lantern being spent, and winded is
-- the one place this chip is allowed to show danger red: the meter is empty.
local READY = UiTheme.Rune
local RUNNING = UiTheme.Lantern
local WINDED = UiTheme.Ember

local gui = Instance.new("ScreenGui")
gui.Name = "SprintHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

-- Bottom right corner, anchored to it rather than positioned from the top left,
-- so the chip stays put on a tall phone as well as a wide monitor. Same 16px
-- margin the right column above it uses.
local chip = UiTheme.chip(gui, UDim2.fromOffset(178, 34), UDim2.new(1, -16, 1, -16), {
	anchor = Vector2.new(1, 1),
})

local title = UiTheme.label(chip, UDim2.new(1, -20, 0, 16), UDim2.new(0, 10, 0, 4), UiTheme.BodyBold, 12, READY)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = LABEL

-- The meter is the chip's rune seam: one glowing line along the bottom edge
-- doing both jobs, rather than a static seam with a second bar above it.
local _track, fill =
	UiTheme.bar(chip, UDim2.new(1, -UiTheme.ChipRadius * 2, 0, 3), UDim2.new(0, UiTheme.ChipRadius, 1, -6), READY)

-- Server truth, plus the clock it arrived on. Seeded full rather than empty so
-- the chip is correct on the frame it is drawn, before the first push lands.
local stamina = Config.Sprint.Seconds
local capacity = Config.Sprint.Seconds
local sprinting = false
local regenIn = 0
local sampledAt = os.clock()

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
	-- The text is the name of the gauge and nothing else; state is the bar and the
	-- colour it is drawn in. Three states, three colours: running, winded, ready.
	-- The loop still writes the colour every frame rather than on the transition,
	-- because a colour set once at build time is the same hint nobody sees that
	-- the old per-branch text was written to avoid.
	if sprinting then
		fill.BackgroundColor3 = RUNNING
		title.TextColor3 = RUNNING
	elseif left < Config.Sprint.MinimumToStart then
		fill.BackgroundColor3 = WINDED
		title.TextColor3 = WINDED
	else
		fill.BackgroundColor3 = READY
		title.TextColor3 = READY
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
		UiTheme.playSound(Config.Sounds.CoinPickup, Config.Juice.CoinVolume, Config.Juice.ShopDeniedPitch)
	elseif event.kind == "ready" then
		-- A flash rather than a chime. The meter refills after every sprint, so a
		-- sound here would be the most repeated noise in the game.
		chip.BackgroundTransparency = 0.05
		task.delay(0.25, function()
			chip.BackgroundTransparency = UiTheme.ChipTransparency
		end)
	end
end)
