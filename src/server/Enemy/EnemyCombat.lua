-- EnemyCombat (ModuleScript) -> ServerScriptService.Enemy.EnemyCombat
-- Everything that takes a player's health, validated here and nowhere else.
--
-- The melee flow is the shipped one and the order is the whole design: flash for
-- Config.Juice.EnemyTellSeconds, then check that the player is still inside
-- EnemyTellReach when the flash ends. Damage that lands because an effect played
-- is damage a player could not have avoided, and a hit that cannot be avoided is
-- the one thing the kid-first tuning refuses.
--
-- The line of sight check at the end is the one deliberate behaviour change in
-- E2 and it is an E2 gate item ("no attacks through walls"). It was reachable
-- before: two cells are 25 studs apart but their shared wall is thin, so a player
-- pressed against one side sits inside EnemyTellReach of something on the other,
-- and both the Touched path and the proximity path would let that hit land. It is
-- checked after the flash rather than before, alongside the reach test, because a
-- wall arriving during the windup is a moving wall saving the player and should.
--
-- Both powerups are re-checked here as well as in the controller's tick. The
-- Touched path can fire between two ticks, and an enemy that hits somebody who
-- was unseen, or that hits at all while frozen, reads as the powerup being broken.
--
-- E4 added the four ways to hurt somebody that are not a swing: a slow, a shove, a
-- thing in flight and a thing on the floor. They are here rather than in the four
-- behavior modules that use them because the file's first line is the rule: every
-- validation a hit needs is written once. A projectile that forgot the Ghost check
-- or a trap that forgot the frozen check is the same bug as a melee that did, and
-- it would have been written four times to find out.
--
-- All four also leave instances in the world, so this module owns them: they are
-- filed under the controller that made them and clearRuntime destroys the lot. A
-- behavior calls that from onStopped and never keeps a list of its own.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local EnemyRig = require(script.Parent:WaitForChild("EnemyRig"))
local EnemySafeZones = require(script.Parent:WaitForChild("EnemySafeZones"))
local EnemyStatusService = require(script.Parent:WaitForChild("EnemyStatusService"))
local EnemyTargeting = require(script.Parent:WaitForChild("EnemyTargeting"))
local EnemyWard = require(script.Parent:WaitForChild("EnemyWard"))
local WalkSpeedResolver = require(script.Parent.Parent:WaitForChild("WalkSpeedResolver"))

local EnemyCombat = {}

-- One stud up, because the root sits at HipHeight and a ray from the floor into a
-- player's feet clips the slab they are both standing on.
local EYE_OFFSET = Vector3.new(0, 1, 0)

-- The factor name a slow spends. One name for every source of one, because the
-- resolver composes across sources and two enemies slowing the same player are one
-- effect rather than a product: half speed twice over is a player standing still.
local SLOW_SOURCE = "EnemySlow"

-- How much of the shove goes upward. A shove that is entirely horizontal slides a
-- player along the floor and reads as lag; a little lift reads as a hit.
local KNOCKBACK_LIFT = 0.35

