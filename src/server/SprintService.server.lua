-- SprintService (Script) -> ServerScriptService
-- Sprint. Hold the key and the character moves at Config.Sprint
-- .WalkSpeedMultiplier until a short stamina meter runs out; let go and the
-- meter refills after a pause.
--
-- Nothing sells this and no tier gates it, which is the difference that shapes
-- the whole file. The Wall Walker's meter refills at a LevelTrigger because a
-- tier is a budget bought for each floor; sprint is a movement verb every player
-- has, so it regenerates on a clock and this service never looks at a tag. That
-- also means there is no capacity of zero to hide the HUD chip behind: the chip
-- is always up and the key is always bound.
--
-- The speed itself is a named factor in WalkSpeedResolver rather than a write to
-- humanoid.WalkSpeed. Sprint is the fourth thing that wants to change how fast a
-- player moves and the first one that is available from the first floor, so it
-- is the one that would have collided with a Speed powerup daily.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local WalkSpeed = require(ServerScriptService:WaitForChild("WalkSpeedResolver"))

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

local remote = findOrCreate(ReplicatedStorage, "RemoteEvent", "SprintUpdate")
local intents = findOrCreate(ReplicatedStorage, "RemoteEvent", "SprintIntent")

local CAPACITY = Config.Sprint.Seconds

-- player -> { stamina, sprinting, regenAt }
local state = {}

local function entryFor(player)
	local entry = state[player]
	if not entry then
		entry = { stamina = CAPACITY, sprinting = false, regenAt = 0 }
		state[player] = entry
	end
	return entry
end

local function push(player, event)
	local entry = state[player]
	if not entry then
		return
	end
	remote:FireClient(player, {
		kind = "state",
		stamina = entry.stamina,
		capacity = CAPACITY,
		sprinting = entry.sprinting,
		-- Seconds still to wait before the meter starts coming back, not the
		-- deadline itself: a remaining time needs no agreement about whose clock
		-- os.clock() is, and the client is going to draw the recovery between
		-- pushes off the same regen rate this loop uses.
		regenIn = math.max(0, entry.regenAt - os.clock()),
		event = event,
	})
end

-- ============================================================
-- The sprint itself
-- ============================================================

-- Whether the character is actually going somewhere. MoveDirection is the
-- humanoid's input vector, so it is zero for a player standing on a key and
-- zero through a slide or zipline ride, where PlatformStand has taken control
-- and a multiplier would be spent on movement the player is not steering.
local function moving(player)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end
	return humanoid.MoveDirection.Magnitude > Config.Sprint.MoveThreshold
end

local function startSprint(player)
	local entry = entryFor(player)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if entry.sprinting or not humanoid or humanoid.Health <= 0 then
		return
	end
	-- A floor rather than "any stamina at all". Starting on the last tenth of a
	-- second is a sprint that fires, moves nobody a stud and stops on the next
	-- frame, which reads as the ability being broken rather than spent.
	if entry.stamina < Config.Sprint.MinimumToStart then
		push(player, { kind = "spent" })
		return
	end

	entry.sprinting = true
	WalkSpeed.set(char, "Sprint", Config.Sprint.WalkSpeedMultiplier)
	push(player, { kind = "started" })
end

local function endSprint(player, reason)
	local entry = state[player]
	if not entry or not entry.sprinting then
		return
	end

	entry.sprinting = false
	-- The delay is counted from the end of the sprint rather than from the last
	-- frame that drained, so letting go early and letting go empty wait the same
	-- amount of time before anything comes back.
	entry.regenAt = os.clock() + Config.Sprint.RegenDelaySeconds

	local char = player.Character
	if char then
		WalkSpeed.clear(char, "Sprint")
	end

	push(player, { kind = reason or "stopped" })
end

-- ============================================================
-- Stamina
-- ============================================================
-- Drains only while moving and regenerates only while not sprinting, so the
-- meter is never doing both and holding the key still is neither a cost nor a
-- free refill. A sprint that empties ends here and cannot resume under a key
-- that is still down: the client only sends start on a fresh press, which is
-- what stops an exhausted hold from stuttering back on every regen tick.

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	local pushDue = false
	accumulator = accumulator + dt
	if accumulator >= Config.Sprint.PushSeconds then
		accumulator = 0
		pushDue = true
	end

	for player, entry in pairs(state) do
		if not player.Parent then
			state[player] = nil
		else
			if entry.sprinting then
				if moving(player) then
					entry.stamina = math.max(0, entry.stamina - dt)
					if entry.stamina <= 0 then
						endSprint(player, "empty")
					end
				end
			elseif entry.stamina < CAPACITY and now >= entry.regenAt then
				entry.stamina = math.min(CAPACITY, entry.stamina + Config.Sprint.RegenPerSecond * dt)
				if entry.stamina >= CAPACITY then
					push(player, { kind = "ready" })
				end
			end

			-- A full meter that is not being spent is the resting state, and the
			-- client already knows that number: it seeds itself full and the "ready"
			-- event above is the last word on the way back up. Pushing regardless
			-- would be nearly seven packets a second per idle player saying nothing.
			if pushDue and (entry.sprinting or entry.stamina < CAPACITY) then
				push(player)
			end
		end
	end
end)

-- ============================================================
-- Intents
-- ============================================================
-- Two kinds and no rate limit, where AbilityIntent has three kinds and a budget.
-- The difference is what a message can cost: an ability intent can change a
-- selection and start an effect, where start while sprinting is ignored, start on
-- a spent meter is refused by MinimumToStart, and stop while stopped is a no-op,
-- so the worst a spammer buys here is one WalkSpeed write per message on a
-- character that is already theirs.

intents.OnServerEvent:Connect(function(player, payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.kind == "start" then
		startSprint(player)
	elseif payload.kind == "stop" then
		endSprint(player, "stopped")
	end
end)

-- ============================================================
-- Lifecycle
-- ============================================================

local function bindPlayer(player)
	entryFor(player)

	player.CharacterAdded:Connect(function()
		-- The old character took its resolver factor with it, so this only has to
		-- forget the sprint. Respawning full is deliberate: a death already costs
		-- the floor, and arriving at the restart with an empty meter would charge
		-- for it twice.
		local entry = entryFor(player)
		entry.sprinting = false
		entry.stamina = CAPACITY
		entry.regenAt = 0
		push(player)
	end)

	push(player)
end

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end
Players.PlayerAdded:Connect(bindPlayer)

Players.PlayerRemoving:Connect(function(player)
	state[player] = nil
end)
