-- PetService (Script) -> ServerScriptService
-- Owns the pet half of the profile: equipping, XP, evolution, the follower rig
-- in workspace.LivePets, and the read-only projection every client draws its UI
-- from. IncubatorService and DailyRewardService write pets and eggs too; they
-- say so on the PetsChanged bindable and this is what re-pushes and re-rigs.
--
-- Two remotes, both find-or-create because any of the three pet services may
-- load first. PetUpdate carries server to client, PetIntent carries client to
-- server and is the first client-authored input this game has ever accepted:
-- every intent is validated against the profile, nothing is trusted, and a
-- player who floods gets their extra intents dropped.
--
-- Followers are anchored parts moved by CFrame, not humanoids. A pathfinding pet
-- in a maze whose walls move is a pet stuck behind one, and a physics pet is one
-- more thing that can shove a player off a parapet. Nothing here is ever
-- parented into workspace.MazeCity.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local Profiles = require(ServerScriptService:WaitForChild("PlayerProfiles"))
local Inventory = require(ServerScriptService:WaitForChild("PetInventory"))

local function findOrCreate(parent, className, name)
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local made = Instance.new(className)
	made.Name = name
	made.Parent = parent
	return made
end

local remote = findOrCreate(ReplicatedStorage, "RemoteEvent", "PetUpdate")
local intents = findOrCreate(ReplicatedStorage, "RemoteEvent", "PetIntent")
local changed = findOrCreate(ServerScriptService, "BindableEvent", "PetsChanged")
local progress = findOrCreate(ServerScriptService, "BindableEvent", "MazeProgress")

local liveFolder = workspace:FindFirstChild("LivePets")
if not liveFolder then
	liveFolder = Instance.new("Folder")
	liveFolder.Name = "LivePets"
	liveFolder.Parent = workspace
end

local petFolder = ServerStorage:FindFirstChild("Pets")

-- player -> { [petUid] = { model, primary, stage, petId, index } }
local followers = {}
-- player -> { tokens, at }
local budget = {}

-- ============================================================
-- Replication
-- ============================================================

local function pushState(player, event)
	local data = Profiles.data(player)
	if not data then
		return
	end
	local payload = Inventory.project(data)
	payload.kind = "state"
	payload.event = event
	remote:FireClient(player, payload)
end

local function deny(player, action, reason)
	remote:FireClient(player, { kind = "denied", action = action, reason = reason })
end

-- ============================================================
-- Follower rigs
-- ============================================================
-- A rig is either a model an artist put in ServerStorage/Pets, or the
-- placeholder below, which is the same bargain EnemyService strikes: the game is
-- fully playable from a cold rojo build with zero Studio-side setup, and real
-- art drops in later by name with no code change.

