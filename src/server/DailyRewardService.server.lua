-- DailyRewardService (Script) -> ServerScriptService
-- One claim per UTC day, a streak that grows while the days are consecutive, and
-- a streak egg plus a piece of Legendary gear on day seven.
--
-- Day arithmetic is done on the UTC day number, math.floor(os.time() / 86400),
-- exactly as the spec has it. Storing the day rather than the timestamp is what
-- makes the streak rule a subtraction instead of a calendar problem, and it is
-- timezone-proof for free: two players in Auckland and Los Angeles roll over at
-- the same instant, which is the only rule that can be explained to either of
-- them.
--
-- No tag, no world object. The claim is a HUD button, because a daily reward
-- that needs a walk to a kiosk is a daily reward people miss.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local Profiles = require(ServerScriptService:WaitForChild("PlayerProfiles"))
local Inventory = require(ServerScriptService:WaitForChild("PetInventory"))

local SECONDS_PER_DAY = 86400

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
local lore = findOrCreate(ServerScriptService, "BindableEvent", "LoreEvent")

local function today()
	return math.floor(os.time() / SECONDS_PER_DAY)
end

-- A brand new profile has lastClaimDayUtc = 0, which is 1970 and would read as a
-- lapsed streak. That is the right answer: their first claim starts the streak
-- at one, which is what a first claim should do.
local function nextStreak(data, day)
	if day - data.daily.lastClaimDayUtc == 1 then
		local grown = data.daily.streak + 1
		if grown > Config.Pets.DailyStreakLength then
			return 1
		end
		return grown
	end
	return 1
end

local function claim(player)
	local data = Profiles.data(player)
	if not data then
		return
	end

	local day = today()
	if day <= data.daily.lastClaimDayUtc then
		remote:FireClient(player, {
			kind = "denied",
			action = "daily",
			reason = "claimed",
			-- Seconds to the next UTC midnight, so the client can count down
			-- without having to agree with the server about what time it is.
			nextIn = (data.daily.lastClaimDayUtc + 1) * SECONDS_PER_DAY - os.time(),
		})
		return
	end

	local streak = nextStreak(data, day)
	data.daily.lastClaimDayUtc = day
	data.daily.streak = streak

	local pets = Config.Pets
	local coinReward = pets.DailyCoinBase + (streak - 1) * pets.DailyCoinPerStreak
	local xpReward = pets.DailyXpBase + (streak - 1) * pets.DailyXpPerStreak

	Profiles.coins(player).Value = Profiles.coins(player).Value + coinReward

	-- XP goes to the equipped pets, the same rule maze completions use. A player
	-- with nothing equipped banks the coins and loses the XP, which is one more
	-- reason to have a pet out.
	local xpPaid = 0
	for _, petUid in ipairs(data.equipped) do
		local ok = Inventory.addXp(data, petUid, xpReward)
		if ok then
			xpPaid = xpReward
		end
	end

	-- Caught here and never polled, which is the one thing about this the journal
	-- cannot work out for itself: the streak wraps back to 1 past DailyStreakLength,
	-- so a saved profile has no way of saying a seventh day was ever reached. The
	-- claim is the only instant the fact exists.
	if streak >= pets.DailyStreakLength then
		lore:Fire({ kind = "SevenDayStreak", player = player })
	end

	local eggName = nil
	if streak >= pets.DailyStreakLength then
		local ok, result = Inventory.grantEgg(data, pets.StreakEggId)
		if ok then
			local eggConfig = Inventory.eggConfig(result.eggId)
			eggName = eggConfig and eggConfig.name or result.eggId
		else
			-- The shelf was full on the one day it mattered. Saying so is the whole
			-- fix available: rolling the streak back would cost them the day, and
			-- holding the egg in escrow is a system this version does not have.
			remote:FireClient(player, { kind = "denied", action = "daily", reason = result })
		end
	end

	-- The second source the accessories plan asks for, and the only way to own a
	-- Legendary: the shop refuses anything with no coinCost, so this is not a
	-- cheaper route to an item, it is the route. Same posture as the egg above,
	-- including keeping the day when the bag is full rather than rolling the
	-- streak back.
	local gearName = nil
	local gearConfig = Inventory.accessoryConfig(Config.Accessories.StreakGearId)
	if streak == Config.Accessories.StreakGearDay and gearConfig then
		local ok, result = Inventory.grantAccessory(data, gearConfig.id)
		if ok then
			gearName = gearConfig.name
			if Config.rarityIndex(gearConfig.rarity) >= Config.rarityIndex(pets.BroadcastFrom) then
				remote:FireAllClients({
					kind = "broadcast",
					playerName = player.DisplayName,
					itemName = gearConfig.name,
					verb = "earned",
					rarity = gearConfig.rarity,
				})
			end
		else
			remote:FireClient(player, { kind = "denied", action = "daily", reason = result })
		end
	end

	changed:Fire({
		player = player,
		event = {
			kind = "daily",
			streak = streak,
			length = pets.DailyStreakLength,
			coins = coinReward,
			xp = xpPaid,
			egg = eggName,
			gear = gearName,
		},
	})
end

intents.OnServerEvent:Connect(function(player, payload)
	if not Config.Pets.Enabled or type(payload) ~= "table" then
		return
	end
	if payload.kind == "daily" then
		claim(player)
	end
end)

-- Told on join so the HUD knows whether the button is live before the player has
-- pressed anything. The projection PetService pushes already carries `daily`, so
-- this only adds what that cannot say: whether today has been claimed.
Profiles.onReady(function(player, data)
	if not Config.Pets.Enabled then
		return
	end
	remote:FireClient(player, {
		kind = "dailyStatus",
		available = today() > data.daily.lastClaimDayUtc,
		streak = data.daily.streak,
		length = Config.Pets.DailyStreakLength,
	})
end)
