-- AbilityGui (LocalScript) -> StarterPlayer/StarterPlayerScripts
-- The ability bar: which abilities you own, which one the key is pointed at, and
-- the charge they all spend. Replaces WallWalkGui, which was a chip for the one
-- ability there used to be.
--
-- **Bottom centre, not a sixth chip down the right edge.** The right column is
-- score, coins, powerup and sprint already, and a selector is not a readout: it
-- is the one thing on screen the player is meant to reach for and press, which
-- is where every game puts an action bar. It also leaves the corners alone,
-- which on a phone are the thumbstick and the jump button.
--
-- **Ownership is read off replicated attributes, not off the remote.**
-- SaveService stamps AbilityTier_<Key> and AbilityService stamps
-- SelectedAbility, both on the player, so a client that joined late, respawned,
-- or reset its GUI draws the correct bar on its first frame with nothing to ask
-- for. The remote carries the charge and the events, which are the two things an
-- attribute is the wrong shape for.
--
-- **The bar hides itself when nothing is owned**, the rule WallWalkGui had: a
-- player who has not been to the stall never learns there is a key, and the
-- first purchase is what teaches it.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local remote = ReplicatedStorage:WaitForChild("AbilityUpdate")
local intents = ReplicatedStorage:WaitForChild("AbilityIntent")
local player = Players.LocalPlayer

local USE_ACTION = "UseAbility"
local CYCLE_ACTION = "CycleAbility"
local SELECT_ACTION = "SelectAbility"

local EMPTY = Config.Abilities.EmptyColor
local GRACE = Config.Abilities.GraceColor
local PANEL = Color3.fromRGB(16, 16, 20)
local DIM = Color3.fromRGB(150, 160, 175)

local BUTTON_W, BUTTON_H = 116, 34
local GAP, PAD, METER_H = 6, 10, 22

-- The number keys, in Config.Abilities.Order's order. Nine because the bar has
-- no reason to be wider than a hand, and a tenth ability would want a different
-- selector rather than a longer row of keys.
local NUMBER_KEYS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
	Enum.KeyCode.Seven,
	Enum.KeyCode.Eight,
	Enum.KeyCode.Nine,
}

local gui = Instance.new("ScreenGui")
gui.Name = "AbilityHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function rounded(inst, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = inst
	return inst
end

local bar = Instance.new("Frame")
bar.Name = "AbilityBar"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -18)
bar.Size = UDim2.fromOffset(0, 0)
bar.BackgroundColor3 = PANEL
bar.BackgroundTransparency = 0.25
bar.BorderSizePixel = 0
bar.Visible = false
bar.Parent = gui
rounded(bar, 10)

local row = Instance.new("Frame")
row.Position = UDim2.fromOffset(PAD, PAD)
row.Size = UDim2.fromOffset(0, BUTTON_H)
row.BackgroundTransparency = 1
row.Parent = bar

local track = Instance.new("Frame")
track.Position = UDim2.new(0, PAD, 0, PAD + BUTTON_H + 8)
track.Size = UDim2.new(1, -PAD * 2, 0, 6)
track.BackgroundColor3 = Color3.fromRGB(50, 52, 62)
track.BorderSizePixel = 0
track.Parent = bar
rounded(track, 3)

local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
fill.BorderSizePixel = 0
fill.Parent = track
rounded(fill, 3)

local hint = Instance.new("TextLabel")
hint.Position = UDim2.new(0, PAD, 0, PAD + BUTTON_H + 16)
hint.Size = UDim2.new(1, -PAD * 2, 0, 16)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.GothamBold
hint.TextSize = 12
hint.TextColor3 = DIM
hint.TextXAlignment = Enum.TextXAlignment.Center
hint.Text = ""
hint.Parent = bar

-- ============================================================
-- Server truth
-- ============================================================
-- The charge and the clock it arrived on. Between pushes the bar is drawn by
-- subtracting elapsed time at the running ability's own rate, so it moves at
-- frame rate off numbers the server owns rather than off a count kept here.

local charge = 1
local active = nil
local grace = false
local sampledAt = os.clock()

local owned = {}
local buttons = {}

local function playSound(assetId, volume, speed)
	local sound = Instance.new("Sound")
	sound.SoundId = assetId
	sound.Volume = volume
	sound.PlaybackSpeed = speed or 1
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, sound.TimeLength > 0 and sound.TimeLength + 1 or 5)
end

local function tierOf(key)
	return player:GetAttribute("AbilityTier_" .. key) or 0
end

local function selectedKey()
	return player:GetAttribute("SelectedAbility")
end

