# Pet & Egg Data Model Spec

Maze climber pet system. Two layers: **static config** (game design data, lives in ReplicatedStorage, safe to hot-swap between updates) and **player data** (persisted per player via ProfileService or your DataStore wrapper).

Core principle: player data stores references (ids) and mutable state only. Names, models, rates, and abilities live in config so you can rebalance without migrating saves.

> Paths and extensions in this document are generic, written before the repo was read. They do not all hold here: this project uses `.lua`, `src/shared` maps directly onto ReplicatedStorage with no `Shared` folder, and coins already live in `leaderstats`. Where this spec and `PETS_PLAN.md`'s "Repo reconciliation" section disagree, the plan wins. Read that section before writing any of the code below.

---

## 1. Shared Types

`src/shared/Types.luau`

```luau
export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"

export type AbilityType =
	"Glow"
	| "DeadEndPing"
	| "CoinMagnet"
	| "CheckpointSave"
	| "SpeedBoost"
	| "HatchBoost"

export type Ability = {
	type: AbilityType,
	params: { [string]: number },
}

export type EvolutionStage = {
	level: number,
	modelId: string,
	displaySuffix: string?,
	abilityMultiplier: number,
}

export type PetConfig = {
	id: string,
	name: string,
	rarity: Rarity,
	baseModelId: string,
	ability: Ability,
	evolutions: { EvolutionStage },
	maxLevel: number,
	xpCurve: { base: number, growth: number },
}

export type HatchEntry = {
	petId: string,
	weight: number,
}

export type EggConfig = {
	id: string,
	name: string,
	modelId: string,
	mazesRequired: number,
	hatchTable: { HatchEntry },
	source: "Climb" | "Premium" | "Event" | "Streak",
	robuxCost: number?,
	coinCost: number?,
	availableUntil: number?,
}

export type PetInstance = {
	uid: string,
	petId: string,
	level: number,
	xp: number,
	stage: number,
	locked: boolean,
	nickname: string?,
	acquiredAt: number,
	sourceEggId: string?,
}

export type EggInstance = {
	uid: string,
	eggId: string,
	acquiredAt: number,
}

export type IncubatorState = {
	eggUid: string,
	mazesCompleted: number,
	placedAt: number,
}

export type DailyState = {
	lastClaimDayUtc: number,
	streak: number,
}

export type PlayerData = {
	schemaVersion: number,
	coins: number,
	pets: { [string]: PetInstance },
	eggs: { [string]: EggInstance },
	equipped: { string },
	maxEquipped: number,
	petStorageCap: number,
	eggStorageCap: number,
	incubator: IncubatorState?,
	daily: DailyState,
	stats: {
		mazesCompleted: number,
		summitsReached: number,
		eggsHatched: number,
	},
	gamepasses: { [string]: boolean },
}

return nil
```

Notes:
- `uid` is a per-instance GUID (`HttpService:GenerateGUID(false)`). `petId`/`eggId` reference config. Two players can own the same `petId` but every instance has a unique `uid`, which is what makes future trading possible.
- `stage` indexes into `evolutions`. Stage 0 = base form.
- `locked` prevents accidental deletion, standard for pet sims and cheap to add now.
- `hatchTable` weights are relative, not percentages. Add entries without renormalizing.
- `availableUntil` (unix time) handles seasonal eggs declaratively.
- `lastClaimDayUtc` stores the UTC day number (`math.floor(os.time() / 86400)`), which makes streak math trivial and timezone-proof.

---

## 2. Config Examples

`src/shared/Config/Pets.luau`