local function sterilise(model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.CastShadow = false
			part.Massless = true
		end
	end
end

local function makePlaceholder(petConfig, stage)
	local look = Inventory.placeholder(petConfig, stage)
	local model = Instance.new("Model")
	model.Name = petConfig.id

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = look.shape == "Ball" and Enum.PartType.Ball or Enum.PartType.Block
	body.Size = Vector3.new(look.size, look.size, look.size)
	body.Color = look.color
	body.Material = Enum.Material.Neon
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Parent = model

	model.PrimaryPart = body
	return model
end

local function buildRig(petConfig, stage)
	local wanted = Inventory.modelName(petConfig, stage)
	if petFolder then
		local template = petFolder:FindFirstChild(wanted)
		if template and template:IsA("Model") then
			local clone = template:Clone()
			if not clone.PrimaryPart then
				clone.PrimaryPart = clone:FindFirstChildWhichIsA("BasePart")
			end
			if clone.PrimaryPart then
				return clone
			end
			clone:Destroy()
			warn("PetService: ServerStorage/Pets/" .. wanted .. " has no BasePart, using the placeholder")
		end
	end
	return makePlaceholder(petConfig, stage)
end

-- Glow is the one ability implemented end to end, and it is a light on the rig
-- rather than anything on the client: a follower is a world object every player
-- can see, so the light that comes off it belongs in the world too, replicated
-- once instead of drawn N times.
--
-- The evolution multiplier scales range and deliberately not brightness. Range
-- is how much maze the pet lights; brightness at 2.5x is a Solar Firefly that
-- blows out the corridor and the player standing in it, which is the same
-- failure Config.World.LampBrightness documents at the other end of the city.
local function applyGlow(primary, petConfig, stage)
	if petConfig.ability.type ~= "Glow" then
		return
	end
	local params = petConfig.ability.params
	local multiplier = Inventory.abilityMultiplier(petConfig, stage)

	local light = Instance.new("PointLight")
	light.Name = "PetGlow"
	light.Color = Inventory.placeholder(petConfig, stage).color
	light.Range = (params.radius or 12) * multiplier
	light.Brightness = params.brightness or 1
	light.Shadows = false
	light.Parent = primary
end

local function destroyFollower(player, petUid)
	local mine = followers[player]
	local entry = mine and mine[petUid]
	if not entry then
		return
	end
	mine[petUid] = nil
	if entry.model.Parent then
		entry.model:Destroy()
	end
end

local function spawnFollower(player, pet, index)
	local petConfig = Inventory.petConfig(pet.petId)
	if not petConfig then
		return
	end

	local model = buildRig(petConfig, pet.stage)
	sterilise(model)
	model.Name = player.Name .. "_" .. pet.uid

	local entry = {
		model = model,
		primary = model.PrimaryPart,
		stage = pet.stage,
		petId = pet.petId,
		index = index,
	}
	applyGlow(entry.primary, petConfig, pet.stage)

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		model:PivotTo(root.CFrame * CFrame.new(0, Config.Pets.FollowHeight, Config.Pets.FollowDistance))
	end
	model.Parent = liveFolder

	followers[player] = followers[player] or {}
	followers[player][pet.uid] = entry
end

-- Rebuilt rather than patched when the stage changes, because an evolution is a
-- different model and a different light: the cheap update is the one that does
-- nothing when nothing moved, which is the first branch below.
local function reconcileFollowers(player)
	local data = Profiles.data(player)
	if not data then
		return
	end

	local wanted = {}
	for index, petUid in ipairs(data.equipped) do
		local pet = data.pets[petUid]
		if pet and Inventory.petConfig(pet.petId) then
			wanted[petUid] = { pet = pet, index = index }
		end
	end

	local mine = followers[player] or {}
	for petUid, entry in pairs(mine) do
		local want = wanted[petUid]
		if not want or want.pet.stage ~= entry.stage or want.pet.petId ~= entry.petId then
			destroyFollower(player, petUid)
		else
			entry.index = want.index
		end
	end

	mine = followers[player] or {}
	for petUid, want in pairs(wanted) do
		if not mine[petUid] then
			spawnFollower(player, want.pet, want.index)
		end
	end
end

local function clearFollowers(player)
	local mine = followers[player]
	if not mine then
		return
	end
	for petUid in pairs(mine) do
		destroyFollower(player, petUid)
	end
	followers[player] = nil
end

-- One pass over every follower in the server, at frame rate. Cost is a CFrame
-- per equipped pet, which at MaxEquipped of one is a CFrame per player.
RunService.Heartbeat:Connect(function(dt)
	local pets = Config.Pets
	local now = os.clock()
	local alpha = math.clamp(dt * pets.FollowLerp, 0, 1)

	for player, mine in pairs(followers) do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		for petUid, entry in pairs(mine) do
			local model = entry.model
			if not model.Parent or not entry.primary or not entry.primary.Parent then
				mine[petUid] = nil
			elseif root then
				-- Slots fan out sideways so a second equipped pet does not stand
				-- inside the first. At MaxEquipped of one this is always zero.
				local side = (entry.index - 1) * pets.FollowSide
				local bob = math.sin((now / pets.BobSeconds) * math.pi * 2) * pets.BobHeight
				local goal = root.CFrame * CFrame.new(side, pets.FollowHeight + bob, pets.FollowDistance)
				-- Wrapped to a turn before it becomes radians. os.clock only ever
				-- grows, and a CFrame holds float32, so an unwrapped angle quantises
				-- into a visible judder after a few hours of server uptime.
				local turn = math.rad((now * pets.SpinDegreesPerSecond) % 360)
				local spun = CFrame.new(goal.Position) * CFrame.Angles(0, turn, 0)

				-- GetPivot, not PrimaryPart.CFrame: an artist's model may carry a
				-- pivot offset, and PivotTo is what is written back.
				local here = model:GetPivot()
				if (goal.Position - here.Position).Magnitude > pets.FollowTeleportRange then
					model:PivotTo(spun)
				else
					model:PivotTo(here:Lerp(spun, alpha))
				end
			end
		end
	end
end)

-- ============================================================
-- XP
-- ============================================================
-- Only the equipped pets earn, which is the whole reason equipping is a choice.
-- Both kinds of maze progress pay, whatever Config.Pets.HatchUnit says a maze
-- is: that setting governs hatching, not levelling, so a player who only ever
-- clears floors still levels a pet.

local function awardXp(player, amount)
	local data = Profiles.data(player)
	if not data or amount <= 0 then
		return
	end

	local rigDirty = false
	local best = nil
	for _, petUid in ipairs(data.equipped) do
		local ok, result = Inventory.addXp(data, petUid, amount)
		if ok and (result.leveled or result.evolved) then
			rigDirty = rigDirty or result.evolved
			local petConfig = Inventory.petConfig(result.pet.petId)
			best = {
				name = Inventory.displayName(result.pet, petConfig),
				level = result.pet.level,
				evolved = result.evolved,
				rarity = petConfig.rarity,
			}
		end
	end

	if rigDirty then
		reconcileFollowers(player)
	end
	pushState(player, best and { kind = "levelup", pet = best } or nil)
end

progress.Event:Connect(function(payload)
	if not Config.Pets.Enabled or not payload or not payload.player then
		return
	end
	local data = Profiles.data(payload.player)
	if not data then
		return
	end

	-- Every counter in stats is kept here rather than split across the three
	-- services that read them, so there is one place to look when a number is
	-- wrong. mazesCompleted counts whatever HatchUnit says a maze is, which is
	-- what makes it the same number the incubator is counting.
	if payload.kind == "floor" then
		data.stats.floorsCleared = data.stats.floorsCleared + 1
	elseif payload.kind == "tower" then
		data.stats.summitsReached = data.stats.summitsReached + 1
	end
	if payload.kind == Config.Pets.HatchUnit then
		data.stats.mazesCompleted = data.stats.mazesCompleted + 1
	end

	if payload.kind == "floor" then
		awardXp(payload.player, Config.Pets.XpPerFloor)
	elseif payload.kind == "tower" then
		awardXp(payload.player, Config.Pets.XpPerTower)
	end
end)

-- ============================================================
-- Intents
-- ============================================================

local function affordIntent(player)
	local now = os.clock()
	local entry = budget[player]
	if not entry then
		entry = { tokens = Config.Pets.IntentsPerSecond, at = now }
		budget[player] = entry
	end
	entry.tokens =
		math.min(Config.Pets.IntentsPerSecond, entry.tokens + (now - entry.at) * Config.Pets.IntentsPerSecond)
	entry.at = now
	if entry.tokens < 1 then
		return false
	end
	entry.tokens = entry.tokens - 1
	return true
end

-- Filtering can fail, and when it does the nickname is refused rather than let
-- through. That is the safe direction for a string other players will read, and
-- it is why nicknames are the one thing in this system that cannot be tested in
-- a Studio session without text filtering.
local function filterNickname(player, text)
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
	end)
	if not ok or not result then
		return nil
	end
	local shown, filtered = pcall(function()
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not shown then
		return nil
	end
	return filtered
end

local handlers = {}

handlers.sync = function(player)
	pushState(player)
end

handlers.equip = function(player, payload)
	local data = Profiles.data(player)
	if not data or type(payload.petUid) ~= "string" then
		return
	end
	local ok, reason = Inventory.equip(data, payload.petUid)
	if not ok then
		deny(player, "equip", reason)
		return
	end
	reconcileFollowers(player)
	pushState(player, { kind = "equipped", petUid = payload.petUid })
end

handlers.unequip = function(player, payload)
	local data = Profiles.data(player)
	if not data or type(payload.petUid) ~= "string" then
		return
	end
	local ok, reason = Inventory.unequip(data, payload.petUid)
	if not ok then
		deny(player, "unequip", reason)
		return
	end
	reconcileFollowers(player)
	pushState(player, { kind = "unequipped", petUid = payload.petUid })
end

handlers.lock = function(player, payload)
	local data = Profiles.data(player)
	if not data or type(payload.petUid) ~= "string" then
		return
	end
	local ok, reason = Inventory.setLocked(data, payload.petUid, payload.locked == true)
	if not ok then
		deny(player, "lock", reason)
		return
	end
	pushState(player)
end

handlers.nickname = function(player, payload)
	local data = Profiles.data(player)
	if not data or type(payload.petUid) ~= "string" then
		return
	end
	if not data.pets[payload.petUid] then
		deny(player, "nickname", "nopet")
		return
	end

	local wanted = payload.nickname
	if wanted == nil or wanted == "" then
		Inventory.setNickname(data, payload.petUid, nil)
		pushState(player)
		return
	end
	if type(wanted) ~= "string" then
		return
	end

	local clean = filterNickname(player, string.sub(wanted, 1, Config.Pets.NicknameMaxLength))
	if not clean then
		deny(player, "nickname", "filter")
		return
	end
	-- The profile may have gone during the filter call's yield.
	if not Profiles.data(player) then
		return
	end
	Inventory.setNickname(data, payload.petUid, clean)
	pushState(player, { kind = "renamed", petUid = payload.petUid })
end

intents.OnServerEvent:Connect(function(player, payload)
	if not Config.Pets.Enabled or type(payload) ~= "table" then
		return
	end
	local handler = handlers[payload.kind]
	if not handler or not affordIntent(player) then
		return
	end
	handler(player, payload)
end)

-- ============================================================
-- Lifecycle
-- ============================================================

changed.Event:Connect(function(payload)
	if not payload or not payload.player then
		return
	end
	reconcileFollowers(payload.player)
	pushState(payload.player, payload.event)
end)

Profiles.onReady(function(player, data)
	-- A catalogue entry can disappear between releases while a saved profile
	-- still names it, and an equipped pet that cannot be built is a follower that
	-- never appears with no way to tell why.
	Inventory.pruneEquipped(data)
	-- Same posture for gear: a worn uid the catalogue no longer knows comes off
	-- the pet, while the item itself stays in the bag in case the entry returns.
	Inventory.pruneWorn(data)
	reconcileFollowers(player)
	pushState(player)
end)

local function bindPlayer(player)
	player.CharacterAdded:Connect(function()
		-- The old character's rigs are still parented and still following a root
		-- part that no longer exists; rebuilding is cheaper than re-pointing them.
		clearFollowers(player)
		reconcileFollowers(player)
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end
Players.PlayerAdded:Connect(bindPlayer)

Players.PlayerRemoving:Connect(function(player)
	clearFollowers(player)
	budget[player] = nil
end)

-- The tag is bound by IncubatorService, which owns what the prompt does. This is
-- here only so a missing pedestal is visible in Output rather than showing up as
-- a summit with nothing on it.
task.delay(20, function()
	if Config.Pets.Enabled and #CollectionService:GetTagged("EggPedestal") == 0 then
		warn("PetService: no EggPedestal tagged 20s in, so no roof has an egg roost on it")
	end
end)
