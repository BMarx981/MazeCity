-- PetGui (LocalScript) -> StarterPlayer/StarterPlayerScripts
-- The whole surface of the pet system: the inventory panel, the egg shelf, the
-- summit roost, the daily claim, the hatch reveal and the server-wide rarity
-- announcement.
--
-- It draws what the server sent and nothing else. Every number in here arrived
-- in a PetUpdate projection with the levels, stages and multipliers already
-- resolved, so the client never has to agree with the server about what level a
-- pet is; it agrees by not having an opinion. Buttons fire intents and then wait
-- to be told what happened, including when the answer is no.
--
-- Its own ScreenGui, not TimerGui's: the floor HUD is up during a climb and this
-- is up when the player stops to look at something, and sharing a banner between
-- them would mean a hatch reveal competing with a floor clear for the same
-- frame.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local EggCatalog = require(ReplicatedStorage:WaitForChild("EggCatalog"))

local remote = ReplicatedStorage:WaitForChild("PetUpdate")
local intents = ReplicatedStorage:WaitForChild("PetIntent")
local player = Players.LocalPlayer

local WHITE = Color3.fromRGB(255, 255, 255)
local DIM = Color3.fromRGB(150, 160, 175)
local PANEL = Color3.fromRGB(16, 16, 20)
local ROW = Color3.fromRGB(28, 29, 36)
local GOLD = Color3.fromRGB(255, 214, 110)
local GREEN = Color3.fromRGB(90, 200, 140)
local RED = Color3.fromRGB(230, 80, 80)

local SECONDS_PER_DAY = 86400
local PANEL_W = Config.Pets.PanelWidth
local PANEL_H = 470
local ROW_H = 62

-- Distance at which the Place button lights up. The server re-checks this with
-- its own slack, so being generous here only ever costs a refusal the player
-- can read, never a placement they should have had.
local ROOST_REACH = Config.Pets.PromptDistance + 4

-- The last projection the server sent. Everything drawn below is a function of
-- this table; nothing is computed from a button press.
local state = nil
local dailyAvailable = false
local openTab = "Pets"
local nickTarget = nil

-- ============================================================
-- Widgets
-- ============================================================

local gui = Instance.new("ScreenGui")
gui.Name = "PetHud"
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

local function button(parent, size, position, text, color)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.TextColor3 = WHITE
	b.Text = text
	b.Parent = parent
	rounded(b, 6)
	return b
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

-- ============================================================
-- Toggle button
-- ============================================================
-- Top left. Every other corner is taken: TimerGui's chips run down the right
-- edge, its floor panel is top centre, and on a phone the bottom two corners are
-- the thumbstick and the jump button.

local toggle = button(gui, UDim2.fromOffset(112, 40), UDim2.new(0, 16, 0, 16), "PETS", PANEL)
toggle.BackgroundTransparency = 0.25

-- The one thing on the toggle that is not a label: an unclaimed daily, or an egg
-- that has finished and cannot hatch, is worth a dot the player can see without
-- opening anything.
local badge = Instance.new("Frame")
badge.Size = UDim2.fromOffset(12, 12)
badge.Position = UDim2.new(1, -8, 0, -4)
badge.BackgroundColor3 = GOLD
badge.BorderSizePixel = 0
badge.Visible = false
badge.Parent = toggle
rounded(badge, 6)

-- ============================================================
-- Panel
-- ============================================================

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.Position = UDim2.new(0.5, -PANEL_W / 2, 0.5, -PANEL_H / 2)
panel.BackgroundColor3 = PANEL
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
rounded(panel, 10)

local title = label(panel, UDim2.new(1, -80, 0, 34), UDim2.new(0, 16, 0, 10), Enum.Font.GothamBlack, 22, WHITE)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Pets"

local closeButton = button(panel, UDim2.fromOffset(30, 30), UDim2.new(1, -42, 0, 12), "X", ROW)

local capLabel = label(panel, UDim2.new(1, -32, 0, 18), UDim2.new(0, 16, 0, 40), Enum.Font.Gotham, 13, DIM)
capLabel.TextXAlignment = Enum.TextXAlignment.Left

