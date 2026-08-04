-- MovingWallService (Script) -> ServerScriptService
-- Drives every part tagged MovingWall. Slow, intermittent, and it refuses to
-- move into a space a player is currently standing in.

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))

local function characterParts()
	local params = OverlapParams.new()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = list
	return params, #list
end

local function spaceIsClear(cframe, size)
	local params, count = characterParts()
	if count == 0 then return true end
	local hits = workspace:GetPartBoundsInBox(cframe, size + Vector3.new(2, 2, 2), params)
	return #hits == 0
end

local function openCFrameFor(part, home)
	local mode = part:GetAttribute("Mode") or "slide"
	local travel = part:GetAttribute("Travel") or 25

	if mode == "rotate" then
		return home * CFrame.Angles(0, math.rad(90), 0)
	end

	local axis = part:GetAttribute("SlideAxis") or "X"
	local offset = (axis == "X") and Vector3.new(travel, 0, 0) or Vector3.new(0, 0, travel)
	return home * CFrame.new(offset)
end

local function run(part)
	if not part:IsA("BasePart") then return end

	local home = part.CFrame
	local away = openCFrameFor(part, home)
	local tweenTime = part:GetAttribute("TweenTime") or 6
	local dwellOpen = part:GetAttribute("DwellOpen") or 10
	local dwellClosed = part:GetAttribute("DwellClosed") or 14
	local phase = part:GetAttribute("Phase") or 0

	local info = TweenInfo.new(tweenTime, Config.MovingWallEasing, Enum.EasingDirection.InOut)

	task.spawn(function()
		task.wait(phase)
		while part.Parent do
			task.wait(dwellClosed)
			if not part.Parent then return end

			TweenService:Create(part, info, { CFrame = away }):Play()
			task.wait(tweenTime + dwellOpen)
			if not part.Parent then return end

			while not spaceIsClear(home, part.Size) do
				task.wait(Config.MovingWallRetrySeconds)
				if not part.Parent then return end
			end

			TweenService:Create(part, info, { CFrame = home }):Play()
			task.wait(tweenTime)
		end
	end)
end

if Config.MovingWallsEnabled then
	for _, part in ipairs(CollectionService:GetTagged("MovingWall")) do
		run(part)
	end
	CollectionService:GetInstanceAddedSignal("MovingWall"):Connect(run)
end
