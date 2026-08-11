-- PetLookPreview (Script) -> ServerScriptService
-- TEMPORARY. Delete this file before the pet looks branch merges.
--
-- Set 1 of docs/PET_LOOKS_PLAN.md has to be eyeballed and there is no way to
-- eyeball generated geometry in edit mode, which CLAUDE.md records as the cost
-- of dropping the Studio plugin. Its own suggested workaround is this: a
-- throwaway RunService:IsStudio() branch that builds the geometry where you can
-- see it, rather than owning eleven pets to look at eleven looks.
--
-- Builds every pet at every stage in one row in front of the caller, labelled,
-- turning at the same rate a real follower turns. Nothing else in the game reads
-- it and it writes nothing back.
--
-- **On demand, never on spawn.** It used to build itself the moment the first
-- character loaded, which put eleven AlwaysOnTop billboards in the view of
-- anyone who pressed Play for any other reason: the labels bunch into one stack
-- at the distance the row sits, and a debug surface that cannot be not-looked-at
-- is a debug surface that ruins every unrelated playtest. So it takes the same
-- two doors EnemyDebug takes, chat as any player or the command bar during Play:
--
--   /petlook          build the row in front of the speaker, replacing any row
--   /petlook clear    take it away
--
--   game:GetService("ServerScriptService").PetLookPreviewCommand:Invoke()
--   game:GetService("ServerScriptService").PetLookPreviewCommand:Invoke("clear")

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

-- The spin loop, held so that clearing stops it. It was a bare Connect on a row
-- built exactly once, which was fine while the row was built exactly once;
-- rebuilding on a command leaves one connection per build turning models that
-- have been destroyed.
local spin = nil

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

local function clearRow()
	if spin then
		spin:Disconnect()
		spin = nil
	end
	local folder = workspace:FindFirstChild("PetLookPreview")
	if folder then
		folder:Destroy()
		return true
	end
	return false
end

local function buildRow(root)
	clearRow()

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

	-- Held in a list rather than read back off the folder, because GetChildren
	-- order is not build order and a row that pairs a model with someone else's
	-- slot spends every frame teleporting past itself.
	spin = RunService.Heartbeat:Connect(function()
		local turn = math.rad((os.clock() * Config.Pets.SpinDegreesPerSecond) % 360)
		for _, entry in ipairs(placed) do
			entry.model:PivotTo(CFrame.new(entry.at.Position) * CFrame.Angles(0, turn, 0))
		end
	end)

	return string.format("%d looks, %d instances", #entries, parts)
end

-- The speaker's own character, falling back to the first player so the command
-- bar door works with no speaker to read a position off.
local function rootFor(speaker)
	local player = speaker or Players:GetPlayers()[1]
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function dispatch(speaker, command)
	if string.lower(tostring(command or "")) == "clear" then
		return clearRow() and "cleared" or "nothing to clear"
	end
	local root = rootFor(speaker)
	if not root then
		return "no character to build in front of"
	end
	return buildRow(root)
end

local function run(speaker, command)
	local result = dispatch(speaker, command)
	print("[PetLookPreview] " .. tostring(result))
	return result
end

local bindable = Instance.new("BindableFunction")
bindable.Name = "PetLookPreviewCommand"
bindable.OnInvoke = function(command)
	return run(nil, command)
end
bindable.Parent = script.Parent

Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(message)
		local words = string.split(message, " ")
		if string.lower(words[1]) == "/petlook" then
			run(player, words[2])
		end
	end)
end)
