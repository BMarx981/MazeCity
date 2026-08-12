-- TowerTimerService (Script) -> ServerScriptService
-- Floor timing, scoring, death respawn, and tower completion.
--
-- The timer counts up. Config.getParTime is a target worth points, not a
-- deadline: a slow floor costs score and nothing else. Dying is the only
-- failure, and it costs only the current floor's elapsed time.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))

local remote = ReplicatedStorage:FindFirstChild("TimerUpdate")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "TimerUpdate"
	remote.Parent = ReplicatedStorage
end

-- The only thing in this file that talks to another server script, and the
-- project's first server-to-server channel. It exists because the pet system
-- needs to know when a maze was finished and this is the one place that already
-- knows: re-binding RoofTrigger somewhere else would duplicate the poll that
-- exists precisely because a touch can miss.
--
-- Same shape as the RemoteEvents: one table, discriminated by `kind`. Both kinds
-- are fired unconditionally, so which of them counts as "a maze" is a config
-- choice on the listening side rather than a decision baked in here.
--
-- FindFirstChild-or-create on both ends, not WaitForChild: scripts in
-- ServerScriptService start in arbitrary order, and a listener that ran first
-- would wait forever on something it is allowed to make itself.
local progress = ServerScriptService:FindFirstChild("MazeProgress")
if not progress then
	progress = Instance.new("BindableEvent")
	progress.Name = "MazeProgress"
	progress.Parent = ServerScriptService
end

local state = {}
-- Set on Died, consumed by the next CharacterAdded. Kept outside state because
-- a player can die with no floor of their own: on a roof, or on the street.
local pendingRespawn = {}
-- Last tower entered, so a death outside a floor still lands in the right
-- district instead of at the enabled section 1 spawns.
local home = {}

local function keyFor(trigger)
	return string.format(
		"%s:%s:%s",
		tostring(trigger:GetAttribute("Section")),
		tostring(trigger:GetAttribute("Building")),
		tostring(trigger:GetAttribute("Level"))
	)
end

-- TowerStart carries Section/Building itself, so match on the tagged part
-- rather than walking ancestors. The walk it replaces started at the Facade
-- folder, which has no attributes, and then stepped to the Facade's own
-- ancestor rather than to Building_N, so it skipped the only folder that
-- could have matched and always returned nil.
local function findTowerStart(section, building)
	for _, spawn in ipairs(CollectionService:GetTagged("TowerStart")) do
		if spawn:GetAttribute("Section") == section and spawn:GetAttribute("Building") == building then
			return spawn
		end
	end
	return nil
end

local function teleport(player, cframe)
	local char = player.Character
	if not char then
		return false
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	root.CFrame = cframe + Vector3.new(0, 4, 0)
	root.AssemblyLinearVelocity = Vector3.zero
	return true
end

local function scoreValue(player)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end
	local score = stats:FindFirstChild("Score")
	if not score then
		score = Instance.new("IntValue")
		score.Name = "Score"
		score.Parent = stats
	end
	return score
end

-- One payload shape for every update. The client hides the timer when there is
-- no level in it, and plays a celebration when event is present, so floor
-- clears and tower completions ride the existing 4 Hz push with no new remote.
local function push(player, event)
	local s = state[player]
	local payload = {
		score = scoreValue(player).Value,
		event = event,
	}
	if s then
		payload.level = s.level
		payload.tower = s.tower
		payload.par = s.par
		payload.elapsed = os.clock() - s.startedAt
		-- The compass arrow needs these to pick the LevelTrigger one floor up out
		-- of every tagged trigger in the city; the tower name alone would not
		-- survive a second section reusing a style letter.
		payload.section = s.section
		payload.building = s.building
	end
	remote:FireClient(player, payload)
end

local function startFloor(player, trigger)
	local level = trigger:GetAttribute("Level") or 0
	local section = trigger:GetAttribute("Section")
	local building = trigger:GetAttribute("Building")

	state[player] = {
		key = keyFor(trigger),
		level = level,
		section = section,
		building = building,
		tower = trigger:GetAttribute("TowerName") or "Tower",
		par = Config.getParTime(level),
		anchor = trigger.CFrame,
		startedAt = os.clock(),
	}
	home[player] = { section = section, building = building }