local tabRow = Instance.new("Frame")
tabRow.Size = UDim2.new(1, -32, 0, 32)
tabRow.Position = UDim2.new(0, 16, 0, 62)
tabRow.BackgroundTransparency = 1
tabRow.Parent = panel

local TABS = { "Pets", "Eggs", "Daily" }
local tabButtons = {}
for i, name in ipairs(TABS) do
	local width = 1 / #TABS
	tabButtons[name] =
		button(tabRow, UDim2.new(width, -6, 1, 0), UDim2.new(width * (i - 1), 3, 0, 0), string.upper(name), ROW)
end

-- Stops above the rename box rather than under it: the box is parented to the
-- panel and not to the list, so that a rebuild mid-typing cannot destroy the
-- field under the player's fingers, and the price of that is reserving its
-- height here.
local body = Instance.new("ScrollingFrame")
body.Size = UDim2.new(1, -24, 1, -158)
body.Position = UDim2.new(0, 12, 0, 102)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 5
body.CanvasSize = UDim2.new()
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.Parent = panel

local bodyLayout = Instance.new("UIListLayout")
bodyLayout.Padding = UDim.new(0, 6)
bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
bodyLayout.Parent = body

-- The rename field lives outside the list so a rebuild mid-typing does not
-- destroy the box under the player's fingers.
local nickBox = Instance.new("TextBox")
nickBox.Size = UDim2.new(1, -24, 0, 34)
nickBox.Position = UDim2.new(0, 12, 1, -46)
nickBox.BackgroundColor3 = ROW
nickBox.BorderSizePixel = 0
nickBox.Font = Enum.Font.Gotham
nickBox.TextSize = 14
nickBox.TextColor3 = WHITE
nickBox.PlaceholderText = "New name, then Enter"
nickBox.Text = ""
nickBox.ClearTextOnFocus = false
nickBox.Visible = false
nickBox.Parent = panel
rounded(nickBox, 6)

-- ============================================================
-- Banner and reveal
-- ============================================================

local banner = Instance.new("Frame")
banner.Size = UDim2.fromOffset(460, 92)
banner.Position = UDim2.new(0.5, -230, 0.2, 0)
banner.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
banner.BackgroundTransparency = 1
banner.BorderSizePixel = 0
banner.Visible = false
banner.ZIndex = 8
banner.Parent = gui
rounded(banner, 10)

local bannerTitle = label(banner, UDim2.new(1, 0, 0, 44), UDim2.new(0, 0, 0, 12), Enum.Font.GothamBlack, 32, WHITE)
bannerTitle.ZIndex = 8
local bannerSub = label(banner, UDim2.new(1, 0, 0, 26), UDim2.new(0, 0, 0, 56), Enum.Font.GothamBold, 18, GOLD)
bannerSub.ZIndex = 8

local bannerToken = 0

local function showBanner(text, subtitle, color, hold)
	bannerToken = bannerToken + 1
	local token = bannerToken

	bannerTitle.Text = text
	bannerTitle.TextColor3 = color
	bannerSub.Text = subtitle or ""

	banner.Visible = true
	banner.BackgroundTransparency = 1
	banner.Position = UDim2.new(0.5, -230, 0.2, 16)
	bannerTitle.TextTransparency = 1
	bannerSub.TextTransparency = 1

	tween(banner, 0.2, { BackgroundTransparency = 0.25, Position = UDim2.new(0.5, -230, 0.2, 0) })
	tween(bannerTitle, 0.2, { TextTransparency = 0 })
	tween(bannerSub, 0.2, { TextTransparency = 0 })

	task.delay(hold, function()
		if token ~= bannerToken then
			return
		end
		tween(banner, 0.4, { BackgroundTransparency = 1, Position = UDim2.new(0.5, -230, 0.2, -16) })
		tween(bannerTitle, 0.4, { TextTransparency = 1 })
		tween(bannerSub, 0.4, { TextTransparency = 1 })
		task.delay(0.45, function()
			if token == bannerToken then
				banner.Visible = false
			end
		end)
	end)
end

