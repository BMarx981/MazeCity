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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local EnemyRig = require(script.Parent:WaitForChild("EnemyRig"))
local EnemyStatusService = require(script.Parent:WaitForChild("EnemyStatusService"))
local EnemyTargeting = require(script.Parent:WaitForChild("EnemyTargeting"))

local EnemyCombat = {}

-- One stud up, because the root sits at HipHeight and a ray from the floor into a
-- player's feet clips the slab they are both standing on.
local EYE_OFFSET = Vector3.new(0, 1, 0)

function EnemyCombat.canReach(controller, character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end
	if (hrp.Position - controller.root.Position).Magnitude > Config.Juice.EnemyTellReach then
		return false
	end
	return EnemyTargeting.hasLineOfSight(controller.root.Position + EYE_OFFSET, hrp)
end

function EnemyCombat.applyDamage(controller, character, amount)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	humanoid:TakeDamage(amount or controller.stats.damage)
	return true
end

-- Returns whether a swing started, not whether it landed. Nothing reads that yet;
-- it is the honest answer because the landing happens after the tell.
function EnemyCombat.tryMelee(controller, character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	local now = os.clock()
	if controller.windingUp or now - controller.lastAttack < controller.stats.attackCooldown then
		return false
	end
	if EnemyStatusService.isFrozen() or EnemyStatusService.has(controller.model, "Stun") then
		return false
	end
	if not EnemyTargeting.isCharacterVisible(character, humanoid) then
		return false
	end
	-- A Lurker that has not revealed itself does not bite. Being scenery is the
	-- whole of what it is doing.
	if controller.hidden then
		return false
	end

	controller.windingUp = true
	controller.lastAttack = now
	EnemyRig.flash(controller, Config.Juice.EnemyTellSeconds)

	task.delay(Config.Juice.EnemyTellSeconds, function()
		controller.windingUp = false
		if not controller.alive then
			return
		end
		if EnemyCombat.canReach(controller, character) then
			EnemyCombat.applyDamage(controller, character, controller.stats.damage)
		end
	end)
	return true
end

return EnemyCombat
