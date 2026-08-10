-- PickupService (Script) -> ServerScriptService
-- Coins and powerups. Discovers Coin and Powerup through CollectionService the
-- way every other service does, so a section built lazily under a player's feet
-- is covered with no extra wiring.
--
-- Coins are a currency, not score. Score says how fast a floor went; coins say
-- how much of it was looked at, so a player who was slow because they explored
-- is not charged for it twice. Milestone P is what gives them somewhere to go.
--
-- The server owns the count. A dedicated PickupUpdate remote carries each pickup
-- rather than the 4 Hz TimerUpdate push, because a ding that lands up to a
-- quarter of a second after the coin vanished reads as a bug.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local WalkSpeed = require(ServerScriptService:WaitForChild("WalkSpeedResolver"))

-- Gear worn by an equipped pet, published by PetService. Read rather than
-- required, so this script still knows nothing about pets. Hoisted because the
-- coin handler is the hottest path in the file and reads one of them per pickup.
local COIN_BONUS = Config.Accessories.Attributes.CoinMultiplier
local MAGNET_BONUS = Config.Accessories.Attributes.PickupRadius

local remote = ReplicatedStorage:FindFirstChild("PickupUpdate")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "PickupUpdate"
	remote.Parent = ReplicatedStorage
end

-- A pickup taken is gone for everyone and comes back on a timer, so a floor
-- restarted after a death is worth walking again. Weak keys because the entry
-- means nothing once the part is collected by the engine.
local taken = setmetatable({}, { __mode = "k" })
-- One powerup at a time per player, so a second pickup cannot read an already
-- boosted WalkSpeed as the value to restore later.
local active = {}
-- Coin multiplier per player, owned by whatever effect is in active[] and torn
-- down by its restore closure. Kept out here rather than read back off the entry
-- because the coin handler is the hottest path in this script and should not
-- have to know what a powerup is.
local coinBonus = {}
-- The fraction of a coin a payout left behind, carried to the next one. Gear's
-- CoinMultiplier is a fraction and CoinValue is 1, so rounding each pickup on
-- its own would turn +20% into either nothing or double; carried, five coins pay
-- six and the number a player was promised is the number they get. Powerup
-- multipliers are whole and leave nothing here, which is why this did not exist
-- before gear did.
local coinCarry = {}

-- What an orb turns out to be is decided here, at the moment it is touched,
-- rather than by MazeGenerator when it was built. Runtime randomness, so it is
-- deliberately not seeded off the world seed: two players taking the same orb
-- should not get the same prize, and neither should the same player after it
-- respawns. Generation determinism is untouched by this, because generation no
-- longer draws for it at all.
local roll = Random.new()

-- Created here as well as in TowerTimerService because either script may see a
-- given player first. Both do it synchronously inside their PlayerAdded
-- handler, which run one after another on the same thread, so there is no
-- window in which both find nothing and both create a folder.
local function statValue(player, name)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end
	local value = stats:FindFirstChild(name)
	if not value then
		value = Instance.new("IntValue")
		value.Name = name
		value.Parent = stats
	end
	return value
end

local function consume(part, seconds)
	taken[part] = true
	part.Transparency = 1
	part.CanTouch = false
	local glow = part:FindFirstChildOfClass("PointLight")
	if glow then
		glow.Enabled = false
	end

	task.delay(seconds, function()
		taken[part] = nil
		if not part.Parent then
			return
		end
		part.Transparency = 0
		part.CanTouch = true
		if glow then
			glow.Enabled = true
		end
	end)
end

-- ============================================================
-- Powerups
-- ============================================================
-- Every effect is expressed as a restore closure, and the closures all guard on
-- the instance still being parented: a player who dies mid-powerup gets a new
-- character, and the old humanoid's WalkSpeed is nobody's business by then.

local function clearEffect(player)
	local current = active[player]
	if current then
		active[player] = nil
		current.restore()
		remote:FireClient(player, { kind = "powerupEnded", powerup = current.name })
	end
end