end

local function inSameTower(s, trigger)
	return s ~= nil and s.section == trigger:GetAttribute("Section") and s.building == trigger:GetAttribute("Building")
end

-- Returns what was actually paid, not the running total, because gear can move
-- it: a pet's ScoreBonus is applied here rather than at the two call sites, so a
-- third payout cannot be written without it, and the caller reports the number
-- the player received rather than the one it asked for.
--
-- Rounded once, on the total, because Score is an IntValue. A floor's payout is
-- tens of points rather than a coin's one, so there is nothing here worth the
-- carried remainder PickupService keeps.
local function award(player, amount)
	local bonus = player:GetAttribute(Config.Accessories.Attributes.ScoreBonus) or 0
	local paid = bonus > 0 and math.floor(amount * (1 + bonus) + 0.5) or amount
	local score = scoreValue(player)
	score.Value = score.Value + paid
	return paid
end

local function enterFloor(player, trigger)
	local s = state[player]
	local level = trigger:GetAttribute("Level") or 0
	local event = nil

	-- Only a climb pays out. Wandering back onto a floor already cleared, or
	-- walking into a different tower, just restarts that floor's clock.
	if inSameTower(s, trigger) and level == s.level + 1 then
		local elapsed = os.clock() - s.startedAt
		local gained = award(player, Config.scoreFloor(s.level, elapsed))
		event = { kind = "floor", level = s.level, elapsed = elapsed, par = s.par, gained = gained }
		progress:Fire({
			kind = "floor",
			player = player,
			section = s.section,
			building = s.building,
			level = s.level,
			elapsed = elapsed,
			gained = gained,
		})
	end

	startFloor(player, trigger)
	push(player, event)
end

local roofCache = {}
local roofWarned = {}

-- A miss here is silent by construction: the poll below just keeps returning
-- false and the tower can never be finished. Warn once per tower so the cause
-- is visible in Output instead of showing up as a timer that never stops. The
-- usual cause is geometry left in the place file from a previous session, whose
-- towers carry LevelTrigger tags but no RoofTrigger; delete workspace.MazeCity.
local function findRoofTrigger(section, building)
	if section == nil or building == nil then
		return nil
	end

	local key = section .. ":" .. building
	local cached = roofCache[key]
	if cached and cached.Parent then
		return cached
	end
	for _, part in ipairs(CollectionService:GetTagged("RoofTrigger")) do
		if part:GetAttribute("Section") == section and part:GetAttribute("Building") == building then
			roofCache[key] = part
			return part
		end
	end

	if not roofWarned[key] then
		roofWarned[key] = true
		warn(
			string.format(
				"TowerTimerService: no RoofTrigger for section %s building %s (%d tagged in total), so this tower cannot be completed",
				tostring(section),
				tostring(building),
				#CollectionService:GetTagged("RoofTrigger")
			)
		)
	end
	return nil
end

-- Roof arrival is polled rather than bound to Touched. It is the one event the
-- whole climb pays off on, and a touch that does not land leaves the tower
-- impossible to finish, so it gets the mechanism with no failure mode instead
-- of the convenient one. The trigger is axis-aligned, so this is a plain
-- extent test, and the loop it runs in is already ticking for the timer push.
local function onRoof(player, s)
	local roof = findRoofTrigger(s.section, s.building)
	if not roof then
		return false
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	local d = root.Position - roof.Position
	local half = roof.Size * 0.5
	return math.abs(d.X) <= half.X and math.abs(d.Y) <= half.Y and math.abs(d.Z) <= half.Z
end

