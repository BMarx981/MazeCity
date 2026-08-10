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

-- The recipe PetModelGenerator builds a rig from. Every field is optional: the
-- generator's DEFAULT_LOOK is the baseline, a pet merges over it, and a stage
-- merges over the pet. Sizes are a number for a sphere or a Vector3 for an
-- ellipsoid, and every part takes its colour from primary (body), secondary
-- (soft parts) or accent (the one neon group, which is always the ability made
-- visible).
export type SymmetricGroup = {
	size: number | Vector3,
	spread: number,
	height: number,
	z: number?,
	tilt: number?,
	sweep: number?,
	pitch: number?,
	forward: number?,
	color: Color3?,
}

export type RingGroup = {
	count: number,
	radius: number,
	size: number | Vector3,
	height: number,
	z: number?,
	tilt: number?,
	color: Color3?,
}

export type Charm = {
	size: number | Vector3,
	offset: Vector3,
	color: Color3?,
}

export type PetLook = {
	scale: number?,
	primary: Color3?,
	secondary: Color3?,
	accent: Color3?,
	body: (number | Vector3)?,
	belly: { size: number | Vector3, offset: Vector3? }?,
	head: (number | Vector3)?,
	headOffset: Vector3?,
	eyeCount: number?,
	eyeSize: number?,
	eyeSpread: number?,
	eyeHeight: number?,
	eyeDepth: number?,
	pupilSize: number?,
	ears: SymmetricGroup?,
	wings: SymmetricGroup?,
	antennae: SymmetricGroup?,
	beak: { size: number | Vector3, height: number?, forward: number?, tilt: number?, color: Color3? }?,
	muzzle: { size: number | Vector3, height: number?, forward: number?, tilt: number?, color: Color3? }?,
	tail: { size: number | Vector3, offset: Vector3?, tilt: number?, color: Color3? }?,
	crest: { size: number | Vector3, height: number?, z: number?, color: Color3? }?,
	collar: RingGroup?,
	halo: RingGroup?,
	motes: RingGroup?,
	charms: { Charm }?,
}

export type EvolutionStage = {
	level: number,
	model: string,
	displaySuffix: string?,
	abilityMultiplier: number,
	placeholder: Placeholder?,
	look: PetLook?,
}

export type PetConfig = {
	id: string,
	name: string,
	rarity: Rarity,
	model: string,
	placeholder: Placeholder,
	look: PetLook?,
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

-- ============================================================
-- Accessories
-- ============================================================
-- Gear worn by a pet. Catalogued in ReplicatedStorage.AccessoryCatalog, capped
-- and priced by Config.Accessories, resolved into one totals table by
-- PetInventory.wornEffects. See docs/PET_ACCESSORIES_PLAN.md.

export type AccessorySlot = "Head" | "Neck" | "Back" | "Aura"

-- Every effect names exactly one integration site. An effect with no site is
-- not in this list, and an effect with two sites is two effects.
export type AccessoryEffectType =
	"WalkSpeed"
	| "PickupRadius"
	| "CoinMultiplier"
	| "GlowRange"
	| "WallWalkSeconds"
	| "PetXp"
	| "HatchProgress"
	| "RouteVision"
	| "PhantomSense"
	| "ScoreBonus"
	| "Armor"

export type AccessoryEffect = {
	type: AccessoryEffectType,
	value: number,
}

-- Not the pet Placeholder: gear is worn, so proportion is the whole of whether
-- a cape reads as a cape, and a size scalar cannot say that. `rate` is read
-- only when shape is "Particle", which is what the Aura slot is made of.
export type AccessoryPlaceholder = {
	color: Color3,
	shape: "Ball" | "Block" | "Cylinder" | "Particle",
	size: Vector3,
	rate: number?,
}

export type AccessoryConfig = {
	id: string,
	name: string,
	slot: AccessorySlot,
	rarity: Rarity,
	model: string,
	placeholder: AccessoryPlaceholder,
	effects: { AccessoryEffect },
	coinCost: number?,
	availableUntil: number?,
}

export type AccessoryInstance = {
	uid: string,
	accessoryId: string,
	locked: boolean,
	acquiredAt: number,
}

-- `worn` maps a slot to an accessory uid, and the accessory stays in
-- PlayerData.accessories while it is worn. That is the opposite of the
-- egg-into-the-incubator move and for the opposite reason: an egg had to exist
-- in exactly one place so it could not be placed twice, where gear has to stay
-- listed so the UI can show it as worn by a named pet. What replaces the
-- structural guarantee is Inventory.wearerOf, which every mutation calls.
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
	-- Optional, and it has to be: a pet hatched before gear existed is a row in a
	-- saved profile with no such field, and `adopt` merges the pets map whole
	-- rather than per pet. Every reader treats absent as empty.
	worn: { [AccessorySlot]: string }?,
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
	accessories: { [string]: AccessoryInstance },
	equipped: { string },
	maxEquipped: number,
	petStorageCap: number,
	eggStorageCap: number,
	accessoryStorageCap: number,
	incubator: IncubatorState?,
	daily: DailyState,
	stats: PlayerStats,
	gamepasses: { [string]: boolean },
	starterGranted: boolean,
}

return Types
