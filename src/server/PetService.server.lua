-- PetService (Script) -> ServerScriptService
-- Owns the pet half of the profile: equipping, XP, evolution, the follower rig
-- in workspace.LivePets, and the read-only projection every client draws its UI
-- from. IncubatorService and DailyRewardService write pets and eggs too; they
-- say so on the PetsChanged bindable and this is what re-pushes and re-rigs.
--
-- Two remotes, both find-or-create because any of the three pet services may
-- load first. PetUpdate carries server to client, PetIntent carries client to
-- server and is the first client-authored input this game has ever accepted:
-- every intent is validated against the profile, nothing is trusted, and a
-- player who floods gets their extra intents dropped.
--
-- Gear leaves this script as six player attributes rather than as calls into six
-- services, which is the same channel the shop's upgrades already use. See
-- publishEffects: this is the one writer of all six and every reader adds.
--
-- Followers are anchored parts moved by CFrame, not humanoids. A pathfinding pet
-- in a maze whose walls move is a pet stuck behind one, and a physics pet is one
-- more thing that can shove a player off a parapet. Nothing here is ever
-- parented into workspace.MazeCity.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local PetModelGenerator = require(ReplicatedStorage:WaitForChild("PetModelGenerator"))
local Profiles = require(ServerScriptService:WaitForChild("PlayerProfiles"))
local Inventory = require(ServerScriptService:WaitForChild("PetInventory"))

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

local remote = findOrCreate(ReplicatedStorage, "RemoteEvent", "PetUpdate")
local intents = findOrCreate(ReplicatedStorage, "RemoteEvent", "PetIntent")
local changed = findOrCreate(ServerScriptService, "BindableEvent", "PetsChanged")
local progress = findOrCreate(ServerScriptService, "BindableEvent", "MazeProgress")

local liveFolder = workspace:FindFirstChild("LivePets")
if not liveFolder then
	liveFolder = Instance.new("Folder")
	liveFolder.Name = "LivePets"
	liveFolder.Parent = workspace
end

local petFolder = ServerStorage:FindFirstChild("Pets")
local accessoryFolder = ServerStorage:FindFirstChild("Accessories")

-- player -> { [petUid] = { model, primary, stage, petId, index } }
local followers = {}
-- player -> { tokens, at }
local budget = {}

-- ============================================================
-- Replication
-- ============================================================

local function pushState(player, event)
	local data = Profiles.data(player)
	if not data then
		return
	end
	local payload = Inventory.project(data)
	payload.kind = "state"
	payload.event = event
	remote:FireClient(player, payload)
end

local function deny(player, action, reason)
	remote:FireClient(player, { kind = "denied", action = action, reason = reason })
end

-- ============================================================
-- Gear that reaches another service
-- ============================================================
-- Six of the eleven accessory effects are spent somewhere this script has no
-- business writing: a humanoid's walk speed, a coin payout, a magnet radius, a
-- charge drain, a score award and a hit landing. They cross the same way the
-- shop's upgrades cross and the Ghost powerup crosses, as an attribute, and the
-- rule that keeps them composable is the plan's: **one attribute, one writer,
-- readers add.** This is the writer of all six; SaveService and PickupService
-- keep owning BaseWalkSpeed and MagnetRange, and TowerTimerService and
-- EnemyCombat never learn that gear exists.
--
-- Stamped as numbers rather than left absent at zero, for the reason the ability
-- tiers are: an absent attribute is indistinguishable from a profile that has
-- not landed, and a reader that adds nil would have to know that.
local function publishEffects(player, data)
	local effects = Inventory.wornEffects(data)
	for effectType, name in pairs(Config.Accessories.Attributes) do
		player:SetAttribute(name, effects[effectType] or 0)
	end
	return effects
end

-- ============================================================
-- Follower rigs
-- ============================================================
-- A rig is either a model an artist put in ServerStorage/Pets, or one
-- PetModelGenerator builds from the stage's look recipe. That is the same bargain
-- EnemyService strikes: the game is fully playable from a cold rojo build with
-- zero Studio-side setup, and real art drops in later by name with no code
-- change. The generator replaced the neon cube every pet used to be, not the
-- artist, so the name still wins.