```luau
local Types = require(script.Parent.Parent.Types)

local Pets: { [string]: Types.PetConfig } = {
	firefly = {
		id = "firefly",
		name = "Firefly",
		rarity = "Common",
		baseModelId = "rbxassetid://0",
		ability = { type = "Glow", params = { radius = 12 } },
		evolutions = {
			{ level = 10, modelId = "rbxassetid://0", displaySuffix = "Radiant", abilityMultiplier = 1.5 },
			{ level = 25, modelId = "rbxassetid://0", displaySuffix = "Solar", abilityMultiplier = 2.5 },
		},
		maxLevel = 50,
		xpCurve = { base = 100, growth = 1.15 },
	},
	compass_crow = {
		id = "compass_crow",
		name = "Compass Crow",
		rarity = "Epic",
		baseModelId = "rbxassetid://0",
		ability = { type = "DeadEndPing", params = { cooldown = 30, range = 40 } },
		evolutions = {
			{ level = 15, modelId = "rbxassetid://0", displaySuffix = "Wayfinder", abilityMultiplier = 1.4 },
		},
		maxLevel = 50,
		xpCurve = { base = 150, growth = 1.18 },
	},
}

return Pets
```

`src/shared/Config/Eggs.luau`

```luau
local Types = require(script.Parent.Parent.Types)

local Eggs: { [string]: Types.EggConfig } = {
	summit_common = {
		id = "summit_common",
		name = "Summit Egg",
		modelId = "rbxassetid://0",
		mazesRequired = 2,
		source = "Climb",
		coinCost = 250,
		hatchTable = {
			{ petId = "firefly", weight = 60 },
			{ petId = "compass_crow", weight = 5 },
		},
	},
	summit_royal = {
		id = "summit_royal",
		name = "Royal Summit Egg",
		modelId = "rbxassetid://0",
		mazesRequired = 8,
		source = "Climb",
		coinCost = 2500,
		hatchTable = {
			{ petId = "compass_crow", weight = 30 },
		},
	},
}

return Eggs
```

---

## 3. Default Player Data

`src/server/Data/DefaultData.luau`

```luau
local Types = require(game.ReplicatedStorage.Shared.Types)

local DefaultData: Types.PlayerData = {
	schemaVersion = 1,
	coins = 0,
	pets = {},
	eggs = {},
	equipped = {},
	maxEquipped = 1,
	petStorageCap = 25,
	eggStorageCap = 5,
	incubator = nil,
	daily = { lastClaimDayUtc = 0, streak = 0 },
	stats = { mazesCompleted = 0, summitsReached = 0, eggsHatched = 0 },
	gamepasses = {},
}

return DefaultData
```

`schemaVersion` plus a migration table on profile load is your insurance policy. When you change the shape later, write `migrations[1] = function(data) ... end` and never touch old saves by hand.

---

## 4. Key State Transitions (server authoritative)

All mutations happen on the server. Client fires intents via remotes, server validates against config and current data.

**PlaceEgg(eggUid)**
- Reject if `incubator ~= nil`, egg not owned, or player not at summit zone.
- Set `incubator = { eggUid = eggUid, mazesCompleted = 0, placedAt = os.time() }`.

**OnMazeCompleted()**
- Increment `stats.mazesCompleted`.
- If incubator active, increment `mazesCompleted` (apply HatchBoost multipliers here).
- If `mazesCompleted >= EggConfig.mazesRequired`, resolve hatch.

**ResolveHatch()**
- Weighted roll over `hatchTable` (single `math.random` against total weight, server side only).
- Reject if pet storage full (prompt cap upgrade, this is a monetization moment).
- Create `PetInstance`, remove `EggInstance`, clear incubator, increment `eggsHatched`, broadcast rarity announcement if Epic+.

**ClaimDaily()**
- `today = math.floor(os.time() / 86400)`. Reject if `today == lastClaimDayUtc`.
- `streak = (today - lastClaimDayUtc == 1) and streak + 1 or 1`.
- Grant pet XP/food scaled by streak. Day 7: grant streak-exclusive `EggInstance`.

**EquipPet(petUid) / UnequipPet(petUid)**
- Enforce `#equipped <= maxEquipped`. `maxEquipped` raised by the multi-equip gamepass, checked against `gamepasses` on join and on purchase receipt.

---

## 5. What deliberately isn't here yet

- **Trading**: the `uid` design supports it, but trading needs escrow, logging, and dupe protection. Separate spec when you get there.
- **Pet food/consumables inventory**: fold into a generic `items: { [itemId]: number }` map when daily rewards need more than raw XP.
- **Client replication shape**: replicate a read-only projection of PlayerData, never the raw profile table.
