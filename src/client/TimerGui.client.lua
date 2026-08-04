-- TimerGui (LocalScript) -> StarterPlayer/StarterPlayerScripts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:WaitForChild("TimerUpdate")
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "FloorTimer"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local holder = Instance.new("Frame")
holder.Size = UDim2.new(0, 220, 0, 68)
holder.Position = UDim2.new(0.5, -110, 0, 16)
holder.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
holder.BackgroundTransparency = 0.25
holder.BorderSizePixel = 0
holder.Visible = false
holder.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = holder

local towerLabel = Instance.new("TextLabel")
towerLabel.Size = UDim2.new(1, -16, 0, 18)
towerLabel.Position = UDim2.new(0, 8, 0, 6)
towerLabel.BackgroundTransparency = 1
towerLabel.Font = Enum.Font.Gotham
towerLabel.TextSize = 13
towerLabel.TextColor3 = Color3.fromRGB(180, 190, 205)
towerLabel.Text = ""
towerLabel.Parent = holder

local timeLabel = Instance.new("TextLabel")
timeLabel.Size = UDim2.new(1, -16, 0, 32)
timeLabel.Position = UDim2.new(0, 8, 0, 24)
timeLabel.BackgroundTransparency = 1
timeLabel.Font = Enum.Font.GothamBlack
timeLabel.TextSize = 28
timeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
timeLabel.Text = "0:00"
timeLabel.Parent = holder

local bar = Instance.new("Frame")
bar.Size = UDim2.new(1, 0, 0, 4)
bar.Position = UDim2.new(0, 0, 1, -4)
bar.BackgroundColor3 = Color3.fromRGB(90, 200, 140)
bar.BorderSizePixel = 0
bar.Parent = holder

local function format(seconds)
	local m = math.floor(seconds / 60)
	local s = math.floor(seconds % 60)
	return string.format("%d:%02d", m, s)
end

remote.OnClientEvent:Connect(function(payload)
	if not payload then
		holder.Visible = false
		return
	end

	holder.Visible = true
	towerLabel.Text = string.format("%s  |  Floor %d", payload.tower, payload.level + 1)
	timeLabel.Text = format(payload.remaining)

	local ratio = math.clamp(payload.remaining / math.max(1, payload.allowance), 0, 1)
	bar.Size = UDim2.new(ratio, 0, 0, 4)

	if ratio < 0.2 then
		bar.BackgroundColor3 = Color3.fromRGB(230, 80, 80)
		timeLabel.TextColor3 = Color3.fromRGB(255, 150, 150)
	elseif ratio < 0.45 then
		bar.BackgroundColor3 = Color3.fromRGB(235, 180, 70)
		timeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	else
		bar.BackgroundColor3 = Color3.fromRGB(90, 200, 140)
		timeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	end
end)