-- The hatch is the moment the whole system is built around, so it gets a full
-- screen wash in the pet's rarity colour rather than the banner every other
-- outcome shares. Rays scale with rarity: a Common gets a modest fan, a
-- Legendary fills the screen, and the difference is legible before the name has
-- finished fading in.
local reveal = Instance.new("Frame")
reveal.Size = UDim2.fromScale(1, 1)
reveal.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
reveal.BackgroundTransparency = 1
reveal.BorderSizePixel = 0
reveal.Visible = false
reveal.ZIndex = 9
reveal.Parent = gui

local revealTitle = label(reveal, UDim2.new(1, 0, 0, 60), UDim2.new(0, 0, 0.42, 0), Enum.Font.GothamBlack, 46, WHITE)
revealTitle.ZIndex = 11
local revealSub = label(reveal, UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0.42, 62), Enum.Font.GothamBold, 20, WHITE)
revealSub.ZIndex = 11

local function showReveal(name, rarity, ability)
	local color = Config.rarityColor(rarity)
	local rays = 6 + Config.rarityIndex(rarity) * 6

	reveal.Visible = true
	reveal.BackgroundTransparency = 0.35
	revealTitle.Text = name
	revealTitle.TextColor3 = color
	revealTitle.TextTransparency = 1
	revealSub.Text = string.upper(rarity) .. "  |  " .. ability
	revealSub.TextColor3 = color
	revealSub.TextTransparency = 1

	for i = 1, rays do
		local ray = Instance.new("Frame")
		ray.AnchorPoint = Vector2.new(0.5, 1)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.fromOffset(6, 0)
		ray.BackgroundColor3 = color
		ray.BorderSizePixel = 0
		ray.Rotation = (i / rays) * 360
		ray.ZIndex = 10
		ray.Parent = reveal
		TweenService:Create(ray, TweenInfo.new(Config.Pets.HatchRevealSeconds, Enum.EasingStyle.Quint), {
			Size = UDim2.fromOffset(6, 700),
			BackgroundTransparency = 1,
		}):Play()
		Debris:AddItem(ray, Config.Pets.HatchRevealSeconds + 0.3)
	end

	tween(revealTitle, 0.35, { TextTransparency = 0 })
	tween(revealSub, 0.35, { TextTransparency = 0 })
	for _, note in ipairs(Config.Sounds.TowerClearArpeggio) do
		task.delay(note[1], function()
			playSound(Config.Sounds.PowerupPickup, Config.Juice.PowerupVolume, note[2])
		end)
	end

	task.delay(Config.Pets.HatchRevealSeconds, function()
		tween(reveal, 0.5, { BackgroundTransparency = 1 })
		tween(revealTitle, 0.5, { TextTransparency = 1 })
		tween(revealSub, 0.5, { TextTransparency = 1 })
		task.delay(0.55, function()
			reveal.Visible = false
		end)
	end)
end

-- ============================================================
-- Reasons
-- ============================================================
-- A refusal the player cannot read is a bug they will report as "the button does
-- nothing", so every reason the server can send has a sentence here. The ones
-- that are genuinely not worth interrupting for are mapped to nil deliberately
-- rather than by omission.

local REASONS = {
	notatroost = "Stand at an egg roost on a roof",
	occupied = "An egg is already hatching",
	noegg = "You do not have that egg",
	eggsfull = "Your egg shelf is full",
	petsfull = "Your pet storage is full",
	equipfull = "Too many pets out already",
	notready = "That egg is not ready yet",
	expired = "That egg is no longer available",
	unknown = "That is not available",
	filter = "Try a different name",
	claimed = "Already claimed, come back tomorrow",
	nopet = nil,
	notequipped = nil,
	already = nil,
}

-- ============================================================
-- Rows
-- ============================================================

local function clearBody()
	for _, child in ipairs(body:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local function row(order, height)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, -6, 0, height or ROW_H)
	frame.BackgroundColor3 = ROW
	frame.BorderSizePixel = 0
	frame.LayoutOrder = order
	frame.Parent = body
	rounded(frame, 8)
	return frame
end