-- Anchored except for the skin, which hangs off the root on Motor6Ds so the
-- client's PetAnimator can pose it. The root itself is never a joint's Part1, so
-- it anchors, and an anchored root makes the whole thing one anchored assembly:
-- PivotTo carries it rigidly, the joints pose it, and no part of it is ever
-- simulated. Gear and the ward ring carry no joint and stay anchored, which is
-- what they were.
--
-- An artist's model gets the same treatment and it is the right one: its
-- PrimaryPart anchors, its limbs hang off whatever joints it shipped with, and a
-- rig with no joints at all comes out exactly as anchored as it used to be.
local function jointed(model)
	local held = {}
	for _, item in ipairs(model:GetDescendants()) do
		if (item:IsA("Motor6D") or item:IsA("WeldConstraint")) and item.Part1 then
			held[item.Part1] = true
		end
	end
	return held
end

local function sterilise(model)
	local held = jointed(model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = not held[part] or part == model.PrimaryPart
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.CastShadow = false
			part.Massless = true
		end
	end
end

local function buildRig(petConfig, stage)
	local wanted = Inventory.modelName(petConfig, stage)
	if petFolder then
		local template = petFolder:FindFirstChild(wanted)
		if template and template:IsA("Model") then
			local clone = template:Clone()
			if not clone.PrimaryPart then
				clone.PrimaryPart = clone:FindFirstChildWhichIsA("BasePart")
			end
			if clone.PrimaryPart then
				return clone
			end
			clone:Destroy()
			warn("PetService: ServerStorage/Pets/" .. wanted .. " has no BasePart, building the look instead")
		end
	end
	-- Built here rather than cloned from a template folder: at MaxEquipped of one
	-- this is a handful of builds per session, which is cheaper than the folder
	-- would be, and PetModelGenerator.build is pure so there is nothing to warm up.
	return PetModelGenerator.build(petConfig.id, stage)
end

-- ============================================================
-- Gear on the rig
-- ============================================================
-- A worn accessory is a model parented into the follower, positioned once and
-- carried by the same PivotTo that carries everything else. No welds and no
-- constraints: the rig is anchored, so a joint would be a solver problem where
-- an offset is arithmetic.
--
-- Nothing here requires AccessoryCatalog. Inventory.wornConfigs hands over the
-- resolved entries, which is the same rule the effects follow: one file knows
-- what an accessoryId means.

-- A <Slot>Attachment on the rig wins. A generated rig authors all four against
-- the extent it actually came out as, which is why a crown lands on top of a
-- Lumen Moth's head and not inside its wings; the bounding box fallback below is
-- now only ever for an artist's model that authored none.
local function slotCFrame(model, slot, boxCFrame, boxSize)
	local attachment = model:FindFirstChild(slot .. "Attachment", true)
	if attachment and attachment:IsA("Attachment") then
		return attachment.WorldCFrame
	end
	local fraction = Config.Accessories.SlotOffsets[slot]
	if not fraction then
		return boxCFrame
	end
	return boxCFrame * CFrame.new(fraction.X * boxSize.X, fraction.Y * boxSize.Y, fraction.Z * boxSize.Z)
end

local function makeGearPlaceholder(config)
	local look = config.placeholder

	-- The Aura slot is never a part. An invisible holder rather than the emitter
	-- on the body, so the particles sit where the slot says and not wherever the
	-- rig's PrimaryPart happens to be.
	if look.shape == "Particle" then
		local holder = Instance.new("Part")
		holder.Name = config.id
		holder.Size = Vector3.new(0.2, 0.2, 0.2)
		holder.Transparency = 1

		local aura = Config.Accessories
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Aura"
		emitter.Color = ColorSequence.new(look.color)
		emitter.Size = NumberSequence.new(look.size.X)
		emitter.Rate = look.rate or 8
		emitter.Lifetime = NumberRange.new(aura.AuraLifetime[1], aura.AuraLifetime[2])
		emitter.Speed = NumberRange.new(aura.AuraSpeed[1], aura.AuraSpeed[2])
		emitter.Drag = aura.AuraDrag
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.LightEmission = 0.6
		emitter.Parent = holder
		return holder
	end

	local part = Instance.new("Part")
	part.Name = config.id
	part.Color = look.color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	if look.shape == "Ball" then
		part.Shape = Enum.PartType.Ball
		part.Size = look.size
	elseif look.shape == "Cylinder" then
		-- A cylinder's circular faces point along its X axis, so a ring worn flat
		-- is sized height-first and laid over. Same turn the ward ring makes.
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(look.size.Y, look.size.X, look.size.Z)
	else
		part.Shape = Enum.PartType.Block
		part.Size = look.size
	end
	return part
end

local function gearOrientation(config)
	if config.placeholder.shape == "Cylinder" then
		return CFrame.Angles(0, 0, math.pi / 2)
	end
	return CFrame.new()
end

local function buildGear(config)
	if accessoryFolder then
		local template = accessoryFolder:FindFirstChild(config.model)
		if template and (template:IsA("Model") or template:IsA("BasePart")) then
			return template:Clone(), true
		end
	end
	return makeGearPlaceholder(config), false
end

-- Called before the glow and the ward, and the order is load-bearing: the ward
-- ring is a disc as wide as the ward itself, so a bounding box measured after it
-- exists would put a crown thirty studs above the pet.
local function attachWorn(entry, data, pet)
	local worn = Inventory.wornConfigs(data, pet)
	if #worn == 0 then
		return
	end
	local boxCFrame, boxSize = entry.model:GetBoundingBox()

	for _, item in ipairs(worn) do
		local gear, fromArt = buildGear(item.config)
		local at = slotCFrame(entry.model, item.slot, boxCFrame, boxSize)

		local placed = true
		if gear:IsA("Model") then
			if not gear.PrimaryPart then
				gear.PrimaryPart = gear:FindFirstChildWhichIsA("BasePart")
			end
			if gear.PrimaryPart then
				gear:PivotTo(at)
			else
				placed = false
				warn("PetService: ServerStorage/Accessories/" .. item.config.model .. " has no BasePart, skipping it")
			end
		else
			-- An artist's part is worn as authored; the placeholder shapes carry the
			-- one turn a flat ring needs.
			gear.CFrame = at * (fromArt and CFrame.new() or gearOrientation(item.config))
		end

		if placed then
			gear.Name = "Gear_" .. item.slot
			gear.Parent = entry.model
		else
			gear:Destroy()
		end
	end

	-- Re-run over the whole rig rather than over each piece: an artist's model can
	-- arrive unanchored and colliding, and there is one funnel for that already.
	sterilise(entry.model)
end

-- Glow is the one ability implemented end to end, and it is a light on the rig
-- rather than anything on the client: a follower is a world object every player
-- can see, so the light that comes off it belongs in the world too, replicated
-- once instead of drawn N times.
--
-- The evolution multiplier scales range and deliberately not brightness. Range
-- is how much maze the pet lights; brightness at 2.5x is a Solar Firefly that
-- blows out the corridor and the player standing in it, which is the same
-- failure Config.World.LampBrightness documents at the other end of the city.
--
-- A GlowRange item adds studs to whatever the ability was worth, which is why
-- this can fire on a pet with no Glow ability at all: a lantern hat on a Coin
-- Bat is a lantern hat. The bonus is added rather than multiplied, so the
-- evolution multiplier stays a property of the pet and not of its hat.
local function applyGlow(primary, petConfig, stage, effects)
	local glowing = petConfig.ability.type == "Glow"
	local bonus = effects.GlowRange or 0
	if not glowing and bonus <= 0 then
		return
	end
	local params = petConfig.ability.params
	local range = bonus
	if glowing then
		range = range + (params.radius or 12) * Inventory.abilityMultiplier(petConfig, stage)
	end

	local light = Instance.new("PointLight")
	light.Name = "PetGlow"
	light.Color = Inventory.look(petConfig, stage).primary
	light.Range = range
	light.Brightness = (glowing and params.brightness) or 1
	light.Shadows = false
	light.Parent = primary
end

-- The Ward, and the first pet ability that reaches into another system. Its whole
-- surface on this side is one attribute: while the ward is running, the rig
-- carries WardRadius, and Enemy/EnemyWard turns that into enemies losing interest
-- and walking home. The attribute existing is the ward being up, so there is no
-- second flag to disagree with the first, and it is the same channel the Ghost
-- powerup and the Cloak ability already use to hide a player.
--
-- Nothing here damages, stuns or moves an enemy. There is no combat in this game
-- and a pet is not where one would start; a warded enemy walks back to its own
-- marker under its own power, which is a branch the controller already had.
--
-- Armed by a scan rather than a timer. An enemy has to come inside the radius to
-- set it off, so a ward is never spent on an empty corridor, and once it lapses it
-- recharges: at six seconds up and ten down it is a way out of a corner rather
-- than a way to switch a floor off. That matters more than it looks, because a
-- ward that never lapsed would be strictly better than the two things a player
-- buys coins for, and this one is only a hatch away.
local function applyWard(entry, petConfig, stage)
	if petConfig.ability.type ~= "Ward" then
		return
	end
	local params = petConfig.ability.params
	local radius = (params.radius or 14) * Inventory.abilityMultiplier(petConfig, stage)
	entry.ward = {
		radius = radius,
		activeSeconds = params.activeSeconds or 5,
		rechargeSeconds = params.rechargeSeconds or 10,
		readyAt = 0,
		activeUntil = 0,
		scanAt = 0,
	}

	-- Drawn flat on the floor, so the size of it is legible from inside. Parented
	-- to the rig, so it goes when the pet does with nothing to remember.
	local ring = Instance.new("Part")
	ring.Name = "WardRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, radius * 2, radius * 2)
	ring.Color = Inventory.look(petConfig, stage).primary
	ring.Material = Enum.Material.Neon
	ring.Transparency = 1
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Massless = true
	ring.Parent = entry.model
	entry.wardRing = ring
end

-- True while an enemy rig is inside the radius. Read off workspace.LiveEnemies
-- rather than the enemy registry, because a rig in that folder is exactly what a
-- player can see coming, and this service has no business knowing what the enemy
-- system keeps.
local function enemyInside(position, radius)
	local live = workspace:FindFirstChild("LiveEnemies")
	if not live then
		return false
	end
	for _, model in ipairs(live:GetChildren()) do
		local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - position).Magnitude <= radius then
			return true
		end
	end
	return false
