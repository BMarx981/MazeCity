-- BestiaryGui (LocalScript) -> StarterPlayer.StarterPlayerScripts
-- The bestiary test screen the plan asks for at E5: every roster row as a
-- spinning portrait on one grid, toggled with B. It exists to prove
-- PortraitGenerator over every recipe at once, so it draws all twenty rows,
-- SplitterChild included, and nothing in it is authoritative about anything.
--
-- Behind Config.Enemies.BestiaryEnabled, which ships false: this whole file is
-- a no-op for a player. Flip the flag in Studio to eyeball the roster.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))

if not Config.Enemies.BestiaryEnabled then
	return
end

local EnemyDefinitions = require(ReplicatedStorage:WaitForChild("EnemyDefinitions"))
local PortraitGenerator = require(ReplicatedStorage:WaitForChild("PortraitGenerator"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local names = {}
for name in pairs(EnemyDefinitions.types) do
	table.insert(names, name)
end
table.sort(names)

local gui = Instance.new("ScreenGui")
gui.Name = "BestiaryGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = playerGui

local backdrop = Instance.new("Frame")
backdrop.Size = UDim2.fromScale(0.8, 0.8)
backdrop.Position = UDim2.fromScale(0.1, 0.1)
backdrop.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
backdrop.BackgroundTransparency = 0.15
backdrop.BorderSizePixel = 0
backdrop.Parent = gui

local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromScale(0.19, 0.235)
grid.CellPadding = UDim2.fromScale(0.008, 0.012)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = backdrop

for index, name in ipairs(names) do
	local cell = Instance.new("Frame")
	cell.Name = name
	cell.LayoutOrder = index
	cell.BackgroundColor3 = Color3.fromRGB(30, 33, 42)
	cell.BorderSizePixel = 0
	cell.Parent = backdrop

	local portrait = PortraitGenerator.portrait(name, { spin = true })
	portrait.Size = UDim2.fromScale(1, 0.85)
	portrait.Parent = cell

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 0.15)
	label.Position = UDim2.fromScale(0, 0.85)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(225, 228, 235)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = name
	label.Parent = cell
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.B then
		gui.Enabled = not gui.Enabled
	end
end)
