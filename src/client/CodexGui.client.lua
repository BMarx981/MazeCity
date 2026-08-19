-- CodexGui (LocalScript) -> StarterPlayer.StarterPlayerScripts
-- The Codex, per docs/LORE.MD 6.2 and PETS_PLAN.md Clutch 7 unit 5. Three
-- chapters of what a player has met, hatched and read, each one a meter over
-- content that is already on this machine.
--
-- **It draws unlock state and owns none of it.** LoreService pushes a
-- projection (a count for the journal, a stage per Kept, a set of pet ids) and
-- everything else on screen is resolved here out of ReplicatedStorage: the
-- lines from Lore and Journal, the names from the catalogues, the pictures
-- built locally through PortraitGenerator from the same two rig recipes the
-- game spawns from. So the chapter costs the same on the wire whether a player
-- has one entry or all of them, and no line of text is ever sent twice.
--
-- **It is a HUD panel and not the monument at the Nest LORE.MD first asked
-- for.** A monument is a part, a part is generation, and generation is
-- deterministic and per section where a Codex is per player: the same objection
-- that stopped the wall writings being baked in. It would also be a reading
-- room at the top of a ten floor climb, so a fragment unlocked on floor three
-- could not be read until the roof and the Kept page could not be read at all
-- by the player who most wants it, which is the one being chased. The Nest
-- keeps the ending: fragment 17 stands there and nowhere else.
--
-- **A chapter's size is what a player can actually reach**, because a meter
-- that cannot fill is a meter nobody trusts. The Kept counts the roster the
-- spawn director may roll, which is the nineteen rows that are not
-- `spawnable = false`: the Splitter Child arrives only from a Splitter breaking
-- and nothing in this game does damage yet, so it is out of the denominator and
-- draws as a row anyway for whoever meets one. Pets counts the catalogue, all
-- of which every egg can roll.
--
-- **There is no Relics chapter and it is not an omission.** `Lore.relics` is
-- empty and nothing writes `codex.relics`, so a fourth tab today would be a
-- meter that reads 0 of 0 forever. It arrives with the gear economy's relic
-- content (LORE.MD Section 5), and arriving is a chapter in this file plus a
-- writer beside the other two, not a rewrite of either.
--
-- The one request in here is the first one. Everything after it is pushed, so a
-- client is correct without polling and without asking again; the sync exists
-- because a remote fired at a player whose LocalScripts have not connected yet
-- is a chapter that never arrives at all.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))

if not Config.Lore.Enabled or not Config.Lore.CodexEnabled then
	return
end

local UiTheme = require(ReplicatedStorage:WaitForChild("UiTheme"))
local Journal = require(ReplicatedStorage:WaitForChild("Journal"))
local Lore = require(ReplicatedStorage:WaitForChild("Lore"))
local PetCatalog = require(ReplicatedStorage:WaitForChild("PetCatalog"))
local EnemyDefinitions = require(ReplicatedStorage:WaitForChild("EnemyDefinitions"))
local PetModelGenerator = require(ReplicatedStorage:WaitForChild("PetModelGenerator"))
local PortraitGenerator = require(ReplicatedStorage:WaitForChild("PortraitGenerator"))

local remote = ReplicatedStorage:WaitForChild("LoreUpdate")
local intents = ReplicatedStorage:WaitForChild("LoreIntent")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PANEL_W = Config.Lore.CodexPanelWidth
local PANEL_H = Config.Lore.CodexPanelHeight
local PORTRAIT = 68
local TEXT_X = PORTRAIT + 22
local JOURNAL_ROW_H = 96
local ENTRY_ROW_H = 104

-- The last projection. Everything below is a function of this table, and nil
-- means the sync has not landed yet rather than an empty Codex.
local state = nil
local openTab = "Journal"

local refresh

-- ============================================================
-- The chapters
-- ============================================================
-- Two lists built once, because neither the catalogue nor the roster changes
-- during a session, and both are the denominator of a meter.

local petIds = {}
for id in pairs(PetCatalog) do
	table.insert(petIds, id)
end
table.sort(petIds, function(a, b)
	local ra, rb = Config.rarityIndex(PetCatalog[a].rarity), Config.rarityIndex(PetCatalog[b].rarity)
	if ra ~= rb then
		return ra < rb
	end
	return PetCatalog[a].name < PetCatalog[b].name
end)

-- Alphabetical and fixed, so a row a player has read once stays where they read
-- it: a list that reshuffles as it fills is a list nobody learns.
local keptIds = {}
for name, row in pairs(EnemyDefinitions.types) do
	if row.spawnable ~= false then
		table.insert(keptIds, name)
	end
end
table.sort(keptIds, function(a, b)
	return EnemyDefinitions.types[a].name < EnemyDefinitions.types[b].name
end)

-- ============================================================
-- Widgets
-- ============================================================

