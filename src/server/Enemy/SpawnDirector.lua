-- SpawnDirector (ModuleScript) -> ServerScriptService.Enemy.SpawnDirector
-- Decides what a floor is populated with, inside a budget. Landed at E5, and it
-- reinterprets what an EnemySpawn marker is: a marker used to be one enemy of
-- the building's style type, and is now only a position. The group of markers
-- sharing (Section, Building, Level) shares Config.Enemies.FloorBudget, and one
-- roll spends it across them. A runtime change only: no marker moves and no
-- part count changes.
--
-- The roll's rules, all of them Config.Enemies.Director knobs except the two
-- the brief fixes at one. The roster is the building's own style type (the
-- anchor, weighted up and exempt from its role gate, because an Ember tower
-- promising Chargers from floor 1 is the game as it already was) plus every
-- spawnable row whose role has unlocked by that floor. At most one enemy per
-- floor is disruptive or elite; a Support type needs a Basic one already in
-- the group; Elites are capped per building across all of its floors, which is
-- where the Warden's rarity is enforced, rarity being a property of what a
-- floor may contain rather than of the type. Config.SectionEnemyOverride is a
-- hard filter: an overridden section's roster is that one type, every other
-- rule waived, because the knob is a sledgehammer for playtests and a
-- district of Wardens that rolled empty floors instead would be the knob not
-- working.
--
-- An assignment is per visit, not per server. It is rolled the first time any
-- of the group's markers needs a type, held while any of the group's rigs is
-- alive (so a death respawns the same enemy the budget already paid for), and
-- dropped when the last rig despawns because everyone walked away. The next
-- visit rolls fresh, which is the variety the budget exists to buy.
--
-- Its randomness is runtime randomness, deliberately not drawn from the world
-- seed, for the same reason PickupService rolls its powerups on touch: a floor
-- that presents the same six enemies to every player on every server is a
-- floor that gets memorised once and never read again.
--
-- Respawn timing stayed in EnemyService, whose comment claims it. This module
-- owns what a marker holds; how long a dead one stays empty is the scan's
-- bookkeeping, and the assignment surviving the delay is what makes the two
-- compose: the same type comes back.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local EnemyDefinitions = require(ReplicatedStorage:WaitForChild("EnemyDefinitions"))
local EnemyTypes = require(ReplicatedStorage:WaitForChild("EnemyTypes"))

local EnemyRegistry = require(script.Parent:WaitForChild("EnemyRegistry"))

local SpawnDirector = {}

local rng = Random.new()

-- key -> { markers = set, count, section, building, level, anchor }
local groups = {}
-- marker -> key
local groupOf = {}
-- key -> { [marker] = typeName | false }. false is a marker the roll left
-- empty on purpose, which is an answer and not an absence: the scan must not
-- treat it as something still waiting to spawn.
local assignments = {}

local function disruptiveSet()
	local set = {}
	for _, name in ipairs(Config.Enemies.Director.Disruptive) do
		set[name] = true
	end
	return set
end

-- ============================================================
-- Markers and groups
-- ============================================================

function SpawnDirector.groupKeyOf(marker)
	return string.format(
		"%d:%d:%d",
		marker:GetAttribute("Section") or 1,
		marker:GetAttribute("Building") or 0,
		marker:GetAttribute("Level") or 0
	)
end

local function track(marker)
	if not marker:IsA("BasePart") or groupOf[marker] then
		return
	end
	local key = SpawnDirector.groupKeyOf(marker)
	groupOf[marker] = key
	local group = groups[key]
	if not group then
		group = {
			markers = {},
			count = 0,
			section = marker:GetAttribute("Section") or 1,
			building = marker:GetAttribute("Building") or 0,
			level = marker:GetAttribute("Level") or 0,
			anchor = marker:GetAttribute("EnemyType"),
		}
		groups[key] = group
	end
	group.markers[marker] = true
	group.count = group.count + 1
end

