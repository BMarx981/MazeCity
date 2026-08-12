-- BuildingLights (LocalScript) -> StarterPlayer/StarterPlayerScripts
-- Draws completion edges only for the local player. The generated building is
-- shared, so the glow lives in a client-only model beside MazeCity.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:WaitForChild("BuildingLightUpdate")
local intents = ReplicatedStorage:WaitForChild("BuildingLightIntent")
local player = Players.LocalPlayer

local fallbackColors = {
	Cobalt = Color3.fromRGB(92, 190, 255),
	Ochre = Color3.fromRGB(255, 176, 72),
	Slate = Color3.fromRGB(172, 208, 228),
	Verdigris = Color3.fromRGB(92, 255, 184),
	Bone = Color3.fromRGB(236, 226, 196),
	Ember = Color3.fromRGB(255, 92, 52),
}

local completed = {}
local overlays = {}

local lightsFolder = Instance.new("Folder")
lightsFolder.Name = "PlayerBuildingLights"
lightsFolder.Parent = workspace

local function rounded(inst, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = inst
end

local resetButton = Instance.new("TextButton")
resetButton.Name = "ResetBuildingLights"
resetButton.Size = UDim2.fromOffset(164, 34)
resetButton.Position = UDim2.new(0, 16, 1, -50)
resetButton.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
resetButton.BackgroundTransparency = 0.2
resetButton.BorderSizePixel = 0
resetButton.AutoButtonColor = false
resetButton.Font = Enum.Font.GothamBold
resetButton.TextSize = 12
resetButton.TextColor3 = Color3.fromRGB(215, 225, 235)
resetButton.Text = "RESET LIGHTS"
resetButton.Visible = false
rounded(resetButton, 8)
resetButton.Parent = player:WaitForChild("PlayerGui"):WaitForChild("FloorTimer")

local function updateResetButton()
	local count = 0
	for _ in pairs(completed) do
		count = count + 1
	end
	resetButton.Visible = count > 0
	resetButton.Text = count > 0 and string.format("RESET LIGHTS  %d", count) or "RESET LIGHTS"
end

local function buildingFor(key)
	local section, building = string.match(key, "^([^:]+):([^:]+)$")
	if not section or not building then
		return nil
	end
	local city = workspace:FindFirstChild("MazeCity")
	local sectionFolder = city and city:FindFirstChild("Section_" .. section)
	return sectionFolder and sectionFolder:FindFirstChild("Building_" .. building), section, building
end

local function addBeam(parent, name, position, size, color)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 0.04
	part.Size = size
	part.CFrame = CFrame.new(position)
	part.Parent = parent
	return part
end

local function createOverlay(key, building)
	local minX = building:GetAttribute("ExteriorMinX")
	local maxX = building:GetAttribute("ExteriorMaxX")
	local minZ = building:GetAttribute("ExteriorMinZ")
	local maxZ = building:GetAttribute("ExteriorMaxZ")
	local baseY = building:GetAttribute("ExteriorBaseY")
	local topY = building:GetAttribute("ExteriorTopY")
	local originX = building:GetAttribute("ExteriorOriginX")
	local originY = building:GetAttribute("ExteriorOriginY")
	local originZ = building:GetAttribute("ExteriorOriginZ")
	if not (minX and maxX and minZ and maxZ and baseY and topY and originX and originY and originZ) then
		return nil
	end

	local color = building:GetAttribute("CompletionLightColor")
	if typeof(color) ~= "Color3" then
		color = fallbackColors[building:GetAttribute("Style")] or Color3.fromRGB(180, 220, 255)
	end

	local model = Instance.new("Model")
	model.Name = "Completed_" .. key:gsub("[^%w]", "_")
	model.Parent = lightsFolder

	local origin = Vector3.new(originX, originY, originZ)
	local xMid = (minX + maxX) / 2
	local zMid = (minZ + maxZ) / 2
	local xLength = maxX - minX + 2.4
	local zLength = maxZ - minZ + 2.4
	local yEdge = 1.2
	local yTop = topY + 0.8
	local cornerOffset = 0.8
	local beamHeight = topY - baseY + 1.6

	-- Four perimeter lines at the crown and four at the street line make the
	-- completion state readable from a distance; the corner columns carry it all
	-- the way down instead of making the tower look capped with a lamp.
	for _, y in ipairs({ yEdge, yTop }) do
		addBeam(
			model,
			"EdgeNorth",
			origin + Vector3.new(xMid, y, minZ - cornerOffset),
			Vector3.new(xLength, 1.2, 1.1),
			color
		)
		addBeam(
			model,
			"EdgeSouth",
			origin + Vector3.new(xMid, y, maxZ + cornerOffset),
			Vector3.new(xLength, 1.2, 1.1),
			color
		)
		addBeam(
			model,
			"EdgeWest",
			origin + Vector3.new(minX - cornerOffset, y, zMid),
			Vector3.new(1.1, 1.2, zLength),
			color
		)
		addBeam(
			model,
			"EdgeEast",
			origin + Vector3.new(maxX + cornerOffset, y, zMid),
			Vector3.new(1.1, 1.2, zLength),
			color
		)
	end

	for _, x in ipairs({ minX - cornerOffset, maxX + cornerOffset }) do
		for _, z in ipairs({ minZ - cornerOffset, maxZ + cornerOffset }) do
			addBeam(
				model,
				"Corner",
				origin + Vector3.new(x, (baseY + topY) / 2, z),
				Vector3.new(1.6, beamHeight, 1.6),
				color
			)
		end
	end

	return model
end

local function reconcile()
	for key, overlay in pairs(overlays) do
		if not completed[key] or not overlay.Parent then
			overlay:Destroy()
			overlays[key] = nil
		end
	end

	for key in pairs(completed) do
		if not overlays[key] then
			local building = buildingFor(key)
			if building then
				overlays[key] = createOverlay(key, building)
			end
		end
	end
	updateResetButton()
end

resetButton.Activated:Connect(function()
	if next(completed) then
		intents:FireServer({ kind = "reset" })
	end
end)

remote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or payload.kind ~= "state" then
		return
	end
	completed = type(payload.completed) == "table" and payload.completed or {}
	reconcile()
end)

workspace.DescendantAdded:Connect(function(descendant)
	if descendant.Name:sub(1, 9) == "Building_" then
		task.defer(reconcile)
	end
end)

-- The profile may have landed before this LocalScript connected its listener.
-- A delayed request makes the saved state self-healing across startup order.
task.delay(2, function()
	intents:FireServer({ kind = "sync" })
end)