end

local function stepWard(entry, now)
	local ward = entry.ward
	if not ward then
		return
	end
	local primary = entry.primary

	if now < ward.activeUntil then
		entry.model:SetAttribute("WardRadius", ward.radius)
		return
	end
	if ward.activeUntil > 0 then
		-- It just ran out. Clearing the attribute is what lets the floor chase again,
		-- so it happens before anything else can fail.
		ward.activeUntil = 0
		ward.readyAt = now + ward.rechargeSeconds
		entry.model:SetAttribute("WardRadius", nil)
		entry.wardRing.Transparency = 1
	end

	if now < ward.readyAt or now < ward.scanAt then
		return
	end
	ward.scanAt = now + Config.Pets.WardScanSeconds
	if enemyInside(primary.Position, ward.radius) then
		ward.activeUntil = now + ward.activeSeconds
		entry.model:SetAttribute("WardRadius", ward.radius)
		entry.wardRing.Transparency = Config.Pets.WardRingTransparency
	end
end

local function destroyFollower(player, petUid)
	local mine = followers[player]
	local entry = mine and mine[petUid]
	if not entry then
		return
	end
	mine[petUid] = nil
	if entry.model.Parent then
		entry.model:Destroy()
	end
end

local function spawnFollower(player, data, pet, index, worn)
	local petConfig = Inventory.petConfig(pet.petId)
	if not petConfig then
		return
	end

	local model = buildRig(petConfig, pet.stage)
	sterilise(model)
	model.Name = player.Name .. "_" .. pet.uid

	local entry = {
		model = model,
		primary = model.PrimaryPart,
		stage = pet.stage,
		petId = pet.petId,
		index = index,
		worn = worn,
	}
	attachWorn(entry, data, pet)
	applyGlow(entry.primary, petConfig, pet.stage, Inventory.wornEffects(data))
	applyWard(entry, petConfig, pet.stage)

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		model:PivotTo(root.CFrame * CFrame.new(0, Config.Pets.FollowHeight, Config.Pets.FollowDistance))
	end
	model.Parent = liveFolder

	followers[player] = followers[player] or {}
	followers[player][pet.uid] = entry
