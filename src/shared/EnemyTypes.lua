-- EnemyTypes (ModuleScript) -> ReplicatedStorage.EnemyTypes
-- The names the enemy system spells out loud: type names, behavior module
-- names, state machine states, and the role groups the spawn director draws
-- from. Constants only, no data and no rules.
--
-- It is shared rather than server-only because the portrait builder and the
-- client effect handler both name enemy types, and a type name misspelled on
-- one side of the remote is a silent no-op rather than an error.
--
-- Behavior names are the brief's. They are live as of E2: EnemyController maps
-- a row's behavior field onto one module under Enemy/Behaviors, and the old
-- Patrol/Stalk/Guard/Pack/Ambush/Charge vocabulary is gone from the repo.

local function enum(...)
	local set = {}
	for _, name in ipairs({ ... }) do
		set[name] = name
	end
	return table.freeze(set)
end

local EnemyTypes = {}

-- The 19 of the roster. Every one of these is a row in EnemyDefinitions and a
-- visual recipe; the six the game already ships are the first six.
EnemyTypes.Name = enum(
	"Drifter",
	"Stalker",
	"Sentry",
	"Swarmer",
	"Lurker",
	"Charger",
	"Watcher",
	"Sprinter",
	"Brute",
	"Spitter",
	"Blinker",
	"Shrieker",
	"Mimic",
	"Warden",
	"Splitter",
	"Shadow",
	"Trapper",
	"Burrower",
	"Gatekeeper"
)

-- One module under Enemy/Behaviors per name, all of them over BaseBehavior.
-- Fewer than there are types: Drifter, Stalker and Sprinter all ride Chaser and
-- differ only by their definition row, which is the point of splitting stats
-- from behavior in the first place.
EnemyTypes.Behavior = enum(
	"Chaser",
	"Guard",
	"Swarmer",
	"Ambusher",
	"Charger",
	"Ranged",
	"Blinker",
	"Shrieker",
	"Mimic",
	"Splitter",
	"Shadow",
	"Trapper",
	"Burrower",
	"Warden"
)

-- Shared across every behavior. A behavior may ignore states it has no use for,
-- but it may not invent one: a state that exists in a single module is a rule
-- the controller, the debug labels and the client effects cannot see.
--
-- Frozen was added at E2 and is the only one of these that no behavior can
-- enter or leave. It belongs to the Freeze powerup, which stops every enemy in
-- the city at once, so the controller owns it above the state machine's own
-- transitions and a behavior cannot transition out of it.
--
-- The Charger is the one type using the attack triplet, and it is worth reading
-- as the worked example: AttackWindup is the flash the player is shown, Attack
-- is the locked straight line, Recover is eating the corner it missed. Alert and
-- Patrol are the two nobody drives yet; Patrol is where an idle wander belongs
-- and Chaser puts it there, Alert waits for a type with an aggro delay.
EnemyTypes.State = enum(
	"Idle",
	"Patrol",
	"Alert",
	"Chase",
	"AttackWindup",
	"Attack",
	"Recover",
	"Search",
	"Return",
	"Stunned",
	"Frozen",
	"Dead"
)

-- What the spawn director balances an encounter across. Which type sits in
-- which group is a property of the type, so it lives on the definition row
-- rather than in a list here.
EnemyTypes.Role = enum("Basic", "Fast", "Heavy", "Ambush", "Ranged", "Support", "Unusual", "Elite")

return table.freeze(EnemyTypes)