function EnemyCombat.canReach(controller, character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end
	if (hrp.Position - controller.root.Position).Magnitude > Config.Juice.EnemyTellReach then
		return false
	end
	-- Checked when the flash ends, like the wall: a player who reaches the pad
	-- during the windup made it, and a swing that lands across the zone line is
	-- the zone not existing.
	if EnemySafeZones.covers(hrp.Position) then
		return false
	end
	return EnemyTargeting.hasLineOfSight(controller.root.Position + EYE_OFFSET, hrp)
end

-- Every point of health anything in this game takes goes through here, which is
-- why a pet's Armor is read here and not at the six places that call it. It
-- arrives as a replicated player attribute rather than as a PetInventory require,
-- because this module has no business learning what gear is: one attribute, one
-- writer, and this reader only subtracts. It is a fraction prevented, already
-- capped in the resolver, so nothing is clamped here.
function EnemyCombat.applyDamage(controller, character, amount)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	local dealt = amount or controller.stats.damage
	local player = Players:GetPlayerFromCharacter(character)
	local armor = player and player:GetAttribute(Config.Accessories.Attributes.Armor) or 0
	if armor > 0 then
		dealt = dealt * (1 - armor)
	end

	humanoid:TakeDamage(dealt)
	return true
end

-- Every hit in the game asks the same questions before it is allowed to start: is
-- this thing already swinging or on cooldown, is it stopped, is it inside a pet's
-- ward, and is it pretending to be something else. Melee, the shockwave and
-- everything on the floor all come through here, so a new way to hurt somebody
-- cannot quietly skip one.
--
-- The ward is checked here as well as in the controller's tick for the same reason
-- the powerups are: the Touched path fires between ticks, and a warded enemy that
-- bit somebody who walked into it while it was retreating would read as the pet
-- being broken rather than as a rule with an edge.
function EnemyCombat.canAttack(controller)
	local now = os.clock()
	if controller.windingUp or now - controller.lastAttack < controller.stats.attackCooldown then
		return false
	end
	if EnemyStatusService.isFrozen() or EnemyStatusService.has(controller.model, "Stun") then
		return false
	end
	if EnemyWard.covers(controller.root.Position) then
		return false
	end
	-- Same edge as the ward: the Touched path fires between ticks, and an enemy
	-- being backed off a plaza margin does not bite on the way out.
	if EnemySafeZones.repels(controller.root.Position) then
		return false
	end
	-- A Lurker that has not revealed itself does not bite, and neither does a Mimic
	-- still wearing a crate. Being scenery is the whole of what they are doing.
	return not controller.hidden
end

-- Returns whether a swing started, not whether it landed. Nothing reads that yet;
-- it is the honest answer because the landing happens after the tell.
--
-- opts.tell is how long the flash runs before the reach is re-checked, and a
-- behavior may lengthen it: a Brute's swing is shown for three times as long as
-- anything else's, which is the trade for hitting three times as hard. It can only
-- ever be lengthened in practice, and a shorter one would be the one thing the
-- kid-first tuning refuses.
--
-- opts.knockback is studs of shove, and it is opt-in rather than read off the row
-- for every hit. Every row carries a knockback and only two hits in the game are
-- heavy enough to spend it, so a default here would have quietly changed how all
-- six playtested types feel as a side effect of the Brute needing one.
function EnemyCombat.tryMelee(controller, character, opts)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end
	if not EnemyCombat.canAttack(controller) then
		return false
	end
	if not EnemyTargeting.isCharacterVisible(character, humanoid) then
		return false
	end

	local tell = (opts and opts.tell) or Config.Juice.EnemyTellSeconds
	local knockback = opts and opts.knockback
	controller.windingUp = true
	controller.lastAttack = os.clock()
	EnemyRig.flash(controller, tell)

	task.delay(tell, function()
		controller.windingUp = false
		if not controller.alive then
			return
		end
		if EnemyCombat.canReach(controller, character) then
			EnemyCombat.applyDamage(controller, character, controller.stats.damage)
			EnemyCombat.applyKnockback(controller, character, knockback)
		end
	end)
	return true
end

-- ============================================================
-- Slow, and the shove
-- ============================================================

-- character -> { multiplier, token }. Weak keys, so a respawn drops the record with
-- the body it was applied to, exactly as the resolver drops the factor.
local slowed = setmetatable({}, { __mode = "k" })
local nextSlowToken = 0

-- A named WalkSpeedResolver factor and never a write to the humanoid, which is the
-- whole reason a Spitter's slow, a Speed orb and a sprint compose instead of
-- cancelling each other. The E2 status system had a Slow row that recorded and
-- restored WalkSpeed itself; the resolver arrived after it and owns that number
-- now, so the row is gone and this is what replaced it.
--
-- Overlapping slows take the stronger multiplier and the newest deadline. The
-- last one to land therefore owns the expiry, which can end a longer weak slow a
-- little early; the alternative is a stack of deadlines per character to buy back
-- a fraction of a second nobody can feel.
function EnemyCombat.applySlow(character, multiplier, seconds)
	if not character or not character.Parent or not seconds or seconds <= 0 then
		return false
	end
	local factor = math.clamp(multiplier or 1, 0.1, 1)
	local existing = slowed[character]
	if existing and existing.multiplier < factor then
		factor = existing.multiplier
	end

	nextSlowToken = nextSlowToken + 1
	local token = nextSlowToken
	slowed[character] = { multiplier = factor, token = token }
	WalkSpeedResolver.set(character, SLOW_SOURCE, factor)

	task.delay(seconds, function()
		local current = slowed[character]
		if current and current.token == token then
			slowed[character] = nil
			WalkSpeedResolver.clear(character, SLOW_SOURCE)
		end
	end)
	return true
end

-- The row's knockback in studs per second, away from whatever hit you, with a
-- little lift. Velocity rather than PlatformStand: a shove the player can walk out
-- of is a shove, and taking control away is what a ride does.
function EnemyCombat.applyKnockback(controller, character, studs)
	if not studs or studs <= 0 then
		return false
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end
	local away = hrp.Position - controller.root.Position
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude < 0.1 then
		return false
	end
	hrp.AssemblyLinearVelocity = away.Unit * studs + Vector3.new(0, studs * KNOCKBACK_LIFT, 0)
	return true
end

-- ============================================================
-- Things left in the world
-- ============================================================

-- controller -> set of handles, each with a destroy. Weak keys for the same reason
-- the slow table has them: a controller nothing holds any more is one whose rig has
-- gone, and its handles go with it.
local runtime = setmetatable({}, { __mode = "k" })

-- Never inside workspace.MazeCity, which stays exactly as the generator built it,
-- and never inside LiveEnemies, whose contents EnemyTargeting excludes from every
-- line of sight test: a bolt in flight that blinded the thing that fired it would
-- be a Spitter that stops shooting the moment it shoots.
function EnemyCombat.effectsFolder()
	local folder = workspace:FindFirstChild("EnemyEffects")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "EnemyEffects"
		folder.Parent = workspace
	end
	return folder
end

local function own(controller, handle)
	local set = runtime[controller]
	if not set then
		set = {}
		runtime[controller] = set
	end
	set[handle] = true
	return handle
end

local function disown(controller, handle)
	local set = runtime[controller]
	if set then
		set[handle] = nil
	end
end

-- Called from EnemyController:stop, which runs on despawn as well as on death.
-- Despawn is the case that matters: walking away is how nearly every enemy in this
-- city ends. It was four behaviors each remembering to call it from onStopped
-- until E6, which is four chances for a fifth to be written without one.
function EnemyCombat.clearRuntime(controller)
	local set = runtime[controller]
	if not set then
		return
	end
	runtime[controller] = nil
	for handle in pairs(set) do
		handle.destroy()
	end
end

local function playerCharacterOf(instance)
	local model = instance and instance:FindFirstAncestorOfClass("Model")
	while model do
		if Players:GetPlayerFromCharacter(model) then
			return model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- Shared by the bolt and the snare: land on a player, or do not. The visibility
-- check is the same one melee makes, so a Ghost orb hides you from a Spitter's
-- bolt exactly as it hides you from a Drifter's hands.
local function landOn(controller, character, spec)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or not EnemyTargeting.isCharacterVisible(character, humanoid) then
		return false
	end
	if EnemyStatusService.isFrozen() then
		return false
	end
	-- The zone protects from everything that lands, not just the swing: a trap
	-- touched from inside it, a shockwave washing over the pad, a bolt that got
	-- past the flight check on the same frame the player stepped in.
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and EnemySafeZones.covers(hrp.Position) then
		return false
	end
	EnemyCombat.applyDamage(controller, character, spec.damage or controller.stats.damage)
	if spec.slowMultiplier then
		EnemyCombat.applySlow(character, spec.slowMultiplier, spec.slowDuration or 0)
	end
	return true
end

-- One shared RaycastParams rewritten per step, on the same reasoning as the one in
-- EnemyTargeting: nothing between writing the filter and firing the ray yields.
local boltParams = RaycastParams.new()
boltParams.FilterType = Enum.RaycastFilterType.Exclude
boltParams.RespectCanCollide = true

-- Position integrated on the server, one raycast per step, and nothing physical
-- about it: a physics projectile in a maze whose walls move is a projectile that
-- ends up inside one. It dies on the first thing it meets, on its lifetime, and on
-- the controller that fired it going away.
--
-- spec: speed, lifetime, radius, damage, slowMultiplier, slowDuration.
function EnemyCombat.launchProjectile(controller, direction, spec)
	if direction.Magnitude < 0.1 then
		return nil
	end
	local step = direction.Unit * (spec.speed or 50)
	local radius = spec.radius or 1
	local from = controller.root.Position + EYE_OFFSET + direction.Unit * radius * 2

	local bolt = Instance.new("Part")
	bolt.Name = "EnemyBolt"
	bolt.Shape = Enum.PartType.Ball
	bolt.Size = Vector3.new(radius, radius, radius) * 2
	bolt.Color = controller.stats.color
	bolt.Material = Enum.Material.Neon
	bolt.Transparency = Config.Juice.EnemyProjectileTransparency
	bolt.Anchored = true
	bolt.CanCollide = false
	bolt.CanTouch = false
	bolt.CanQuery = false
	bolt.CastShadow = false
	bolt.Position = from
	bolt.Parent = EnemyCombat.effectsFolder()

	local handle = {}
	local connection
	handle.destroy = function()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		if bolt.Parent then
			bolt:Destroy()
		end
	end
	local function finish()
		disown(controller, handle)
		handle.destroy()
	end

	local remaining = spec.lifetime or 3
	connection = RunService.Heartbeat:Connect(function(dt)
		remaining = remaining - dt
		if remaining <= 0 or not bolt.Parent then
			finish()
			return
		end
		local was = bolt.Position
		local now = was + step * dt
		-- Dies at the boundary, not on a hit inside it: a bolt sailing over the
		-- plaza pad ends there whether or not anybody is standing on it.
		if EnemySafeZones.covers(now) then
			finish()
			return
		end

		-- Looked up per step and each one guarded, exactly as EnemyTargeting does it:
		-- a nil in this list is a hole in an array the engine reads by length, and
		-- it would drop whichever folder came after it out of the filter.
		local filter = { EnemyCombat.effectsFolder() }
		local enemies = workspace:FindFirstChild("LiveEnemies")
		if enemies then
			table.insert(filter, enemies)
		end
		local pets = workspace:FindFirstChild("LivePets")
		if pets then
			table.insert(filter, pets)
		end
		boltParams.FilterDescendantsInstances = filter

		local hit = workspace:Raycast(was, now - was, boltParams)
		if hit then
			local character = playerCharacterOf(hit.Instance)
			if character then
				landOn(controller, character, spec)
			end
			finish()
			return
		end
		bolt.Position = now
	end)

	return own(controller, handle)
end

-- A disc on the floor that arms as soon as it is placed. Touched alone is enough
-- here where it was not enough for a coin: the trigger is trapTriggerRadius across
-- rather than 3.4 studs, so it is walked onto rather than walked at.
--
-- spec: radius, lifetime, damage, slowMultiplier, slowDuration.
function EnemyCombat.placeTrap(controller, position, spec)
	local juice = Config.Juice
	local radius = spec.radius or 4

	local trap = Instance.new("Part")
	trap.Name = "EnemyTrap"
	trap.Shape = Enum.PartType.Cylinder
	-- A Cylinder's length runs along X, so it is stood on its end to lie flat.
	trap.Size = Vector3.new(0.2, radius * 2, radius * 2)
	trap.CFrame = CFrame.new(position + Vector3.new(0, juice.EnemyTrapHeight, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	trap.Color = controller.stats.color
	trap.Material = Enum.Material.Neon
	trap.Transparency = juice.EnemyTrapTransparency
	trap.Anchored = true
	trap.CanCollide = false
	trap.CanQuery = false
	trap.CastShadow = false
	trap.Parent = EnemyCombat.effectsFolder()

	local handle = { part = trap }
	local connection
	handle.destroy = function()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		if trap.Parent then
			trap:Destroy()
		end
	end
	local function finish()
		disown(controller, handle)
		handle.destroy()
	end

	connection = trap.Touched:Connect(function(hit)
		local character = playerCharacterOf(hit)
		if character and landOn(controller, character, spec) then
			finish()
		end
	end)
	task.delay(spec.lifetime or 15, finish)

	return own(controller, handle)
end

-- A disc that does nothing, which is the point: a Blinker's arrival mark and a
-- Burrower's mound are both a promise that something is about to happen here and
-- has not happened yet. It is owned like the things that do bite, because it is the
-- same problem the moment its enemy despawns mid-move.
--
-- Returns the handle so a caller that wants to move its marker can, which the
-- Burrower does for the whole of its travel.
function EnemyCombat.markGround(controller, position, radius, seconds)
	local mark = Instance.new("Part")
	mark.Name = "EnemyMark"
	mark.Shape = Enum.PartType.Cylinder
	mark.Size = Vector3.new(0.25, radius * 2, radius * 2)
	mark.CFrame = CFrame.new(position + Vector3.new(0, Config.Juice.EnemyTrapHeight, 0))
		* CFrame.Angles(0, 0, math.pi / 2)
	mark.Color = controller.stats.color
	mark.Material = Enum.Material.Neon
	mark.Transparency = Config.Juice.EnemyMarkerTransparency
	mark.Anchored = true
	mark.CanCollide = false
	mark.CanTouch = false
	mark.CanQuery = false
	mark.CastShadow = false
	mark.Parent = EnemyCombat.effectsFolder()

	local handle = { part = mark }
	handle.destroy = function()
		if mark.Parent then
			mark:Destroy()
		end
	end
	own(controller, handle)
	task.delay(seconds, function()
		disown(controller, handle)
		handle.destroy()
	end)
	return handle
end

-- A ring on the floor and everything inside it takes the hit, so long as it can be
-- seen from the middle: a wall between you and a Warden is a wall the shockwave
-- does not go through either.
--
-- spec: radius, damage, knockback.
function EnemyCombat.shockwave(controller, spec)
	local radius = spec.radius or 12
	local origin = controller.root.Position

	local ring = Instance.new("Part")
	ring.Name = "EnemyShockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.3, radius * 2, radius * 2)
	ring.CFrame = CFrame.new(origin - Vector3.new(0, controller.humanoid.HipHeight, 0))
		* CFrame.Angles(0, 0, math.pi / 2)
	ring.Color = controller.stats.color
	ring.Material = Enum.Material.Neon
	ring.Transparency = Config.Juice.EnemyMarkerTransparency
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Parent = EnemyCombat.effectsFolder()
	local handle = {}
	handle.destroy = function()
		if ring.Parent then
			ring:Destroy()
		end
	end
	own(controller, handle)
	task.delay(Config.Juice.EnemyShockwaveSeconds, function()
		disown(controller, handle)
		handle.destroy()
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - origin).Magnitude <= radius then
			if EnemyTargeting.hasLineOfSight(origin + EYE_OFFSET, hrp) and landOn(controller, character, spec) then
				EnemyCombat.applyKnockback(controller, character, spec.knockback)
			end
		end
	end
end

return EnemyCombat
