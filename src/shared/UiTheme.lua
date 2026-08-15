-- UiTheme (ModuleScript) -> ReplicatedStorage
-- The Kept's chrome, and the only place it is defined (docs/HUD_THEME_PLAN.md):
-- dark stone slabs, one teal rune accent, one warm lantern, red kept for danger.
-- Every client GUI requires this the way every speed change goes through
-- WalkSpeedResolver; a converted file holds zero Color3 literals for chrome.
-- Semantic colours (rarity, powerup kinds, per-upgrade accents, the compass)
-- stay in MazeConfig and the catalogues, because they are shared with world
-- geometry; the theme frames them and never absorbs them.
--
-- Nothing here is an image asset. The look is UICorner, UIStroke and UIGradient
-- over frames, so a cold rojo build is the whole game and nothing can 404.

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local UiTheme = {}

-- Stone base, darkest to lightest. Ink is washes and banner backgrounds, Slab
-- is the universal panel, Stone is rows and idle buttons, Track is the empty
-- half of any bar, and Etch is the border line that makes a slab read as cut
-- stone rather than a floating rectangle.
UiTheme.Ink = Color3.fromRGB(8, 11, 20)
UiTheme.Slab = Color3.fromRGB(17, 22, 34)
UiTheme.Stone = Color3.fromRGB(30, 38, 54)
UiTheme.Track = Color3.fromRGB(36, 46, 64)
UiTheme.Etch = Color3.fromRGB(74, 86, 108)

-- The three accents, each meaning one thing. Rune is positive: progress,
-- selection, ready. Lantern is warm: economy, reward, and the active or
-- warning states. Ember is danger only: death, empty, spent.
UiTheme.Rune = Color3.fromRGB(92, 230, 208)
UiTheme.Lantern = Color3.fromRGB(255, 205, 105)
UiTheme.Ember = Color3.fromRGB(233, 88, 74)

UiTheme.Text = Color3.fromRGB(228, 233, 242)
UiTheme.Dim = Color3.fromRGB(146, 160, 182)

UiTheme.ChipRadius = 6
UiTheme.PanelRadius = 10
UiTheme.ChipTransparency = 0.25
UiTheme.PanelTransparency = 0.08
-- Near 0.5 the stroke reads as embers in a seam; much lower and the HUD goes
-- neon. One knob, deliberately (HUD_THEME_PLAN open decision 3).
UiTheme.StrokeTransparency = 0.5
UiTheme.SeamTransparency = 0.35

-- Two families, and no other file names a font. Display is hero text only:
-- the floor number, banner and panel titles, the hatch reveal. Everything else
-- is the Body family, three weights of it, because body text is doing
-- legibility work at 11 to 14 px where a blackletter face is unreadable.
-- Both ship with the client; nothing is uploaded.
UiTheme.Display = Font.fromName("GrenzeGotisch", Enum.FontWeight.Bold)
UiTheme.Body = Font.fromName("GothamSSm", Enum.FontWeight.Regular)
UiTheme.BodyBold = Font.fromName("GothamSSm", Enum.FontWeight.Bold)
UiTheme.BodyBlack = Font.fromName("GothamSSm", Enum.FontWeight.Heavy)

function UiTheme.rounded(inst, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or UiTheme.ChipRadius)
	corner.Parent = inst
	return inst
end

-- Moonlight on masonry: the slab's own colour, lit a little from above. The
-- gradient multiplies BackgroundColor3, so a retinted slab keeps its light.
function UiTheme.gradient(inst)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(196, 200, 212))
	g.Parent = inst
	return inst
end

function UiTheme.stroke(inst, color)
	local s = Instance.new("UIStroke")
	s.Color = color or UiTheme.Etch
	s.Transparency = UiTheme.StrokeTransparency
	s.Parent = inst
	return s
end

-- The teal glow along a slab's bottom edge, inset past the corner radius so it
-- sits in the seam rather than clipping through the rounded corners.
function UiTheme.seam(inst, radius)
	radius = radius or UiTheme.ChipRadius
	local line = Instance.new("Frame")
	line.Size = UDim2.new(1, -radius * 2, 0, 2)
	line.Position = UDim2.new(0, radius, 1, -3)
	line.BackgroundColor3 = UiTheme.Rune
	line.BackgroundTransparency = UiTheme.SeamTransparency
	line.BorderSizePixel = 0
	line.Parent = inst
	return line
