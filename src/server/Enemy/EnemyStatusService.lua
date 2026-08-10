-- EnemyStatusService (ModuleScript) -> ServerScriptService.Enemy.EnemyStatusService
-- Timed statuses on players and on enemies, from the rows in
-- ReplicatedStorage.StatusDefinitions.
--
-- One rule decides the shape: a status never writes a permanent value. It
-- records what it found, applies its own, and restores what it found when it
-- expires or when the character it was on is destroyed, which is the same
-- restore-closure discipline PickupService already uses for its powerups.
--
-- Expiry is a task.delay and not a poll, guarded by a token: reapplying a status
-- bumps the token, so the delay the first application armed finds a stale token
-- and does nothing rather than restoring a value the second one is still using.
-- A polling loop over every status on every enemy in the city is a cost paid
-- constantly for something that fires seconds apart.
--
-- The records table has weak keys, so a character that respawns and is collected
-- takes its statuses with it whether or not anything remembered to clear them.
-- Destroying is still connected, because the restore has to run before the
-- instance goes away rather than whenever the collector gets to it.
--
-- Freeze is here too and is not a row. It is a deadline on workspace written by
-- PickupService, so it applies to every enemy in the city at once and there is no
-- per-instance record to keep. It lives in this module because a caller asking
-- "is this thing stopped" should not have to know that one answer is a status and
-- the other is an attribute somebody else owns.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatusDefinitions = require(ReplicatedStorage:WaitForChild("StatusDefinitions"))

local EnemyStatusService = {}

local records = setmetatable({}, { __mode = "k" })
local destroyers = setmetatable({}, { __mode = "k" })
local nextToken = 0

-- The Freeze powerup, stored as a deadline rather than a flag so two players
-- freezing overlapping crowds extend the thaw instead of ending it early.
function EnemyStatusService.isFrozen()
	local until_ = workspace:GetAttribute("EnemyFreezeUntil")
	return until_ ~= nil and os.clock() < until_
end

-- The Destroying connection is held beside the bucket and dropped with it. Left
-- unheld it was one new connection every time a status arrived on an instance
-- whose bucket had been cleared, which is the cheapest possible leak and the
-- hardest to see: nothing misbehaves, the tally just climbs all session. Beside
-- rather than inside because a bucket is keyed by status name and everything in
-- it is a record.
local function forInstance(instance, create)
	local bucket = records[instance]
	if not bucket and create then
		bucket = {}
		records[instance] = bucket
		destroyers[instance] = instance.Destroying:Connect(function()
			EnemyStatusService.clearAll(instance)
		end)
	end
	return bucket
end

local function undo(record)
	record.token = nil
	if record.restore then
		local ok, err = pcall(record.restore)
		if not ok then
			warn("EnemyStatusService: restore failed for " .. record.name .. ": " .. tostring(err))
		end
		record.restore = nil
	end
end

function EnemyStatusService.apply(instance, statusName, seconds, magnitude)
	local definition = StatusDefinitions.get(statusName)
	if not definition then
		warn("EnemyStatusService: no status called " .. tostring(statusName))
		return false
	end
	if not instance or not instance.Parent then
		return false
	end
	if definition.target == "Humanoid" then
		local humanoid = instance:IsA("Humanoid") and instance or instance:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return false
		end
	end

	local bucket = forInstance(instance, true)
	local existing = bucket[statusName]
	-- Refresh extends the running one and leaves what it applied alone; Replace
	-- undoes it first, because a second Slow computed against an already slowed
	-- speed compounds and the restore only remembers one of them.
	if existing and existing.token then
		if definition.stacks == "Refresh" then
			existing.expiresAt = os.clock() + seconds
			nextToken = nextToken + 1
			existing.token = nextToken
			local token = nextToken
			task.delay(seconds, function()
				if existing.token == token then
					undo(existing)
				end
			end)
			return true
		end
		undo(existing)
	end

	nextToken = nextToken + 1
	local token = nextToken
	local record = {
		name = statusName,
		token = token,
		magnitude = magnitude,
		expiresAt = os.clock() + seconds,
		restore = nil,
	}
	bucket[statusName] = record

	if definition.onApply then
		local ok, result = pcall(definition.onApply, instance, magnitude)
		if not ok then
			warn("EnemyStatusService: apply failed for " .. statusName .. ": " .. tostring(result))
			record.token = nil
			return false
		end
		record.restore = result
	end

	task.delay(seconds, function()
		if record.token == token then
			undo(record)
		end
	end)
	return true
end

function EnemyStatusService.has(instance, statusName)
	local bucket = records[instance]
	local record = bucket and bucket[statusName]
	return record ~= nil and record.token ~= nil and os.clock() < record.expiresAt
end

function EnemyStatusService.magnitudeOf(instance, statusName)
	local bucket = records[instance]
	local record = bucket and bucket[statusName]
	if record and record.token and os.clock() < record.expiresAt then
		return record.magnitude
	end
	return nil
end

function EnemyStatusService.clear(instance, statusName)
	local bucket = records[instance]
	local record = bucket and bucket[statusName]
	if record then
		undo(record)
		bucket[statusName] = nil
	end
end

function EnemyStatusService.clearAll(instance)
	local bucket = records[instance]
	if not bucket then
		return
	end
	for name, record in pairs(bucket) do
		undo(record)
		bucket[name] = nil
	end
	records[instance] = nil
	local destroying = destroyers[instance]
	if destroying then
		destroying:Disconnect()
		destroyers[instance] = nil
	end
end

return EnemyStatusService