local function untrack(marker)
	local key = groupOf[marker]
	if not key then
		return
	end
	groupOf[marker] = nil
	local group = groups[key]
	if not group then
		return
	end
	if group.markers[marker] then
		group.markers[marker] = nil
		group.count = group.count - 1
	end
	local assignment = assignments[key]
	if assignment then
		assignment[marker] = nil
	end
	if group.count <= 0 then
		groups[key] = nil
		assignments[key] = nil
	end
end

for _, marker in ipairs(CollectionService:GetTagged("EnemySpawn")) do
	track(marker)
end
CollectionService:GetInstanceAddedSignal("EnemySpawn"):Connect(track)
CollectionService:GetInstanceRemovedSignal("EnemySpawn"):Connect(untrack)

-- ============================================================
-- Budget and roster
-- ============================================================

function SpawnDirector.budgetFor(level)
	local floorBudget = Config.Enemies.FloorBudget
	local budget = math.min(floorBudget.Base + (level or 0) * floorBudget.PerLevel, floorBudget.Max)
	return budget * (Config.Enemies.Difficulty.BudgetMultiplier or 1)
end

-- The types a floor may draw from, as { row, weight } entries, plus whether an
-- override made it a hard filter. anchorType may be nil (a debug wave has no
-- building), in which case everything stands on its role gate alone.
function SpawnDirector.rosterFor(anchorType, level, sectionIndex)
	local override = sectionIndex and Config.SectionEnemyOverride[sectionIndex]
	if override then
		-- get() warns and falls back on a typo, so a misspelt override is
		-- Drifters that said so, same as it was before the director. spawnable
		-- is deliberately not checked here: it keeps the roll from picking a
		-- type, and an override is not a pick.
		return { { row = EnemyDefinitions.get(override), weight = 1 } }, true
	end

	local director = Config.Enemies.Director
	local roster = {}
	for name, row in pairs(EnemyDefinitions.types) do
		if row.spawnable ~= false then
			if name == anchorType then
				table.insert(roster, { row = row, weight = director.AnchorWeight })
			else
				local gate = director.RoleMinLevel[row.role]
				if gate and (level or 0) >= gate then
					table.insert(roster, { row = row, weight = 1 })
				end
			end
		end
	end
	return roster, false
end

-- ============================================================
-- The roll
-- ============================================================

