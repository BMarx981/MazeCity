-- SaveService (Script) -> ServerScriptService
-- One DataStore profile per player: coins, upgrade tiers, furthest section
-- reached. The schema is deliberately small and versioned through the key
-- prefix, because kid-first or not, this is the part a later public release
-- inherits.
--
-- Failure posture: a profile that fails to load is never saved over. The load
-- error is warned once and the session runs with defaults, so a Studio session
-- without DataStore API access plays identically and wipes nothing. Purchases
-- made in such a session are honestly lost, which beats the alternative.
--
-- The shop is bought from here too, through the ShopItem tag the generator
-- puts on each pedestal. Upgrades reach the rest of the game as attributes:
-- BaseWalkSpeed on the character (PickupService's Speed boost restores to it),
-- MagnetBonus on the player (PickupService adds it to the sweep radius). The
-- attribute channel is the same one Ghost and Freeze already use to cross a
-- service boundary.

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))

local remote = ReplicatedStorage:FindFirstChild("ShopUpdate")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "ShopUpdate"
	remote.Parent = ReplicatedStorage
end

local store = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Persistence.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("SaveService: DataStore unavailable, running session-only: " .. tostring(result))
	end
end

-- player -> { data = { upgrades, furthestSection }, loaded = bool }
-- Coins live in leaderstats and are only read back at save time, so this table
-- never has a second copy of the number the whole game already replicates.
local profiles = {}

local function storeKey(player)
	return Config.Persistence.KeyPrefix .. player.UserId
end

local function statValue(player, name)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end
	local value = stats:FindFirstChild(name)
	if not value then
		value = Instance.new("IntValue")
		value.Name = name
		value.Parent = stats
	end
	return value
end

local function tier(entry, key)
	return entry.data.upgrades[key] or 0
end

-- ============================================================
-- Applying upgrades
-- ============================================================
-- Re-run on every spawn and after every purchase. Everything derives from the
-- tier counts, so applying twice is applying once.

local function applyStats(player)
	local entry = profiles[player]
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not entry or not humanoid then
		return
	end

	local shop = Config.Shop
	local walk = shop.BaseWalkSpeed + tier(entry, "Speed") * shop.Upgrades.Speed.WalkSpeedPerTier
	char:SetAttribute("BaseWalkSpeed", walk)
	humanoid.WalkSpeed = walk

	local jumpBoost = 1 + tier(entry, "Jump") * shop.Upgrades.Jump.JumpBoostPerTier
	if humanoid.UseJumpPower then
		humanoid.JumpPower = shop.BaseJumpPower * jumpBoost
	else
		humanoid.JumpHeight = shop.BaseJumpHeight * jumpBoost
	end

	player:SetAttribute("MagnetBonus", tier(entry, "Magnet") * shop.Upgrades.Magnet.RadiusPerTier)
end

-- ============================================================
-- Load and save
-- ============================================================

local function load(player)
	local entry = profiles[player]
	if not entry or not store then
		return
	end
	local ok, result = pcall(function()
		return store:GetAsync(storeKey(player))
	end)
	if not ok then
		warn("SaveService: load failed for " .. player.Name .. ", not saving this session: " .. tostring(result))
		return
	end
	if not profiles[player] then
		return
	end
	entry.loaded = true
	if result then
		entry.data.upgrades = result.upgrades or {}
		entry.data.furthestSection = result.furthestSection or 1
		-- Added, not assigned: anything picked up between join and the load
		-- landing is already in the value.
		local coins = statValue(player, "Coins")
		coins.Value = coins.Value + (result.coins or 0)
	end
	applyStats(player)
end

local function save(player)
	local entry = profiles[player]
	if not entry or not entry.loaded or not store then
		return
	end
	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild("Coins")
	local data = {
		coins = coins and coins.Value or 0,
		upgrades = entry.data.upgrades,
		furthestSection = entry.data.furthestSection,
		savedAt = os.time(),
	}
	local ok, err = pcall(function()
		store:UpdateAsync(storeKey(player), function()
			return data
		end)
	end)
	if not ok then
		warn("SaveService: save failed for " .. player.Name .. ": " .. tostring(err))
	end
end

-- ============================================================
-- Shop purchases
-- ============================================================

local function buy(player, upgradeKey)
	local entry = profiles[player]
	local def = Config.Shop.Upgrades[upgradeKey]
	if not entry or not def then
		return
	end

	local owned = tier(entry, upgradeKey)
	if owned >= #def.Costs then
		remote:FireClient(player, { kind = "maxed", upgrade = upgradeKey, label = def.Label })
		return
	end

	local cost = def.Costs[owned + 1]
	local coins = statValue(player, "Coins")
	if coins.Value < cost then
		remote:FireClient(player, {
			kind = "poor",
			upgrade = upgradeKey,
			label = def.Label,
			need = cost - coins.Value,
		})
		return
	end

	coins.Value = coins.Value - cost
	entry.data.upgrades[upgradeKey] = owned + 1
	applyStats(player)
	remote:FireClient(player, {
		kind = "bought",
		upgrade = upgradeKey,
		label = def.Label,
		tier = owned + 1,
		maxTier = #def.Costs,
		cost = cost,
	})
end

local function bindShopItem(part)
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		return
	end
	prompt.Triggered:Connect(function(player)
		buy(player, part:GetAttribute("Upgrade"))
	end)
end

for _, part in ipairs(CollectionService:GetTagged("ShopItem")) do
	bindShopItem(part)
end
CollectionService:GetInstanceAddedSignal("ShopItem"):Connect(bindShopItem)

-- ============================================================
-- Furthest section
-- ============================================================
-- Stored for the schema's sake: nothing spawns off it yet, but a later
-- checkpoint feature should not need a data migration to exist. A player is
-- credited with a section by standing on any of its plaza spawn pads, which is
-- the one part every arrival route (slide, zipline, walk) actually crosses.

local function bindTowerStart(part)
	if not part:IsA("BasePart") then
		return
	end
	part.Touched:Connect(function(hit)
		local char = hit:FindFirstAncestorOfClass("Model")
		local player = char and Players:GetPlayerFromCharacter(char)
		local entry = player and profiles[player]
		if not entry then
			return
		end
		local section = part:GetAttribute("Section") or 1
		if section > entry.data.furthestSection then
			entry.data.furthestSection = section
		end
	end)
end

for _, part in ipairs(CollectionService:GetTagged("TowerStart")) do
	bindTowerStart(part)
end
CollectionService:GetInstanceAddedSignal("TowerStart"):Connect(bindTowerStart)

-- ============================================================
-- Player lifecycle
-- ============================================================

local function bindPlayer(player)
	profiles[player] = {
		data = { upgrades = {}, furthestSection = 1 },
		loaded = false,
	}
	statValue(player, "Coins")

	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("Humanoid", 5)
		applyStats(player)
	end)
	if player.Character then
		applyStats(player)
	end

	task.spawn(load, player)
end

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end
Players.PlayerAdded:Connect(bindPlayer)

Players.PlayerRemoving:Connect(function(player)
	save(player)
	profiles[player] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		save(player)
	end
end)

task.spawn(function()
	while true do
		task.wait(Config.Persistence.AutosaveSeconds)
		for _, player in ipairs(Players:GetPlayers()) do
			save(player)
		end
	end
end)
