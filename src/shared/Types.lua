-- Types (ModuleScript) -> ReplicatedStorage.Types
-- The pet and egg data model, as exported Luau types. Nothing here runs: the
-- module returns an empty table and exists so PetCatalog, EggCatalog,
-- PlayerProfiles and the services can annotate against one shared shape.
--
-- Reconciled against docs/PET_EGG_DATA_SPEC.md section 1, which was written
-- provider-neutral. Two deliberate departures, both recorded in
-- docs/PETS_PLAN.md:
--
--  1. PlayerData has no `coins`. Coins are leaderstats.Coins and are stored in
--     exactly one place; a second copy here is the bug the spec's shape invites.
--  2. `baseModelId`/`modelId` become `model`, a child name under
--     ServerStorage/Pets rather than an rbxassetid. This project loads rigs the
--     way EnemyService already does, so an asset id would be a field nothing
--     reads. `placeholder` is what gets drawn until an artist puts a rig there.

local Types = {}

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"

export type AbilityType = "Glow" | "DeadEndPing" | "CoinMagnet" | "CheckpointSave" | "SpeedBoost" | "HatchBoost"

export type Ability = {
	type: AbilityType,
	params: { [string]: number },
}

-- What the placeholder rig looks like until ServerStorage/Pets/<model> exists.
-- Every pet still reads as its own creature from across a corridor, which is
-- what keeps the system testable with zero Studio-side setup.
export type Placeholder = {
	color: Color3,
	shape: "Ball" | "Block",
	size: number,
}

export type EvolutionStage = {
	level: number,
	model: string,
	displaySuffix: string?,
	abilityMultiplier: number,
	placeholder: Placeholder?,
}

export type PetConfig = {
	id: string,
	name: string,
	rarity: Rarity,
	model: string,
	placeholder: Placeholder,
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
	color: Color3,
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

-- `eggId` is here and not in the spec's version. Placing an egg takes the
-- EggInstance out of the eggs map, so it exists in exactly one place and cannot
-- be placed twice; the config key has to come with it or the incubator is a
-- reference to something that no longer exists.
export type IncubatorState = {
	eggUid: string,
	eggId: string,
	mazesCompleted: number,
	placedAt: number,
}

export type DailyState = {
	lastClaimDayUtc: number,
	streak: number,
}

export type PlayerStats = {
	mazesCompleted: number,
	floorsCleared: number,
	summitsReached: number,
	eggsHatched: number,
}

-- The saved profile, whole. `upgrades` and `furthestSection` predate the pet
-- system and are listed here because there is one profile, not two.
export type PlayerData = {
	schemaVersion: number,
	upgrades: { [string]: number },
	furthestSection: number,
	pets: { [string]: PetInstance },
	eggs: { [string]: EggInstance },
	equipped: { string },
	maxEquipped: number,
	petStorageCap: number,
	eggStorageCap: number,
	incubator: IncubatorState?,
	daily: DailyState,
	stats: PlayerStats,
	gamepasses: { [string]: boolean },
	starterGranted: boolean,
}

return Types
