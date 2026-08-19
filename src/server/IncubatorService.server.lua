-- IncubatorService (Script) -> ServerScriptService
-- Eggs: the summit roost, buying one, placing one, the climb that hatches it,
-- and the roll that decides what comes out. Since the accessories plan's Set 5
-- the same counter also sells gear, because the roost is where this game already
-- spends coins at a pedestal and a second storefront would be a second door.
--
-- Consumes the EggPedestal tag the generator puts on every roof deck, the way
-- SaveService consumes ShopItem. The prompt itself only opens the client's egg
-- panel; the intents that follow are validated here against the profile and
-- against the player still standing at a roost, so a client that skips the
-- prompt entirely gets nowhere.
--
-- One incubator slot per player, not per pedestal. Every roof in the city has a
-- roost and they are all the same roost: what makes a summit special is that it
-- is the only place an egg can be placed, not which one it was.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

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
-- Waited on rather than found-or-created, against the convention above,
-- because a BindableFunction has a single owner: PurchaseService makes it, and
-- a copy made here would be a gate nothing answers.
local promptPurchase = ServerScriptService:WaitForChild("PromptPurchase")

-- The prompt reaches PromptDistance from the pedestal's centre; this check is
-- against the root part, which sits about three studs off the floor and can be
-- another two out from where the prompt was triggered by the time the intent
-- lands. The slack is what stops a legitimate placement being refused for
-- having walked half a step.
local ROOST_SLACK = 4

-- A tower topped out with no egg in the slot is held as one credit rather than
-- thrown away. Placing an egg means standing on a summit, and the only way onto
-- a roof is up through that tower's ten floors: the zipline and the slide both
-- run downward. So the climb that carried the player to the roost is a climb
-- they made, and without crediting it the Summit Egg's "2 towers" is really
-- three and the number in the catalogue is not the number of climbs.
--
-- Exactly one is held. It is spent by the next placement, or overwritten by the
-- next summit, and it is never accumulated: two towers climbed before placing
-- still buys one credit, because the egg was not in the slot for either of them.
-- A summit that goes to an active incubator sets nothing, which is what stops a
-- player hatching at a summit and then placing a second egg into the same
-- climb's credit.
local pendingSummit = {}

local function deny(player, action, reason)
	remote:FireClient(player, { kind = "denied", action = action, reason = reason })
end

local function announce(player, event)
	changed:Fire({ player = player, event = event })
end

