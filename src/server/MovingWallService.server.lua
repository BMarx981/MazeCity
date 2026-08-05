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
	if count == 0 then
		return true
	end
	local hits = workspace:GetPartBoundsInBox(cframe, size + Vector3.new(2, 2, 2), params)
	return #hits == 0
end

-- MazeGenerator stamps every one of these on each MovingWall it makes. The
-- fallbacks that used to stand in for them turned a generator bug into a wall
-- that cycled on plausible-looking numbers, so nothing ever looked wrong.
local REQUIRED = { "Mode", "Travel", "TweenTime", "DwellOpen", "DwellClosed", "Phase" }

local function readSettings(part)
	local settings = {}
	for _, name in ipairs(REQUIRED) do
		local value = part:GetAttribute(name)
		if value == nil then
			warn("MovingWallService: " .. part:GetFullName() .. " has no " .. name .. " attribute, leaving it static")
			return nil
		end
		settings[name] = value
	end

	if settings.Mode ~= "rotate" then
		settings.SlideAxis = part:GetAttribute("SlideAxis")
		if settings.SlideAxis == nil then
			warn("MovingWallService: " .. part:GetFullName() .. " has no SlideAxis attribute, leaving it static")
			return nil
		end
	end

	return settings
end

local function openCFrameFor(home, settings)
	if settings.Mode == "rotate" then
		return home * CFrame.Angles(0, math.rad(90), 0)
	end

	local travel = settings.Travel
	local offset = (settings.SlideAxis == "X") and Vector3.new(travel, 0, 0) or Vector3.new(0, 0, travel)
	return home * CFrame.new(offset)
end

local function run(part)
	if not part:IsA("BasePart") then
		return
	end

	local settings = readSettings(part)
	if not settings then
		return
	end

	local home = part.CFrame
	local away = openCFrameFor(home, settings)
	local tweenTime = settings.TweenTime
	local dwellOpen = settings.DwellOpen
	local dwellClosed = settings.DwellClosed

	local info = TweenInfo.new(tweenTime, Config.MovingWallEasing, Enum.EasingDirection.InOut)

	task.spawn(function()
		task.wait(settings.Phase)
		while part.Parent do
			task.wait(dwellClosed)
			if not part.Parent then
				return
			end

			TweenService:Create(part, info, { CFrame = away }):Play()
			task.wait(tweenTime + dwellOpen)
			if not part.Parent then
				return
			end

			while not spaceIsClear(home, part.Size) do
				task.wait(Config.MovingWallRetrySeconds)
				if not part.Parent then
					return
				end
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
