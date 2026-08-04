-- TraversalService (Script) -> ServerScriptService
-- Slide between sections, plus the roof deck bounce pads.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))

local riding = {}
local bounceCooldown = {}

local function playerFrom(hit)
	local char = hit:FindFirstAncestorOfClass("Model")
	if not char then
		return nil, nil, nil
	end
	local player = Players:GetPlayerFromCharacter(char)
	if not player then
		return nil, nil, nil
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	return player, humanoid, root
end

local function endRide(player, humanoid)
	if not riding[player] then
		return
	end
	riding[player] = nil
	if humanoid then
		humanoid.PlatformStand = false
	end
end

local function bindEntrance(part)
	if not part:IsA("BasePart") then
		return
	end
	part.Touched:Connect(function(hit)
		local player, humanoid, root = playerFrom(hit)
		if not player or not humanoid or not root then
			return
		end
		if riding[player] then
			return
		end

		riding[player] = os.clock()
		humanoid.PlatformStand = true
		root.AssemblyLinearVelocity = root.CFrame.LookVector * 30

		task.delay(Config.SlideMaxSeconds, function()
			if riding[player] and os.clock() - riding[player] >= Config.SlideMaxSeconds - 0.1 then
				endRide(player, humanoid)
			end
		end)
	end)
end

local function bindBooster(part)
	if not part:IsA("BasePart") then
		return
	end
	part.Touched:Connect(function(hit)
		local player, _, root = playerFrom(hit)
		if not player or not root or not riding[player] then
			return
		end

		local dir =
			Vector3.new(part:GetAttribute("DirX") or 0, part:GetAttribute("DirY") or 0, part:GetAttribute("DirZ") or 0)
		if dir.Magnitude < 0.01 then
			return
		end

		local speed = part:GetAttribute("Speed") or Config.SlideBoostSpeed
		root.AssemblyLinearVelocity = dir.Unit * speed
	end)
end

local function bindExit(part)
	if not part:IsA("BasePart") then
		return
	end
	part.Touched:Connect(function(hit)
		local player, humanoid = playerFrom(hit)
		if not player then
			return
		end
		endRide(player, humanoid)
	end)
end

local function bindBouncePad(part)
	if not part:IsA("BasePart") then
		return
	end
	part.Touched:Connect(function(hit)
		local player, _, root = playerFrom(hit)
		if not player or not root then
			return
		end

		local last = bounceCooldown[player] or 0
		if os.clock() - last < Config.BouncePadCooldown then
			return
		end
		bounceCooldown[player] = os.clock()

		local power = part:GetAttribute("Power") or 140
		root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, power, root.AssemblyLinearVelocity.Z)
	end)
end

local binders = {
	SlideEntrance = bindEntrance,
	SlideBooster = bindBooster,
	SlideExit = bindExit,
	BouncePad = bindBouncePad,
}

for tag, binder in pairs(binders) do
	for _, part in ipairs(CollectionService:GetTagged(tag)) do
		binder(part)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(binder)
end

Players.PlayerRemoving:Connect(function(player)
	riding[player] = nil
	bounceCooldown[player] = nil
end)
