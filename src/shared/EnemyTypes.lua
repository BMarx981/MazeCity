-- EnemyTypes (ModuleScript) -> ReplicatedStorage.EnemyTypes
-- The names the enemy system spells out loud: type names, behavior module
-- names, state machine states, and the role groups the spawn director draws
-- from. Constants only, no data and no rules.
--
-- It is shared rather than server-only because the portrait builder and the
-- client effect handler both name enemy types, and a type name misspelled on
-- one side of the remote is a silent no-op rather than an error.
--
-- Behavior names are the brief's, not the ones the live EnemyService uses. The
-- old service reads profile.behavior with the values Patrol/Stalk/Guard/Pack/
-- Ambush/Charge; the mapping onto these is Patrol and Stalk to Chaser, Pack to
-- Swarmer, Ambush to Ambusher, Charge to Charger, and Guard to Guard. Guard is
-- the trap: it is the one name that means the same thing in both vocabularies,
-- so a half-migrated read of profile.behavior against this table looks correct
-- for exactly one type. Nothing reads these until E2 retires the old field.

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
EnemyTypes.State =
	enum("Idle", "Patrol", "Alert", "Chase", "AttackWindup", "Attack", "Recover", "Search", "Return", "Stunned", "Dead")

-- What the spawn director balances an encounter across. Which type sits in
-- which group is a property of the type, so it lives on the definition row
-- rather than in a list here.
EnemyTypes.Role = enum("Basic", "Fast", "Heavy", "Ambush", "Ranged", "Support", "Unusual", "Elite")

return table.freeze(EnemyTypes)