local function emptyNote(text)
	local frame = row(1, 46)
	frame.BackgroundTransparency = 0.4
	local l = label(frame, UDim2.new(1, -24, 1, 0), UDim2.new(0, 12, 0, 0), Enum.Font.Gotham, 14, DIM)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.TextWrapped = true
end

local function send(payload)
	intents:FireServer(payload)
end

local function nearRoost()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	for _, part in ipairs(CollectionService:GetTagged("EggPedestal")) do
		if part.Parent and (part.Position - root.Position).Magnitude <= ROOST_REACH then
			return true
		end
	end
	return false
end

local function petRow(pet, order)
	local frame = row(order)

	local swatch = Instance.new("Frame")
	swatch.Size = UDim2.fromOffset(6, ROW_H - 16)
	swatch.Position = UDim2.new(0, 8, 0, 8)
	swatch.BackgroundColor3 = Config.rarityColor(pet.rarity)
	swatch.BorderSizePixel = 0
	swatch.Parent = frame
	rounded(swatch, 3)

	local name = label(frame, UDim2.new(0, 190, 0, 20), UDim2.new(0, 22, 0, 8), Enum.Font.GothamBold, 15, WHITE)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = (pet.locked and "[L] " or "") .. pet.name

	local sub = label(frame, UDim2.new(0, 190, 0, 16), UDim2.new(0, 22, 0, 28), Enum.Font.Gotham, 12, DIM)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	local multiplier = pet.multiplier > 1 and string.format("  x%.1f", pet.multiplier) or ""
	sub.Text = string.format("Lv %d  |  %s%s", pet.level, pet.ability, multiplier)

	-- A pet at max level has no xpNeed, which draws as a full bar rather than an
	-- empty one: the alternative reads as a pet that stopped earning by mistake.
	local track = Instance.new("Frame")
	track.Size = UDim2.new(0, 190, 0, 4)
	track.Position = UDim2.new(0, 22, 0, 48)
	track.BackgroundColor3 = Color3.fromRGB(50, 52, 62)
	track.BorderSizePixel = 0
	track.Parent = frame

	local ratio = pet.xpNeed and math.clamp(pet.xpInto / pet.xpNeed, 0, 1) or 1
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(ratio, 1)
	fill.BackgroundColor3 = Config.rarityColor(pet.rarity)
	fill.BorderSizePixel = 0
	fill.Parent = track

	-- Right hand column, sized against the 390 a row actually gets: equip and lock
	-- share the top line, rename spans both underneath. The text on the left is
	-- 190 wide from x=22, so 218 is where this column can start without ever
	-- running into a long nickname.
	local equip = button(
		frame,
		UDim2.fromOffset(82, 26),
		UDim2.new(1, -172, 0, 8),
		pet.equipped and "UNEQUIP" or "EQUIP",
		pet.equipped and GREEN or Color3.fromRGB(60, 62, 74)
	)
	equip.TextSize = 12
	equip.MouseButton1Click:Connect(function()
		send({ kind = pet.equipped and "unequip" or "equip", petUid = pet.uid })
	end)

	local lock = button(
		frame,
		UDim2.fromOffset(76, 26),
		UDim2.new(1, -84, 0, 8),
		pet.locked and "UNLOCK" or "LOCK",
		Color3.fromRGB(60, 62, 74)
	)
	lock.TextSize = 12
	lock.MouseButton1Click:Connect(function()
		send({ kind = "lock", petUid = pet.uid, locked = not pet.locked })
	end)

	local rename =
		button(frame, UDim2.fromOffset(164, 22), UDim2.new(1, -172, 0, 38), "RENAME", Color3.fromRGB(60, 62, 74))
	rename.TextSize = 11
	rename.MouseButton1Click:Connect(function()
		nickTarget = pet.uid
		nickBox.Visible = true
		nickBox.Text = pet.nickname or ""
		nickBox.PlaceholderText = "New name for " .. pet.name
		nickBox:CaptureFocus()
	end)
end