end

local function slab(parent, size, position, radius, transparency, opts)
	opts = opts or {}
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = position
	if opts.anchor then
		f.AnchorPoint = opts.anchor
	end
	f.BackgroundColor3 = UiTheme.Slab
	f.BackgroundTransparency = transparency
	f.BorderSizePixel = 0
	UiTheme.rounded(f, radius)
	UiTheme.gradient(f)
	UiTheme.stroke(f)
	if opts.seam then
		UiTheme.seam(f, radius)
	end
	f.Parent = parent
	return f
end

function UiTheme.chip(parent, size, position, opts)
	return slab(parent, size, position, UiTheme.ChipRadius, UiTheme.ChipTransparency, opts)
end

function UiTheme.panel(parent, size, position, opts)
	return slab(parent, size, position, UiTheme.PanelRadius, UiTheme.PanelTransparency, opts)
end

function UiTheme.label(parent, size, position, font, textSize, color)
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.FontFace = font
	l.TextSize = textSize
	l.TextColor3 = color or UiTheme.Text
	l.Text = ""
	l.Parent = parent
	return l
end

-- The accent is the filled, buyable state; no accent is the Stone idle both
-- old button helpers greyed to.
function UiTheme.button(parent, size, position, text, accent)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = accent or UiTheme.Stone
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.FontFace = UiTheme.BodyBold
	b.TextSize = 14
	b.TextColor3 = UiTheme.Text
	b.Text = text
	b.Parent = parent
	UiTheme.rounded(b, UiTheme.ChipRadius)
	return b
end

-- The wordmark: the Display face given an etched outline and one rune line under
-- it, which is the whole of the treatment (HUD_THEME_PLAN Slate 6). The line is
-- sized to the text and not to the label, so a title that changes its word keeps
-- its underline, and it is capped to the label so a long tower name cannot run a
-- rule off the side of a banner. Alignment is read off the label rather than
-- passed in: a left-aligned panel title underlines from its left edge, a centred
-- banner title from its middle, and no caller has to say so twice.
function UiTheme.wordmark(label, opts)
	opts = opts or {}
	local align = label.TextXAlignment
	local anchorX = 0.5
	if align == Enum.TextXAlignment.Left then
		anchorX = 0
	elseif align == Enum.TextXAlignment.Right then
		anchorX = 1
	end

	local stroke = UiTheme.stroke(label)
	stroke.Thickness = 1

	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(anchorX, 0)
	line.Position = UDim2.new(anchorX, 0, 1, opts.drop or -6)
	line.Size = UDim2.fromOffset(0, 2)
	line.BackgroundColor3 = UiTheme.Rune
	line.BackgroundTransparency = UiTheme.SeamTransparency
	line.BorderSizePixel = 0
	line.ZIndex = label.ZIndex
	line.Parent = label

	local mark = { stroke = stroke, line = line }

	local function resize()
		local width = math.floor(label.TextBounds.X) + (opts.pad or 10)
		local room = label.AbsoluteSize.X
		if room > 0 then
			width = math.min(width, room)
		end
		line.Size = UDim2.fromOffset(width, 2)
	end
	label:GetPropertyChangedSignal("TextBounds"):Connect(resize)
	label:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	resize()

	function mark.show(on)
		stroke.Enabled = on
		line.Visible = on
	end

	-- The outline and the rule have their own transparencies, so a label whose
	-- TextTransparency is being tweened has to bring them along or the treatment
	-- pops in at full while the word it belongs to is still fading up.
	function mark.fade(time, hidden)
		UiTheme.tween(stroke, time, { Transparency = hidden and 1 or UiTheme.StrokeTransparency })
		UiTheme.tween(line, time, { BackgroundTransparency = hidden and 1 or UiTheme.SeamTransparency })
	end

	return mark
end

-- Track and fill, returned separately because every caller drives the fill's
-- Size, and usually its colour, itself.
function UiTheme.bar(parent, size, position, color)
	local track = Instance.new("Frame")
	track.Size = size
	track.Position = position
	track.BackgroundColor3 = UiTheme.Track
	track.BorderSizePixel = 0
	track.Parent = parent

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color or UiTheme.Rune
	fill.BorderSizePixel = 0
	fill.Parent = track
	return track, fill
