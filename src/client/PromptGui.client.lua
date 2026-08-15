-- PromptGui (LocalScript) -> StarterPlayer/StarterPlayerScripts
-- The last unthemed surface in the game (docs/HUD_THEME_PLAN.md Slate 6a): every
-- door into a menu is a stock ProximityPrompt, white and round-cornered against a
-- city of cut stone. This draws them instead, as the same chip every other HUD
-- readout is, and owns nothing else: the engine still handles the key, the hold
-- and the trigger, so a prompt whose chip is never built still works.
--
-- Two things about that are deliberate. `Style = Custom` is set **here, on the
-- client**, never in the generator: the server keeps shipping stock prompts, so
-- this file is chrome that can be deleted without the shop closing, and there is
-- no generator change and no determinism ritual for a look. And prompts are
-- found through the tags their parts already carry rather than by sweeping
-- workspace, which is the line CLAUDE.md draws for everything else that crosses
-- from generation to runtime. The cost of that is the rule: a prompt on an
-- untagged part keeps the stock look. That is the right failure, being the one
-- that still reads and still opens what it opens.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiTheme = require(ReplicatedStorage:WaitForChild("UiTheme"))
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Every part in the game that carries a prompt carries one of these.
local HOST_TAGS = { "EggPedestal", "ShopItem" }

-- The billboard is deliberately much larger than the chip: a prompt's UIOffset
-- is in pixels and a BillboardGui has no pixel offset of its own, so the chip
-- floats at the middle of an oversized transparent board and takes the offset as
-- its own position. That is what keeps the stall's two prompts stacked the way
-- the generator asked for, rather than sitting on top of each other.
local BOARD_W = 420
local BOARD_H = 260
local CHIP_H = 40
local KEY = 24
local PAD = 8

local adopted = setmetatable({}, { __mode = "k" })
local live = setmetatable({}, { __mode = "k" })

local function keyText(prompt, inputType)
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "TAP"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		return (string.gsub(prompt.GamepadKeyCode.Name, "^Button", ""))
	end
	return prompt.KeyboardKeyCode.Name
end