local function applyPowerup(player, kindName)
	local profile = Config.getPowerupKind(kindName)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	clearEffect(player)

	local undo = {}
	local granted = nil

	-- Paid immediately and never taken back, so it is not in the undo list. A
	-- multiplier on its own is worth nothing to a player who has already emptied
	-- the floor; the lump is what makes this land as a prize wherever it is found.
	if profile.coinGrantMin then
		granted = roll:NextInteger(profile.coinGrantMin, profile.coinGrantMax)
		local coins = statValue(player, "Coins")
		coins.Value = coins.Value + granted
	end

	if profile.coinMultiplier then
		coinBonus[player] = profile.coinMultiplier
		table.insert(undo, function()
			coinBonus[player] = nil
		end)
	end

	if profile.walkSpeedMultiplier then
		-- A named factor rather than a raw write. The undo removes this one term
		-- from the product instead of restoring a number it remembered, which is
		-- what lets a sprint or a phase run underneath the boost and survive it
		-- expiring. A Fast Feet purchase made mid-boost still lands, because the
		-- resolver reads BaseWalkSpeed fresh every time it recomputes.
		WalkSpeed.set(char, "Powerup", profile.walkSpeedMultiplier)
		table.insert(undo, function()
			WalkSpeed.clear(char, "Powerup")
		end)
	end

	if kindName == "Ghost" then
		-- An attribute on the character rather than a table here, because the
		-- thing that has to read it is EnemyService, and an attribute is the
		-- channel this codebase already uses to cross that line.
		char:SetAttribute("Unseen", true)

		local shimmer = Instance.new("Highlight")
		shimmer.Name = "UnseenHighlight"
		shimmer.FillColor = profile.highlightColor or profile.color
		shimmer.FillTransparency = 0.55
		shimmer.OutlineTransparency = 0.2
		shimmer.Parent = char

		table.insert(undo, function()
			if char.Parent then
				char:SetAttribute("Unseen", nil)
			end
			shimmer:Destroy()
		end)
	end

	if kindName == "Freeze" then
		-- A deadline, not a flag: two players freezing overlapping crowds should
		-- extend the thaw rather than have the first one's expiry end both. The
		-- restore is deliberately empty, so picking up something else does not
		-- wake the enemies back up early.
		local until_ = os.clock() + profile.duration
		local current = workspace:GetAttribute("EnemyFreezeUntil") or 0
		if until_ > current then
			workspace:SetAttribute("EnemyFreezeUntil", until_)
		end
	end

	local entry = {
		name = kindName,
		restore = function()
			for _, fn in ipairs(undo) do
				fn()
			end
		end,
	}
	active[player] = entry

	task.delay(profile.duration, function()
		if active[player] == entry then
			clearEffect(player)
		end
	end)

	return true, granted
end

-- ============================================================
-- Binding
-- ============================================================

local function playerFromHit(hit)
	local char = hit:FindFirstAncestorOfClass("Model")
	if not char then
		return nil
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return Players:GetPlayerFromCharacter(char)
end

-- Kept alongside the Touched binding below so the proximity sweep can reach the
-- same handler a touch would have reached. Both paths guard on taken[part], and
-- neither yields between reading that guard and setting it, so a coin cannot be
-- awarded twice however it was reached.
local handlers = {}

