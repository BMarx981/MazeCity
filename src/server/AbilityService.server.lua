-- AbilityService (Script) -> ServerScriptService
-- The active half of the shop: which abilities a player owns, which one the key
-- is currently pointed at, and the charge all of them spend. Was
-- WallWalkService, back when there was one thing to hold a key for.
--
-- **One charge, not one meter each.** The charge is a fraction between 0 and 1,
-- refilled at every LevelTrigger, and each ability spends it at its own rate:
-- a Hold drains 1/SecondsPerTier[tier] a second, a Cast takes
-- ChargeCostPerTier[tier] in one go. So owning three abilities is three ways to
-- spend one floor rather than three floors of resource, switching on an empty
-- bar buys nothing, and a tier makes its ability cheaper rather than handing out
-- a second meter. It is also one bar on the HUD instead of three.
--
-- **The service owns everything shared; a module owns only what it does.** The
-- charge, the selection, the refill, the grace, the remotes and the teardown on
-- death all live here, which is why Abilities/Cloak is thirty lines. The split
-- is EnemyController and a Behavior again, for the same reason: a module that
-- only meant to describe an effect cannot be asked to remember the respawn path.
--
-- **Tiers arrive as attributes, selection leaves as one.** SaveService stamps
-- AbilityTier_<Key> on the player when a purchase lands, the same channel
-- MagnetRange and BaseWalkSpeed already use, and this service stamps
-- SelectedAbility back. Both replicate, so AbilityGui draws the whole bar (which
-- abilities exist, which are owned, which is selected, at what tier) off
-- attributes and the remote carries only the charge and the events. A client
-- that joins late or respawns reads the attributes and is correct immediately,
-- with nothing to request and nothing to miss.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local Profiles = require(ServerScriptService:WaitForChild("PlayerProfiles"))

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

local remote = findOrCreate(ReplicatedStorage, "RemoteEvent", "AbilityUpdate")
local intents = findOrCreate(ReplicatedStorage, "RemoteEvent", "AbilityIntent")

-- ============================================================
-- The roster
-- ============================================================
-- Config.Abilities.Order is the list; a module of the same name under
-- Abilities/ is the implementation. A key missing either its Shop.Upgrades row
-- or its module is dropped from the roster with a warning rather than given
-- BaseAbility the way a behaviorless enemy is given BaseBehavior. The two cases
-- are not alike: a baseline enemy still chases, where a baseline ability is a
-- pedestal that takes a player's coins for a key that does nothing.
--
-- The pedestal is generated from the same list and is not dropped with it, so a
-- half-added ability is still for sale. That is a warning at server start
-- naming the key, and the first playtest finds it.

local folder = ServerScriptService:WaitForChild("Abilities")

local abilities = {}
local roster = {}

for _, key in ipairs(Config.Abilities.Order) do
	local def = Config.abilityDef(key)
	local module = folder:FindFirstChild(key)
	if not def then
		warn(string.format("AbilityService: %q is in Config.Abilities.Order with no Shop.Upgrades row", key))
	elseif not module then
		warn(string.format("AbilityService: %q has no module in ServerScriptService.Abilities", key))
	else
		abilities[key] = require(module)
		table.insert(roster, key)
	end
end

-- ============================================================
-- State
-- ============================================================
-- player -> { charge, active, char, graceUntil, floorKey, budget, budgetAt }
-- `char` is the character the active ability started on, held rather than read
-- back off the player so that stopping always undoes on the body it did
-- something to, even when that body has since been replaced.

local state = {}

local function entryFor(player)
	local entry = state[player]
	if not entry then
		entry = { charge = 1, active = nil, char = nil, graceUntil = 0, floorKey = nil, budget = 0, budgetAt = 0 }
		state[player] = entry
	end
	return entry
end

local function tierOf(player, key)
	return player:GetAttribute("AbilityTier_" .. key) or 0
end

