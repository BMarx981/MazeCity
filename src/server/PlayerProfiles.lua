-- PlayerProfiles (ModuleScript) -> ServerScriptService.PlayerProfiles
-- The one saved profile per player, and the only thing that talks to the
-- DataStore. SaveService used to be all of this; the pet system needed the same
-- table from three more scripts, and a Script cannot be required, so the storage
-- moved out here and SaveService kept the shop.
--
-- Failure posture, carried over unchanged and load-bearing: a profile that fails
-- to load sets loaded = false and is then never saved over. A Studio session
-- with no DataStore API access plays identically and wipes nothing. Every field
-- added here has to keep that property, which is why load merges field by field
-- against defaults instead of replacing the table.
--
-- Coins are deliberately not in the profile table. They are leaderstats.Coins,
-- read back off the IntValue at save time, so the number the whole game already
-- replicates is the only copy of it. Everything else lives in `data`.
--
-- The schema is versioned two ways and they do different jobs.
-- Config.Persistence.KeyPrefix is the wipe: bumping it starts every player
-- clean. SCHEMA_VERSION in the payload is the record: it costs nothing, it is
-- what a future migration table would key off, and it must not be confused for
-- the other one. Pet fields were added without touching either, because an
-- absent field loads as its default and an old profile is simply a player with
-- no pets.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))

local SCHEMA_VERSION = 1

local Profiles = {}

local store = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Persistence.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("PlayerProfiles: DataStore unavailable, running session-only: " .. tostring(result))
	end
end

-- player -> { data = <PlayerData minus coins>, loaded = bool, ready = bool }
local profiles = {}
local readyCallbacks = {}

local function defaults()
	local pets = Config.Pets
	return {
		schemaVersion = SCHEMA_VERSION,
		-- Tiers for everything the stall sells, passive and active alike. The
		-- abilities were not given a map of their own on purpose: a tier is a tier,
		-- the keys cannot collide, and splitting them would have retired the Wall
		-- Walker tiers players had already bought for the sake of a tidier field.
		upgrades = {},
		-- Which ability the key fires, or nil for "the first one they own". Stored
		-- rather than defaulted every session because it is a preference, and a
		-- player who chose the Cloak on Monday did not choose it for Monday.
		selectedAbility = nil,
		furthestSection = 1,
		completedBuildings = {},
		pets = {},
		eggs = {},
		-- Worn gear is not here: a pet's `worn` map rides inside the pet row, so it
		-- saves and loads with the pet that is wearing it.
		accessories = {},
		equipped = {},
		maxEquipped = pets.MaxEquipped,
		petStorageCap = pets.PetStorageCap,
		eggStorageCap = pets.EggStorageCap,
		accessoryStorageCap = Config.Accessories.AccessoryStorageCap,
		incubator = nil,
		daily = { lastClaimDayUtc = 0, streak = 0 },
		stats = { mazesCompleted = 0, floorsCleared = 0, summitsReached = 0, eggsHatched = 0 },
		-- The Codex, four chapters of unlock state; Types.CodexState is where the
		-- shape is explained. The journal chapter is a count rather than a set
		-- because its fragments unlock strictly in order, plus the bank of the
		-- accomplishments that happened before the fragment owed them came up.
		codex = { pets = {}, kept = {}, relics = {}, journal = { unlocked = 0, banked = {} } },
		gamepasses = {},
		-- Robux purchase ids already granted, PurchaseId -> os.time() of the
		-- grant. The idempotency half of PurchaseService's receipt spine: a
		-- Roblox retry that finds its id here is answered Granted without
		-- granting again. Pruned in adopt, so it stays bounded by a month of
		-- buying.
		receipts = {},
		starterGranted = false,
	}
end

local function storeKey(player)
	return Config.Persistence.KeyPrefix .. player.UserId
end

-- Created here as well as in PickupService and TowerTimerService because any of
-- them may see a given player first. All three do it synchronously inside their
-- own PlayerAdded handler, which run one after another on the same thread, so
-- there is no window in which two of them find nothing and both make a folder.
function Profiles.statValue(player, name)
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

function Profiles.coins(player)
	return Profiles.statValue(player, "Coins")
end

function Profiles.get(player)
	return profiles[player]
end

-- The profile table itself, or nil if this player has none yet. Callers mutate
-- it in place; there is no setter, and no copy, because two copies of a profile
-- is how one of them goes stale.
function Profiles.data(player)
	local entry = profiles[player]
	return entry and entry.data or nil
end

function Profiles.isLoaded(player)
	local entry = profiles[player]
	return entry ~= nil and entry.loaded
end

-- Called once per player, after the load attempt has finished, whether or not it
-- succeeded: a session-only profile still has to hand out a starter egg and
-- still has to apply upgrade stats. Registering late is safe, because anyone
-- already ready is replayed immediately.
function Profiles.onReady(callback)
	table.insert(readyCallbacks, callback)
	for player, entry in pairs(profiles) do
		if entry.ready then
			task.spawn(callback, player, entry.data)
		end
	end
end

local function fireReady(player, entry)
	if entry.ready then
		return
	end
	entry.ready = true
	for _, callback in ipairs(readyCallbacks) do
		task.spawn(callback, player, entry.data)
	end
end

