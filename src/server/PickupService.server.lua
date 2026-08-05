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

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))

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

	if profile.walkSpeedMultiplier then
		local base = humanoid.WalkSpeed
		humanoid.WalkSpeed = base * profile.walkSpeedMultiplier
		table.insert(undo, function()
			if humanoid.Parent then
				humanoid.WalkSpeed = base
			end
		end)
	end

	if profile.jumpMultiplier then
		-- Humanoids express jump as power or as height depending on
		-- UseJumpPower, and which one a place uses is a Studio-side setting, so
		-- the multiplier is applied to whichever is live.
		if humanoid.UseJumpPower then
			local base = humanoid.JumpPower
			humanoid.JumpPower = base * profile.jumpMultiplier
			table.insert(undo, function()
				if humanoid.Parent then
					humanoid.JumpPower = base
				end
			end)
		else
			local base = humanoid.JumpHeight
			humanoid.JumpHeight = base * profile.jumpMultiplier
			table.insert(undo, function()
				if humanoid.Parent then
					humanoid.JumpHeight = base
				end
			end)
		end
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

	return true
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

local function bindTag(tag, handler)
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
	local coins = statValue(player, "Coins")
	coins.Value = coins.Value + Config.Collectibles.CoinValue
	consume(part, Config.Collectibles.CoinRespawnSeconds)
	remote:FireClient(player, { kind = "coin" })
end)

bindTag("Powerup", function(player, part)
	local kindName = part:GetAttribute("Kind") or "Speed"
	if not applyPowerup(player, kindName) then
		return
	end

	local profile = Config.getPowerupKind(kindName)
	consume(part, Config.Collectibles.PowerupRespawnSeconds)
	remote:FireClient(player, {
		kind = "powerup",
		powerup = kindName,
		label = profile.label,
		duration = profile.duration,
	})
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
end)