-- Spends budget across at most `slots` picks from the roster and returns the
-- list of type names. eliteAllowance is how many Elite-role picks this roll may
-- still make; the per-building arithmetic is the caller's.
--
-- opts.unruly waives the diversity rules (an override district plays by its
-- own), never the budget. The one guarantee either way: a non-empty roster
-- never rolls an empty floor. Unreachable outside an override, because the
-- anchor always costs less than FloorBudget.Base, and worth having inside one:
-- a Warden district's floor 1 holds one Warden rather than nothing.
function SpawnDirector.roll(roster, budget, slots, eliteAllowance, opts)
	local unruly = opts and opts.unruly
	local disruptive = disruptiveSet()
	local remaining = budget
	local eliteRemaining = eliteAllowance or 0
	local disruptiveUsed = false
	local basics = 0
	local picks = {}

	for _ = 1, slots do
		local candidates = {}
		local totalWeight = 0
		for _, entry in ipairs(roster) do
			local row = entry.row
			local cost = row.spawnCost or 1
			local isElite = row.role == EnemyTypes.Role.Elite
			local isDisruptive = isElite or disruptive[row.name]
			local ok = cost <= remaining
			if ok and not unruly then
				local supportBlocked = row.role == EnemyTypes.Role.Support
					and Config.Enemies.Director.SupportNeedsBasic
					and basics == 0
				ok = not (isDisruptive and disruptiveUsed)
					and not (isElite and eliteRemaining <= 0)
					and not supportBlocked
			end
			if ok then
				table.insert(candidates, entry)
				totalWeight = totalWeight + entry.weight
			end
		end

		if #candidates > 0 then
			local ticket = rng:NextNumber(0, totalWeight)
			local chosen = candidates[#candidates]
			for _, entry in ipairs(candidates) do
				ticket = ticket - entry.weight
				if ticket <= 0 then
					chosen = entry
					break
				end
			end

			local row = chosen.row
			table.insert(picks, row.name)
			remaining = remaining - (row.spawnCost or 1)
			if row.role == EnemyTypes.Role.Elite then
				eliteRemaining = eliteRemaining - 1
				disruptiveUsed = true
			elseif disruptive[row.name] then
				disruptiveUsed = true
			end
			if row.role == EnemyTypes.Role.Basic then
				basics = basics + 1
			end
		end
	end

	if #picks == 0 and #roster > 0 and slots > 0 then
		local cheapest = roster[1]
		for _, entry in ipairs(roster) do
			if (entry.row.spawnCost or 1) < (cheapest.row.spawnCost or 1) then
				cheapest = entry
			end
		end
		table.insert(picks, cheapest.row.name)
	end

	return picks
end

-- Elite picks already standing in this building's other assignments. Bounded by
-- ten groups of three per building, and assignments only exist for floors
-- somebody has visited and not yet left.
local function elitesAssigned(section, building, exceptKey)
	local count = 0
	for key, assignment in pairs(assignments) do
		local group = groups[key]
		if group and key ~= exceptKey and group.section == section and group.building == building then
			for _, typeName in pairs(assignment) do
				local row = typeName and EnemyDefinitions.types[typeName]
				if row and row.role == EnemyTypes.Role.Elite then
					count = count + 1
				end
			end
		end
	end
	return count
end

local function rollGroup(key)
	local group = groups[key]
	local assignment = {}
	if not group or group.count == 0 then
		return assignment
	end

	local members = {}
	for marker in pairs(group.markers) do
		table.insert(members, marker)
	end
	for i = #members, 2, -1 do
		local j = rng:NextInteger(1, i)
		members[i], members[j] = members[j], members[i]
	end

	local roster, unruly = SpawnDirector.rosterFor(group.anchor, group.level, group.section)
	local allowance =
		math.max(0, Config.Enemies.Director.ElitePerBuilding - elitesAssigned(group.section, group.building, key))
	local picks =
		SpawnDirector.roll(roster, SpawnDirector.budgetFor(group.level), #members, allowance, { unruly = unruly })

	for index, marker in ipairs(members) do
		assignment[marker] = picks[index] or false
	end
	return assignment
end

-- ============================================================
-- What the scan asks
-- ============================================================

-- The type this marker holds right now, or nil for "nothing": the roll left it
-- empty, or its group is gone. Rolls the whole group on first ask.
function SpawnDirector.typeFor(marker)
	local key = groupOf[marker]
	if not key then
		track(marker)
		key = groupOf[marker]
		if not key then
			return nil
		end
	end
	local assignment = assignments[key]
	if not assignment then
		assignment = rollGroup(key)
		assignments[key] = assignment
	end
	return assignment[marker] or nil
end

-- Called by the scan when a rig despawns because everyone walked away, and
-- deliberately not when one dies: a death's marker keeps its type through the
-- respawn delay. When the last live rig of the group is gone, the visit is
-- over and the assignment goes with it.
function SpawnDirector.noteDespawned(marker)
	local key = groupOf[marker]
	local group = key and groups[key]
	if not group then
		return
	end
	for member in pairs(group.markers) do
		if EnemyRegistry.get(member) then
			return
		end
	end
	assignments[key] = nil
end

-- A debug wave: the whole unlocked roster at the given level (default: all of
-- it), no anchor, no building. The elite allowance is the per-building cap,
-- there being no building to count against.
function SpawnDirector.rollWave(budget, level)
	local roster = SpawnDirector.rosterFor(nil, level or 9, nil)
	local slots = math.max(1, math.ceil(budget))
	return SpawnDirector.roll(roster, budget, slots, Config.Enemies.Director.ElitePerBuilding)
end

return SpawnDirector
