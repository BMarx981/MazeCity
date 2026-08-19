-- EnemyLore (ModuleScript) -> ServerScriptService.Enemy.EnemyLore
-- The one file on this side that knows anything outside the enemy system is
-- listening, the way EnemyWard is the one that knows pets exist. Nothing here
-- decides what a moment is worth: it publishes facts about enemies onto the
-- LoreEvent channel and LoreService decides which fragment, if any, a fact
-- satisfies. So renaming a journal fragment never reaches into the AI, and an
-- enemy that gains a moment worth writing about needs no new channel.
--
-- **An encounter is a pair, and surviving one is the enemy giving up while you
-- are alive.** It opens where the controller acquires a target and closes where
-- that same rig loses it, walks home or stops, which covers despawn as well as
-- death: walking away is how nearly every enemy in this city ends. A player who
-- died between the two closes nothing, which is the whole of what stops a chase
-- that killed somebody reading as one they survived, and it is why the close
-- re-reads the humanoid rather than trusting the pair.
--
-- The close carries a reason and it is not a guess. EnemyTargeting.pick drops a
-- held target for exactly two reasons, out of sight and out of leash, and the
-- second is directly answerable at the instant of the close from the position
-- the target was last at. That is what makes a Gatekeeper's leash reset a thing
-- the journal can be told about; the docs/PETS_PLAN.md audit recorded it as
-- having no source, and it has one because the close is a place to ask from.
--
-- Marks are for the fragment that names something more specific than a chase.
-- A Shrieker that chased somebody and gave up is not a scream survived, so the
-- shriek marks the open encounter and the close carries the mark.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local EnemyTargeting = require(script.Parent:WaitForChild("EnemyTargeting"))

-- FindFirstChild-or-create on both ends, the rule for every BindableEvent in
-- this game: scripts in ServerScriptService start in arbitrary order, and this
-- module is required from the controller, which may well run before the service
-- that listens.
local channel = ServerScriptService:FindFirstChild("LoreEvent")
if not channel then
	channel = Instance.new("BindableEvent")
	channel.Name = "LoreEvent"
	channel.Parent = ServerScriptService
end

local EnemyLore = {}

local function subjectOf(hrp)
	local character = hrp and hrp.Parent
	if not character then
		return nil
	end
	return Players:GetPlayerFromCharacter(character)
end

function EnemyLore.opened(controller, hrp)
	local player = subjectOf(hrp)
	if not player then
		return
	end
	controller.encounter = { player = player, hrp = hrp, character = hrp.Parent, marks = {} }
	channel:Fire({
		kind = "Encounter",
		phase = "opened",
		enemyType = controller.enemyType,
		player = player,
	})
end

-- Something more specific than being chased happened during this encounter, and
-- the close is where it is worth anything. No-ops when nothing is open, so a
-- behavior may mark unconditionally.
function EnemyLore.mark(controller, flag)
	local open = controller.encounter
	if open then
		open.marks[flag] = true
	end
end

function EnemyLore.closed(controller)
	local open = controller.encounter
	if not open then
		return
	end
	controller.encounter = nil

	-- Died, or respawned into a body this encounter was never about. Either way
	-- nobody survived anything.
	if open.player.Character ~= open.character then
		return
	end
	local humanoid = open.character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local out = (open.hrp.Position - controller.home).Magnitude > EnemyTargeting.leashFor(controller)
	channel:Fire({
		kind = "Encounter",
		phase = "survived",
		enemyType = controller.enemyType,
		player = open.player,
		reason = out and "leash" or "lost",
		marks = open.marks,
	})
end

-- A moment that is neither end of an encounter: a disguise dropped, a statue
-- caught. The player is whoever caused it, which is not always the target.
function EnemyLore.moment(controller, kind, hrp)
	local player = subjectOf(hrp)
	if not player then
		return
	end
	channel:Fire({ kind = kind, enemyType = controller.enemyType, player = player })
end

return EnemyLore