end

-- Rebuilt rather than patched when the stage changes, because an evolution is a
-- different model and a different light: the cheap update is the one that does
-- nothing when nothing moved, which is the first branch below.
local function reconcileFollowers(player)
	local data = Profiles.data(player)
	if not data then
		return
	end

	-- Here rather than beside pushState, because this is what every mutation that
	-- can move a total already calls: equipping, benching, wearing, unwearing, a
	-- PetsChanged from another service, a profile landing, a respawn. Renaming a
	-- pet calls neither, which is correct.
	publishEffects(player, data)

	local wanted = {}
	for index, petUid in ipairs(data.equipped) do
		local pet = data.pets[petUid]
		if pet and Inventory.petConfig(pet.petId) then
			wanted[petUid] = { pet = pet, index = index, worn = Inventory.wornSignature(data, pet) }
		end
	end

	local mine = followers[player] or {}
	for petUid, entry in pairs(mine) do
		local want = wanted[petUid]
		-- Worn gear joins stage and petId in the comparison, so putting a crown on
		-- rebuilds the one rig wearing it and leaves every other follower alone.
		if not want or want.pet.stage ~= entry.stage or want.pet.petId ~= entry.petId or want.worn ~= entry.worn then
			destroyFollower(player, petUid)
		else
			entry.index = want.index
		end
	end

	mine = followers[player] or {}
	for petUid, want in pairs(wanted) do
		if not mine[petUid] then
			spawnFollower(player, data, want.pet, want.index, want.worn)
		end
	end
