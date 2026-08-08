-- EnemyController (ModuleScript) -> ServerScriptService.Enemy.EnemyController
-- One per live rig. Owns that enemy's runtime state, drives its state machine,
-- and calls into its behavior module for anything type specific.
--
-- The division it enforces: the controller knows how to move, look, attack and
-- die, the behavior knows when. A behavior that reaches past the controller into
-- the Humanoid is a behavior that has to re-implement the freeze deadline, the
-- stun, the floor band and the tell, and one of the fifteen will get it wrong.
--
-- The tick order is the contract and is asserted in the E2 harness rather than
-- left to memory: freeze, stun, off-floor, behavior.update, target selection
-- wrapped in filterTarget and the two transition hooks, growl, then chase or
-- search or return or idle. Three hooks can claim a tick and end it there.
--
-- tick never yields. It matters twice. The Charger's windup used to be a
-- task.wait inside the think loop, which parked the thread for its whole length
-- and meant a Freeze powerup landing during a windup did not stop the charge
-- until after it had already started; it is a deadline on the AttackWindup state
-- now. And a tick that cannot yield is a tick that could be driven from one
-- shared slice loop instead of a thread per rig, which is the shape E6's stagger
-- audit should measure before anybody writes it.
--
-- Dormancy is not here. A rig only exists while somebody is near enough to meet
-- it, so the cheap-poll-when-nobody-is-looking layer the brief describes is
-- EnemyService's spawn scan instead, and there is no such thing as an enemy in
-- this city that nobody is near.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local EnemyTypes = require(ReplicatedStorage:WaitForChild("EnemyTypes"))
local ModelGenerator = require(ReplicatedStorage:WaitForChild("ModelGenerator"))

local EnemyCombat = require(script.Parent:WaitForChild("EnemyCombat"))
local EnemyPathfinding = require(script.Parent:WaitForChild("EnemyPathfinding"))
local EnemyRig = require(script.Parent:WaitForChild("EnemyRig"))
local EnemyStateMachine = require(script.Parent:WaitForChild("EnemyStateMachine"))
local EnemyStatusService = require(script.Parent:WaitForChild("EnemyStatusService"))
local EnemyTargeting = require(script.Parent:WaitForChild("EnemyTargeting"))

local Behaviors = script.Parent:WaitForChild("Behaviors")
local BaseBehavior = require(Behaviors:WaitForChild("BaseBehavior"))

-- Keyed by EnemyTypes.Behavior. Nine of the fourteen names have no module yet;
-- a row naming one gets BaseBehavior, which chases and hits like the baseline
-- rather than standing there, and warns once so a missing module is a message and
-- not a mystery.
local MODULES = {
	[EnemyTypes.Behavior.Chaser] = require(Behaviors:WaitForChild("Chaser")),
	[EnemyTypes.Behavior.Guard] = require(Behaviors:WaitForChild("Guard")),
	[EnemyTypes.Behavior.Swarmer] = require(Behaviors:WaitForChild("Swarmer")),
	[EnemyTypes.Behavior.Ambusher] = require(Behaviors:WaitForChild("Ambusher")),
	[EnemyTypes.Behavior.Charger] = require(Behaviors:WaitForChild("Charger")),
}
local warnedMissing = {}

local State = EnemyTypes.State

-- One stud up, because the root sits at HipHeight and a ray from the floor into a
-- player's feet clips the slab they are both standing on.
local EYE_OFFSET = Vector3.new(0, 1, 0)

-- How close to its marker counts as home, and how far it may drift before
-- walking back. RETURN_RADIUS has to cover the widest idle wander any behavior
-- performs or a wanderer reads as needing to come home the moment it reaches the
-- edge of its own wander; Chaser's WANDER_RADIUS is the number it covers.
local HOME_RADIUS = 5
local RETURN_RADIUS = 13

-- How long it keeps hunting a position after losing sight. The rows carry a
-- per-type `memory` for this and it is deliberately still dormant: 3.5 is the
-- number that went through a playtest, and Drifter's memory of 6 would make every
-- enemy in the city noticeably more persistent as a side effect of a refactor.
local SEARCH_SECONDS = 3.5

local EnemyController = {}
EnemyController.__index = EnemyController

local function flatTo(from, to)
	return Vector3.new(to.X - from.X, 0, to.Z - from.Z)
end