local function completeTower(player)
	local s = state[player]
	local elapsed = os.clock() - s.startedAt
	local gained = award(player, Config.scoreFloor(s.level, elapsed) + Config.Scoring.TowerBonus)

	local event = {
		kind = "tower",
		level = s.level,
		elapsed = elapsed,
		par = s.par,
		gained = gained,
		tower = s.tower,
	}
	-- Clearing state both ends the floor timer and takes the player out of the
	-- poll, so the bonus can only be collected once. It is also what makes this
	-- the safe place to fire the bindable: a listener cannot be handed the same
	-- tower twice however it was reached, poll or touch.
	state[player] = nil
	push(player, event)
	progress:Fire({
		kind = "tower",
		player = player,
		section = s.section,
		building = s.building,
		level = s.level,
		elapsed = elapsed,
		gained = gained,
		tower = s.tower,
	})
end

-- Where a death sends the player. Also the answer the death banner shows, so
-- it is computed once here and read by the Died handler.
local function respawnKind(player)
	if state[player] and Config.DeathAction ~= "restartTower" then
		return "floor"
	end
	return "tower"
end

local function respawnAfterDeath(player)
	local s = state[player]

	if respawnKind(player) == "floor" and teleport(player, s.anchor) then
		s.startedAt = os.clock()
		push(player)
		return
	end

	-- Either restartTower, or the floor anchor was unusable. Dropping the state
	-- is what stops a floor-7 timer from running while the player stands on the
	-- plaza. Only section 1's plazas are enabled SpawnLocations, so without the
	-- teleport a death anywhere else restarts the whole city.
	state[player] = nil
	local h = home[player]
	if h then
		local start = findTowerStart(h.section, h.building)
		if start then
			teleport(player, start.CFrame)
		end
	end
	push(player)
end

local function bindCharacter(player, char)
	local humanoid = char:WaitForChild("Humanoid", 5)
	if humanoid then
		humanoid.Died:Connect(function()
			pendingRespawn[player] = true
			push(player, { kind = "death", restart = respawnKind(player) })
		end)
	end

	char:WaitForChild("HumanoidRootPart", 5)
	task.wait(0.2)

	if pendingRespawn[player] then
		pendingRespawn[player] = nil
		respawnAfterDeath(player)
	else
		push(player)
	end
end

local function playerFromHit(hit)
	local char = hit:FindFirstAncestorOfClass("Model")
	if not char then
		return nil
	end
	return Players:GetPlayerFromCharacter(char)
end

local function bindTag(tag, handler)
	local function bind(part)
		if not part:IsA("BasePart") then
			return
		end
		part.Touched:Connect(function(hit)
			local player = playerFromHit(hit)
			if player then
				handler(player, part)
			end
		end)
	end

	for _, part in ipairs(CollectionService:GetTagged(tag)) do
		bind(part)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(bind)
end

bindTag("LevelTrigger", function(player, trigger)
	local s = state[player]
	if s then
		if s.key == keyFor(trigger) then
			return
		end
		if (os.clock() - s.startedAt) < Config.GraceSeconds then
			return
		end
	end
	enterFloor(player, trigger)
end)

-- Second path to the same completion. The poll is the one with no failure mode
-- and normally gets there first, at which point state is already nil and this
-- does nothing; it exists so a tower still finishes if the poll's lookup misses.
bindTag("RoofTrigger", function(player, trigger)
	local s = state[player]
	if s and inSameTower(s, trigger) then
		completeTower(player)
	end
end)

local function bindPlayer(player)
	scoreValue(player)
	player.CharacterAdded:Connect(function(char)
		bindCharacter(player, char)
	end)
	if player.Character then
		task.spawn(bindCharacter, player, player.Character)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end
Players.PlayerAdded:Connect(bindPlayer)

Players.PlayerRemoving:Connect(function(player)
	state[player] = nil
	pendingRespawn[player] = nil
	home[player] = nil
end)

-- Always runs: this is where roof arrival is detected and where state for a
-- departed player is dropped. Config.TimerEnabled only governs the live clock
-- the client draws, not progression.
local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator = accumulator + dt
	if accumulator < 0.25 then
		return
	end
	accumulator = 0

	for player, s in pairs(state) do
		if not player.Parent then
			state[player] = nil
		elseif not pendingRespawn[player] then
			if onRoof(player, s) then
				completeTower(player)
			elseif Config.TimerEnabled then
				push(player)
			end
		end
	end
end)