-- Field by field rather than a wholesale assignment, so a profile written before
-- a field existed loads with that field's default instead of a nil the rest of
-- the game then has to guard against. This is the whole of the migration story
-- for an additive change, and the reason KeyPrefix did not have to move.
local function adopt(data, result)
	local pets = Config.Pets
	data.schemaVersion = SCHEMA_VERSION
	data.upgrades = result.upgrades or {}
	-- Not validated here. A key retired from Config.Abilities.Order since the
	-- profile was written is a selection AbilityService will simply not find in
	-- the owned list, and it re-picks; this module's job is to hand back what was
	-- stored, not to hold an opinion about what the shop currently sells.
	data.selectedAbility = result.selectedAbility
	data.furthestSection = result.furthestSection or 1
	data.completedBuildings = type(result.completedBuildings) == "table" and result.completedBuildings or {}
	data.pets = result.pets or {}
	data.eggs = result.eggs or {}
	data.accessories = result.accessories or {}
	data.equipped = result.equipped or {}
	data.maxEquipped = result.maxEquipped or pets.MaxEquipped
	data.petStorageCap = result.petStorageCap or pets.PetStorageCap
	data.eggStorageCap = result.eggStorageCap or pets.EggStorageCap
	data.accessoryStorageCap = result.accessoryStorageCap or Config.Accessories.AccessoryStorageCap
	data.incubator = result.incubator
	data.daily = result.daily or { lastClaimDayUtc = 0, streak = 0 }
	data.stats = result.stats or { mazesCompleted = 0, floorsCleared = 0, summitsReached = 0, eggsHatched = 0 }
	-- Added after stats itself was, so an otherwise current profile can still be
	-- missing exactly this one.
	data.stats.floorsCleared = data.stats.floorsCleared or 0
	-- Chapter by chapter rather than handed over whole, so a codex written before
	-- a chapter existed gains that chapter empty instead of nil. The type checks
	-- are because this is the one field indexed into on the way in, and adopt runs
	-- after entry.loaded is already true: an error here would leave a profile that
	-- is allowed to save holding nothing but defaults, which is the wipe the whole
	-- failure posture exists to prevent.
	local codex = type(result.codex) == "table" and result.codex or {}
	local journal = type(codex.journal) == "table" and codex.journal or {}
	data.codex = {
		pets = codex.pets or {},
		kept = codex.kept or {},
		relics = codex.relics or {},
		journal = { unlocked = journal.unlocked or 0, banked = journal.banked or {} },
	}
	data.gamepasses = result.gamepasses or {}
	-- Pruned on the way in rather than on a timer: a receipt's whole job is
	-- making Roblox's retries idempotent, and a retry arrives in days at the
	-- outside, so anything older than the keep window is a key that can never be
	-- asked about again.
	data.receipts = {}
	local receiptCutoff = os.time() - Config.Robux.ReceiptKeepDays * 86400
	for purchaseId, grantedAt in pairs(result.receipts or {}) do
		if type(grantedAt) == "number" and grantedAt >= receiptCutoff then
			data.receipts[purchaseId] = grantedAt
		end
	end
	data.starterGranted = result.starterGranted == true
end

local function load(player)
	local entry = profiles[player]
	if not entry then
		return
	end
	if not store then
		fireReady(player, entry)
		return
	end

	local ok, result = pcall(function()
		return store:GetAsync(storeKey(player))
	end)
	-- The player may have left during the yield above, in which case there is
	-- nothing left to fill in and firing ready would hand a departed player to
	-- every service that registered.
	if not profiles[player] then
		return
	end

	if not ok then
		warn("PlayerProfiles: load failed for " .. player.Name .. ", not saving this session: " .. tostring(result))
		fireReady(player, entry)
		return
	end

	entry.loaded = true
	if result then
		adopt(entry.data, result)
		-- Added, not assigned: anything picked up between join and the load
		-- landing is already in the value.
		local coins = Profiles.coins(player)
		coins.Value = coins.Value + (result.coins or 0)
	end
	fireReady(player, entry)
end

-- Returns whether the profile actually reached the DataStore, because the
-- receipt spine's "granted means saved" rule needs the answer: PurchaseService
-- returns PurchaseGranted only on true and lets Roblox retry otherwise. Every
-- older caller ignores the return, which is unchanged behaviour.
function Profiles.save(player)
	local entry = profiles[player]
	if not entry or not entry.loaded or not store then
		return false
	end

	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild("Coins")
	local data = entry.data
	local payload = {
		schemaVersion = SCHEMA_VERSION,
		coins = coins and coins.Value or 0,
		upgrades = data.upgrades,
		selectedAbility = data.selectedAbility,
		furthestSection = data.furthestSection,
		completedBuildings = data.completedBuildings,
		pets = data.pets,
		eggs = data.eggs,
		accessories = data.accessories,
		equipped = data.equipped,
		maxEquipped = data.maxEquipped,
		petStorageCap = data.petStorageCap,
		eggStorageCap = data.eggStorageCap,
		accessoryStorageCap = data.accessoryStorageCap,
		incubator = data.incubator,
		daily = data.daily,
		stats = data.stats,
		codex = data.codex,
		gamepasses = data.gamepasses,
		receipts = data.receipts,
		starterGranted = data.starterGranted,
		savedAt = os.time(),
	}

	local ok, err = pcall(function()
		store:UpdateAsync(storeKey(player), function()
			return payload
		end)
	end)
	if not ok then
		warn("PlayerProfiles: save failed for " .. player.Name .. ": " .. tostring(err))
	end
	return ok
end

local function bindPlayer(player)
	profiles[player] = { data = defaults(), loaded = false, ready = false }
	Profiles.coins(player)
	task.spawn(load, player)
end

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end
Players.PlayerAdded:Connect(bindPlayer)

Players.PlayerRemoving:Connect(function(player)
	Profiles.save(player)
	profiles[player] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		Profiles.save(player)
	end
end)

task.spawn(function()
	while true do
		task.wait(Config.Persistence.AutosaveSeconds)
		for _, player in ipairs(Players:GetPlayers()) do
			Profiles.save(player)
		end
	end
end)

return Profiles
