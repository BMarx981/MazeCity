-- SaveService (Script) -> ServerScriptService
-- The upgrade shop, and the furthest-section credit. The profile it reads and
-- writes lives in PlayerProfiles, which is where the DataStore, the load posture
-- and the autosave went when the pet system needed the same table from three
-- more scripts and found that a Script cannot be required.
--
-- What is left here is what a shop is: prices, tier counts, and turning those
-- counts into stats. Upgrades reach the rest of the game as attributes, which is
-- the same channel Ghost and Freeze already use to cross a service boundary:
-- BaseWalkSpeed on the character (the baseline every WalkSpeedResolver factor
-- multiplies), MagnetRange on the player (PickupService pulls coins in from it),
-- and one AbilityTier_<Key> per ability (AbilityService sizes the drain by it,
-- AbilityGui draws the bar from it).
--
-- The stall sells two kinds of row and this file knows the difference in exactly
-- one place, the AbilityTier loop in applyStats: a row with a Mode is an ability,
-- is bound to a key and competes for the selection, and everything about that
-- lives in AbilityService. Buying one is buying any other row.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local Profiles = require(ServerScriptService:WaitForChild("PlayerProfiles"))
local WalkSpeed = require(ServerScriptService:WaitForChild("WalkSpeedResolver"))

local remote = ReplicatedStorage:FindFirstChild("ShopUpdate")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "ShopUpdate"
	remote.Parent = ReplicatedStorage
end

local function tier(data, key)
	return data.upgrades[key] or 0
end

-- ============================================================
-- Applying upgrades
-- ============================================================
-- Re-run on every spawn, on profile load, and after every purchase. Everything
-- derives from the tier counts, so applying twice is applying once.

local function applyStats(player)
	local data = Profiles.data(player)
	if not data then
		return
	end

	local shop = Config.Shop

	-- Player attributes first and outside the character guard. They are what the
	-- ability HUD draws itself from, and a profile that lands a moment before the
	-- body would otherwise leave the bar blank until the spawn caught up.
	-- The pull in studs, not a bonus on anything: an unbought magnet is a zero,
	-- which is what tells PickupService there is no second sweep to run.
	player:SetAttribute("MagnetRange", shop.Upgrades.Magnet.RangePerTier[tier(data, "Magnet")] or 0)

	-- One attribute per ability, which AbilityService reads to size the drain and
	-- to know what is selectable, and AbilityGui reads to draw the bar. The same
	-- channel MagnetRange and BaseWalkSpeed already use, and stamped for every key
	-- in the order rather than only for owned ones: a zero is what tells the HUD
	-- an ability exists and has not been bought, where an absent attribute is
	-- indistinguishable from a profile that has not landed.
	for _, key in ipairs(Config.Abilities.Order) do
		player:SetAttribute("AbilityTier_" .. key, tier(data, key))
	end

	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local walk = shop.BaseWalkSpeed + tier(data, "Speed") * shop.Upgrades.Speed.WalkSpeedPerTier
	char:SetAttribute("BaseWalkSpeed", walk)
	-- Through the resolver rather than straight onto the humanoid. This runs on
	-- every purchase, and writing the bare baseline here would cancel a sprint or
	-- a powerup that happened to be live: buying Fast Feet mid-sprint would slow
	-- the player down. The resolver re-multiplies whatever is still applied.
	WalkSpeed.apply(char)
end

-- ============================================================
-- Shop purchases
-- ============================================================

local function buy(player, upgradeKey)
	local data = Profiles.data(player)
	local def = Config.Shop.Upgrades[upgradeKey]
	if not data or not def then
		return
	end

	local owned = tier(data, upgradeKey)
	if owned >= #def.Costs then
		remote:FireClient(player, { kind = "maxed", upgrade = upgradeKey, label = def.Label })
		return
	end

	local cost = def.Costs[owned + 1]
	local coins = Profiles.coins(player)
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
	data.upgrades[upgradeKey] = owned + 1
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
		local data = player and Profiles.data(player)
		if not data then
			return
		end
		local section = part:GetAttribute("Section") or 1
		if section > data.furthestSection then
			data.furthestSection = section
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
-- PlayerProfiles owns join, leave, autosave and BindToClose. All this needs is
-- to be told when a profile is readable and when a body exists to stamp.

local function bindPlayer(player)
	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("Humanoid", 5)
		applyStats(player)
	end)
	if player.Character then
		applyStats(player)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end
Players.PlayerAdded:Connect(bindPlayer)

Profiles.onReady(function(player)
	applyStats(player)
end)