local gui = Instance.new("ScreenGui")
gui.Name = "CodexGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- Directly above the pet panel's own chip, which is the left edge becoming the
-- column of things that open rather than two buttons that found the same wall.
local toggle = UiTheme.button(gui, UDim2.fromOffset(112, 40), UDim2.new(0, 16, 0.5, -46), "CODEX", UiTheme.Slab)
toggle.AnchorPoint = Vector2.new(0, 0.5)
toggle.BackgroundTransparency = UiTheme.ChipTransparency
UiTheme.gradient(toggle)
UiTheme.stroke(toggle)

local panel = UiTheme.panel(gui, UDim2.fromOffset(PANEL_W, PANEL_H), UDim2.new(0.5, -PANEL_W / 2, 0.5, -PANEL_H / 2))
panel.Visible = false

local title = UiTheme.label(panel, UDim2.new(1, -180, 0, 34), UDim2.new(0, 16, 0, 10), UiTheme.Display, 22)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Codex"
UiTheme.wordmark(title)

-- The Cartographer title, drawn where somebody who earned it goes to look. It
-- is a replicated player attribute rather than anything on the remote, so it is
-- right on this file's first frame and after a rejoin that unlocks nothing.
local earned =
	UiTheme.label(panel, UDim2.new(0, 130, 0, 20), UDim2.new(1, -178, 0, 16), UiTheme.BodyBold, 13, UiTheme.Lantern)
earned.TextXAlignment = Enum.TextXAlignment.Right

local closeButton = UiTheme.button(panel, UDim2.fromOffset(30, 30), UDim2.new(1, -42, 0, 12), "X", UiTheme.Stone)

local meterLabel =
	UiTheme.label(panel, UDim2.new(1, -32, 0, 18), UDim2.new(0, 16, 0, 44), UiTheme.Body, 13, UiTheme.Dim)
meterLabel.TextXAlignment = Enum.TextXAlignment.Left

local tabRow = Instance.new("Frame")
tabRow.Size = UDim2.new(1, -32, 0, 30)
tabRow.Position = UDim2.new(0, 16, 0, 66)
tabRow.BackgroundTransparency = 1
tabRow.Parent = panel

local TABS = { "Journal", "Kept", "Pets" }
local tabButtons = {}
for i, name in ipairs(TABS) do
	local width = 1 / #TABS
	tabButtons[name] =
		UiTheme.button(tabRow, UDim2.new(width, -6, 1, 0), UDim2.new(width * (i - 1), 3, 0, 0), name, UiTheme.Stone)
	tabButtons[name].TextSize = 13
end

-- The open chapter's meter. The tab labels carry every chapter's fraction, so
-- this is the one that is worth a bar: a fraction is a number to read and a bar
-- is a thing to fill.
local meterTrack, meterFill = UiTheme.bar(panel, UDim2.new(1, -32, 0, 4), UDim2.new(0, 16, 0, 102), UiTheme.Rune)
meterTrack.BorderSizePixel = 0
UiTheme.rounded(meterTrack, 2)
UiTheme.rounded(meterFill, 2)

local body = Instance.new("ScrollingFrame")
body.Size = UDim2.new(1, -24, 1, -126)
body.Position = UDim2.new(0, 12, 0, 114)
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
	frame.Size = UDim2.new(1, -6, 0, height)
	frame.BackgroundColor3 = UiTheme.Stone
	frame.BorderSizePixel = 0
	frame.LayoutOrder = order
	frame.Parent = body
	UiTheme.rounded(frame, 8)
	return frame
end

-- A locked row is dimmer than an unlocked one all the way through rather than
-- greyed at the last moment, which is what makes a full chapter read as full
-- from across the panel without anybody counting.
local function dim(frame)
	frame.BackgroundTransparency = 0.45
end

local function wrapped(frame, x, y, height, size, color)
	local label =
		UiTheme.label(frame, UDim2.new(1, -x - 14, 0, height), UDim2.new(0, x, 0, y), UiTheme.Body, size, color)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	return label
end

-- The plate a portrait would have been. Deliberately not a darkened silhouette:
-- the Kept's first unlock is the silhouette, so showing one before it is met
-- would hand over the thing the row is for.
local function lockedPlate(frame)
	local plate = Instance.new("Frame")
	plate.Size = UDim2.fromOffset(PORTRAIT, PORTRAIT)
	plate.Position = UDim2.new(0, 12, 0, 12)
	plate.BackgroundColor3 = UiTheme.Ink
	plate.BackgroundTransparency = 0.35
	plate.BorderSizePixel = 0
	plate.Parent = frame
	UiTheme.rounded(plate, 6)

	local mark = UiTheme.label(plate, UDim2.fromScale(1, 1), UDim2.new(), UiTheme.Display, 26, UiTheme.Etch)
	mark.Text = "?"
	return plate