-- The button says why it cannot be pressed rather than going grey and silent: a
-- Place that does nothing is the exact failure the REASONS table exists to stop,
-- and here the reason is knowable before the press.
local function eggRow(egg, order, canPlace, blockedBy)
	local frame = row(order, 46)

	local swatch = Instance.new("Frame")
	swatch.Size = UDim2.fromOffset(6, 30)
	swatch.Position = UDim2.new(0, 8, 0, 8)
	swatch.BackgroundColor3 = egg.color
	swatch.BorderSizePixel = 0
	swatch.Parent = frame
	rounded(swatch, 3)

	local name = label(frame, UDim2.new(0, 210, 0, 18), UDim2.new(0, 22, 0, 6), Enum.Font.GothamBold, 14, WHITE)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = egg.name

	local sub = label(frame, UDim2.new(0, 210, 0, 14), UDim2.new(0, 22, 0, 24), Enum.Font.Gotham, 11, DIM)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Text = string.format("%d %s to hatch", egg.required, Config.Pets.HatchUnit == "tower" and "towers" or "floors")

	local place = button(
		frame,
		UDim2.fromOffset(96, 26),
		UDim2.new(1, -108, 0, 10),
		canPlace and "PLACE" or blockedBy,
		canPlace and GREEN or Color3.fromRGB(52, 54, 64)
	)
	place.TextSize = canPlace and 13 or 10
	place.MouseButton1Click:Connect(function()
		send({ kind = "placeEgg", eggUid = egg.uid })
	end)
end

local function shelfRow(eggConfig, order, canBuy)
	local frame = row(order, 46)
	frame.BackgroundTransparency = 0.35

	local name =
		label(frame, UDim2.new(0, 210, 0, 18), UDim2.new(0, 14, 0, 6), Enum.Font.GothamBold, 14, eggConfig.color)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = eggConfig.name

	local sub = label(frame, UDim2.new(0, 210, 0, 14), UDim2.new(0, 14, 0, 24), Enum.Font.Gotham, 11, DIM)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Text = string.format(
		"%d coins  |  %d %s",
		eggConfig.coinCost,
		eggConfig.mazesRequired,
		Config.Pets.HatchUnit == "tower" and "towers" or "floors"
	)

	local buy = button(
		frame,
		UDim2.fromOffset(96, 26),
		UDim2.new(1, -108, 0, 10),
		canBuy and "BUY" or "AT A ROOST",
		canBuy and GOLD or Color3.fromRGB(52, 54, 64)
	)
	buy.TextSize = canBuy and 13 or 10
	buy.TextColor3 = canBuy and Color3.fromRGB(30, 26, 12) or WHITE
	buy.MouseButton1Click:Connect(function()
		send({ kind = "buyEgg", eggId = eggConfig.id })
	end)
end

local function incubatorRow(incubator, order)
	local frame = row(order, 58)
	frame.BackgroundColor3 = Color3.fromRGB(34, 38, 44)

	local name =
		label(frame, UDim2.new(1, -24, 0, 20), UDim2.new(0, 14, 0, 8), Enum.Font.GothamBold, 15, incubator.color)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = incubator.name .. " is hatching"

	local sub = label(frame, UDim2.new(1, -24, 0, 16), UDim2.new(0, 14, 0, 28), Enum.Font.Gotham, 12, DIM)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	local unit = Config.Pets.HatchUnit == "tower" and "towers" or "floors"
	sub.Text = string.format("%d / %d %s", math.min(incubator.done, incubator.required), incubator.required, unit)

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -28, 0, 5)
	track.Position = UDim2.new(0, 14, 1, -12)
	track.BackgroundColor3 = Color3.fromRGB(50, 52, 62)
	track.BorderSizePixel = 0
	track.Parent = frame

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(math.clamp(incubator.done / math.max(1, incubator.required), 0, 1), 1)
	fill.BackgroundColor3 = incubator.color
	fill.BorderSizePixel = 0
	fill.Parent = track

	-- Only ever shown for an egg that is finished and did not hatch, which today
	-- means the pet shelf was full when it came due.
	if incubator.done >= incubator.required then
		local hatch = button(frame, UDim2.fromOffset(84, 24), UDim2.new(1, -96, 0, 8), "HATCH", GREEN)
		hatch.MouseButton1Click:Connect(function()
			send({ kind = "hatch" })
		end)
	end
