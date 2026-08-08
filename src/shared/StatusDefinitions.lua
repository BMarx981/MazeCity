-- StatusDefinitions (ModuleScript) -> ReplicatedStorage.StatusDefinitions
-- The timed statuses EnemyStatusService can put on a character or a rig. Content
-- on the same split EnemyDefinitions uses: a status is added here as a row, and
-- the service that runs them is not edited.
--
--   target    "Any", or "Humanoid" to refuse an instance without one
--   stacks    "Refresh" to extend the running one, "Replace" to undo and reapply
--   onApply   optional. Receives (instance, magnitude) and returns a closure that
--             undoes exactly what it did. Nil for a status that is only ever read.
--
-- The one rule the shape enforces: a status never writes a permanent value. It
-- records what it found, applies its own, and puts back what it recorded. Two
-- systems that each set WalkSpeed absolutely will eventually overlap, and the
-- loser leaves a player slowed for the rest of the session. PickupService's Speed
-- boost is the system it will overlap with, and it uses the same discipline.
--
-- Two rows, and that is deliberate. The brief also names Reveal and Marked, and
-- both arrive with the type that applies them (a Watcher marks, a Shrieker
-- reveals) at E4. A status nothing applies is a row nobody can check.

local StatusDefinitions = {}

local statuses = {}

-- Scales walk speed by magnitude and restores the value it found rather than
-- recomputing one. The value found may itself be a powerup's, and dividing back
-- out gets that wrong the moment the powerup expires first.
statuses.Slow = {
	target = "Humanoid",
	stacks = "Replace",
	onApply = function(instance, magnitude)
		local humanoid = instance:IsA("Humanoid") and instance or instance:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return nil
		end
		local was = humanoid.WalkSpeed
		humanoid.WalkSpeed = was * math.clamp(magnitude or 0.5, 0, 1)
		return function()
			if humanoid.Parent then
				humanoid.WalkSpeed = was
			end
		end
	end,
}

-- Read rather than applied: EnemyController halts a stunned rig and skips its
-- behavior for the duration. Nothing is written to the Humanoid, because a stun
-- that sets WalkSpeed fights whatever the behavior sets on the tick it ends.
statuses.Stun = {
	target = "Any",
	stacks = "Refresh",
}

StatusDefinitions.statuses = table.freeze(statuses)

function StatusDefinitions.get(name)
	return statuses[name]
end

return table.freeze(StatusDefinitions)