end

local function mount(frame, portrait)
	if not portrait then
		lockedPlate(frame)
		return
	end
	portrait.Size = UDim2.fromOffset(PORTRAIT, PORTRAIT)
	portrait.Position = UDim2.new(0, 12, 0, 12)
	portrait.Parent = frame
end

local function journalRow(index, fragment, unlocked)
	local frame = row(index, JOURNAL_ROW_H)
	local head = UiTheme.label(frame, UDim2.new(1, -28, 0, 26), UDim2.new(0, 14, 0, 8), UiTheme.Display, 20)
	head.TextXAlignment = Enum.TextXAlignment.Left

	if unlocked then
		head.Text = "Day " .. tostring(fragment.day)
		-- Chalk, the same Lantern the toast and the wall itself letter it in: it
		-- is somebody else's handwriting wherever it is being read.
		wrapped(frame, 14, 34, 54, 13, UiTheme.Lantern).Text = fragment.text
	else
		dim(frame)
		head.Text = "???"
		head.TextColor3 = UiTheme.Etch
		wrapped(frame, 14, 34, 54, 13, UiTheme.Dim).Text = fragment.hint
	end
	return frame
end

local function keptRow(order, typeName, stage)
	local config = EnemyDefinitions.types[typeName]
	local lore = Lore.kept[typeName]
	local survivalLine = stage >= 2 and lore and lore.survivalLine or nil
	local frame = row(order, ENTRY_ROW_H + (survivalLine and 18 or 0))

	if stage <= 0 then
		dim(frame)
		mount(frame, nil)
		local name = UiTheme.label(
			frame,
			UDim2.new(1, -TEXT_X - 14, 0, 20),
			UDim2.new(0, TEXT_X, 0, 14),
			UiTheme.BodyBold,
			15,
			UiTheme.Etch
		)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Text = "???"
		wrapped(frame, TEXT_X, 38, 40, 12, UiTheme.Dim).Text = "Not met. The Maze has not shown you this one."
		return frame
	end

	mount(frame, PortraitGenerator.portrait(typeName))

	local name =
		UiTheme.label(frame, UDim2.new(1, -TEXT_X - 14, 0, 20), UDim2.new(0, TEXT_X, 0, 12), UiTheme.BodyBold, 15)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = config.name

	if stage < 2 then
		wrapped(frame, TEXT_X, 36, 56, 12, UiTheme.Dim).Text =
			"Met. Get away from one alive and it will tell you what it is."
		return frame
	end

	wrapped(frame, TEXT_X, 36, 56, 12, UiTheme.Text).Text = lore and lore.loreLine or ""
	if survivalLine then
		wrapped(frame, TEXT_X, 94, 22, 12, UiTheme.Lantern).Text = survivalLine
	end
	return frame
end

local function petRow(order, petId, known)
	local config = PetCatalog[petId]
	local frame = row(order, ENTRY_ROW_H)

	if not known then
		dim(frame)
		mount(frame, nil)
		local name = UiTheme.label(
			frame,
			UDim2.new(1, -TEXT_X - 14, 0, 20),
			UDim2.new(0, TEXT_X, 0, 14),
			UiTheme.BodyBold,
			15,
			UiTheme.Etch
		)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Text = "???"
		wrapped(frame, TEXT_X, 38, 40, 12, UiTheme.Dim).Text = "Not hatched. Something is still inside a shell."
		return frame
	end

	-- The generated silhouette, always: an artist's model in ServerStorage/Pets
	-- is invisible to a client, which is the caveat PET_LOOKS_PLAN records and
	-- the same trade PetGui's own rows and the bestiary already make.
	local model = PetModelGenerator.build(petId, 0)
	mount(frame, model and PortraitGenerator.of(model) or nil)

	local name =
		UiTheme.label(frame, UDim2.new(1, -TEXT_X - 70, 0, 20), UDim2.new(0, TEXT_X, 0, 12), UiTheme.BodyBold, 15)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = config.name

	local rarity = UiTheme.label(
		frame,
		UDim2.new(0, 62, 0, 18),
		UDim2.new(1, -76, 0, 13),
		UiTheme.BodyBold,
		12,
		Config.rarityColor(config.rarity)
	)
	rarity.TextXAlignment = Enum.TextXAlignment.Right
	rarity.Text = config.rarity

	local lore = Lore.pets[petId]
	wrapped(frame, TEXT_X, 36, 60, 12, UiTheme.Text).Text = lore and lore.hatchLine or ""
	return frame
end

-- ============================================================
-- Meters
-- ============================================================
-- One function per chapter, returning what is known, what the chapter holds and
-- the line under the title. The counts are computed here rather than sent,
-- which is the same reason nothing else is: the client has both denominators
-- already and a number it derives cannot disagree with the list it drew.