end

-- ============================================================
-- Tabs
-- ============================================================

local function drawPets()
	title.Text = "Pets"
	capLabel.Text = string.format(
		"%d of %d kept  |  %d of %d out",
		state.petCount,
		state.petCap,
		#state.equipped,
		state.maxEquipped
	)
	if #state.pets == 0 then
		emptyNote("No pets yet. Put an egg on a roof roost and climb.")
		return
	end
	for i, pet in ipairs(state.pets) do
		petRow(pet, i)
	end
end

local function drawEggs()
	title.Text = "Eggs"
	capLabel.Text = string.format("%d of %d on the shelf", state.eggCount, state.eggCap)

	local order = 0
	if state.incubator then
		order = order + 1
		incubatorRow(state.incubator, order)
	end

	local canReach = nearRoost()
	local blockedBy = state.incubator and "SLOT FULL" or "AT A ROOST"
	for _, egg in ipairs(state.eggs) do
		order = order + 1
		eggRow(egg, order, canReach and not state.incubator, blockedBy)
	end
	if #state.eggs == 0 and not state.incubator then
		order = order + 1
		emptyNote("No eggs. Buy one at a roof roost below.")
	end

	-- The shelf is every catalogued egg with a price. Sorted by cost so the one a
	-- new player can afford is the one at the top.
	local forSale = {}
	for _, eggConfig in pairs(EggCatalog) do
		if eggConfig.coinCost then
			table.insert(forSale, eggConfig)
		end
	end
	table.sort(forSale, function(a, b)
		return a.coinCost < b.coinCost
	end)
	for _, eggConfig in ipairs(forSale) do
		order = order + 1
		shelfRow(eggConfig, order, canReach)
	end
end

local function drawDaily()
	title.Text = "Daily"
	capLabel.Text = "One claim per day, UTC"

	local streak = state.daily and state.daily.streak or 0
	local length = Config.Pets.DailyStreakLength

	local frame = row(1, 96)
	local head = label(frame, UDim2.new(1, -24, 0, 24), UDim2.new(0, 14, 0, 10), Enum.Font.GothamBold, 17, WHITE)
	head.TextXAlignment = Enum.TextXAlignment.Left
	head.Text = string.format("Day %d of %d", math.max(1, streak), length)

	local sub = label(frame, UDim2.new(1, -24, 0, 18), UDim2.new(0, 14, 0, 34), Enum.Font.Gotham, 12, DIM)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Text = string.format(
		"%d coins and %d XP today. Day %d pays a Streak Egg.",
		Config.Pets.DailyCoinBase + math.max(0, streak) * Config.Pets.DailyCoinPerStreak,
		Config.Pets.DailyXpBase + math.max(0, streak) * Config.Pets.DailyXpPerStreak,
		length
	)
	sub.TextWrapped = true

	local pips = Instance.new("Frame")
	pips.Size = UDim2.new(1, -28, 0, 10)
	pips.Position = UDim2.new(0, 14, 0, 60)
	pips.BackgroundTransparency = 1
	pips.Parent = frame

	for i = 1, length do
		local pip = Instance.new("Frame")
		pip.Size = UDim2.new(1 / length, -4, 1, 0)
		pip.Position = UDim2.new((i - 1) / length, 2, 0, 0)
		pip.BackgroundColor3 = i <= streak and GOLD or Color3.fromRGB(50, 52, 62)
		pip.BorderSizePixel = 0
		pip.Parent = pips
		rounded(pip, 4)
	end

	local claim = button(
		body,
		UDim2.new(1, -6, 0, 40),
		UDim2.new(),
		dailyAvailable and "CLAIM TODAY" or "CLAIMED, COME BACK TOMORROW",
		dailyAvailable and GOLD or Color3.fromRGB(52, 54, 64)
	)
	claim.LayoutOrder = 2
	claim.TextSize = dailyAvailable and 16 or 12
	claim.TextColor3 = dailyAvailable and Color3.fromRGB(30, 26, 12) or DIM
	claim.MouseButton1Click:Connect(function()
		send({ kind = "daily" })
	end)

	local stats = row(3, 68)
	stats.BackgroundTransparency = 0.4
	local statLabel = label(stats, UDim2.new(1, -24, 1, -12), UDim2.new(0, 14, 0, 6), Enum.Font.Gotham, 12, DIM)
	statLabel.TextXAlignment = Enum.TextXAlignment.Left
	statLabel.TextYAlignment = Enum.TextYAlignment.Top
	local s = state.stats or {}
	statLabel.Text = string.format(
		"Floors cleared  %d\nSummits reached  %d\nEggs hatched  %d",
		s.floorsCleared or 0,
		s.summitsReached or 0,
		s.eggsHatched or 0
	)
