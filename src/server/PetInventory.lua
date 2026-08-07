-- PetInventory (ModuleScript) -> ServerScriptService.PetInventory
-- The rules of the pet system, as functions over a profile table. No remotes, no
-- instances, no DataStore, no yielding: everything here takes the `data` table
-- PlayerProfiles owns and returns what happened.
--
-- It exists because three services mutate the same inventory. PetService equips
-- and levels, IncubatorService hatches, DailyRewardService grants, and all three
-- need the same cap checks and the same idea of what a level is. Written once
-- here, those cannot drift apart; written three times, they would.
--
-- Every mutating function returns ok, reasonOrValue. A refusal is an ordinary
-- return, never an error and never a silent no-op, because the client is going
-- to be told why.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local PetCatalog = require(ReplicatedStorage:WaitForChild("PetCatalog"))
local EggCatalog = require(ReplicatedStorage:WaitForChild("EggCatalog"))

local Inventory = {}

Inventory.PetCatalog = PetCatalog
Inventory.EggCatalog = EggCatalog

-- Runtime randomness, deliberately not seeded off Config.World.Seed. Two players
-- opening the same egg should not get the same pet, and neither should the same
-- player twice, which is the same reasoning PickupService's powerup roll uses.
local roll = Random.new()

local function uid()
	return HttpService:GenerateGUID(false)
end

-- A catalogue entry can disappear between one release and the next while a saved
-- profile still references it. That is a warning and a skipped instance, not a
-- crash: the pet stays in the profile in case the entry comes back.
function Inventory.petConfig(petId)
	return PetCatalog[petId]
end

function Inventory.eggConfig(eggId)
	return EggCatalog[eggId]
end

local function count(map)
	local n = 0
	for _ in pairs(map) do
		n = n + 1
	end
	return n
end

Inventory.count = count

-- ============================================================
-- Levels and evolution
-- ============================================================
-- xp on a PetInstance is the total ever earned, not the remainder toward the
-- next level. Storing the total means a curve that gets rebalanced re-derives
-- every existing pet's level correctly instead of freezing them wherever the old
-- curve left them.

function Inventory.xpForLevel(petConfig, level)
	return math.floor(petConfig.xpCurve.base * petConfig.xpCurve.growth ^ (level - 1))
end

-- Returns level, xp into that level, xp needed to leave it. At maxLevel the
-- third value is nil, which is what the UI draws as a full bar.
function Inventory.levelFor(petConfig, xp)
	local level = 1
	local remaining = math.max(0, xp)
	while level < petConfig.maxLevel do
		local need = Inventory.xpForLevel(petConfig, level)
		if remaining < need then
			return level, remaining, need
		end
		remaining = remaining - need
		level = level + 1
	end
	return petConfig.maxLevel, 0, nil
end

-- Stage 0 is the base form. Stage N is evolutions[N], and evolutions are assumed
-- to be in ascending level order, which is how the catalogue is written.
function Inventory.stageFor(petConfig, level)
	local stage = 0
	for i, evolution in ipairs(petConfig.evolutions) do
		if level >= evolution.level then
			stage = i
		end
	end
	return stage
end

function Inventory.stageData(petConfig, stage)
	if stage > 0 then
		return petConfig.evolutions[stage]
	end
	return nil
end

function Inventory.abilityMultiplier(petConfig, stage)
	local evolution = Inventory.stageData(petConfig, stage)
	return evolution and evolution.abilityMultiplier or 1
end

function Inventory.modelName(petConfig, stage)
	local evolution = Inventory.stageData(petConfig, stage)
	return evolution and evolution.model or petConfig.model
end

function Inventory.placeholder(petConfig, stage)
	local evolution = Inventory.stageData(petConfig, stage)
	return (evolution and evolution.placeholder) or petConfig.placeholder
end

function Inventory.displayName(pet, petConfig)
	if pet.nickname and pet.nickname ~= "" then
		return pet.nickname
	end
	local evolution = Inventory.stageData(petConfig, pet.stage)
	if evolution and evolution.displaySuffix then
		return evolution.displaySuffix .. " " .. petConfig.name
	end
	return petConfig.name
end

-- Recomputes level and stage from xp and reports whether either moved, so the
-- caller can decide whether a level-up is worth telling the player about and
-- whether the follower rig has to be rebuilt.
function Inventory.addXp(data, petUid, amount)
	local pet = data.pets[petUid]
	if not pet or amount <= 0 then
		return false, "nopet"
	end
	local petConfig = PetCatalog[pet.petId]
	if not petConfig then
		return false, "nopet"
	end

	local wasLevel, wasStage = pet.level, pet.stage
	pet.xp = pet.xp + amount
	pet.level = Inventory.levelFor(petConfig, pet.xp)
	pet.stage = Inventory.stageFor(petConfig, pet.level)

	return true,
		{
			pet = pet,
			gained = amount,
			leveled = pet.level > wasLevel,
			evolved = pet.stage > wasStage,
		}