end

function UiTheme.tween(inst, time, props)
	TweenService:Create(inst, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

function UiTheme.playSound(assetId, volume, playbackSpeed)
	local sound = Instance.new("Sound")
	sound.SoundId = assetId
	sound.Volume = volume
	sound.PlaybackSpeed = playbackSpeed or 1
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, sound.TimeLength > 0 and sound.TimeLength + 1 or 5)
end

-- The one banner, ending the TimerGui/PetGui fork. Returns a table whose show
-- is what both showBanner copies were: fade and slide in over Ink, hold, fade
-- out, with a token guarding the sequence so a second celebration landing
-- mid-fade takes the banner over rather than racing the first one's fade-out.
--
-- `show`'s last argument used to mean only "bigger", and now means hero: the
-- Display face at the larger size plus the wordmark treatment. Exactly one
-- banner in the game passes it, the topped-out tower, which is the point. It
-- also buys the subtitle eight pixels of daylight, because the rule under a
-- 52 px title lands where a 22 px subtitle otherwise starts.
function UiTheme.banner(gui, opts)
	opts = opts or {}
	local width = opts.width or 460
	local height = opts.height or 108
	local yScale = opts.y or 0.34
	local titleSize = opts.titleSize or 38
	local bigSize = opts.bigTitleSize or 52
	local subSize = opts.subSize or 22
	local zindex = opts.zindex or 1

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(width, height)
	frame.Position = UDim2.new(0.5, -width / 2, yScale, 0)
	frame.BackgroundColor3 = UiTheme.Ink
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ZIndex = zindex
	frame.Parent = gui
	UiTheme.rounded(frame, UiTheme.PanelRadius)

	local titleHeight = math.floor(height * 0.48)
	local title =
		UiTheme.label(frame, UDim2.new(1, 0, 0, titleHeight), UDim2.new(0, 0, 0, 14), UiTheme.Display, titleSize)
	title.ZIndex = zindex
	local subY = 14 + titleHeight
	local sub = UiTheme.label(
		frame,
		UDim2.new(1, 0, 0, subSize + 6),
		UDim2.new(0, 0, 0, subY),
		UiTheme.BodyBold,
		subSize,
		UiTheme.Lantern
	)
	sub.ZIndex = zindex

	local mark = UiTheme.wordmark(title, { drop = 3 })
	mark.show(false)

	local token = 0
	local banner = { frame = frame, title = title, sub = sub }

	function banner.show(text, subtitle, titleColor, hold, big)
		token = token + 1
		local mine = token

		title.Text = text
		title.TextColor3 = titleColor or UiTheme.Text
		title.TextSize = big and bigSize or titleSize
		sub.Text = subtitle or ""
		sub.Position = UDim2.new(0, 0, 0, big and subY + 8 or subY)

		mark.show(big and true or false)
		if big then
			mark.stroke.Transparency = 1
			mark.line.BackgroundTransparency = 1
			mark.fade(0.22, false)
		end

		frame.Visible = true
		frame.BackgroundTransparency = 1
		frame.Position = UDim2.new(0.5, -width / 2, yScale, 18)
		title.TextTransparency = 1
		sub.TextTransparency = 1

		UiTheme.tween(frame, 0.22, {
			BackgroundTransparency = UiTheme.ChipTransparency,
			Position = UDim2.new(0.5, -width / 2, yScale, 0),
		})
		UiTheme.tween(title, 0.22, { TextTransparency = 0 })
		UiTheme.tween(sub, 0.22, { TextTransparency = 0 })

		task.delay(hold, function()
			if mine ~= token then
				return
			end
			UiTheme.tween(frame, 0.45, {
				BackgroundTransparency = 1,
				Position = UDim2.new(0.5, -width / 2, yScale, -18),
			})
			UiTheme.tween(title, 0.45, { TextTransparency = 1 })
			UiTheme.tween(sub, 0.45, { TextTransparency = 1 })
			if big then
				mark.fade(0.45, true)
			end
			task.delay(0.5, function()
				if mine == token then
					frame.Visible = false
				end
			end)
		end)
	end

	return banner
end

return UiTheme
