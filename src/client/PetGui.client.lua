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
-- Read for the shop list only, exactly as EggCatalog is above it, and that is
-- not the accessories plan's third invariant being bent: what an item costs is
-- not what an effect is worth. The owned rows still draw from the projection,
-- what a raw 0.25 means still comes from Config.Accessories, and nothing here
-- resolves an effect. A storefront has to be able to name a thing nobody owns.
local AccessoryCatalog = require(ReplicatedStorage:WaitForChild("AccessoryCatalog"))
-- Portraits are built here, from the recipes, not sent: the projection already
-- names the pet and the stage, so a row draws the same rig the follower is
-- without one extra byte over the remote.
local PetModelGenerator = require(ReplicatedStorage:WaitForChild("PetModelGenerator"))
local PortraitGenerator = require(ReplicatedStorage:WaitForChild("PortraitGenerator"))

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
-- Taller than the rest, because a pet row carries a strip of worn-gear chips
-- under its XP bar that nothing else has.
local PET_ROW_H = 78
-- The portrait square and where the text starts once it is in. A row is 390
-- wide and its right hand button column begins at 218, so the text column is
-- 132 rather than the 190 it had before the picture took the left edge.
local PORTRAIT = 58
local PET_TEXT_X = 82
local PET_TEXT_W = 132

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
-- The accessory uid waiting for a pet to be picked. Set by WEAR on a gear row,
-- cleared by the pick, by Cancel, and by anything that leaves the tab: a picker
-- still open over a list the player has moved on from is a press that lands
-- somewhere unexpected.
local gearTarget = nil

-- Forward declared, because opening and cancelling the picker are redraws of the
-- list the buttons doing it are drawn into.
local refresh

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

-- A ViewportFrame of the pet at that stage, or nil for a petId this client's
-- catalogue does not have. Nil rather than a fallback square: a row missing its
-- picture still says everything it said before Set 3, and the caller only has
-- to not parent it.
--
-- The caveat PET_LOOKS_PLAN records and accepts: this is always the generated
-- silhouette. An artist's model in ServerStorage/Pets is invisible to a client,
-- so it wins in the world and loses in the UI until a replicated template
-- folder exists, which is a different bargain. Same trade the bestiary made.
local function petPortrait(petId, stage, spin)
	local model = PetModelGenerator.build(petId, stage or 0)
	if not model then
		return nil
	end
	return PortraitGenerator.of(model, { spin = spin })
end

-- ============================================================
-- Toggle button
-- ============================================================
-- Left edge, vertically centred. It was at the top left corner, which is the one
-- place on a Roblox screen that is never actually free: the topbar owns the first
-- 36 pixels and the chat window hangs below it, so a button at (16, 16) under
-- IgnoreGuiInset sat behind both and the label could not be read at all. Nobody
-- notices that in Studio with chat closed.
--
-- Mid-left is the corner-free spot on every device. The rest of the screen is
-- spoken for: TimerGui's chips and the ability bar run down the right edge, the
-- floor panel is top centre, the sprint meter is the bottom right corner, and on
-- a phone the bottom two corners are the thumbstick and the jump button.

local toggle = button(gui, UDim2.fromOffset(112, 40), UDim2.new(0, 16, 0.5, 0), "PETS", PANEL)
toggle.AnchorPoint = Vector2.new(0, 0.5)
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

local TABS = { "Pets", "Eggs", "Gear", "Daily" }
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

local REVEAL_PORTRAIT = 240

-- The portrait currently on screen. Held rather than looked up, because it is
-- torn down from a delayed callback and from the next hatch, and a spinning
-- viewport left parented to a hidden frame is a RenderStepped connection
-- running for the rest of the session.
local revealPortrait = nil

local function clearRevealPortrait()
	if revealPortrait then
		revealPortrait:Destroy()
		revealPortrait = nil
	end
end