end

-- ============================================================
-- Granting
-- ============================================================

function Inventory.grantEgg(data, eggId)
	local eggConfig = EggCatalog[eggId]
	if not eggConfig then
		return false, "unknown"
	end
	if eggConfig.availableUntil and os.time() > eggConfig.availableUntil then
		return false, "expired"
	end
	-- The egg sitting in the incubator has left the eggs map, so it does not
	-- count against the cap: a full shelf plus one hatching is the honest reading
	-- of "five eggs", and the alternative strands a player who placed their last
	-- one.
	if count(data.eggs) >= data.eggStorageCap then
		return false, "eggsfull"
	end

	local egg = { uid = uid(), eggId = eggId, acquiredAt = os.time() }
	data.eggs[egg.uid] = egg
	return true, egg
end

function Inventory.grantPet(data, petId, sourceEggId)
	local petConfig = PetCatalog[petId]
	if not petConfig then
		return false, "unknown"
	end
	if count(data.pets) >= data.petStorageCap then
		return false, "petsfull"
	end

	local pet = {
		uid = uid(),
		petId = petId,
		level = 1,
		xp = 0,
		stage = Inventory.stageFor(petConfig, 1),
		locked = false,
		nickname = nil,
		acquiredAt = os.time(),
		sourceEggId = sourceEggId,
	}
	data.pets[pet.uid] = pet
	return true, pet
end

-- ============================================================
-- Hatching
-- ============================================================

-- One draw against the total weight. Weights are relative, so an entry naming a
-- pet that no longer exists is skipped rather than renormalised away, and a
-- table that is entirely stale falls through to nil instead of picking wrongly.
function Inventory.rollHatch(eggConfig)
	local total = 0
	for _, entry in ipairs(eggConfig.hatchTable) do
		if PetCatalog[entry.petId] then
			total = total + entry.weight
		end
	end
	if total <= 0 then
		return nil
	end

	local pick = roll:NextNumber() * total
	for _, entry in ipairs(eggConfig.hatchTable) do
		if PetCatalog[entry.petId] then
			pick = pick - entry.weight
			if pick <= 0 then
				return entry.petId
			end
		end
	end
	-- Floating point can leave the loop one hair short of the last entry.
	for i = #eggConfig.hatchTable, 1, -1 do
		local entry = eggConfig.hatchTable[i]
		if PetCatalog[entry.petId] then
			return entry.petId
		end
	end
	return nil
end

function Inventory.placeEgg(data, eggUid)
	if data.incubator then
		return false, "occupied"
	end
	local egg = data.eggs[eggUid]
	if not egg then
		return false, "noegg"
	end
	if not EggCatalog[egg.eggId] then
		return false, "unknown"
	end

	-- Out of the eggs map and into the incubator, so it exists in exactly one
	-- place and cannot be placed twice or sold out from under itself.
	data.eggs[eggUid] = nil
	data.incubator = { eggUid = eggUid, eggId = egg.eggId, mazesCompleted = 0, placedAt = os.time() }
	return true, data.incubator
end

-- Returns the incubator state and whether it is now full, so the caller can do
-- the hatch itself: hatching writes a pet, clears the slot and announces, none
-- of which belongs behind a progress counter.
function Inventory.addMazeProgress(data, amount)
	local incubator = data.incubator
	if not incubator then
		return false, "empty"
	end
	local eggConfig = EggCatalog[incubator.eggId]
	if not eggConfig then
		return false, "unknown"
	end

	incubator.mazesCompleted = incubator.mazesCompleted + amount
	return true,
		{
			incubator = incubator,
			required = eggConfig.mazesRequired,
			ready = incubator.mazesCompleted >= eggConfig.mazesRequired,
		}
end

-- ============================================================
-- Equipping
-- ============================================================

function Inventory.isEquipped(data, petUid)
	for _, uidValue in ipairs(data.equipped) do
		if uidValue == petUid then
			return true
		end
	end
	return false
end

function Inventory.equip(data, petUid)
	if not data.pets[petUid] then
		return false, "nopet"
	end
	if Inventory.isEquipped(data, petUid) then
		return true, "already"
	end
	if #data.equipped >= data.maxEquipped then
		-- One slot is the v1 rule, so swapping is what a player means by equipping
		-- a second pet. Above one slot they mean the list is full, and are told so.
		if data.maxEquipped == 1 then
			table.remove(data.equipped, 1)
		else
			return false, "equipfull"
		end
	end
	table.insert(data.equipped, petUid)
	return true, "equipped"
end

function Inventory.unequip(data, petUid)
	for i, uidValue in ipairs(data.equipped) do
		if uidValue == petUid then
			table.remove(data.equipped, i)
			return true, "unequipped"
		end
	end
	return false, "notequipped"
end