function EnemyController.new(model, stats, context)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not humanoid or not root then
		return nil
	end

	local self = setmetatable({}, EnemyController)
	self.model = model
	self.humanoid = humanoid
	self.root = root
	self.torso = model:FindFirstChild("Torso") or root
	self.stats = stats
	self.enemyType = stats.enemyType
	self.behaviorConfig = stats.behaviorConfig
	self.anim = context.anim
	self.marker = context.marker
	self.home = context.home
	self.homeY = context.home.Y
	-- Carried for the registry's per-building cap and for a debug label. Nothing an
	-- enemy does reads them; where it is, is its marker's business.
	self.section = context.section
	self.building = context.building
	self.level = context.level
	self.skin = ModelGenerator.readSkin(model)
	self.growl = EnemyRig.makeGrowl(root)

	self.alive = true
	self.target = nil
	self.lastSeen = nil
	self.searchUntil = nil
	self.leashMultiplier = 1
	self.windingUp = false
	self.flashing = false
	self.hidden = false
	self.frozen = false
	self.lastAttack = 0
	self.animClock = 0
	-- Runtime randomness, deliberately not seeded off the world seed: this is the
	-- same call PickupService makes when it rolls a powerup. It only has to stop six
	-- shades in a room bobbing in lockstep, and a rig is not part of what a seed is
	-- supposed to reproduce.
	self.phase = math.random() * math.pi * 2

	local behavior = MODULES[stats.behavior]
	if not behavior then
		behavior = BaseBehavior
		if stats.behavior and not warnedMissing[stats.behavior] then
			warnedMissing[stats.behavior] = true
			warn("EnemyController: no module for behavior " .. tostring(stats.behavior) .. ", using BaseBehavior")
		end
	end
	self.behavior = behavior

	self.machine = EnemyStateMachine.new(self)
	self.path = EnemyPathfinding.new(self)
	self.connections = {}

	behavior.init(self, self.behaviorConfig)
	return self
end

-- ============================================================
-- Lifecycle
-- ============================================================

function EnemyController:start()
	local root = self.root
	table.insert(
		self.connections,
		root.Touched:Connect(function(hit)
			if not self.alive then
				return
			end
			local character = hit:FindFirstAncestorOfClass("Model")
			if not character or not Players:GetPlayerFromCharacter(character) then
				return
			end
			-- Touched is the zero-latency path and the one that cannot be missed. An
			-- enemy standing inside a player fires Touched once and then never again
			-- while neither of them crosses a boundary, which is how a cornered player
			-- used to take no damage at all from something pressed against them.
			if not self.behavior.tryAttack(self, character) then
				EnemyCombat.tryMelee(self, character)
			end
		end)
	)

	table.insert(
		self.connections,
		self.humanoid.Died:Connect(function()
			-- Guarded on alive because Destroy fires Died too, and an ordinary
			-- walk-away despawn must not arm the respawn timer: a player who steps off
			-- a floor and comes straight back would find it empty for the whole of
			-- Config.Enemies.RespawnSeconds.
			if not self.alive then
				return
			end
			self.alive = false
			self.machine:transition(State.Dead)
			self.behavior.onDeath(self, self.lastDamageSource)
			if self.onDied then
				self.onDied(self)
			end
		end)
	)

	self.thread = task.spawn(function()
		-- The stagger. Every rig thinks at the same rate and none of them think on
		-- the same frame, which costs one wait and is the whole of what the brief's
		-- staggered update groups are for at this scale.
		task.wait(math.random() * Config.Enemies.ThinkInterval)
		local last = os.clock()
		while self.alive and self.model.Parent do
			local now = os.clock()
			local dt = now - last
			last = now
			-- pcall so one enemy that trips over a destroyed target does not end its
			-- own thread and leave a rig standing there forever, which is
			-- indistinguishable from the stuck bug this system exists to fix.
			local ok, err = pcall(self.tick, self, dt)
			if not ok then
				warn("EnemyController: tick failed for " .. tostring(self.enemyType) .. ": " .. tostring(err))
			end
			task.wait(Config.Enemies.ThinkInterval)
		end
	end)
end

function EnemyController:stop()
	self.alive = false
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)
	self.path:destroy()
	self.thread = nil
end

function EnemyController:destroy()
	self:stop()
	EnemyStatusService.clearAll(self.model)
	if self.model.Parent then
		self.model:Destroy()
	end
end

-- ============================================================
-- Things done to it
-- ============================================================

function EnemyController:setTarget(character)
	if not character then
		self:loseTarget()
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		self:acquire(hrp)
	end
end

function EnemyController:applyStun(seconds)
	EnemyStatusService.apply(self.model, "Stun", seconds)
	self.path:halt()
end

-- Nothing in the game damages an enemy, so this is reachable only from a debug
-- command. It is wired correctly anyway, so that adding a weapon is adding a
-- weapon and not also a lifecycle.
function EnemyController:takeDamage(amount, source)
	if not self.alive or self.humanoid.Health <= 0 then
		return
	end
	self.lastDamageSource = source
	self.humanoid:TakeDamage(amount)
	self.behavior.onDamaged(self, amount, source)
end

-- ============================================================
-- Things it does
-- ============================================================

function EnemyController:halt()
	self.path:halt()
end

function EnemyController:flash(seconds)
	EnemyRig.flash(self, seconds)