end

local function refresh()
	if not panel.Visible or not state then
		return
	end
	clearBody()
	for name, tabButton in pairs(tabButtons) do
		tabButton.BackgroundColor3 = name == openTab and Color3.fromRGB(60, 62, 74) or ROW
	end
	if openTab == "Pets" then
		drawPets()
	elseif openTab == "Eggs" then
		drawEggs()
	else
		drawDaily()
	end
end

-- Walking up to a roost with the panel already open has to light the Place
-- button, and no server message accompanies a walk. Redrawn only when
-- reachability actually flips, because a rebuild every half second would reset
-- the scroll position under anyone reading the list.
task.spawn(function()
	local lastReach = nil
	while true do
		if panel.Visible and openTab == "Eggs" then
			local reach = nearRoost()
			if reach ~= lastReach then
				lastReach = reach
				refresh()
			end
		else
			lastReach = nil
		end
		task.wait(0.5)
	end
end)

local function updateBadge()
	local stuck = state and state.incubator and state.incubator.done >= state.incubator.required
	badge.Visible = dailyAvailable or stuck == true
end

local function openPanel(tab)
	openTab = tab or openTab
	panel.Visible = true
	nickBox.Visible = false
	nickTarget = nil
	if not state then
		send({ kind = "sync" })
	end
	refresh()
end

local function closePanel()
	panel.Visible = false
	nickBox.Visible = false
	nickTarget = nil
end

toggle.MouseButton1Click:Connect(function()
	if panel.Visible then
		closePanel()
	else
		openPanel()
	end
end)

closeButton.MouseButton1Click:Connect(closePanel)

for name, tabButton in pairs(tabButtons) do
	tabButton.MouseButton1Click:Connect(function()
		openTab = name
		nickBox.Visible = false
		nickTarget = nil
		refresh()
	end)
end

nickBox.FocusLost:Connect(function(enterPressed)
	local target = nickTarget
	nickBox.Visible = false
	nickTarget = nil
	if enterPressed and target then
		send({ kind = "nickname", petUid = target, nickname = nickBox.Text })
	end
end)

-- ============================================================
-- The egg over the roost
-- ============================================================
-- A placed egg is per player and every roof in the city has a roost, so the egg
-- the player is hatching is drawn by their own client over whichever roost they
-- are standing at. Same rule the Reveal trail follows: markers go in a model of
-- this client's own beside MazeCity, never inside it.

local hintModel = nil

local function clearHint()
	if hintModel then
		hintModel:Destroy()
		hintModel = nil
	end
end

