-- EnemyPathfinding (ModuleScript) -> ServerScriptService.Enemy.EnemyPathfinding
-- Paths, waypoint following, replanning and stuck detection. One per live rig,
-- owning that rig's Path object and the only thing that calls Humanoid:MoveTo.
--
-- Two things here are hard won and must survive any change.
--
-- Nothing blocks on MoveToFinished. MoveTo carries an eight second internal
-- timeout, so waiting on it meant an enemy that clipped a corner stood still for
-- eight seconds with its replan check sitting unreachable underneath. Arrival is
-- decided here, as a distance test on the horizontal plane, because a waypoint's
-- Y sits on the navmesh and the rig's sits at HipHeight above it.
--
-- A plan goes stale on both a timer and a drift. The timer covers a moving wall
-- closing across a path that was clear when it was drawn, the drift covers the
-- player rounding a corner, and neither alone caught both.
--
-- The tolerances below are local and the rates are in Config.Enemies, and the
-- line between them is what a designer could sensibly move. How often to think
-- is a tuning decision; how many studs from a waypoint counts as reaching it is
-- a property of the navmesh and the rig's own width.
--
-- Teleporting is not navigation. The give-up teleport home stays the last resort
-- it is: it is ugly and almost never reached, and an enemy welded into a corner
-- for the rest of the session is worse and is what used to happen.

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))

local EnemySafeZones = require(script.Parent:WaitForChild("EnemySafeZones"))

local WAYPOINT_REACHED = 4
local REPLAN_DRIFT = 8

-- Stuck means "supposed to be moving and did not".
local STUCK_EPSILON = 1.5
local STUCK_SECONDS = 0.9
local STUCK_GIVE_UP = 4

local EnemyPathfinding = {}
EnemyPathfinding.__index = EnemyPathfinding

-- ============================================================
-- Where a thing may appear
-- ============================================================
-- Two questions the types that arrive somewhere rather than walk there have to
-- ask: is the line to it clear, and is there floor under it. A Blinker, a Burrower
-- and a Trapper all ask, and they ask here rather than each raycasting for
-- themselves, because a destination check written four times is three chances to
-- forget the filter and put an enemy inside a wall.
--
-- It is not a contradiction of the note above about teleporting. That one is about
-- the give-up teleport home, which is a last resort and not navigation; these are
-- how a move that is supposed to cross a wall proves it may.
--
-- The safe zones landed here at E5 as the third question, and with the margin:
-- nothing may arrive inside one or on its doorstep, and there is nowhere else
-- every arrival passes through.

local reachParams = RaycastParams.new()
reachParams.FilterType = Enum.RaycastFilterType.Exclude
reachParams.RespectCanCollide = true

-- Rebuilt per call and each entry guarded, on the same reasoning as
-- EnemyTargeting's: a nil in this list is a hole in an array the engine reads by
-- length, and it drops whatever came after it out of the filter.
local function worldFilter()
	local filter = {}
	for _, name in ipairs({ "LiveEnemies", "LivePets", "EnemyEffects" }) do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(filter, folder)
		end
	end
	return filter
end

function EnemyPathfinding.isClearBetween(from, to)
	if EnemySafeZones.repels(to) then
		return false
	end
	reachParams.FilterDescendantsInstances = worldFilter()
	return workspace:Raycast(from, to - from, reachParams) == nil
end

-- The point of floor under a position, or nil if there is none within `drop`
-- studs. nil is the answer that matters: it is a stairwell shaft, the gap outside
-- the facade, or thin air over the plaza, and something about to appear there
-- should not.
function EnemyPathfinding.groundBelow(position, drop)
	if EnemySafeZones.repels(position) then
		return nil
	end
	reachParams.FilterDescendantsInstances = worldFilter()
	local hit = workspace:Raycast(position, Vector3.new(0, -(drop or 12), 0), reachParams)
	return hit and hit.Position or nil
end