local function build(prompt, inputType)
	local board = Instance.new("BillboardGui")
	board.Name = "PromptChip"
	board.Adornee = prompt.Parent
	board.AlwaysOnTop = true
	board.Size = UDim2.fromOffset(BOARD_W, BOARD_H)
	board.Parent = playerGui

	-- The seam, because a prompt is a door: it is the same mark Slate 5 put over
	-- the two counters outdoors, on the near side of the same doors.
	local chip = UiTheme.chip(
		board,
		UDim2.fromOffset(160, CHIP_H),
		UDim2.new(0.5, prompt.UIOffset.X, 0.5, prompt.UIOffset.Y),
		{ anchor = Vector2.new(0.5, 0.5), seam = true }
	)

	local cap = Instance.new("Frame")
	cap.Size = UDim2.fromOffset(KEY, KEY)
	cap.Position = UDim2.new(0, PAD, 0.5, 0)
	cap.AnchorPoint = Vector2.new(0, 0.5)
	cap.BackgroundColor3 = UiTheme.Stone
	cap.BorderSizePixel = 0
	cap.ClipsDescendants = true
	cap.Parent = chip
	UiTheme.rounded(cap, 4)
	UiTheme.stroke(cap)

	-- The hold is the key filling up, not the seam growing: the seam says there
	-- is a door here and says it the whole time the chip is up, where the fill is
	-- on the one thing the player is actually pressing.
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, 0, 0, 0)
	fill.Position = UDim2.fromScale(0, 1)
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.BackgroundColor3 = UiTheme.Rune
	fill.BackgroundTransparency = 0.35
	fill.BorderSizePixel = 0
	fill.Parent = cap

	local keyLabel = UiTheme.label(cap, UDim2.fromScale(1, 1), UDim2.new(), UiTheme.BodyBold, 13, UiTheme.Text)
	keyLabel.Text = keyText(prompt, inputType)
	keyLabel.ZIndex = 2

	local textX = PAD * 2 + KEY
	local hasObject = prompt.ObjectText ~= ""

	-- Display names the thing, Body states the verb, which is Slate 5's rule for
	-- the plates outdoors read indoors: a prompt is a plate you can press.
	local object = UiTheme.label(chip, UDim2.fromOffset(0, 17), UDim2.new(0, textX, 0, 4), UiTheme.Display, 15)
	object.TextXAlignment = Enum.TextXAlignment.Left
	object.AutomaticSize = Enum.AutomaticSize.X
	object.Text = prompt.ObjectText
	object.Visible = hasObject

	local action = UiTheme.label(
		chip,
		UDim2.fromOffset(0, 15),
		UDim2.new(0, textX, 0, hasObject and 21 or 0),
		UiTheme.BodyBold,
		12,
		UiTheme.Rune
	)
	action.TextXAlignment = Enum.TextXAlignment.Left
	action.AutomaticSize = Enum.AutomaticSize.X
	action.Text = prompt.ActionText
	if not hasObject then
		action.Size = UDim2.new(0, 0, 1, 0)
	end

	-- Width comes off what the two labels actually measured rather than from a
	-- guess: "Buy with Robux" and "Eggs" are the same chip and neither is padded
	-- to the other. AbsoluteSize lands a frame later, which the fade-in covers.
	local function fit()
		local widest = math.max(object.Visible and object.AbsoluteSize.X or 0, action.AbsoluteSize.X)
		chip.Size = UDim2.fromOffset(textX + widest + PAD, CHIP_H)
	end
	object:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	action:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	local base = chip.Position
	chip.Position = base + UDim2.fromOffset(0, 6)
	chip.BackgroundTransparency = 1
	object.TextTransparency = 1
	action.TextTransparency = 1
	UiTheme.tween(chip, 0.12, { BackgroundTransparency = UiTheme.ChipTransparency, Position = base })
	UiTheme.tween(object, 0.12, { TextTransparency = 0 })
	UiTheme.tween(action, 0.12, { TextTransparency = 0 })

	local view = { board = board }

	function view.hold(on)
		if on then
			UiTheme.tween(fill, math.max(prompt.HoldDuration, 0.05), { Size = UDim2.fromScale(1, 1) })
		else
			UiTheme.tween(fill, 0.1, { Size = UDim2.new(1, 0, 0, 0) })
		end
	end

	function view.trigger()
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundTransparency = 0
		UiTheme.tween(fill, 0.3, { BackgroundTransparency = 1 })
	end

	function view.destroy()
		UiTheme.tween(chip, 0.12, { BackgroundTransparency = 1, Position = base + UDim2.fromOffset(0, -6) })
		UiTheme.tween(object, 0.12, { TextTransparency = 1 })
		UiTheme.tween(action, 0.12, { TextTransparency = 1 })
		Debris:AddItem(board, 0.2)
	end

	return view
end

local function adopt(child)
	if not child:IsA("ProximityPrompt") or adopted[child] then
		return
	end
	adopted[child] = true
	child.Style = Enum.ProximityPromptStyle.Custom
end

local function watch(part)
	for _, child in ipairs(part:GetChildren()) do
		adopt(child)
	end
	part.ChildAdded:Connect(adopt)
end

for _, tag in ipairs(HOST_TAGS) do
	for _, part in ipairs(CollectionService:GetTagged(tag)) do
		watch(part)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(watch)
end

-- Only prompts this file switched to Custom are drawn. Anything else is still
-- being drawn by the engine, and a chip over the top of that is two prompts.
ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
	if not adopted[prompt] then
		return
	end
	local previous = live[prompt]
	if previous then
		previous.destroy()
	end
	live[prompt] = build(prompt, inputType)
end)

ProximityPromptService.PromptHidden:Connect(function(prompt)
	local view = live[prompt]
	if view then
		live[prompt] = nil
		view.destroy()
	end
end)

ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, who)
	local view = live[prompt]
	if view and who == player then
		view.hold(true)
	end
end)

ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt, who)
	local view = live[prompt]
	if view and who == player then
		view.hold(false)
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	local view = live[prompt]
	if view and who == player then
		view.trigger()
	end
end)