local function journalCounts()
	local unlocked = state and state.unlocked or 0
	return unlocked, #Journal, string.format("The Cartographer's Trail: %d of %d found.", unlocked, #Journal)
end

local function keptCounts()
	local met, read = 0, 0
	local kept = state and state.kept or {}
	for _, typeName in ipairs(keptIds) do
		local stage = kept[typeName] or 0
		if stage >= 1 then
			met = met + 1
		end
		if stage >= 2 then
			read = read + 1
		end
	end
	return met, #keptIds, string.format("The Kept: %d of %d met, %d survived.", met, #keptIds, read)
end

local function petCounts()
	local known = 0
	local pets = state and state.pets or {}
	for _, petId in ipairs(petIds) do
		if pets[petId] then
			known = known + 1
		end
	end
	return known, #petIds, string.format("Pets: %d of %d hatched.", known, #petIds)
end

local COUNTS = { Journal = journalCounts, Kept = keptCounts, Pets = petCounts }

-- ============================================================
-- Drawing
-- ============================================================

local function drawJournal()
	local unlocked = state and state.unlocked or 0
	for index, fragment in ipairs(Journal) do
		journalRow(index, fragment, index <= unlocked)
	end
end

local function drawKept()
	local kept = state and state.kept or {}
	local order = 0
	for _, typeName in ipairs(keptIds) do
		order = order + 1
		keptRow(order, typeName, kept[typeName] or 0)
	end
	-- Anything met that the director cannot roll. Out of the denominator above
	-- so the meter can still fill, and drawn here so a player who somehow met
	-- one is not told they imagined it.
	for typeName, stage in pairs(kept) do
		local config = EnemyDefinitions.types[typeName]
		if config and config.spawnable == false and stage >= 1 then
			order = order + 1
			keptRow(order, typeName, stage)
		end
	end
end

local function drawPets()
	local pets = state and state.pets or {}
	for index, petId in ipairs(petIds) do
		petRow(index, petId, pets[petId] == true)
	end
end

function refresh()
	if not panel.Visible then
		return
	end
	clearBody()

	for name, button in pairs(tabButtons) do
		local have, total = COUNTS[name]()
		local open = name == openTab
		button.Text = string.format("%s %d/%d", string.upper(name), have, total)
		button.BackgroundColor3 = open and UiTheme.Rune or UiTheme.Stone
		button.TextColor3 = open and UiTheme.Ink or UiTheme.Text
	end

	local have, total, line = COUNTS[openTab]()
	meterLabel.Text = line
	meterFill.Size = UDim2.fromScale(total > 0 and have / total or 0, 1)
	-- A finished chapter goes warm. Rune is progress everywhere else in this
	-- game and Lantern is what a reward looks like, so a full bar changing
	-- colour is the chapter saying it is done rather than nearly done.
	meterFill.BackgroundColor3 = (total > 0 and have >= total) and UiTheme.Lantern or UiTheme.Rune

	if openTab == "Journal" then
		drawJournal()
	elseif openTab == "Kept" then
		drawKept()
	else
		drawPets()
	end
end

local function drawTitle()
	local held = player:GetAttribute("CodexTitle")
	earned.Text = held or ""
end

-- ============================================================
-- Opening
-- ============================================================
-- Two centred panels in one game is two panels that would sit on top of each
-- other, so each says when it opened and the other closes. The channel is a
-- BindableEvent in the PlayerGui, found-or-created on both ends for exactly the
-- reason every server-side one is: these are separate LocalScripts and neither
-- can know which of them ran first.

local panels = playerGui:FindFirstChild("UiPanelOpened")
if not panels then
	panels = Instance.new("BindableEvent")
	panels.Name = "UiPanelOpened"
	panels.Parent = playerGui
end

local function closePanel()
	panel.Visible = false
end

local function openPanel()
	panel.Visible = true
	panels:Fire("Codex")
	if not state then
		intents:FireServer({ kind = "sync" })
	end
	drawTitle()
	refresh()
end

panels.Event:Connect(function(name)
	if name ~= "Codex" then
		closePanel()
	end
end)

toggle.MouseButton1Click:Connect(function()
	if panel.Visible then
		closePanel()
	else
		openPanel()
	end
end)

closeButton.MouseButton1Click:Connect(closePanel)

for name, button in pairs(tabButtons) do
	button.MouseButton1Click:Connect(function()
		openTab = name
		refresh()
	end)
end

remote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or payload.kind ~= "codex" then
		return
	end
	state = payload
	refresh()
end)

player:GetAttributeChangedSignal("CodexTitle"):Connect(drawTitle)
drawTitle()

-- The one request, and it is the join rather than the panel: a projection fired
-- at a client whose scripts had not connected yet is a Codex that stays empty
-- until the next floor is cleared, and a player who opens it in between is told
-- they have nothing.
intents:FireServer({ kind = "sync" })