end

function EnemyController:playSound(soundId, volume, pitch)
	EnemyRig.playOnce(self.root, soundId, volume, pitch)
end

function EnemyController:hasLineOfSightTo(part)
	return EnemyTargeting.hasLineOfSight(self.root.Position + EYE_OFFSET, part)
end

-- Walk speed for this tick. An unwatchedSpeed on the row is the whole of what
-- makes a Stalker a Stalker: it is data rather than a behavior branch, so
-- Sprinter and Brute ride the same module without one.
function EnemyController:chaseSpeed(target)
	local stats = self.stats
	if stats.unwatchedSpeed and not EnemyTargeting.isWatched(self, target) then
		return stats.unwatchedSpeed
	end
	return stats.walkSpeed
end

function EnemyController:acquire(target)
	local hadNone = self.target == nil
	self.target = target
	self.lastSeen = target.Position
	self.searchUntil = nil
	if hadNone then
		self:playSound(Config.Sounds.EnemyAlert, Config.Juice.EnemyAlertVolume, 0.8)
		self.behavior.onTargetAcquired(self, target)
	end
end

function EnemyController:loseTarget()
	if not self.target then
		return
	end
	self.target = nil
	self.searchUntil = os.clock() + SEARCH_SECONDS
	self.behavior.onTargetLost(self)
end

-- Fell down a stairwell, or gave up on a corner it could not path out of. Ugly
-- and almost never reached, and an enemy welded into a corner for the rest of the
-- session is worse and is what used to happen.
function EnemyController:goHome()
	self.model:PivotTo(CFrame.new(self.home))
	self.target = nil
	self.lastSeen = nil
	self.path:reset()
	self.path:halt()
	self.machine:transition(State.Idle)
end

-- ============================================================
-- The tick
-- ============================================================

function EnemyController:tick(dt)
	local behavior = self.behavior
	local stats = self.stats

	if EnemyStatusService.isFrozen() then
		-- Stopped where it stands, silent, and with the animation held, because a
		-- growl or a bob coming off something that cannot move is the wrong read.
		self.frozen = true
		self.machine:transition(State.Frozen)
		self.path:halt()
		self.growl.Playing = false
		return
	end
	self.frozen = false

	if EnemyStatusService.has(self.model, "Stun") then
		self.machine:transition(State.Stunned)
		self.path:halt()
		return
	end

	-- Fell down a stairwell, or was shoved off its floor. Either way it is no longer
	-- where it belongs and pathing back up a spiral it has no business on is not
	-- worth trying.
	if math.abs(self.root.Position.Y - self.homeY) > Config.Enemies.FloorBand then
		self:goHome()
		return
	end

	if behavior.update(self, dt) then
		return
	end

	local target = behavior.filterTarget(self, EnemyTargeting.pick(self))
	if target then
		self:acquire(target)
	else
		self:loseTarget()
	end
	EnemyRig.updateGrowl(self)

	if self.target then
		local hrp = self.target
		if behavior.onChase(self, hrp) then
			return
		end

		self.machine:transition(State.Chase)
		self.humanoid.WalkSpeed = self:chaseSpeed(hrp)
		if self:hasLineOfSightTo(hrp) then
			self.path:direct(hrp.Position)
		else
			self.path:moveTo(hrp.Position)
		end

		local character = hrp.Parent
		if character and (hrp.Position - self.root.Position).Magnitude <= Config.Juice.EnemyTellReach * 0.7 then
			if not behavior.tryAttack(self, character) then
				EnemyCombat.tryMelee(self, character)
			end
		end

		if self.path:isStuck() then
			self:goHome()
		end
		return
	end

	if self.lastSeen and os.clock() < (self.searchUntil or 0) then
		self.machine:transition(State.Search)
		self.humanoid.WalkSpeed = stats.walkSpeed
		if flatTo(self.root.Position, self.lastSeen).Magnitude > HOME_RADIUS then
			self.path:moveTo(self.lastSeen)
			if self.path:isStuck() then
				self:goHome()
			end
			return
		end
		self.searchUntil = nil
	end
	self.lastSeen = nil

	if flatTo(self.root.Position, self.home).Magnitude > RETURN_RADIUS then
		self.machine:transition(State.Return)
		self.humanoid.WalkSpeed = stats.walkSpeed
		self.path:moveTo(self.home)
		if self.path:isStuck() then
			self:goHome()
		end
		return
	end

	-- The stuck window is reset here and not just cleared, because it is only
	-- sampled while moving. Left stale through a long idle, the first tick of the
	-- next chase compares against a position from minutes ago and reads as stuck
	-- immediately, so every enemy jumped on the spot the moment it saw anybody.
	self.path:reset()
	if not behavior.onIdle(self) then
		self.machine:transition(State.Idle)
		self.path:halt()
	end
end

return EnemyController