local function showReveal(name, rarity, ability, petId, stage)
	local color = Config.rarityColor(rarity)
	local rays = 6 + Config.rarityIndex(rarity) * 6

	clearRevealPortrait()
	if petId then
		revealPortrait = petPortrait(petId, stage, true)
	end
	if revealPortrait then
		revealPortrait.Size = UDim2.fromOffset(REVEAL_PORTRAIT, REVEAL_PORTRAIT)
		revealPortrait.Position = UDim2.new(0.5, -REVEAL_PORTRAIT / 2, 0.42, 96)
		revealPortrait.ZIndex = 11
		revealPortrait.ImageTransparency = 1
		revealPortrait.Parent = reveal
	end

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
	if revealPortrait then
		tween(revealPortrait, 0.35, { ImageTransparency = 0 })
	end
	for _, note in ipairs(Config.Sounds.TowerClearArpeggio) do
		task.delay(note[1], function()
			playSound(Config.Sounds.PowerupPickup, Config.Juice.PowerupVolume, note[2])
		end)
	end

	-- Compared rather than captured and destroyed outright, because a second
	-- hatch inside the reveal of the first has already replaced this one and
	-- must not have its picture taken down by its predecessor's timer.
	local mine = revealPortrait
	task.delay(Config.Pets.HatchRevealSeconds, function()
		tween(reveal, 0.5, { BackgroundTransparency = 1 })
		tween(revealTitle, 0.5, { TextTransparency = 1 })
		tween(revealSub, 0.5, { TextTransparency = 1 })
		if mine and revealPortrait == mine then
			tween(mine, 0.5, { ImageTransparency = 1 })
		end
		task.delay(0.55, function()
			if revealPortrait == mine then
				clearRevealPortrait()
				reveal.Visible = false
			end
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
	expired = "That one is no longer available",
	unknown = "That is not available",
	filter = "Try a different name",
	claimed = "Already claimed, come back tomorrow",
	noitem = "You do not have that piece of gear",
	gearfull = "Your gear bag is full",
	locked = "That item is locked",
	worn = "Take it off a pet first",
	notforsale = "That one is not for sale",
	nopet = nil,
	notequipped = nil,
	notworn = nil,
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

-- One chip per worn slot, in the rarity colour of what is in it, under the XP
-- bar. The initial rather than the name: four items in a text column this
-- narrow is four letters, and the Gear tab beside this is where the names are.
local function wornChips(frame, worn)
	local index = 0
	for _, slot in ipairs(Config.Accessories.Slots) do
		local item = worn and worn[slot]
		if item then
			local chip = Instance.new("Frame")
			chip.Size = UDim2.fromOffset(30, 16)
			chip.Position = UDim2.new(0, PET_TEXT_X + index * 34, 0, 56)
			chip.BackgroundColor3 = Config.rarityColor(item.rarity)
			chip.BorderSizePixel = 0
			chip.Parent = frame
			rounded(chip, 4)

			local mark = label(chip, UDim2.fromScale(1, 1), UDim2.new(), Enum.Font.GothamBold, 11, PANEL)
			mark.Text = string.sub(slot, 1, 1)
			index = index + 1
		end
	end
end

local function petRow(pet, order)
	local frame = row(order, PET_ROW_H)

	local swatch = Instance.new("Frame")
	swatch.Size = UDim2.fromOffset(6, PET_ROW_H - 16)
	swatch.Position = UDim2.new(0, 8, 0, 8)
	swatch.BackgroundColor3 = Config.rarityColor(pet.rarity)
	swatch.BorderSizePixel = 0
	swatch.Parent = frame
	rounded(swatch, 3)

	-- The pet itself, beside its rarity rather than instead of it: the swatch,
	-- the XP bar and the reveal text are Config.rarityColor and the picture is
	-- look.primary, and the two never read each other. Not spun, unlike the
	-- reveal and the bestiary: twenty five rows are twenty five RenderStepped
	-- connections, and a shelf is read rather than watched.
	local portrait = petPortrait(pet.petId, pet.stage, false)
	if portrait then
		portrait.Size = UDim2.fromOffset(PORTRAIT, PORTRAIT)
		portrait.Position = UDim2.new(0, 18, 0, (PET_ROW_H - PORTRAIT) / 2)
		portrait.Parent = frame
	end

	local name =
		label(frame, UDim2.new(0, PET_TEXT_W, 0, 20), UDim2.new(0, PET_TEXT_X, 0, 8), Enum.Font.GothamBold, 15, WHITE)
	name.TextXAlignment = Enum.TextXAlignment.Left
	-- A nickname can be twenty characters and the column is now 132 pixels, so
	-- it elides rather than running under the buttons.
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = (pet.locked and "[L] " or "") .. pet.name

	local sub =
		label(frame, UDim2.new(0, PET_TEXT_W, 0, 16), UDim2.new(0, PET_TEXT_X, 0, 28), Enum.Font.Gotham, 12, DIM)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextTruncate = Enum.TextTruncate.AtEnd
	local multiplier = pet.multiplier > 1 and string.format("  x%.1f", pet.multiplier) or ""
	sub.Text = string.format("Lv %d  |  %s%s", pet.level, pet.ability, multiplier)

	-- A pet at max level has no xpNeed, which draws as a full bar rather than an
	-- empty one: the alternative reads as a pet that stopped earning by mistake.
	local track = Instance.new("Frame")
	track.Size = UDim2.new(0, PET_TEXT_W, 0, 4)
	track.Position = UDim2.new(0, PET_TEXT_X, 0, 48)
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

	wornChips(frame, pet.worn)
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

-- What a raw effect value means in words. The projection carries numbers and the
-- catalogue is server-side, so which of them is a fraction comes from
-- Config.Accessories rather than from a second table kept here.
local function effectText(effect)
	local name = Config.Accessories.EffectLabels[effect.type] or effect.type
	if Config.Accessories.EffectPercent[effect.type] then
		return string.format("%s +%d%%", name, math.floor(effect.value * 100 + 0.5))
	end
	if effect.value == math.floor(effect.value) then
		return string.format("%s +%d", name, effect.value)
	end
	return string.format("%s +%.1f", name, effect.value)
end

local function effectsLine(item)
	if #item.effects == 0 then
		return "Cosmetic"
	end
	local parts = {}
	for _, effect in ipairs(item.effects) do
		table.insert(parts, effectText(effect))
	end
	return table.concat(parts, ", ")
end

local GEAR_ROW_H = 58

local function gearRow(item, order, wearerName, canReach)
	local frame = row(order, GEAR_ROW_H)

	local swatch = Instance.new("Frame")
	swatch.Size = UDim2.fromOffset(6, GEAR_ROW_H - 16)
	swatch.Position = UDim2.new(0, 8, 0, 8)
	swatch.BackgroundColor3 = Config.rarityColor(item.rarity)
	swatch.BorderSizePixel = 0
	swatch.Parent = frame
	rounded(swatch, 3)

	local name = label(frame, UDim2.new(0, 250, 0, 18), UDim2.new(0, 22, 0, 6), Enum.Font.GothamBold, 14, WHITE)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = (item.locked and "[L] " or "") .. item.name

	local sub = label(frame, UDim2.new(0, 250, 0, 14), UDim2.new(0, 22, 0, 24), Enum.Font.Gotham, 11, DIM)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Text = string.format("%s  |  %s", item.slot, effectsLine(item))

	local where = label(frame, UDim2.new(0, 250, 0, 14), UDim2.new(0, 22, 0, 38), Enum.Font.Gotham, 11, DIM)
	where.TextXAlignment = Enum.TextXAlignment.Left
	if wearerName then
		where.Text = "Worn by " .. wearerName
		where.TextColor3 = GREEN
	elseif item.sellValue then
		where.Text = string.format("In the bag  |  sells for %d", item.sellValue)
	else
		where.Text = "In the bag  |  not for sale"
	end

	local wear = button(
		frame,
		UDim2.fromOffset(96, 24),
		UDim2.new(1, -108, 0, 6),
		item.wornBy and "TAKE OFF" or "WEAR",
		item.wornBy and Color3.fromRGB(60, 62, 74) or GREEN
	)
	wear.TextSize = 12
	wear.MouseButton1Click:Connect(function()
		if item.wornBy then
			send({ kind = "unwear", petUid = item.wornBy, slot = item.slot })
		else
			gearTarget = item.uid
			refresh()
		end
	end)

	-- Lock keeps the full width while the item cannot be sold at all, which is
	-- every worn item and the two that were never for sale. Half a row each
	-- otherwise, because the price is on the line to the left of them and these
	-- two only have to say which verb they are.
	local sellable = item.sellValue ~= nil and not item.wornBy
	local lock = button(
		frame,
		UDim2.fromOffset(sellable and 46 or 96, 20),
		UDim2.new(1, -108, 0, 32),
		item.locked and "UNLOCK" or "LOCK",
		Color3.fromRGB(60, 62, 74)
	)
	lock.TextSize = 11
	lock.MouseButton1Click:Connect(function()
		send({ kind = "lockAccessory", accessoryUid = item.uid, locked = not item.locked })
	end)

	if not sellable then
		return
	end

	-- Same bargain the Place button makes: it says why rather than going grey and
	-- silent, and a locked item keeps its button so the refusal names the lock the
	-- player set rather than nothing happening.
	local sell = button(
		frame,
		UDim2.fromOffset(46, 20),
		UDim2.new(1, -58, 0, 32),
		canReach and "SELL" or "ROOST",
		canReach and Color3.fromRGB(120, 70, 70) or Color3.fromRGB(52, 54, 64)
	)
	sell.TextSize = 11
	sell.MouseButton1Click:Connect(function()
		send({ kind = "sellAccessory", accessoryUid = item.uid })
	end)
end

-- The shop half of the tab. Everything catalogued with a price, whether or not
-- the player already owns one: gear is instanced, so a second Coin Chain is a
-- thing somebody may well want, and hiding what is owned would make the list
-- change shape as it is bought out.
local function gearShelfRow(config, order, canBuy)
	local frame = row(order, 52)
	frame.BackgroundTransparency = 0.35

	local name = label(
		frame,
		UDim2.new(0, 250, 0, 18),
		UDim2.new(0, 14, 0, 4),
		Enum.Font.GothamBold,
		14,
		Config.rarityColor(config.rarity)
	)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = config.name

	local sub = label(frame, UDim2.new(0, 250, 0, 14), UDim2.new(0, 14, 0, 21), Enum.Font.Gotham, 11, DIM)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextTruncate = Enum.TextTruncate.AtEnd
	sub.Text = string.format("%s  |  %s", config.slot, effectsLine(config))

	local price = label(frame, UDim2.new(0, 250, 0, 14), UDim2.new(0, 14, 0, 35), Enum.Font.Gotham, 11, GOLD)
	price.TextXAlignment = Enum.TextXAlignment.Left
	price.Text = string.format("%d coins", config.coinCost)

	local buy = button(
		frame,
		UDim2.fromOffset(96, 26),
		UDim2.new(1, -108, 0, 13),
		canBuy and "BUY" or "AT A ROOST",
		canBuy and GOLD or Color3.fromRGB(52, 54, 64)
	)
	buy.TextSize = canBuy and 13 or 10
	buy.TextColor3 = canBuy and Color3.fromRGB(30, 26, 12) or WHITE
	buy.MouseButton1Click:Connect(function()
		send({ kind = "buyAccessory", accessoryId = config.id })
	end)
end

-- One line per pet while a piece of gear is waiting to be put on. It says what
-- the pet is already wearing in that slot, because wearing is a replace and the
-- thing being replaced should not be a surprise.
local function pickRow(pet, item, order)
	local frame = row(order, 44)

	local name = label(frame, UDim2.new(0, 240, 0, 18), UDim2.new(0, 14, 0, 5), Enum.Font.GothamBold, 14, WHITE)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = pet.name .. (pet.equipped and "  (out)" or "")

	local sub = label(frame, UDim2.new(0, 240, 0, 14), UDim2.new(0, 14, 0, 24), Enum.Font.Gotham, 11, DIM)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	local occupied = pet.worn and pet.worn[item.slot]
	if occupied then
		sub.Text = "Replaces " .. occupied.name
	elseif not pet.equipped then
		sub.Text = "Benched, so it will not do anything yet"
	else
		sub.Text = item.slot .. " is empty"
	end

	local put = button(frame, UDim2.fromOffset(84, 26), UDim2.new(1, -96, 0, 9), "PUT ON", GREEN)
	put.TextSize = 12
	put.MouseButton1Click:Connect(function()
		send({ kind = "wear", petUid = pet.uid, accessoryUid = item.uid })
		gearTarget = nil
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

local function drawGear()
	title.Text = "Gear"
	local items = state.accessories or {}
	local names = {}
	for _, pet in ipairs(state.pets) do
		names[pet.uid] = pet.name
	end

	-- The picker takes over the whole list rather than opening beside it: at 390
	-- pixels there is no beside, and a player who has pressed WEAR has one
	-- question left to answer.
	if gearTarget then
		local item = nil
		for _, candidate in ipairs(items) do
			if candidate.uid == gearTarget then
				item = candidate
			end
		end
		-- The item can be gone by the time this redraws, if the server refused or
		-- something else changed underneath.
		if not item then
			gearTarget = nil
		else
			capLabel.Text = "Pick a pet"
			-- Order 0, so the "no pets" note below (which is always order 1) cannot
			-- tie with it and draw above the question it answers.
			local header = row(0, 44)
			header.BackgroundTransparency = 0.35
			local ask = label(header, UDim2.new(0, 250, 1, 0), UDim2.new(0, 14, 0, 0), Enum.Font.GothamBold, 14, WHITE)
			ask.TextXAlignment = Enum.TextXAlignment.Left
			ask.Text = string.format("Put %s on which pet?", item.name)

			local cancel = button(header, UDim2.fromOffset(84, 26), UDim2.new(1, -96, 0, 9), "CANCEL", ROW)
			cancel.TextSize = 12
			cancel.MouseButton1Click:Connect(function()
				gearTarget = nil
				refresh()
			end)

			if #state.pets == 0 then
				emptyNote("No pets to put it on yet.")
				return
			end
			for i, pet in ipairs(state.pets) do
				pickRow(pet, item, i + 1)
			end
			return
		end
	end

	-- The server's count, not #items: a row whose catalogue entry vanished is not
	-- drawn but still holds a slot in the bag, and the cap is what refuses.
	capLabel.Text = string.format(
		"%d of %d kept  |  worn gear works on the pet you have out",
		state.accessoryCount or #items,
		state.accessoryCap or 0
	)

	local canReach = nearRoost()
	local order = 0
	if #items == 0 then
		order = order + 1
		emptyNote("No gear yet. A piece of gear goes on one pet, and only the pet you have out gets what it does.")
	end
	for _, item in ipairs(items) do
		order = order + 1
		gearRow(item, order, item.wornBy and names[item.wornBy] or nil, canReach)
	end

	-- The shop is every catalogued piece with a price, cheapest first, and the two
	-- without one are absent rather than greyed: an item that is only ever earned
	-- has no business taking up a row in a shop.
	local forSale = {}
	for _, config in pairs(AccessoryCatalog) do
		if config.coinCost then
			table.insert(forSale, config)
		end
	end
	table.sort(forSale, function(a, b)
		if a.coinCost ~= b.coinCost then
			return a.coinCost < b.coinCost
		end
		return a.id < b.id
	end)

	order = order + 1
	local header = row(order, 26)
	header.BackgroundTransparency = 1
	local heading = label(header, UDim2.new(1, -24, 1, 0), UDim2.new(0, 14, 0, 0), Enum.Font.GothamBold, 12, GOLD)
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.Text = canReach and "FOR SALE" or "FOR SALE AT ANY ROOF ROOST"

	for _, config in ipairs(forSale) do
		order = order + 1
		gearShelfRow(config, order, canReach)
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

function refresh()
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
	elseif openTab == "Gear" then
		drawGear()
	else
		drawDaily()
	end
end

-- Walking up to a roost with the panel already open has to light the Place
-- button, and no server message accompanies a walk. Redrawn only when
-- reachability actually flips, because a rebuild every half second would reset
-- the scroll position under anyone reading the list. The Gear tab joined this
-- when it grew a shop: buying and selling are the same counter and the same
-- proximity re-check on the server.
task.spawn(function()
	local lastReach = nil
	while true do
		if panel.Visible and (openTab == "Eggs" or openTab == "Gear") then
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
	gearTarget = nil
	if not state then
		send({ kind = "sync" })
	end
	refresh()
end

local function closePanel()
	panel.Visible = false
	nickBox.Visible = false
	nickTarget = nil
	gearTarget = nil
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
		gearTarget = nil
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

-- "Climb to hatch it" is what this replaces, and it read as a lie to anyone who
-- had just climbed: a roost is on a roof, so placing an egg always happens the
-- moment a tower is finished. A count cannot be misread that way, and it is the
-- only line in the UI that has to survive HatchUnit being flipped, hence the
-- singular.
local function remaining(done, required)
	local left = math.max(0, required - done)
	local unit = Config.Pets.HatchUnit == "tower" and "tower" or "floor"
	return string.format("%d more %s to hatch", left, left == 1 and unit or unit .. "s")
end

local function playEvent(event)
	if not event then
		return
	end

	if event.kind == "hatched" then
		showReveal(event.name, event.rarity, event.ability, event.petId, event.stage)
	elseif event.kind == "levelup" then
		local what = event.pet.evolved and "evolved!" or string.format("reached level %d", event.pet.level)
		showBanner(event.pet.name .. " " .. what, "", Config.rarityColor(event.pet.rarity), 2)
		playSound(Config.Sounds.PowerupPickup, Config.Juice.PowerupVolume, 1.4)
	elseif event.kind == "worn" then
		-- The subtitle is the whole reason a move is not silent: at one equipped pet
		-- a player moving a crown has just changed which pet it works on.
		showBanner(
			string.format("%s on %s", event.name, event.petName or "your pet"),
			event.takenFrom and ("Taken off " .. event.takenFrom) or "",
			GREEN,
			2
		)
	elseif event.kind == "unworn" then
		showBanner(
			string.format("%s off %s", event.name or "Gear", event.petName or "your pet"),
			"",
			Color3.fromRGB(150, 160, 175),
			1.6
		)
	elseif event.kind == "placed" then
		showBanner("Egg placed", remaining(event.done, event.required), GREEN, 2.5)
	elseif event.kind == "bought" then
		showBanner(event.name, string.format("-%d coins", event.cost), GOLD, 1.8)
	elseif event.kind == "sold" then
		showBanner(string.format("Sold %s", event.name), string.format("+%d coins", event.value), GOLD, 1.8)
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
		if event.gear then
			table.insert(parts, event.gear .. "!")
		end
		dailyAvailable = false
		showBanner(string.format("Day %d streak", event.streak), table.concat(parts, "  |  "), GOLD, 3)
	elseif event.kind == "incubated" then
		-- Fires alongside TimerGui's own tower celebration, so it is deliberately
		-- short and quiet: the point is the count, not another fanfare.
		showBanner(
			string.format("Egg  %d / %d", math.min(event.done, event.required), event.required),
			remaining(event.done, event.required),
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
		-- Two things are worth announcing to a whole server and they are not both
		-- hatches, so the verb and the noun both ride the payload. The hatch sends
		-- neither and reads as it always did.
		showBanner(
			string.format(
				"%s %s a %s!",
				payload.playerName,
				payload.verb or "hatched",
				payload.itemName or payload.petName
			),
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
