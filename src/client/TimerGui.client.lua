-- TimerGui (LocalScript) -> StarterPlayer/StarterPlayerScripts
-- Count-up floor timer, running score, and celebration banners. All three read
-- the single TimerUpdate payload the server already pushes at 4 Hz, so nothing
-- here needs a remote of its own.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local remote = ReplicatedStorage:WaitForChild("TimerUpdate")
local player = Players.LocalPlayer

local GREEN = Color3.fromRGB(90, 200, 140)
local AMBER = Color3.fromRGB(235, 180, 70)
local RED = Color3.fromRGB(230, 80, 80)
local WHITE = Color3.fromRGB(255, 255, 255)
local GOLD = Color3.fromRGB(255, 214, 110)

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

-- Timer panel
local holder = Instance.new("Frame")
holder.Size = UDim2.new(0, 220, 0, 86)
holder.Position = UDim2.new(0.5, -110, 0, 16)
holder.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
holder.BackgroundTransparency = 0.25
holder.BorderSizePixel = 0
holder.Visible = false
holder.Parent = gui
rounded(holder, 8)

local towerLabel =
	label(holder, UDim2.new(1, -16, 0, 18), UDim2.new(0, 8, 0, 6), Enum.Font.Gotham, 13, Color3.fromRGB(180, 190, 205))
local timeLabel = label(holder, UDim2.new(1, -16, 0, 32), UDim2.new(0, 8, 0, 24), Enum.Font.GothamBlack, 28, WHITE)
timeLabel.Text = "0:00"
local parLabel =
	label(holder, UDim2.new(1, -16, 0, 16), UDim2.new(0, 8, 0, 58), Enum.Font.Gotham, 12, Color3.fromRGB(150, 160, 175))

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

local function format(seconds)
	local m = math.floor(seconds / 60)
	local s = math.floor(seconds % 60)
	return string.format("%d:%02d", m, s)
end

local function tween(inst, time, props)
	TweenService:Create(inst, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
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
		pulseScore(1)
	elseif event.kind == "tower" then
		showBanner(event.tower .. " topped out", string.format("+%d  |  roof reached", event.gained), GOLD, 4, true)
		pulseScore(3)
	elseif event.kind == "death" then
		local where = event.restart == "tower" and "Back to the tower entrance" or "Back to the start of this floor"
		showBanner("Caught", where, RED, 1.6, false)
	end
end

remote.OnClientEvent:Connect(function(payload)
	if not payload then
		holder.Visible = false
		return
	end

	if payload.score then
		scoreLabel.Text = string.format("%d", payload.score)
	end

	if payload.level then
		holder.Visible = true
		towerLabel.Text = string.format("%s  |  Floor %d", payload.tower, payload.level + 1)
		timeLabel.Text = format(payload.elapsed)
		parLabel.Text = string.format("par %s", format(payload.par))

		-- The bar fills toward par instead of draining toward zero. Full and
		-- red means the floor is still winnable, just no longer worth a speed
		-- bonus, which is the whole point of the count-up rework.
		local ratio = math.clamp(payload.elapsed / math.max(1, payload.par), 0, 1)
		bar.Size = UDim2.new(ratio, 0, 0, 4)

		if payload.elapsed >= payload.par then
			bar.BackgroundColor3 = RED
			timeLabel.TextColor3 = Color3.fromRGB(255, 150, 150)
			parLabel.TextColor3 = RED
		elseif ratio > 0.7 then
			bar.BackgroundColor3 = AMBER
			timeLabel.TextColor3 = WHITE
			parLabel.TextColor3 = Color3.fromRGB(150, 160, 175)
		else
			bar.BackgroundColor3 = GREEN
			timeLabel.TextColor3 = WHITE
			parLabel.TextColor3 = Color3.fromRGB(150, 160, 175)
		end
	else
		holder.Visible = false
	end

	if payload.event then
		playEvent(payload.event)
	end
end)
