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
-- records what it found, applies its own, and puts back what it recorded.
--
-- Both shipped rows are read rather than applied, and the row that is not here is
-- the reason worth reading. E2 wrote a Slow that scaled a Humanoid's WalkSpeed and
-- restored the value it found. Sprint landed after it and brought WalkSpeedResolver,
-- which is now the only writer of a player's WalkSpeed and the only reason Fast
-- Feet, a Speed orb, a phase and a sprint compose; a status doing its own
-- record-and-restore beside it is exactly the last-writer-wins the resolver exists
-- to end. So E4's Spitter and Trapper, the first things in the game that slow
-- anybody, spend a named resolver factor in EnemyCombat instead, and Slow is not a
-- row. onApply stays supported for a status that genuinely owns its own value; the
-- test for a new one is whether anything else already owns the thing it writes.
--
-- The brief also names Marked, and it is deliberately not here either. Nothing E4
-- ships applies one: a Watcher that spots you tells the floor where you are, which
-- is EnemyAlert, and a status nothing applies is a row nobody can check.

local StatusDefinitions = {}

local statuses = {}

-- Read rather than applied: EnemyController halts a stunned rig and skips its
-- behavior for the duration. Nothing is written to the Humanoid, because a stun
-- that sets WalkSpeed fights whatever the behavior sets on the tick it ends.
statuses.Stun = {
	target = "Any",
	stacks = "Refresh",
}

-- A Shrieker's answer to hiding. Read in exactly one place, EnemyTargeting's
-- visibility test, where it overrides the Ghost powerup and the Cloak ability for
-- as long as it lasts.
--
-- It is Refresh rather than Replace because two Shriekers on a floor should extend
-- one reveal rather than restart it, and it is short and telegraphed on purpose:
-- cancelling something a player bought is fair only while they can see what did it
-- and walk away from that instead.
statuses.Revealed = {
	target = "Any",
	stacks = "Refresh",
}

StatusDefinitions.statuses = table.freeze(statuses)

function StatusDefinitions.get(name)
	return statuses[name]
end

return table.freeze(StatusDefinitions)