function EnemyPathfinding.new(controller)
	local self = setmetatable({}, EnemyPathfinding)
	self.controller = controller
	self.humanoid = controller.humanoid
	self.root = controller.root

	self.waypoints = nil
	self.wpIndex = 1
	self.plannedFor = nil
	self.replanAt = 0
	self.blocked = false

	self.stuckPos = controller.root.Position
	self.stuckAt = os.clock()
	self.stuckCount = 0

	self.path = PathfindingService:CreatePath({
		AgentRadius = 2.5,
		AgentHeight = 6,
		-- A maze floor is flat. Jump waypoints only ever appeared because the
		-- planner found a lip somewhere, and an enemy hopping down a corridor reads
		-- as a bug. The stuck handler still jumps deliberately.
		AgentCanJump = false,
	})
	-- The engine's own answer to a moving wall closing across a plan that was clear
	-- when it was drawn. The replan timer would catch it too, half a second later
	-- and after the enemy had already walked into it.
	self.blockedConn = self.path.Blocked:Connect(function()
		self.blocked = true
	end)

	return self
end

function EnemyPathfinding:destroy()
	if self.blockedConn then
		self.blockedConn:Disconnect()
		self.blockedConn = nil
	end
	self.waypoints = nil
end

function EnemyPathfinding:needsReplan(goal)
	if self.waypoints == nil or self.blocked then
		return true
	end
	if os.clock() >= self.replanAt then
		return true
	end
	return self.plannedFor ~= nil and (goal - self.plannedFor).Magnitude > REPLAN_DRIFT
end

function EnemyPathfinding:repath(goal)
	local ok = pcall(function()
		self.path:ComputeAsync(self.root.Position, goal)
	end)
	self.replanAt = os.clock() + Config.Enemies.PathReplanSeconds
	self.blocked = false
	if ok and self.path.Status == Enum.PathStatus.Success then
		self.waypoints = self.path:GetWaypoints()
		self.wpIndex = 2
		self.plannedFor = goal
		return true
	end
	self.waypoints = nil
	return false
end

-- One step of "walk toward goal". Returns true while there is still a plan to
-- follow. Nothing here yields.
function EnemyPathfinding:moveTo(goal)
	if self:needsReplan(goal) and not self:repath(goal) then
		-- No route. Hold rather than walking the straight line into whatever wall is
		-- in the way, which is what the old fallback did and what made a blocked
		-- enemy look brain dead instead of blocked.
		self.humanoid:MoveTo(self.root.Position)
		return false
	end

	local waypoints = self.waypoints
	if not waypoints then
		return false
	end

	while self.wpIndex <= #waypoints do
		local point = waypoints[self.wpIndex].Position
		local flat = Vector3.new(point.X - self.root.Position.X, 0, point.Z - self.root.Position.Z)
		if flat.Magnitude > WAYPOINT_REACHED then
			self.humanoid:MoveTo(point)
			return true
		end
		self.wpIndex = self.wpIndex + 1
	end

	self.waypoints = nil
	self.humanoid:MoveTo(goal)
	return true
end

-- Straight at it, no planner. Down a corridor the path and the straight line are
-- the same thing, and skipping ComputeAsync there is both cheaper and sharper: an
-- enemy that has you in view walks at you rather than around the navmesh corner
-- it planned two ticks ago.
function EnemyPathfinding:direct(goal)
	self.waypoints = nil
	self.humanoid:MoveTo(goal)
end

function EnemyPathfinding:halt()
	self.humanoid.WalkSpeed = 0
	self.humanoid:MoveTo(self.root.Position)
	self.waypoints = nil
end

-- Clears the stuck window instead of just zeroing the counter. It is only
-- sampled while moving, so left stale through a long idle the first tick of the
-- next chase compares against a position from minutes ago and reads as stuck
-- immediately, which had every enemy jumping on the spot the moment it saw
-- anybody.
function EnemyPathfinding:reset()
	self.stuckCount = 0
	self.stuckPos = self.root.Position
	self.stuckAt = os.clock()
end

-- True when the give-up threshold is reached. The jump and the dropped plan are
-- navigation and happen here; what to do about having given up is the
-- controller's call, because going home is about more than position.
function EnemyPathfinding:isStuck()
	local now = os.clock()
	local moved = (self.root.Position - self.stuckPos).Magnitude
	if moved > STUCK_EPSILON then
		self.stuckPos = self.root.Position
		self.stuckAt = now
		self.stuckCount = 0
		return false
	end
	if now - self.stuckAt < STUCK_SECONDS then
		return false
	end

	self.stuckAt = now
	self.stuckCount = self.stuckCount + 1
	self.waypoints = nil
	self.humanoid.Jump = true
	return self.stuckCount >= STUCK_GIVE_UP
end

return EnemyPathfinding