end

local function clearFollowers(player)
	local mine = followers[player]
	if not mine then
		return
	end
	for petUid in pairs(mine) do
		destroyFollower(player, petUid)
	end
	followers[player] = nil
end

-- One pass over every follower in the server, at frame rate. Cost is a CFrame
-- per equipped pet, which at MaxEquipped of one is a CFrame per player.
RunService.Heartbeat:Connect(function(dt)
	local pets = Config.Pets
	local now = os.clock()
	local alpha = math.clamp(dt * pets.FollowLerp, 0, 1)

	for player, mine in pairs(followers) do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		-- The slab the player is standing on, derived rather than guessed: a root
		-- sits its own half height plus HipHeight above the floor. It is what the
		-- ward ring is drawn on, and it costs one subtraction per player.
		local floorY = root and humanoid and (root.Position.Y - humanoid.HipHeight - root.Size.Y / 2)

		for petUid, entry in pairs(mine) do
			local model = entry.model
			if not model.Parent or not entry.primary or not entry.primary.Parent then
				mine[petUid] = nil
			else
				-- Outside the root check, so a ward that was up when its owner died
				-- still runs its clock down and clears itself rather than leaving the
				-- floor permanently warded by a pet nobody is following.
				stepWard(entry, now)

				if root then
					-- Slots fan out sideways so a second equipped pet does not stand
					-- inside the first. At MaxEquipped of one this is always zero.
					local side = (entry.index - 1) * pets.FollowSide
					local bob = math.sin((now / pets.BobSeconds) * math.pi * 2) * pets.BobHeight
					local goal = root.CFrame * CFrame.new(side, pets.FollowHeight + bob, pets.FollowDistance)
					-- Wrapped to a turn before it becomes radians. os.clock only ever
					-- grows, and a CFrame holds float32, so an unwrapped angle quantises
					-- into a visible judder after a few hours of server uptime.
					local turn = math.rad((now * pets.SpinDegreesPerSecond) % 360)
					local spun = CFrame.new(goal.Position) * CFrame.Angles(0, turn, 0)

					-- GetPivot, not PrimaryPart.CFrame: an artist's model may carry a
					-- pivot offset, and PivotTo is what is written back.
					local here = model:GetPivot()
					if (goal.Position - here.Position).Magnitude > pets.FollowTeleportRange then
						model:PivotTo(spun)
					else
						model:PivotTo(here:Lerp(spun, alpha))
					end

					-- Put back on the floor afterwards, because the pivot above dragged
					-- it up to the pet and set it spinning and bobbing. A ward is an area
					-- and an area is read off the ground.
					if entry.wardRing and floorY then
						local at = entry.primary.Position
						entry.wardRing.CFrame = CFrame.new(at.X, floorY + pets.WardRingHeight, at.Z)
							* CFrame.Angles(0, 0, math.pi / 2)
					end
				end
			end
		end
	end
end)

-- ============================================================
-- XP
-- ============================================================
-- Only the equipped pets earn, which is the whole reason equipping is a choice.
-- Both kinds of maze progress pay, whatever Config.Pets.HatchUnit says a maze
-- is: that setting governs hatching, not levelling, so a player who only ever
-- clears floors still levels a pet.