local function perTier(list, tier)
	if not list or tier <= 0 then
		return nil
	end
	return list[math.min(tier, #list)]
end

-- Seconds of Hold a full charge buys at this tier, and the drain rate's
-- reciprocal. Zero means unowned or misconfigured, and is refused rather than
-- divided by.
--
-- Gear adds seconds to the one ability its effect is named for, as an addend on
-- top of the tier rather than a meter of its own: what a Phase Pack buys is a
-- slower drain on the charge every ability already shares. It is added after the
-- zero check on purpose, so it cannot conjure a Wall Walker for a player who
-- never bought one. A tier of zero is what makes a key selectable at all, so
-- gear that granted seconds without one would be seconds on a key the HUD does
-- not draw and the selection refuses to point at.
local function holdSeconds(player, key, def)
	local seconds = perTier(def.SecondsPerTier, tierOf(player, key)) or 0
	if seconds <= 0 then
		return 0
	end
	if key == Config.Accessories.WallWalkAbility then
		seconds = seconds + (player:GetAttribute(Config.Accessories.Attributes.WallWalkSeconds) or 0)
	end
	return seconds
end

local function push(player, event)
	local entry = state[player]
	if not entry then
		return
	end
	-- Only the charge and the events. Everything else the HUD draws is an
	-- attribute the client already has.
	remote:FireClient(player, {
		kind = "state",
		charge = entry.charge,
		active = entry.active,
		grace = entry.graceUntil > os.clock(),
		event = event,
	})
end

-- ============================================================
-- Selection
-- ============================================================
-- The profile stores the preference; the attribute publishes the resolution.
-- They differ whenever the stored key is not currently usable (never bought,
-- bought on a build that has since retired it, or its module failed to load), in
-- which case the first owned ability stands in without overwriting what the
-- player chose. Buying the missing one back therefore restores their choice.

local function ownedFirst(player)
	for _, key in ipairs(roster) do
		if tierOf(player, key) > 0 then
			return key
		end
	end
	return nil
end

local function usable(player, key)
	return key ~= nil and abilities[key] ~= nil and tierOf(player, key) > 0
end

local function resolveSelection(player)
	local data = Profiles.data(player)
	local chosen = data and data.selectedAbility
	if usable(player, chosen) then
		return chosen
	end
	return ownedFirst(player)
end

local stopActive

local function republishSelection(player)
	local selected = resolveSelection(player)
	if player:GetAttribute("SelectedAbility") == selected then
		return
	end
	-- Switching mid-phase ends the phase. It cannot carry: the Wall Walker's
	-- collision group and the Cloak's flag are undone by their own module, so
	-- leaving one running under another's name would strand whichever was live.
	stopActive(player, "stopped")
	player:SetAttribute("SelectedAbility", selected)
	push(player, { kind = "selected", ability = selected })
end

local function chooseAbility(player, key)
	if not usable(player, key) then
		push(player, { kind = "denied", ability = key })
		return
	end
	local data = Profiles.data(player)
	if data then
		data.selectedAbility = key
	end
	republishSelection(player)
end

-- ============================================================
-- Using one
-- ============================================================

function stopActive(player, reason)
	local entry = state[player]
	if not entry or not entry.active then
		return
	end

	local key = entry.active
	local char = entry.char
	entry.active = nil
	entry.char = nil
	entry.graceUntil = 0

	abilities[key].stop(player, char, reason or "stopped")
	push(player, { kind = reason or "stopped", ability = key })
end

local function useAbility(player)
	local entry = entryFor(player)
	if entry.active then
		return
	end

	local key = player:GetAttribute("SelectedAbility")
	local def = key and Config.abilityDef(key)
	local ability = key and abilities[key]
	local tier = key and tierOf(player, key) or 0
	if not def or not ability or tier <= 0 then
		return
	end

	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	if entry.charge <= Config.Abilities.MinimumToStart then
		push(player, { kind = "empty", ability = key })
		return
	end

	if def.Mode == "Cast" then
		local cost = perTier(def.ChargeCostPerTier, tier) or 1
		if entry.charge < cost then
			push(player, { kind = "empty", ability = key })
			return
		end
		local ok, payload = ability.cast(player, char, tier, def)
		if not ok then
			return
		end
		-- Spent after the cast rather than before it, so an ability that refuses
		-- itself costs nothing. Nothing in a cast yields, so there is no window
		-- between the two in which a second intent could see the old charge.
		entry.charge = math.max(0, entry.charge - cost)
		push(player, {
			kind = "cast",
			ability = key,
			seconds = payload and payload.seconds,
		})
		return
	end

	if holdSeconds(player, key, def) <= 0 then
		return
	end
	if not ability.start(player, char, tier, def) then
		return
	end

	entry.active = key
	entry.char = char
	push(player, { kind = "started", ability = key })
end

-- ============================================================
-- The charge
-- ============================================================

local function refill(player, reason)
	local entry = entryFor(player)
	entry.charge = 1
	push(player, { kind = reason or "refilled" })
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	local pushDue = false
	accumulator = accumulator + dt
	if accumulator >= Config.Abilities.PushSeconds then
		accumulator = 0
		pushDue = true
	end

	for player, entry in pairs(state) do
		if not player.Parent then
			state[player] = nil
		elseif entry.active then
			local key = entry.active
			local def = Config.abilityDef(key)
			local seconds = def and holdSeconds(player, key, def) or 0
			local char = entry.char
			local humanoid = char and char.Parent and char:FindFirstChildOfClass("Humanoid")

			if not humanoid or humanoid.Health <= 0 or seconds <= 0 then
				-- A body that died between two ticks, or a tier that went to zero
				-- under a running phase. Neither is a state to keep draining in.
				stopActive(player, "stopped")
			else
				if entry.charge > 0 then
					entry.charge = math.max(0, entry.charge - dt / seconds)
					if entry.charge <= 0 then
						-- Empty is where the grace starts, not where the ability stops.
						entry.graceUntil = now + Config.Abilities.GraceSeconds
					end
				elseif not abilities[key].blocked(player, char) or now >= entry.graceUntil then
					stopActive(player, "empty")
				end

				if pushDue and entry.active then
					push(player)
				end
			end
		end
	end
end)

-- ============================================================
-- Intents
-- ============================================================
-- Three kinds, and a budget rather than a correctness measure: use while
-- something is running is ignored, release while nothing is is a no-op, and
-- select is validated against what the player owns. The cap exists because a
-- held key is two messages and a player mashing the selector is cheap to make
-- expensive; every intent is idempotent or refused, so dropping the extras
-- costs nothing but the mashing.

local function withinBudget(player)
	local entry = entryFor(player)
	local now = os.clock()
	local elapsed = now - entry.budgetAt
	entry.budgetAt = now
	entry.budget =
		math.min(Config.Abilities.IntentsPerSecond, entry.budget + elapsed * Config.Abilities.IntentsPerSecond)
	if entry.budget < 1 then
		return false
	end
	entry.budget = entry.budget - 1
	return true
end

intents.OnServerEvent:Connect(function(player, payload)
	if type(payload) ~= "table" or not withinBudget(player) then
		return
	end

	if payload.kind == "use" then
		useAbility(player)
	elseif payload.kind == "release" then
		local entry = state[player]
		if entry and entry.active then
			-- Letting go owes the ability the same clearance check an empty charge
			-- gets: for the Wall Walker, releasing inside a wall is how a player gets
			-- stuck in geometry. Draining to zero puts it on the grace path rather
			-- than stopping it here.
			if abilities[entry.active].blocked(player, entry.char) then
				entry.charge = 0
				entry.graceUntil = os.clock() + Config.Abilities.GraceSeconds
			else
				stopActive(player, "stopped")
			end
		end
	elseif payload.kind == "select" then
		chooseAbility(player, payload.ability)
	end
end)

-- ============================================================
-- Floors
-- ============================================================
-- The charge refills on arriving at a floor, which is what makes a tier a budget
-- per floor rather than per life. Bound here rather than read off MazeProgress
-- because that fires on a floor cleared, and the first floor of a tower is
-- entered without one having been cleared.

local function bindLevelTrigger(part)
	if not part:IsA("BasePart") then
		return
	end
	part.Touched:Connect(function(hit)
		if not Config.Abilities.RefillOnFloor then
			return
		end
		local char = hit:FindFirstAncestorOfClass("Model")
		local player = char and Players:GetPlayerFromCharacter(char)
		if not player then
			return
		end
		local key = string.format(
			"%s:%s:%s",
			tostring(part:GetAttribute("Section")),
			tostring(part:GetAttribute("Building")),
			tostring(part:GetAttribute("Level"))
		)
		local entry = entryFor(player)
		if entry.floorKey ~= key then
			entry.floorKey = key
			refill(player)
		end
	end)
end

for _, part in ipairs(CollectionService:GetTagged("LevelTrigger")) do
	bindLevelTrigger(part)
end
CollectionService:GetInstanceAddedSignal("LevelTrigger"):Connect(bindLevelTrigger)

-- ============================================================
-- Lifecycle
-- ============================================================

local function bindPlayer(player)
	entryFor(player)

	-- One connection per ability rather than one for all of them, because
	-- GetAttributeChangedSignal is per name. A purchase changes exactly one, and
	-- the work either way is republishing a selection that usually has not moved.
	for _, key in ipairs(roster) do
		player:GetAttributeChangedSignal("AbilityTier_" .. key):Connect(function()
			republishSelection(player)
			-- A tier bought mid-floor does not top the charge up. What it buys is a
			-- lower drain rate, which the tick reads on its next pass, so the bar the
			-- player is looking at simply starts falling more slowly.
			push(player, { kind = "tier", ability = key })
		end)
	end

	player.CharacterRemoving:Connect(function()
		-- Before the body leaves, so the module undoes on the character it acted on
		-- rather than on nothing. The collision group and the highlight go with the
		-- corpse either way; the WalkSpeedResolver factor is keyed by character and
		-- goes with it too. What this buys is the module never seeing a half-gone
		-- character, which is where a stray attribute write would land.
		stopActive(player, "stopped")
	end)

	player.CharacterAdded:Connect(function()
		local entry = entryFor(player)
		entry.floorKey = nil
		-- Respawning full is deliberate, and it is the same call SprintService
		-- makes: a death already costs the floor, and arriving back at the restart
		-- with an empty bar would charge for it twice. The wait is for the
		-- LevelTrigger touch that a respawn lands on, so the refill is not
		-- immediately followed by the floor's own.
		task.wait(0.2)
		refill(player, "respawn")
	end)

	republishSelection(player)
	push(player)
end

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end
Players.PlayerAdded:Connect(bindPlayer)

Players.PlayerRemoving:Connect(function(player)
	stopActive(player, "stopped")
	state[player] = nil
end)

-- The stored selection arrives with the profile, which lands after the join, so
-- the attribute has to be republished rather than sampled once at bind time.
Profiles.onReady(function(player)
	republishSelection(player)
	push(player)
end)