local function perTier(list, tier)
	if not list or tier <= 0 then
		return nil
	end
	return list[math.min(tier, #list)]
end

-- ============================================================
-- The bar
-- ============================================================

-- Assigned in the input section below, which is where the bindings it switches
-- are. Declared here because rebuild is the one thing that knows whether the bar
-- has anything on it.
local setBound

local function colorOf(key)
	local def = Config.abilityDef(key)
	return def and def.Color or Color3.fromRGB(255, 255, 255)
end

local function paintButtons()
	local selected = selectedKey()
	for key, button in pairs(buttons) do
		local isSelected = key == selected
		local color = colorOf(key)
		button.BackgroundColor3 = isSelected and color or Color3.fromRGB(38, 38, 46)
		button.BackgroundTransparency = isSelected and 0.15 or 0.35
		button.TextColor3 = isSelected and Color3.fromRGB(20, 20, 24) or color
		-- The selected one is the only thing on the bar drawn in its own colour at
		-- full strength, because at a glance the bar has exactly one question to
		-- answer and it is which key press does what.
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = color
			stroke.Transparency = isSelected and 0 or 0.6
		end
	end
end

local function rebuild()
	local list = {}
	for _, key in ipairs(Config.Abilities.Order) do
		if Config.abilityDef(key) and tierOf(key) > 0 then
			table.insert(list, key)
		end
	end
	owned = list

	for _, button in pairs(buttons) do
		button:Destroy()
	end
	buttons = {}

	local count = #owned
	bar.Visible = count > 0
	setBound(count > 0)
	if count == 0 then
		return
	end

	local width = PAD * 2 + count * BUTTON_W + (count - 1) * GAP
	bar.Size = UDim2.fromOffset(width, PAD * 2 + BUTTON_H + 8 + METER_H)
	row.Size = UDim2.fromOffset(width - PAD * 2, BUTTON_H)

	for i, key in ipairs(owned) do
		local def = Config.abilityDef(key)

		local button = Instance.new("TextButton")
		button.Size = UDim2.fromOffset(BUTTON_W, BUTTON_H)
		button.Position = UDim2.fromOffset((i - 1) * (BUTTON_W + GAP), 0)
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.Font = Enum.Font.GothamBold
		button.TextSize = 13
		button.Text = (i <= #NUMBER_KEYS and string.format("%d  %s", i, def.Label) or def.Label)
		button.Parent = row
		rounded(button, 7)

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1.5
		stroke.Parent = button

		-- Tapping is the only selector a phone has, and it is also the one a player
		-- finds without being told. The number keys below are the shortcut.
		button.Activated:Connect(function()
			intents:FireServer({ kind = "select", ability = key })
		end)

		buttons[key] = button
	end

	paintButtons()
end

-- ============================================================
-- Drawing
-- ============================================================
-- Seconds are computed here rather than sent, because the client already has
-- every term: the charge from the last push, the tier from an attribute, and the
-- rate from the row. That is also what lets the number fall smoothly between
-- pushes instead of stepping four times a second.

local function holdSeconds(key, def)
	return perTier(def.SecondsPerTier, tierOf(key)) or 0
end

local function shownCharge()
	if not active then
		return charge
	end
	local def = Config.abilityDef(active)
	local seconds = def and holdSeconds(active, def) or 0
	if seconds <= 0 then
		return charge
	end
	return math.max(0, charge - (os.clock() - sampledAt) / seconds)
end

RunService.RenderStepped:Connect(function()
	if not bar.Visible then
		return
	end

	local key = selectedKey()
	local def = key and Config.abilityDef(key)
	local left = shownCharge()
	fill.Size = UDim2.fromScale(math.clamp(left, 0, 1), 1)

	if not def then
		fill.BackgroundColor3 = DIM
		hint.Text = "Pick an ability"
		hint.TextColor3 = DIM
		return
	end

	local color = def.Color
	if grace then
		fill.BackgroundColor3 = GRACE
		hint.Text = "SQUEEZE OUT!"
		hint.TextColor3 = GRACE
	elseif def.Mode == "Cast" then
		local cost = perTier(def.ChargeCostPerTier, tierOf(key)) or 1
		local casts = math.floor(left / cost)
		if casts < 1 then
			fill.BackgroundColor3 = EMPTY
			hint.Text = "PRESS [Q]  empty"
			hint.TextColor3 = EMPTY
		else
			fill.BackgroundColor3 = color
			-- Casts left rather than seconds, because for a Cast the charge is not a
			-- duration and a clock counting down would be the wrong promise.
			hint.Text = string.format("PRESS [Q]  %d left", casts)
			hint.TextColor3 = color
		end
	else
		local seconds = left * holdSeconds(key, def)
		-- Running is tested before empty, because a hold does not stop at
		-- MinimumToStart: that floor is only what it takes to *begin* one, and a
		-- phase already under way runs the charge to zero. Reading them the other
		-- way round put "empty" under a player who was still walking through a wall.
		if active then
			fill.BackgroundColor3 = Color3.fromRGB(255, 240, 150)
			hint.Text = string.format("USING  %.1fs", seconds)
			hint.TextColor3 = Color3.fromRGB(255, 240, 150)
		elseif left <= Config.Abilities.MinimumToStart then
			fill.BackgroundColor3 = EMPTY
			hint.Text = "HOLD [Q]  empty"
			hint.TextColor3 = EMPTY
		else
			fill.BackgroundColor3 = color
			-- The key stays in the text on every branch. A label written once at
			-- build time is a hint nobody ever sees, because the first visible frame
			-- overwrites it; that was a real bug in the chip this replaced.
			hint.Text = string.format("HOLD [Q]  %.1fs", seconds)
			hint.TextColor3 = color
		end
	end
end)

-- ============================================================
-- Input
-- ============================================================
-- ContextActionService rather than UserInputService, for the reason the sprint
-- and wall walk chips both give: it hands over the touch button for free, and
-- the same binding covers a gamepad face button. L1 and R1 are taken by the wall
-- walk key's old binding and by sprint, so the ability key is ButtonX and the
-- selector is the D-pad.

local function handleUse(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		intents:FireServer({ kind = "use" })
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		intents:FireServer({ kind = "release" })
	end
	return Enum.ContextActionResult.Pass
end

local function selectIndex(index)
	local key = owned[index]
	if key then
		intents:FireServer({ kind = "select", ability = key })
	end
end

local function handleSelect(_, inputState, input)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	for i, keyCode in ipairs(NUMBER_KEYS) do
		if input.KeyCode == keyCode then
			selectIndex(i)
			break
		end
	end
	return Enum.ContextActionResult.Pass
end

-- Cycling exists for the gamepad, which has no number row, and it is a nicety on
-- a keyboard. It steps through the owned list from wherever the selection
-- currently is, so it is the same walk the buttons do left to right.
local function handleCycle(_, inputState, input)
	if inputState ~= Enum.UserInputState.Begin or #owned == 0 then
		return Enum.ContextActionResult.Pass
	end
	local step = (input.KeyCode == Enum.KeyCode.DPadLeft) and -1 or 1
	local current = 1
	local selected = selectedKey()
	for i, key in ipairs(owned) do
		if key == selected then
			current = i
			break
		end
	end
	selectIndex((current - 1 + step) % #owned + 1)
	return Enum.ContextActionResult.Pass
end

-- Bound only while something is owned, which matters on a phone rather than on a
-- keyboard: `createTouchButton` is true for the use action, so leaving it bound
-- would put a USE button on screen for a player who has never been to the stall
-- and give them nothing when they press it. The selector bindings are keyboard
-- and gamepad only and could stay, but they follow the same switch so there is
-- one answer to "is the bar live" rather than two.
local bound = false

function setBound(live)
	if live == bound then
		return
	end
	bound = live
	if live then
		ContextActionService:BindAction(USE_ACTION, handleUse, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonX)
		ContextActionService:SetTitle(USE_ACTION, "USE")
		ContextActionService:BindAction(SELECT_ACTION, handleSelect, false, table.unpack(NUMBER_KEYS))
		ContextActionService:BindAction(CYCLE_ACTION, handleCycle, false, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight)
	else
		ContextActionService:UnbindAction(USE_ACTION)
		ContextActionService:UnbindAction(SELECT_ACTION)
		ContextActionService:UnbindAction(CYCLE_ACTION)
	end
end

-- ============================================================
-- Wiring
-- ============================================================

for _, key in ipairs(Config.Abilities.Order) do
	player:GetAttributeChangedSignal("AbilityTier_" .. key):Connect(rebuild)
end
player:GetAttributeChangedSignal("SelectedAbility"):Connect(paintButtons)

remote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or payload.kind ~= "state" then
		return
	end

	charge = payload.charge or 0
	active = payload.active
	grace = payload.grace == true
	sampledAt = os.clock()

	local event = payload.event
	if not event then
		return
	end

	local juice = Config.Juice
	if event.kind == "started" then
		playSound(Config.Sounds.PhantomPass, juice.PhantomSparkleVolume, 0.8)
	elseif event.kind == "cast" then
		playSound(Config.Sounds.PowerupPickup, juice.PowerupVolume, 1.1)
	elseif event.kind == "empty" or event.kind == "denied" then
		playSound(Config.Sounds.CoinPickup, juice.CoinVolume, juice.ShopDeniedPitch)
	elseif event.kind == "selected" then
		playSound(Config.Sounds.CoinPickup, juice.CoinVolume * 0.6, 1.4)
	elseif event.kind == "refilled" or event.kind == "respawn" then
		-- A flash rather than a chime. The charge refills on every floor, and a
		-- sound there would be the most repeated noise in a ten floor climb.
		bar.BackgroundTransparency = 0.05
		task.delay(0.25, function()
			bar.BackgroundTransparency = 0.25
		end)
	end
end)

rebuild()