-- The strongest equipped instance of one ability, as its param table scaled by
-- that pet's evolution multiplier, or nil if nothing equipped has it. Written
-- once here because two services ask: PetService for Glow, IncubatorService for
-- the HatchBoost the spec's OnMazeCompleted applies. An ability that no
-- catalogued pet carries yet simply never resolves, which is why adding one
-- later is a catalogue edit and not a service edit.
function Inventory.equippedAbility(data, abilityType)
	local best = nil
	for _, petUid in ipairs(data.equipped) do
		local pet = data.pets[petUid]
		local petConfig = pet and PetCatalog[pet.petId]
		if petConfig and petConfig.ability.type == abilityType then
			local multiplier = Inventory.abilityMultiplier(petConfig, pet.stage)
			if not best or multiplier > best.multiplier then
				best = { pet = pet, config = petConfig, params = petConfig.ability.params, multiplier = multiplier }
			end
		end
	end
	return best
end

-- A pet whose catalogue entry vanished, or that was released, must not stay in
-- the equipped list: the follower would be a rig nothing can build.
function Inventory.pruneEquipped(data)
	local kept = {}
	for _, uidValue in ipairs(data.equipped) do
		local pet = data.pets[uidValue]
		if pet and PetCatalog[pet.petId] and #kept < data.maxEquipped then
			table.insert(kept, uidValue)
		end
	end
	data.equipped = kept
	return kept
end

function Inventory.setLocked(data, petUid, locked)
	local pet = data.pets[petUid]
	if not pet then
		return false, "nopet"
	end
	pet.locked = locked and true or false
	return true, pet
end

function Inventory.setNickname(data, petUid, nickname)
	local pet = data.pets[petUid]
	if not pet then
		return false, "nopet"
	end
	if nickname == nil or nickname == "" then
		pet.nickname = nil
	else
		pet.nickname = string.sub(nickname, 1, Config.Pets.NicknameMaxLength)
	end
	return true, pet
end

-- ============================================================
-- Client projection
-- ============================================================
-- A read-only snapshot, never the profile table itself. Everything the UI needs
-- is resolved here rather than on the client, so the client never has to agree
-- with the server about what level a pet is; it just draws the number it was
-- sent.

function Inventory.project(data)
	local pets = {}
	for petUid, pet in pairs(data.pets) do
		local petConfig = PetCatalog[pet.petId]
		if petConfig then
			local level, into, need = Inventory.levelFor(petConfig, pet.xp)
			table.insert(pets, {
				uid = petUid,
				petId = pet.petId,
				name = Inventory.displayName(pet, petConfig),
				rarity = petConfig.rarity,
				ability = petConfig.ability.type,
				level = level,
				xpInto = into,
				xpNeed = need,
				stage = pet.stage,
				locked = pet.locked,
				nickname = pet.nickname,
				equipped = Inventory.isEquipped(data, petUid),
				multiplier = Inventory.abilityMultiplier(petConfig, pet.stage),
			})
		end
	end
	table.sort(pets, function(a, b)
		if a.rarity ~= b.rarity then
			return Config.rarityIndex(a.rarity) > Config.rarityIndex(b.rarity)
		end
		if a.level ~= b.level then
			return a.level > b.level
		end
		return a.uid < b.uid
	end)

	local eggs = {}
	for eggUid, egg in pairs(data.eggs) do
		local eggConfig = EggCatalog[egg.eggId]
		if eggConfig then
			table.insert(eggs, {
				uid = eggUid,
				eggId = egg.eggId,
				name = eggConfig.name,
				color = eggConfig.color,
				required = eggConfig.mazesRequired,
			})
		end
	end
	table.sort(eggs, function(a, b)
		if a.required ~= b.required then
			return a.required < b.required
		end
		return a.uid < b.uid
	end)

	local incubator = nil
	if data.incubator then
		local eggConfig = EggCatalog[data.incubator.eggId]
		if eggConfig then
			incubator = {
				eggId = data.incubator.eggId,
				name = eggConfig.name,
				color = eggConfig.color,
				-- Floored because a HatchBoost multiplier makes progress fractional
				-- and "1.4 of 2 mazes" is not a thing anyone has climbed.
				done = math.floor(data.incubator.mazesCompleted),
				required = eggConfig.mazesRequired,
			}
		end
	end

	return {
		pets = pets,
		eggs = eggs,
		incubator = incubator,
		-- Copied, not referenced. Everything else in here was built fresh above,
		-- and a projection that hands out one live pointer into the profile is a
		-- projection only until somebody holds onto it.
		equipped = table.clone(data.equipped),
		maxEquipped = data.maxEquipped,
		petCap = data.petStorageCap,
		eggCap = data.eggStorageCap,
		petCount = count(data.pets),
		eggCount = count(data.eggs),
		daily = table.clone(data.daily),
		stats = table.clone(data.stats),
	}
end

return Inventory
