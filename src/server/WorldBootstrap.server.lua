-- WorldBootstrap (Script) -> ServerScriptService
-- Builds the world at server start and extends it lazily: touching a slide
-- entrance guarantees the destination section exists before anyone lands.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local MazeGenerator = require(ServerScriptService:WaitForChild("MazeGenerator"))

local seed = Config.World.Seed
local root = Instance.new("Folder")
root.Name = "MazeCity"
root.Parent = workspace

local built = {}
local inProgress = {}

local function ensureSection(sectionIndex)
	if sectionIndex < 1 or built[sectionIndex] then
		return
	end
	if inProgress[sectionIndex] then
		while inProgress[sectionIndex] do
			task.wait(0.25)
		end
		return
	end

	inProgress[sectionIndex] = true
	local t0 = os.clock()
	local ok, err = pcall(function()
		MazeGenerator.buildSection(root, sectionIndex, seed)
	end)
	inProgress[sectionIndex] = nil

	if ok then
		built[sectionIndex] = true
		print(string.format("MazeCity: section %d built in %.2fs", sectionIndex, os.clock() - t0))
	else
		warn(string.format("MazeCity: section %d failed to build: %s", sectionIndex, tostring(err)))
	end
end

for i = 1, math.max(1, Config.World.PregenerateSections) do
	ensureSection(i)
end

workspace:SetAttribute("MazeCityReady", true)

if Config.World.LazyGeneration then
	local function bindEntrance(part)
		if not part:IsA("BasePart") then
			return
		end
		local target = part:GetAttribute("ToSection")
		if not target then
			return
		end
		part.Touched:Connect(function()
			task.spawn(ensureSection, target)
		end)
	end

	for _, part in ipairs(CollectionService:GetTagged("SlideEntrance")) do
		bindEntrance(part)
	end
	CollectionService:GetInstanceAddedSignal("SlideEntrance"):Connect(bindEntrance)
end