local function awardXp(player, amount)
	local data = Profiles.data(player)
	if not data or amount <= 0 then
		return
	end

	-- Gear pays here rather than at either call site, so a future third source of
	-- XP is boosted by having gone through this function. Floored: a level is
	-- drawn as a whole number of XP into a whole number needed, and 16.2 of 60 is
	-- a number nobody can act on.
	local bonus = Inventory.wornEffects(data).PetXp or 0
	if bonus > 0 then
		amount = math.floor(amount * (1 + bonus))
	end

	local rigDirty = false
	local best = nil
	for _, petUid in ipairs(data.equipped) do
		local ok, result = Inventory.addXp(data, petUid, amount)
		if ok and (result.leveled or result.evolved) then
			rigDirty = rigDirty or result.evolved
			local petConfig = Inventory.petConfig(result.pet.petId)
			best = {
				name = Inventory.displayName(result.pet, petConfig),
				level = result.pet.level,
				evolved = result.evolved,
				rarity = petConfig.rarity,
			}
		end
	end

	if rigDirty then
		reconcileFollowers(player)
	end
	pushState(player, best and { kind = "levelup", pet = best } or nil)
end

progress.Event:Connect(function(payload)
	if not Config.Pets.Enabled or not payload or not payload.player then
		return
	end
	local data = Profiles.data(payload.player)
	if not data then
		return
	end

	-- Every counter in stats is kept here rather than split across the three
	-- services that read them, so there is one place to look when a number is
	-- wrong. mazesCompleted counts whatever HatchUnit says a maze is, which is
	-- what makes it the same number the incubator is counting.
	if payload.kind == "floor" then
		data.stats.floorsCleared = data.stats.floorsCleared + 1
	elseif payload.kind == "tower" then
		data.stats.summitsReached = data.stats.summitsReached + 1
	end
	if payload.kind == Config.Pets.HatchUnit then
		data.stats.mazesCompleted = data.stats.mazesCompleted + 1
	end

	if payload.kind == "floor" then
		awardXp(payload.player, Config.Pets.XpPerFloor)
	elseif payload.kind == "tower" then
		awardXp(payload.player, Config.Pets.XpPerTower)
	end
end)

-- ============================================================
-- Intents
-- ============================================================

local function affordIntent(player)
	local now = os.clock()
	local entry = budget[player]
	if not entry then
		entry = { tokens = Config.Pets.IntentsPerSecond, at = now }
		budget[player] = entry
	end
	entry.tokens =
		math.min(Config.Pets.IntentsPerSecond, entry.tokens + (now - entry.at) * Config.Pets.IntentsPerSecond)
	entry.at = now
	if entry.tokens < 1 then
		return false
	end
	entry.tokens = entry.tokens - 1
	return true
end

