-- LoreGui (LocalScript) -> StarterPlayer.StarterPlayerScripts
-- The unlock toast for the Cartographer's Trail, per docs/LORE.MD 9.2. Draws one
-- thing and reads no tags: LoreService says a fragment unlocked and this is what
-- that looks like.
--
-- **It is a toast and deliberately not a banner.** UiTheme.banner is the game's
-- celebration and it lands in the middle of the screen, which is the right shape
-- for topping out a tower and the wrong one for finding a wall writing halfway up
-- one: a discovery must never be something a player has to wait out or read
-- through a moving wall. So this is a chip on the free left edge, sliding in from
-- off-screen and back out on its own clock, at the one height nothing else in the
-- HUD uses. The top centre is the floor chip, the right column is score, coins,
-- powerup and ability, the bottom centre is the ability selector and the bottom
-- right is sprint.
--
-- Fragments arrive in runs, which is what banking is for: a player whose fifth
-- summit satisfies three fragments at once gets three of these in a row rather
-- than two drawn on top of each other. Hence the queue, and hence the payload
-- carrying its own index and total so a toast says where in the seventeen it
-- landed without this file holding a count it would have to keep in step.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local UiTheme = require(ReplicatedStorage:WaitForChild("UiTheme"))

local remote = ReplicatedStorage:WaitForChild("LoreUpdate")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local WIDTH = 320
local HEIGHT = 132
local EDGE = 18
local Y = 0.54

local gui = Instance.new("ScreenGui")
gui.Name = "LoreGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local chip = UiTheme.chip(gui, UDim2.fromOffset(WIDTH, HEIGHT), UDim2.new(0, -WIDTH, Y, 0), { seam = true })
chip.Visible = false

local kicker = UiTheme.label(chip, UDim2.new(1, -28, 0, 16), UDim2.new(0, 14, 0, 10), UiTheme.Body, 12, UiTheme.Rune)
kicker.TextXAlignment = Enum.TextXAlignment.Left

local day = UiTheme.label(chip, UDim2.new(1, -28, 0, 30), UDim2.new(0, 14, 0, 26), UiTheme.Display, 26)
day.TextXAlignment = Enum.TextXAlignment.Left

-- Chalk rather than the body Text colour: it is somebody else's handwriting, and
-- the Lantern is the same face the world's plates letter a place name in.
local body = UiTheme.label(chip, UDim2.new(1, -28, 0, 60), UDim2.new(0, 14, 0, 58), UiTheme.Body, 14, UiTheme.Lantern)
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Top
body.TextWrapped = true

local queue = {}
local showing = false

local function present(payload)
	if payload.kind == "caughtUp" then
		-- The join summary. One line for a whole backlog, because everything in it
		-- was earned in an earlier session and a run of toasts for old news is a
		-- run of toasts for old news.
		kicker.Text = string.format("Journal %d/%d", payload.index, payload.total)
		day.Text = payload.count == 1 and "1 writing" or (payload.count .. " writings")
		body.Text = "Found on earlier climbs. The Codex has them."
	else
		kicker.Text = string.format("New wall writing   Journal %d/%d", payload.index, payload.total)
		day.Text = "Day " .. tostring(payload.day)
		body.Text = payload.text
	end

	chip.Visible = true
	chip.Position = UDim2.new(0, -WIDTH, Y, 0)
	UiTheme.tween(chip, 0.28, { Position = UDim2.new(0, EDGE, Y, 0) })
	UiTheme.playSound(Config.Sounds.JournalUnlock, 0.35, 0.45)
end

local function pump()
	if showing then
		return
	end
	local payload = table.remove(queue, 1)
	if not payload then
		return
	end
	showing = true
	present(payload)

	task.delay(Config.Lore.ToastSeconds, function()
		UiTheme.tween(chip, 0.35, { Position = UDim2.new(0, -WIDTH, Y, 0) })
		task.delay(0.35 + Config.Lore.ToastGapSeconds, function()
			chip.Visible = false
			showing = false
			pump()
		end)
	end)
end

remote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.kind ~= "unlocked" and payload.kind ~= "caughtUp" then
		return
	end
	table.insert(queue, payload)
	pump()
end)
