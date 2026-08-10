-- PetLookPreview (Script) -> ServerScriptService
-- TEMPORARY. Delete this file before the pet looks branch merges.
--
-- Set 1 of docs/PET_LOOKS_PLAN.md has to be eyeballed and there is no way to
-- eyeball generated geometry in edit mode, which CLAUDE.md records as the cost
-- of dropping the Studio plugin. Its own suggested workaround is this: a
-- throwaway RunService:IsStudio() branch that builds the geometry where you can
-- see it, rather than owning eleven pets to look at eleven looks.
--
-- Builds every pet at every stage in one row in front of the first character to
-- spawn, labelled, turning at the same rate a real follower turns. Nothing else
-- in the game reads it and it writes nothing back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local PetCatalog = require(ReplicatedStorage:WaitForChild("PetCatalog"))
local PetModelGenerator = require(ReplicatedStorage:WaitForChild("PetModelGenerator"))

local SPACING = 5
local AHEAD = 16
local HEIGHT = 3

local built = false

-- Sorted, because pairs over the catalogue is not a stable order and a row that
-- reshuffles between runs is a row you cannot compare against the last one.
local function everyLook()
	local ids = {}
	for petId in pairs(PetCatalog) do
		table.insert(ids, petId)
	end
	table.sort(ids)

	local entries = {}
	for _, petId in ipairs(ids) do
		local petConfig = PetCatalog[petId]
		for stage = 0, #petConfig.evolutions do
			local evolution = stage > 0 and petConfig.evolutions[stage] or nil
			table.insert(entries, {
				petId = petId,
				stage = stage,
				label = petConfig.name .. (evolution and (" " .. (evolution.displaySuffix or stage)) or ""),
			})
		end
	end
	return entries
end

local function labelFor(model, text)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 22)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = true
	gui.Parent = model.PrimaryPart

	local name = Instance.new("TextLabel")
	name.Size = UDim2.fromScale(1, 1)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextSize = 13
	name.TextColor3 = Color3.fromRGB(255, 255, 255)
	name.TextStrokeTransparency = 0.4
	name.Text = text
	name.Parent = gui
end

local function buildRow(root)
	local folder = Instance.new("Folder")
	folder.Name = "PetLookPreview"
	folder.Parent = workspace

	local entries = everyLook()
	local origin = root.CFrame * CFrame.new(-(#entries - 1) * SPACING / 2, HEIGHT, -AHEAD)

	local placed = {}
	local parts = 0
	for index, entry in ipairs(entries) do
		local model = PetModelGenerator.build(entry.petId, entry.stage)
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
			end
		end
		local at = origin * CFrame.new((index - 1) * SPACING, 0, 0)
		model:PivotTo(at)
		labelFor(model, entry.label)
		model.Parent = folder
		parts = parts + #model:GetDescendants()
		table.insert(placed, { model = model, at = at })
	end

	print(string.format("PetLookPreview: %d looks, %d instances", #entries, parts))

	-- Held in a list rather than read back off the folder, because GetChildren
	-- order is not build order and a row that pairs a model with someone else's
	-- slot spends every frame teleporting past itself.
	RunService.Heartbeat:Connect(function()
		local turn = math.rad((os.clock() * Config.Pets.SpinDegreesPerSecond) % 360)
		for _, entry in ipairs(placed) do
			entry.model:PivotTo(CFrame.new(entry.at.Position) * CFrame.Angles(0, turn, 0))
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		if built then
			return
		end
		built = true
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if root then
			buildRow(root)
		end
	end)
end)