-- Filtering can fail, and when it does the nickname is refused rather than let
-- through. That is the safe direction for a string other players will read, and
-- it is why nicknames are the one thing in this system that cannot be tested in
-- a Studio session without text filtering.
local function filterNickname(player, text)
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
	end)
	if not ok or not result then
		return nil
	end
	local shown, filtered = pcall(function()
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not shown then
		return nil
	end
	return filtered
end

local handlers = {}

handlers.sync = function(player)
	pushState(player)
end

handlers.equip = function(player, payload)
	local data = Profiles.data(player)
	if not data or type(payload.petUid) ~= "string" then
		return
	end
	local ok, reason = Inventory.equip(data, payload.petUid)
	if not ok then
		deny(player, "equip", reason)
		return
	end
	reconcileFollowers(player)
	pushState(player, { kind = "equipped", petUid = payload.petUid })
end

handlers.unequip = function(player, payload)
	local data = Profiles.data(player)
	if not data or type(payload.petUid) ~= "string" then
		return
	end
	local ok, reason = Inventory.unequip(data, payload.petUid)
	if not ok then
		deny(player, "unequip", reason)
		return
	end
	reconcileFollowers(player)
	pushState(player, { kind = "unequipped", petUid = payload.petUid })
end

handlers.lock = function(player, payload)
	local data = Profiles.data(player)
	if not data or type(payload.petUid) ~= "string" then
		return
	end
	local ok, reason = Inventory.setLocked(data, payload.petUid, payload.locked == true)
	if not ok then
		deny(player, "lock", reason)
		return
	end
	pushState(player)
end

-- Gear intents, validated the way equip is: the client names a uid and a slot
-- and is told what happened, including when the answer is no. Wearing is allowed
-- on a benched pet, because gear doing nothing there is a rule about effects and
-- not a reason to refuse dressing a pet up.

local function petName(data, petUid)
	local pet = data.pets[petUid]
	local petConfig = pet and Inventory.petConfig(pet.petId)
	if not petConfig then
		return nil
	end
	return Inventory.displayName(pet, petConfig)
end

handlers.wear = function(player, payload)
	local data = Profiles.data(player)
	if not data or type(payload.petUid) ~= "string" or type(payload.accessoryUid) ~= "string" then
		return
	end
	local ok, result = Inventory.wear(data, payload.petUid, payload.accessoryUid)
	if not ok then
		deny(player, "wear", result)
		return
	end
	reconcileFollowers(player)
	pushState(player, {
		kind = "worn",
		name = result.config.name,
		slot = result.slot,
		petName = petName(data, payload.petUid),
		-- Names the pet that lost it, so moving an item is never silent.
		takenFrom = result.takenFrom and petName(data, result.takenFrom) or nil,
	})
end

handlers.unwear = function(player, payload)
	local data = Profiles.data(player)
	if not data or type(payload.petUid) ~= "string" or type(payload.slot) ~= "string" then
		return
	end
	local ok, result = Inventory.unwear(data, payload.petUid, payload.slot)
	if not ok then
		deny(player, "unwear", result)
		return
	end
	local instance = data.accessories[result]
	local config = instance and Inventory.accessoryConfig(instance.accessoryId)
	reconcileFollowers(player)
	pushState(player, {
		kind = "unworn",
		name = config and config.name or nil,
		petName = petName(data, payload.petUid),
	})
end

handlers.lockAccessory = function(player, payload)
	local data = Profiles.data(player)
	if not data or type(payload.accessoryUid) ~= "string" then
		return
	end
	local ok, reason = Inventory.setAccessoryLocked(data, payload.accessoryUid, payload.locked == true)
	if not ok then
		deny(player, "lockAccessory", reason)
		return
	end
	pushState(player)
end

handlers.nickname = function(player, payload)
	local data = Profiles.data(player)
	if not data or type(payload.petUid) ~= "string" then
		return
	end
	if not data.pets[payload.petUid] then
		deny(player, "nickname", "nopet")
		return
	end

	local wanted = payload.nickname
	if wanted == nil or wanted == "" then
		Inventory.setNickname(data, payload.petUid, nil)
		pushState(player)
		return
	end
	if type(wanted) ~= "string" then
		return
	end

	local clean = filterNickname(player, string.sub(wanted, 1, Config.Pets.NicknameMaxLength))
	if not clean then
		deny(player, "nickname", "filter")
		return
	end
	-- The profile may have gone during the filter call's yield.
	if not Profiles.data(player) then
		return
	end
	Inventory.setNickname(data, payload.petUid, clean)
	pushState(player, { kind = "renamed", petUid = payload.petUid })
end

intents.OnServerEvent:Connect(function(player, payload)
	if not Config.Pets.Enabled or type(payload) ~= "table" then
		return
	end
	local handler = handlers[payload.kind]
	if not handler or not affordIntent(player) then
		return
	end
	handler(player, payload)
end)

-- ============================================================
-- Lifecycle
-- ============================================================

changed.Event:Connect(function(payload)
	if not payload or not payload.player then
		return
	end
	reconcileFollowers(payload.player)
	pushState(payload.player, payload.event)
end)

Profiles.onReady(function(player, data)
	-- A catalogue entry can disappear between releases while a saved profile
	-- still names it, and an equipped pet that cannot be built is a follower that
	-- never appears with no way to tell why.
	Inventory.pruneEquipped(data)
	-- Same posture for gear: a worn uid the catalogue no longer knows comes off
	-- the pet, while the item itself stays in the bag in case the entry returns.
	Inventory.pruneWorn(data)
	reconcileFollowers(player)
	pushState(player)
end)

local function bindPlayer(player)
	player.CharacterAdded:Connect(function()
		-- The old character's rigs are still parented and still following a root
		-- part that no longer exists; rebuilding is cheaper than re-pointing them.
		clearFollowers(player)
		reconcileFollowers(player)
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end
Players.PlayerAdded:Connect(bindPlayer)

Players.PlayerRemoving:Connect(function(player)
	clearFollowers(player)
	budget[player] = nil
end)

-- The tag is bound by IncubatorService, which owns what the prompt does. This is
-- here only so a missing pedestal is visible in Output rather than showing up as
-- a summit with nothing on it.
task.delay(20, function()
	if Config.Pets.Enabled and #CollectionService:GetTagged("EggPedestal") == 0 then
		warn("PetService: no EggPedestal tagged 20s in, so no roof has an egg roost on it")
	end
end)