local function atRoost(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local reach = Config.Pets.PromptDistance + ROOST_SLACK
	for _, part in ipairs(CollectionService:GetTagged("EggPedestal")) do
		if part.Parent and (part.Position - root.Position).Magnitude <= reach then
			return true
		end
	end
	return false
end

-- ============================================================
-- Hatching
-- ============================================================

local function broadcastable(rarity)
	return Config.rarityIndex(rarity) >= Config.rarityIndex(Config.Pets.BroadcastFrom)
end

-- Refuses rather than destroys when storage is full: the egg stays in the
-- incubator, finished, and the player is told. Hatching into a full shelf and
-- dropping the pet on the floor is how a system loses somebody's Legendary, and
-- a finished egg sitting there is also the moment a storage upgrade is worth
-- selling, which is the spec's point about this being a monetization beat.
local function resolveHatch(player, quiet)
	local data = Profiles.data(player)
	local incubator = data and data.incubator
	if not incubator then
		return false
	end

	local eggConfig = Inventory.eggConfig(incubator.eggId)
	if not eggConfig then
		-- The egg's catalogue entry went away underneath a placed egg. Clearing the
		-- slot is the only move that does not strand the player forever.
		warn("IncubatorService: unknown egg " .. tostring(incubator.eggId) .. " placed, clearing the slot")
		data.incubator = nil
		announce(player)
		return false
	end
	if incubator.mazesCompleted < eggConfig.mazesRequired then
		if not quiet then
			deny(player, "hatch", "notready")
		end
		return false
	end

	local petId = Inventory.rollHatch(eggConfig)
	if not petId then
		warn("IncubatorService: " .. eggConfig.id .. " has no hatchable entries left in its table")
		return false
	end

	local ok, result = Inventory.grantPet(data, petId, eggConfig.id)
	if not ok then
		deny(player, "hatch", result)
		return false
	end

	data.incubator = nil
	data.stats.eggsHatched = data.stats.eggsHatched + 1

	local petConfig = Inventory.petConfig(petId)
	announce(player, {
		kind = "hatched",
		petUid = result.uid,
		-- The reveal draws the pet, and it draws it from the same recipes the
		-- follower is built from, so the payload carries the two things
		-- PetModelGenerator.build takes and no geometry at all.
		petId = result.petId,
		stage = result.stage,
		name = Inventory.displayName(result, petConfig),
		rarity = petConfig.rarity,
		ability = petConfig.ability.type,
		eggName = eggConfig.name,
	})

	if broadcastable(petConfig.rarity) then
		-- The id and not the line (LORE.MD 6.1): every client already holds
		-- `Lore.pets`, so quoting the pet on a server-wide banner costs the
		-- wire nothing and a rewritten line ships without touching this file.
		remote:FireAllClients({
			kind = "broadcast",
			playerName = player.DisplayName,
			petName = petConfig.name,
			petId = result.petId,
			rarity = petConfig.rarity,
		})
	end
	return true
end

-- ============================================================
-- Maze progress
-- ============================================================

progress.Event:Connect(function(payload)
	if not Config.Pets.Enabled or not payload or not payload.player then
		return
	end
	if payload.kind ~= Config.Pets.HatchUnit then
		return
	end

	local player = payload.player
	local data = Profiles.data(player)
	if not data then
		return
	end

	-- PetService keeps the counters, including mazesCompleted. This service owns
	-- exactly one thing: the egg in the slot.
	if not data.incubator then
		pendingSummit[player] = true
		return
	end

	-- HatchBoost is catalogued but no pet carries it yet, so this resolves to one
	-- for now. It is here rather than deferred because the spec puts it here, and
	-- because the day a HatchBoost pet is added it should be a catalogue edit and
	-- nothing else.
	local boost = Inventory.equippedAbility(data, "HatchBoost")
	local amount = boost and (boost.params.rate or 1) * boost.multiplier or 1

	-- Gear is the second source and, until a HatchBoost pet exists, the only one
	-- that ever moves this off 1. Read straight off the resolver rather than off
	-- an attribute, because this script already requires PetInventory: an
	-- attribute would be a second copy of a number with a single reader.
	local hatch = Inventory.wornEffects(data).HatchProgress or 0
	if hatch > 0 then
		amount = amount * (1 + hatch)
	end

	local ok, result = Inventory.addMazeProgress(data, amount)
	if not ok then
		return
	end

	if result.ready then
		if resolveHatch(player, true) then
			return
		end
		-- Finished and could not hatch, which today means a full pet shelf.
		-- resolveHatch has already said why, so this pushes the state without an
		-- event of its own rather than putting a second banner over the first.
		announce(player)
		return
	end
	announce(
		player,
		{ kind = "incubated", done = math.floor(result.incubator.mazesCompleted), required = result.required }
	)
end)

-- ============================================================
-- Intents
-- ============================================================
-- PetService owns the rate limit and the PetIntent remote's other kinds; these
-- three are ignored there and handled here. Both scripts read every payload and
-- act on the kinds they own, which is how one remote serves the whole system
-- without either of them having to know the other exists.

local function placeEgg(player, payload)
	local data = Profiles.data(player)
	if not data or type(payload.eggUid) ~= "string" then
		return
	end
	if not atRoost(player) then
		deny(player, "placeEgg", "notatroost")
		return
	end

	local ok, reason = Inventory.placeEgg(data, payload.eggUid)
	if not ok then
		deny(player, "placeEgg", reason)
		return
	end

	local eggId = data.incubator.eggId
	local eggConfig = Inventory.eggConfig(eggId)
	local required = eggConfig and eggConfig.mazesRequired or 0

	if pendingSummit[player] then
		pendingSummit[player] = nil
		local credited, result = Inventory.addMazeProgress(data, 1)
		-- A one-maze egg is finished the moment it is placed, and hatching it here
		-- rather than on the next summit is the right answer: the player is already
		-- standing on one. Nothing in the catalogue is a one-maze egg today, so
		-- this branch is written for the day one is and not for a bug.
		if credited and result.ready then
			if resolveHatch(player, true) then
				return
			end
			announce(player)
			return
		end
	end

	announce(player, {
		kind = "placed",
		eggId = eggId,
		done = math.floor(data.incubator.mazesCompleted),
		required = required,
	})
end

local function buyEgg(player, payload)
	local data = Profiles.data(player)
	if not data or type(payload.eggId) ~= "string" then
		return
	end
	if not atRoost(player) then
		deny(player, "buyEgg", "notatroost")
		return
	end

	local eggConfig = Inventory.eggConfig(payload.eggId)
	-- An egg with no coinCost is not for sale, which is what keeps the streak egg
	-- out of the shelf without needing a second flag on it.
	if not eggConfig or not eggConfig.coinCost then
		deny(player, "buyEgg", "unknown")
		return
	end
	if eggConfig.availableUntil and os.time() > eggConfig.availableUntil then
		deny(player, "buyEgg", "expired")
		return
	end
	if Inventory.count(data.eggs) >= data.eggStorageCap then
		deny(player, "buyEgg", "eggsfull")
		return
	end

	local coins = Profiles.coins(player)
	if coins.Value < eggConfig.coinCost then
		remote:FireClient(player, {
			kind = "denied",
			action = "buyEgg",
			reason = "poor",
			need = eggConfig.coinCost - coins.Value,
			label = eggConfig.name,
		})
		return
	end

	-- Deducted before the grant and refunded if the grant refuses, so a cap check
	-- that fires between the two cannot charge for nothing.
	coins.Value = coins.Value - eggConfig.coinCost
	local ok, reason = Inventory.grantEgg(data, payload.eggId)
	if not ok then
		coins.Value = coins.Value + eggConfig.coinCost
		deny(player, "buyEgg", reason)
		return
	end
	announce(player, { kind = "bought", eggId = eggConfig.id, name = eggConfig.name, cost = eggConfig.coinCost })
end

-- Gear is a second list through the same door: the same roost, the same
-- leaderstats.Coins, the same deduct-then-refund order, and the same proximity
-- re-check on the mutation rather than on the prompt that opened the panel. It
-- is here rather than in PetService for the reason the plan gives: this is
-- already the service that spends coins at a pedestal, and PetService owns no
-- purchase.
local function buyAccessory(player, payload)
	local data = Profiles.data(player)
	if not data or type(payload.accessoryId) ~= "string" then
		return
	end
	if not atRoost(player) then
		deny(player, "buyAccessory", "notatroost")
		return
	end

	local config = Inventory.accessoryConfig(payload.accessoryId)
	if not config then
		deny(player, "buyAccessory", "unknown")
		return
	end
	-- No coinCost is the whole of what keeps the streak Legendary and the event
	-- trail out of the shop, the same flag-free rule the streak egg already uses,
	-- and Set 1 settled that it keeps them out of the sell path too.
	if not config.coinCost then
		deny(player, "buyAccessory", "notforsale")
		return
	end
	if config.availableUntil and os.time() > config.availableUntil then
		deny(player, "buyAccessory", "expired")
		return
	end
	if Inventory.count(data.accessories) >= data.accessoryStorageCap then
		deny(player, "buyAccessory", "gearfull")
		return
	end

	local coins = Profiles.coins(player)
	if coins.Value < config.coinCost then
		remote:FireClient(player, {
			kind = "denied",
			action = "buyAccessory",
			reason = "poor",
			need = config.coinCost - coins.Value,
			label = config.name,
		})
		return
	end

	coins.Value = coins.Value - config.coinCost
	local ok, reason = Inventory.grantAccessory(data, payload.accessoryId)
	if not ok then
		coins.Value = coins.Value + config.coinCost
		deny(player, "buyAccessory", reason)
		return
	end
	announce(player, { kind = "bought", accessoryId = config.id, name = config.name, cost = config.coinCost })
end

-- The Robux half of the same two storefronts (docs/ROBUX_PLAN.md, R3). An
-- intent here validates what only this service can, which is the player still
-- standing at a roost and the row existing and not having expired, then asks
-- the prompt gate, which re-checks everything a receipt would refuse: the
-- offer, the loaded profile, the storage caps. Deliberately no coinCost check,
-- coinCost and robuxProductId being two independent one-field rules; the gate
-- refuses a row with no offer on its own. Nothing is granted here and no coin
-- moves: the grant is PurchaseService's, on the receipt, and a refusal from
-- either side rides the same denied message the coin paths send.
local function buyEggRobux(player, payload)
	local data = Profiles.data(player)
	if not data or type(payload.eggId) ~= "string" then
		return
	end
	if not atRoost(player) then
		deny(player, "buyEggRobux", "notatroost")
		return
	end
	local eggConfig = Inventory.eggConfig(payload.eggId)
	if not eggConfig then
		deny(player, "buyEggRobux", "unknown")
		return
	end
	if eggConfig.availableUntil and os.time() > eggConfig.availableUntil then
		deny(player, "buyEggRobux", "expired")
		return
	end
	local ok, reason = promptPurchase:Invoke(player, "egg", payload.eggId)
	if not ok then
		deny(player, "buyEggRobux", reason)
	end
end

local function buyAccessoryRobux(player, payload)
	local data = Profiles.data(player)
	if not data or type(payload.accessoryId) ~= "string" then
		return
	end
	if not atRoost(player) then
		deny(player, "buyAccessoryRobux", "notatroost")
		return
	end
	local config = Inventory.accessoryConfig(payload.accessoryId)
	if not config then
		deny(player, "buyAccessoryRobux", "unknown")
		return
	end
	if config.availableUntil and os.time() > config.availableUntil then
		deny(player, "buyAccessoryRobux", "expired")
		return
	end
	local ok, reason = promptPurchase:Invoke(player, "accessory", payload.accessoryId)
	if not ok then
		deny(player, "buyAccessoryRobux", reason)
	end
end

-- R5, and the one Robux purchase with no coin twin: a pet is gambled for, not
-- bought, so its price is what rolling for it costs and the offer is Robux
-- only, derived in Storefront.impliedCoinsForPet from the same hatchTable the
-- roll reads. No expiry check because a pet row has no availableUntil; the
-- storage cap is the gate's hasRoom, and the grant lands through the same
-- PetInventory.grantPet a hatch uses.
local function buyPetRobux(player, payload)
	local data = Profiles.data(player)
	if not data or type(payload.petId) ~= "string" then
		return
	end
	if not atRoost(player) then
		deny(player, "buyPetRobux", "notatroost")
		return
	end
	if not Inventory.petConfig(payload.petId) then
		deny(player, "buyPetRobux", "unknown")
		return
	end
	local ok, reason = promptPurchase:Invoke(player, "pet", payload.petId)
	if not ok then
		deny(player, "buyPetRobux", reason)
	end
end

-- The refusals are all Inventory.sellAccessory's: locked, worn, an item that was
-- never for sale, and an id this player does not own. Nothing is checked twice
-- here, and the coins are paid after the instance is gone rather than before, so
-- a refusal cannot pay out.
local function sellAccessory(player, payload)
	local data = Profiles.data(player)
	if not data or type(payload.accessoryUid) ~= "string" then
		return
	end
	if not atRoost(player) then
		deny(player, "sellAccessory", "notatroost")
		return
	end

	local ok, result = Inventory.sellAccessory(data, payload.accessoryUid)
	if not ok then
		deny(player, "sellAccessory", result)
		return
	end

	local coins = Profiles.coins(player)
	coins.Value = coins.Value + result.value
	announce(player, { kind = "sold", name = result.config.name, value = result.value })
end

intents.OnServerEvent:Connect(function(player, payload)
	if not Config.Pets.Enabled or type(payload) ~= "table" then
		return
	end
	if payload.kind == "placeEgg" then
		placeEgg(player, payload)
	elseif payload.kind == "buyEgg" then
		buyEgg(player, payload)
	elseif payload.kind == "buyAccessory" then
		buyAccessory(player, payload)
	elseif payload.kind == "buyEggRobux" then
		buyEggRobux(player, payload)
	elseif payload.kind == "buyAccessoryRobux" then
		buyAccessoryRobux(player, payload)
	elseif payload.kind == "buyPetRobux" then
		buyPetRobux(player, payload)
	elseif payload.kind == "sellAccessory" then
		sellAccessory(player, payload)
	elseif payload.kind == "hatch" then
		-- The manual retry for a finished egg that could not hatch into a full
		-- shelf. Releasing a pet is not in this version, so what unblocks it today
		-- is a storage cap raise; the intent exists so that when one arrives the
		-- player does not have to climb another tower to use it.
		resolveHatch(player, false)
	end
end)

-- ============================================================
-- The roost
-- ============================================================

local function bindPedestal(part)
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		return
	end
	prompt.Triggered:Connect(function(player)
		if not Config.Pets.Enabled then
			return
		end
		-- The prompt is a door into the UI and nothing else. Every mutation behind
		-- it re-checks proximity itself, so this can afford to be a plain nudge.
		remote:FireClient(player, { kind = "roost" })
	end)
end

for _, part in ipairs(CollectionService:GetTagged("EggPedestal")) do
	bindPedestal(part)
end
CollectionService:GetInstanceAddedSignal("EggPedestal"):Connect(bindPedestal)

-- ============================================================
-- Starter egg
-- ============================================================
-- Without this a new player's only routes to an egg are 250 coins they have not
-- earned and a seven day streak, so the loop the whole system is built around
-- would be unreachable on day one. Granted once and remembered, including in a
-- session-only profile, where "remembered" lasts as long as the session and
-- costs nothing but a second egg no DataStore will ever see.

Profiles.onReady(function(player, data)
	if not Config.Pets.Enabled or data.starterGranted then
		return
	end
	data.starterGranted = true
	local ok = Inventory.grantEgg(data, Config.Pets.StarterEggId)
	if ok then
		announce(player, { kind = "starter", eggId = Config.Pets.StarterEggId })
	end
end)

Players.PlayerRemoving:Connect(function(player)
	pendingSummit[player] = nil
end)