local function nearestPedestal(root)
	local best, bestDistance = nil, ROOST_REACH * 2
	for _, part in ipairs(CollectionService:GetTagged("EggPedestal")) do
		if part.Parent then
			local distance = (part.Position - root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = part, distance
			end
		end
	end
	return best
end

task.spawn(function()
	while true do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local incubator = state and state.incubator
		local pedestal = (root and incubator) and nearestPedestal(root) or nil

		if not pedestal then
			clearHint()
		else
			if not hintModel then
				hintModel = Instance.new("Model")
				hintModel.Name = "EggHint"

				local egg = Instance.new("Part")
				egg.Name = "Egg"
				egg.Shape = Enum.PartType.Ball
				egg.Size = Vector3.new(3, 3.8, 3)
				egg.Anchored = true
				egg.CanCollide = false
				egg.CanTouch = false
				egg.CanQuery = false
				egg.CastShadow = false
				egg.Material = Enum.Material.Neon
				egg.Parent = hintModel

				hintModel.PrimaryPart = egg
				hintModel.Parent = workspace
			end
			local egg = hintModel.PrimaryPart
			egg.Color = incubator.color
			egg.Position = pedestal.Position + Vector3.new(0, 6, 0)
		end
		task.wait(0.5)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	if hintModel and hintModel.PrimaryPart then
		hintModel.PrimaryPart.CFrame = hintModel.PrimaryPart.CFrame
			* CFrame.Angles(0, math.rad(Config.Pets.SpinDegreesPerSecond * dt), 0)
	end
end)

player.CharacterAdded:Connect(clearHint)

-- ============================================================
-- Server messages
-- ============================================================

local function playEvent(event)
	if not event then
		return
	end

	if event.kind == "hatched" then
		showReveal(event.name, event.rarity, event.ability)
	elseif event.kind == "levelup" then
		local what = event.pet.evolved and "evolved!" or string.format("reached level %d", event.pet.level)
		showBanner(event.pet.name .. " " .. what, "", Config.rarityColor(event.pet.rarity), 2)
		playSound(Config.Sounds.PowerupPickup, Config.Juice.PowerupVolume, 1.4)
	elseif event.kind == "placed" then
		showBanner("Egg placed", "Climb to hatch it", GREEN, 2)
	elseif event.kind == "bought" then
		showBanner(event.name, string.format("-%d coins", event.cost), GOLD, 1.8)
	elseif event.kind == "starter" then
		showBanner("A free egg!", "Open PETS to place it at a roof roost", GOLD, 4)
	elseif event.kind == "daily" then
		local parts = { string.format("+%d coins", event.coins) }
		if event.xp > 0 then
			table.insert(parts, string.format("+%d XP", event.xp))
		end
		if event.egg then
			table.insert(parts, event.egg .. "!")
		end
		dailyAvailable = false
		showBanner(string.format("Day %d streak", event.streak), table.concat(parts, "  |  "), GOLD, 3)
	elseif event.kind == "incubated" then
		-- Fires alongside TimerGui's own tower celebration, so it is deliberately
		-- short and quiet: the point is the count, not another fanfare.
		local unit = Config.Pets.HatchUnit == "tower" and "towers" or "floors"
		showBanner(
			string.format("Egg  %d / %d", math.min(event.done, event.required), event.required),
			string.format("%s to go", unit),
			GREEN,
			1.5
		)
	end
end

remote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end

	if payload.kind == "state" then
		state = payload
		-- The projection carries the stored day; whether today has been claimed is
		-- a comparison the client can make on its own, os.time being UTC epoch on
		-- both ends, so a claim needs no second message to update the button.
		if state.daily then
			dailyAvailable = math.floor(os.time() / SECONDS_PER_DAY) > state.daily.lastClaimDayUtc
		end
		updateBadge()
		refresh()
		playEvent(payload.event)
	elseif payload.kind == "dailyStatus" then
		dailyAvailable = payload.available
		updateBadge()
		refresh()
	elseif payload.kind == "roost" then
		openPanel("Eggs")
	elseif payload.kind == "denied" then
		local text = REASONS[payload.reason]
		if payload.reason == "poor" then
			text = string.format("%d more coins for %s", payload.need, payload.label)
		end
		if text then
			showBanner(text, "", RED, 2)
			playSound(Config.Sounds.CoinPickup, Config.Juice.CoinVolume, Config.Juice.ShopDeniedPitch)
		end
	elseif payload.kind == "broadcast" then
		showBanner(
			string.format("%s hatched a %s!", payload.playerName, payload.petName),
			string.upper(payload.rarity),
			Config.rarityColor(payload.rarity),
			Config.Pets.BroadcastSeconds
		)
	end
end)

-- The panel is drawn from a projection, and the projection arrives on its own
-- when the profile is ready. This only covers the case where this script loaded
-- after that push went out.
task.delay(2, function()
	if not state then
		send({ kind = "sync" })
	end
end)

if not Config.Pets.Enabled then
	toggle.Visible = false
	gui.Enabled = false
end