local function bindTag(tag, handler)
	handlers[tag] = handler

	local function bind(part)
		if not part:IsA("BasePart") then
			return
		end
		part.Touched:Connect(function(hit)
			if taken[part] then
				return
			end
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

bindTag("Coin", function(player, part)
	-- Added, never chained: a CoinBoost orb worth 2x with a Gilded Crown's +25%
	-- pays 2.25, not 2.5. Every multiplier in this system sums its bonus fraction
	-- and is applied once, which is the version a player can predict.
	local multiplier = (coinBonus[player] or 1) + (player:GetAttribute(COIN_BONUS) or 0)
	local coins = statValue(player, "Coins")
	local owed = Config.Collectibles.CoinValue * multiplier + (coinCarry[player] or 0)
	local paid = math.floor(owed)
	coinCarry[player] = owed - paid
	coins.Value = coins.Value + paid
	consume(part, Config.Collectibles.CoinRespawnSeconds)
	-- The part itself rather than its position, because the client draws the
	-- magnet's flight by cloning it: the disc that flies in is then the disc that
	-- vanished, down to its size and colour, and neither side has to carry the
	-- other's geometry constants. It is safe to hand over because a coin is never
	-- destroyed, only hidden, and the server never moves one.
	remote:FireClient(player, { kind = "coin", multiplier = multiplier, coin = part })
end)

bindTag("Powerup", function(player, part)
	-- The orb carries no Kind. It is a mystery box, rolled here, so the same orb
	-- is a different prize to the next player to reach it and to the same player
	-- once it has respawned.
	local pool = Config.Collectibles.PowerupRoll
	local kindName = pool[roll:NextInteger(1, #pool)]

	local ok, granted = applyPowerup(player, kindName)
	if not ok then
		return
	end

	local profile = Config.getPowerupKind(kindName)
	consume(part, Config.Collectibles.PowerupRespawnSeconds)
	remote:FireClient(player, {
		kind = "powerup",
		powerup = kindName,
		label = profile.label,
		duration = profile.duration,
		coins = granted,
	})
end)

-- ============================================================
-- Proximity sweep
-- ============================================================
-- Touched alone meant a coin had to be walked into almost exactly: the disc is
-- 3.4 studs across and standing beside one did nothing, which reads as a broken
-- coin rather than as a miss. The roof arcs were the sharp end of it, a coin at
-- ARC_RADIUS 3.2 leaving about half a stud of clearance against a torso going
-- straight up. So a radius around the player collects too, and Touched stays as
-- the zero-latency path for the ones actually walked into.
--
-- Cost is one spatial query per living player per sweep, two for a player who
-- owns the Coin Magnet, rather than a distance test against every coin in the
-- city, of which there are 990 per section. The query is answered by the
-- engine's broadphase, so it does not care how much geometry is around; the
-- handful of parts it comes back with are filtered by tag here.

local COLLECTIBLE_TAGS = { "Coin", "Powerup" }

local sweepParams = OverlapParams.new()
sweepParams.FilterType = Enum.RaycastFilterType.Exclude

local function sweep(player)
	local char = player.Character
	if not char then
		return
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end

	sweepParams.FilterDescendantsInstances = { char }
	local collectibles = Config.Collectibles
	local near = workspace:GetPartBoundsInRadius(root.Position, collectibles.PickupRadius, sweepParams)

	for _, part in ipairs(near) do
		if not taken[part] then
			for _, tag in ipairs(COLLECTIBLE_TAGS) do
				if CollectionService:HasTag(part, tag) then
					handlers[tag](player, part)
					break
				end
			end
		end
	end

	-- The Coin Magnet, as a second query rather than as a wider first one. The two
	-- answer different questions: the sweep above is "close enough to have touched
	-- it", which is every collectible, and this is "close enough for the magnet to
	-- take it", which is coins and nothing else. Widening the one radius, which is
	-- what the old MagnetBonus did, also hoovered powerup orbs out of rooms the
	-- player never entered, and an orb that arrives from behind a wall with no
	-- flight and no orb to see reads as a bug rather than as a prize.
	--
	-- Nothing here tests line of sight, which is the feature: a magnet stops at a
	-- wall only if somebody writes the raycast, and none is written.
	--
	-- The shop's tier and gear's studs add rather than either one winning, which
	-- is the only rule that lets SaveService keep writing MagnetRange without ever
	-- hearing about a Coin Chain. The guard is deliberately against the sum: a +2
	-- trinket on a player who never bought the magnet does not reach past the
	-- radius they already sweep, and that is the honest answer for a +2 trinket
	-- rather than a case to route around.
	local range = (player:GetAttribute("MagnetRange") or 0) + (player:GetAttribute(MAGNET_BONUS) or 0)
	if range <= collectibles.PickupRadius then
		return
	end

	for _, part in ipairs(workspace:GetPartBoundsInRadius(root.Position, range, sweepParams)) do
		if
			not taken[part]
			and CollectionService:HasTag(part, "Coin")
			and math.abs(part.Position.Y - root.Position.Y) <= collectibles.MagnetHeight
		then
			handlers.Coin(player, part)
		end
	end
end

task.spawn(function()
	while true do
		for _, player in ipairs(Players:GetPlayers()) do
			sweep(player)
		end
		task.wait(Config.Collectibles.PickupSweepSeconds)
	end
end)

-- The counter itself is the replicated leaderstats value, which the client
-- reads directly; this only has to exist before the client waits on it. The
-- remote carries the ding and the banner, which are events rather than state,
-- so a client that connects late misses a sound and never a number.
local function bindPlayer(player)
	statValue(player, "Coins")
end

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end
Players.PlayerAdded:Connect(bindPlayer)

Players.PlayerRemoving:Connect(function(player)
	active[player] = nil
	coinBonus[player] = nil
	coinCarry[player] = nil
end)
